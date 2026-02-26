import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';

import '../models/persons.dart';
import '../utils/hangul_utils.dart';
import '../providers/person_provider.dart';

/// 전역적으로 사용할 폰트 패밀리 (FA 현장 시인성 최적화)
const String _fontPretendard = 'Pretendard';

class PersonPage extends StatefulWidget {
  final String searchQuery;
  final String filter;
  final bool isMobile;
  final String baseUrl;

  const PersonPage({
    super.key,
    required this.searchQuery,
    required this.filter,
    required this.isMobile,
    required this.baseUrl,
  });

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  final TextEditingController _searchController = TextEditingController();
  String _currentSearchQuery = "";
  late String _currentFilter;

  // [UI 규격 상수] 헤더와 목록의 높이를 동일하게 관리
  static const double _rowHeight = 56.0;
  static const double _colImgWidth = 70.0;
  static const int _flexName = 4;
  static const int _flexDept = 5;
  static const int _flexCode = 3;
  static const int _flexEpc = 6;
  static const int _flexDynamic = 4;
  static const double _colActionWidth = 80.0;

  @override
  void initState() {
    super.initState();
    _currentFilter = widget.filter;
    _currentSearchQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// [데이터 안전] 메타데이터 탐색 (중합 구조 대응)
  String _getMetaValue(Person item, String key) {
    if (item.metadata.containsKey(key)) {
      return item.metadata[key]?.toString() ?? "-";
    }
    final dynamic nested = item.metadata['original_row_data'];
    if (nested is Map) {
      return nested[key]?.toString() ?? "-";
    }
    return "-";
  }

  /// [데이터 분석] 사용 가능한 모든 엑셀 컬럼 키 추출
  List<String> _extractAvailableMetaKeys(List<Person> list) {
    final Set<String> keySet = {};
    const systemKeys = {
      'import_source',
      'original_row_data',
      'id',
      'created',
      'updated',
      'collectionId',
      'collectionName'
    };
    for (var p in list) {
      for (var key in p.metadata.keys) {
        if (!systemKeys.contains(key)) {
          keySet.add(key);
        }
      }
      final dynamic nested = p.metadata['original_row_data'];
      if (nested is Map) {
        for (var key in nested.keys) {
          keySet.add(key.toString());
        }
      }
    }
    return keySet.toList()..sort();
  }

  /// [FA 핵심 기능] 전체 데이터 초기화
  void _showResetConfirmationDialog(PersonProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("데이터 전체 초기화",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        content: const Text("서버에 등록된 모든 인원 정보가 영구히 삭제됩니다.\n정말 진행하시겠습니까?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.resetAllPersons();
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('초기화가 완료되었습니다.')),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("전체 삭제"),
          ),
        ],
      ),
    );
  }

  /// [FA 핵심 기능] 엑셀 일괄 등록
  Future<void> _handleBatchImport(PersonProvider provider) async {
    final int count = await provider.batchImportFromExcel();
    if (!mounted) {
      return;
    }
    if (count > 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$count명의 데이터가 등록되었습니다.')));
    }
  }

  /// [FA 핵심 기능] 현재 리스트를 엑셀 파일로 추출
  Future<void> _exportToExcel(List<Person> dataList) async {
    if (dataList.isEmpty) {
      return;
    }
    try {
      var excel = excel_pkg.Excel.createExcel();
      excel_pkg.Sheet sheetObject = excel['인원리스트'];
      excel.rename('Sheet1', '인원리스트');

      List<String> metaKeys = _extractAvailableMetaKeys(dataList);
      List<String> headers = ['성명', '사번/코드', '부서/소속', 'RFID EPC', '비고'];
      headers.addAll(metaKeys);

      for (int i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(
            excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = excel_pkg.TextCellValue(headers[i]);
      }

      for (int rowIdx = 0; rowIdx < dataList.length; rowIdx++) {
        final p = dataList[rowIdx];
        List<String> rowData = [p.name, p.code, p.department, p.tagId, p.remarks];
        for (var key in metaKeys) {
          rowData.add(_getMetaValue(p, key));
        }
        for (int colIdx = 0; colIdx < rowData.length; colIdx++) {
          var cell = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(
              columnIndex: colIdx, rowIndex: rowIdx + 1));
          cell.value = excel_pkg.TextCellValue(rowData[colIdx]);
        }
      }

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '엑셀 파일 저장 위치 선택',
        fileName: '인원관리_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (!mounted) {
        return;
      }

      if (outputFile != null) {
        final bytes = excel.encode();
        if (bytes != null) {
          final file = File(outputFile);
          await file.create(recursive: true);
          await file.writeAsBytes(bytes);

          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('엑셀 파일이 저장되었습니다.')));
        }
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장 오류: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final personProvider = context.watch<PersonProvider>();
    final currentSelectedColumns = personProvider.selectedColumns;

    final filtered = personProvider.list.where((p) {
      bool matchesFilter = _currentFilter == '전체' ||
          (_currentFilter == '정상 등록' ? p.tagId.isNotEmpty : p.tagId.isEmpty);
      bool matchesSearch = HangulUtils.matches(_currentSearchQuery, p.name) ||
          p.code.toLowerCase().contains(_currentSearchQuery.toLowerCase()) ||
          p.department.toLowerCase().contains(_currentSearchQuery.toLowerCase());
      return matchesFilter && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text("인원 정보 관리",
            style: TextStyle(
                fontFamily: _fontPretendard, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
              onPressed: () => _showResetConfirmationDialog(personProvider),
              icon: const Icon(Icons.delete_sweep_outlined,
                  color: Colors.redAccent)),
          IconButton(
            onPressed: () => _handleBatchImport(personProvider),
            icon: const FaIcon(FontAwesomeIcons.fileExcel,
                color: Color(0xFF1D6F42), size: 20),
            tooltip: "엑셀 일괄 등록",
          ),
          IconButton(
            onPressed: () => _exportToExcel(filtered),
            icon: const FaIcon(FontAwesomeIcons.fileArrowDown,
                color: Color(0xFF1D6F42), size: 20),
            tooltip: "엑셀로 내보내기",
          ),
          IconButton(
            onPressed: () => personProvider.fetchData(),
            icon: personProvider.isLoading
                ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, color: Colors.indigo),
          ),
          IconButton(
              onPressed: () => _showColumnSelectionDialog(personProvider),
              icon: const Icon(Icons.settings_suggest_outlined,
                  color: Colors.indigo)),
          const SizedBox(width: 20),
        ],
      ),
      body: Column(
        children: [
          if (personProvider.isSaving || personProvider.isParsing)
            const LinearProgressIndicator(minHeight: 2, color: Colors.indigo),
          _buildSearchBar(),
          _buildFilterToggle(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                      color: Colors.indigo.withValues(alpha: 0.2), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(builder: (context, constraints) {
                  bool showFull = constraints.maxWidth > 750;
                  bool showMedium = constraints.maxWidth > 450;
                  return Column(
                    children: [
                      _buildHeader(showFull, showMedium, currentSelectedColumns),
                      const Divider(
                          height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
                      Expanded(
                        child: personProvider.isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _buildListView(filtered, personProvider, showFull,
                            showMedium, currentSelectedColumns),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context, personProvider, null),
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 5, 26, 5),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _currentSearchQuery = val),
        decoration: InputDecoration(
          labelText: '성명, 사번, 부서 검색',
          prefixIcon: const Icon(Icons.search, color: Colors.indigo, size: 20),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildFilterToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
      child: Row(
        children: ['전체', '정상 등록', '미등록'].map((m) {
          bool isSelected = _currentFilter == m;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ActionChip(
                label: Center(child: Text(m)),
                onPressed: () => setState(() => _currentFilter = m),
                backgroundColor: isSelected ? Colors.indigo : Colors.white,
                labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontSize: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeader(bool showFull, bool showMedium, List<String> columns) {
    const headerStyle = TextStyle(
        fontFamily: _fontPretendard,
        fontWeight: FontWeight.bold,
        fontSize: 13,
        color: Colors.black54);
    return Container(
      height: _rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: Colors.indigo.withValues(alpha: 0.04),
      child: Row(children: [
        const SizedBox(width: _colImgWidth, child: Text('사진', style: headerStyle)),
        const Expanded(flex: _flexName, child: Text('성명', style: headerStyle)),
        for (var colName in columns)
          Expanded(
              flex: _flexDynamic,
              child: Text(colName,
                  style: headerStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
        if (showMedium && columns.isEmpty)
          const Expanded(
              flex: _flexDept, child: Text('부서 / 거래처', style: headerStyle)),
        if (showFull)
          const Expanded(flex: _flexCode, child: Text('사번', style: headerStyle)),
        if (showMedium)
          const Expanded(
              flex: _flexEpc, child: Text('RFID EPC', style: headerStyle)),
        const SizedBox(
            width: _colActionWidth,
            child: Text('관리', textAlign: TextAlign.center, style: headerStyle)),
      ]),
    );
  }

  Widget _buildListView(List<Person> list, PersonProvider provider,
      bool showFull, bool showMedium, List<String> columns) {
    if (list.isEmpty) {
      return const Center(child: Text("표시할 데이터가 없습니다."));
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (ctx, idx) =>
      const Divider(height: 1, color: Color(0xFFF5F5F5)),
      itemBuilder: (context, index) {
        final item = list[index];
        return InkWell(
          onTap: () => _showForm(context, provider, item),
          child: Container(
            height: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SizedBox(
                    width: _colImgWidth,
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildAvatar(item))),
                Expanded(
                    flex: _flexName,
                    child: Text(item.name,
                        style: const TextStyle(
                            fontFamily: _fontPretendard,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: Color(0xFF1A237E)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                for (var colName in columns)
                  Expanded(
                      flex: _flexDynamic,
                      child: Text(_getMetaValue(item, colName),
                          style: const TextStyle(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                if (showMedium && columns.isEmpty)
                  Expanded(
                      flex: _flexDept,
                      child: Text(item.department,
                          style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                if (showFull)
                  Expanded(
                      flex: _flexCode,
                      child: Text(item.code, style: const TextStyle(fontSize: 12))),
                if (showMedium)
                  Expanded(
                      flex: _flexEpc,
                      child: Text(item.tagId.isEmpty ? "미등록" : item.tagId,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.indigo,
                              fontWeight: FontWeight.w500)))
                ,
                SizedBox(
                    width: _colActionWidth,
                    child: Center(
                        child: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent, size: 20),
                            onPressed: () =>
                                _confirmDelete(context, provider, item)))),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(Person item) {
    final url = item.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: Colors.black.withValues(alpha: 0.1), width: 0.5)),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network(url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
          const Icon(Icons.person, color: Colors.grey))
          : const Icon(Icons.camera_alt_outlined, color: Colors.grey, size: 18),
    );
  }

  void _showColumnSelectionDialog(PersonProvider provider) {
    final availableKeys = _extractAvailableMetaKeys(provider.list);
    List<String> tempSelection = List.from(provider.selectedColumns);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setDlgState) => AlertDialog(
            title: const Text("표시 항목 설정"),
            content: SizedBox(
              width: 400,
              child: availableKeys.isEmpty
                  ? const Text("필드가 없습니다.")
                  : SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: availableKeys
                        .map((key) => CheckboxListTile(
                      title: Text(key),
                      value: tempSelection.contains(key),
                      onChanged: (val) {
                        setDlgState(() {
                          if (val == true) {
                            if (tempSelection.length < 5) {
                              tempSelection.add(key);
                            }
                          } else {
                            tempSelection.remove(key);
                          }
                        });
                      },
                    ))
                        .toList()),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("취소")),
              ElevatedButton(
                  onPressed: () async {
                    await provider.saveRemoteSettings(tempSelection);
                    if (!ctx.mounted) {
                      return;
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text("적용"))
            ],
          )),
    );
  }

  Widget _buildField(String label, TextEditingController c) {
    return TextField(
      controller: c,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
              fontSize: 12, color: Colors.indigo, fontWeight: FontWeight.bold),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
          filled: true,
          fillColor: Colors.grey.withValues(alpha: 0.02)),
    );
  }

  Future<void> _showForm(
      BuildContext context, PersonProvider provider, Person? p) async {
    final nameC = TextEditingController(text: p?.name ?? "");
    final codeC = TextEditingController(text: p?.code ?? "");
    final tagC = TextEditingController(text: p?.tagId ?? "");
    final deptC = TextEditingController(text: p?.department ?? "");
    final remarksC = TextEditingController(text: p?.remarks ?? "");
    bool isActive = p?.isActive ?? true;
    XFile? pickedFile;
    Uint8List? previewBytes;

    final Map<String, TextEditingController> metaControllers = {};
    if (p != null) {
      for (var key in p.metadata.keys) {
        if (key != 'original_row_data' && key != 'import_source') {
          metaControllers[key] =
              TextEditingController(text: p.metadata[key]?.toString() ?? "");
        }
      }
      final dynamic nested = p.metadata['original_row_data'];
      if (nested is Map) {
        for (var key in nested.keys) {
          final String keyStr = key.toString();
          if (!metaControllers.containsKey(keyStr)) {
            metaControllers[keyStr] =
                TextEditingController(text: nested[key]?.toString() ?? "");
          }
        }
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
        Widget imageWidget =
        const Icon(Icons.camera_alt_outlined, color: Colors.grey, size: 40);
        if (previewBytes != null) {
          imageWidget = ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(previewBytes!, fit: BoxFit.cover));
        } else if (p != null && p.image != null && p.image!.isNotEmpty) {
          final String? url = p.getImageUrl(widget.baseUrl);
          if (url != null) {
            imageWidget = ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(url, fit: BoxFit.cover));
          }
        }

        return AlertDialog(
          title: Text(p == null ? '신규 등록' : '수정'),
          content: SizedBox(
              width: 700,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Column(children: [
                        GestureDetector(
                          onTap: () async {
                            final picker = ImagePicker();
                            final img =
                            await picker.pickImage(source: ImageSource.gallery);
                            if (img != null) {
                              final b = await img.readAsBytes();
                              setDialogState(() {
                                pickedFile = img;
                                previewBytes = b;
                              });
                            }
                          },
                          child: Container(
                              width: 140,
                              height: 160,
                              decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(10)),
                              child: Center(child: imageWidget)),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          const Text("활성",
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                          Switch(
                              value: isActive,
                              onChanged: (v) => setDialogState(() => isActive = v))
                        ]),
                      ]),
                      const SizedBox(width: 20),
                      Expanded(
                          child: Column(children: [
                            _buildField("성명", nameC),
                            const SizedBox(height: 12),
                            _buildField("부서", deptC),
                            const SizedBox(height: 12),
                            _buildField("사번", codeC),
                            const SizedBox(height: 12),
                            _buildField("RFID 태그", tagC),
                            const SizedBox(height: 12),
                            _buildField("비고", remarksC)
                          ])),
                    ]),
                    if (metaControllers.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Divider(),
                      const Align(
                          alignment: Alignment.centerLeft, child: Text("추가 정보")),
                      Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: metaControllers.entries
                              .map((e) => SizedBox(
                              width: 210, child: _buildField(e.key, e.value)))
                              .toList())
                    ]
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
            ElevatedButton(
                onPressed: provider.isSaving
                    ? null
                    : () async {
                  if (nameC.text.trim().isEmpty) {
                    return;
                  }
                  Map<String, dynamic> updatedMeta =
                  Map<String, dynamic>.from(p?.metadata ?? {});
                  Map<String, dynamic> originalRow =
                  updatedMeta['original_row_data'] is Map
                      ? Map<String, dynamic>.from(
                      updatedMeta['original_row_data'])
                      : {};
                  metaControllers.forEach((k, v) {
                    if (originalRow.containsKey(k)) {
                      originalRow[k] = v.text.trim();
                    } else {
                      updatedMeta[k] = v.text.trim();
                    }
                  });
                  if (originalRow.isNotEmpty) {
                    updatedMeta['original_row_data'] = originalRow;
                  }
                  final data = {
                    'name': nameC.text.trim(),
                    'code': codeC.text.trim(),
                    'tag_id': tagC.text.trim(),
                    'department': deptC.text.trim(),
                    'is_active': isActive,
                    'remarks': remarksC.text.trim(),
                    'metadata': updatedMeta
                  };
                  final success = await provider.handleSave(
                      p: p, data: data, imageXFile: pickedFile);
                  if (!ctx.mounted) {
                    return;
                  }
                  if (success) {
                    Navigator.pop(ctx);
                  }
                },
                child: Text(provider.isSaving ? "저장 중..." : "저장")),
          ],
        );
      }),
    );
  }

  void _confirmDelete(BuildContext context, PersonProvider provider, Person p) {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
            title: const Text("삭제 확인"),
            content: Text("${p.name}님의 정보를 삭제하시겠습니까?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text("취소")),
              ElevatedButton(
                  onPressed: () async {
                    final success = await provider.deletePerson(p.id);
                    if (!c.mounted) {
                      return;
                    }
                    if (success) {
                      Navigator.pop(c);
                    }
                  },
                  child: const Text("삭제"))
            ]));
  }
}