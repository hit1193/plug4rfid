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

/// 전역 폰트 및 스타일 상수
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

  // 테이블 레이아웃 수치 정의
  static const double _rowHeight = 56.0;
  static const double _colImgWidth = 70.0;
  static const double _colActionWidth = 80.0;
  static const int _flexName = 4;
  static const int _flexDynamic = 4;
  static const int _flexDept = 5;
  static const int _flexCode = 3;
  static const int _flexRFID = 6;

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

  // 데이터 가공 헬퍼
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

  List<String> _extractAvailableMetaKeys(List<Person> list) {
    final Set<String> keySet = {};
    const systemKeys = {
      'import_source', 'original_row_data', 'id', 'created', 'updated', 'collectionId', 'collectionName'
    };
    for (final p in list) {
      for (final key in p.metadata.keys) {
        if (!systemKeys.contains(key)) keySet.add(key);
      }
      final dynamic nested = p.metadata['original_row_data'];
      if (nested is Map) {
        for (final key in nested.keys) {
          keySet.add(key.toString());
        }
      }
    }
    return keySet.toList()..sort();
  }

  // 비동기 작업 시 Context 안전 처리 패턴
  Future<void> _showResetConfirmationDialog(PersonProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("데이터 전체 초기화", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        content: const Text("서버의 모든 인원 정보가 영구 삭제됩니다.\n정말 진행하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("전체 삭제"),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await provider.resetAllPersons();
      messenger.showSnackBar(const SnackBar(content: Text('데이터가 초기화되었습니다.')));
    }
  }

  Future<void> _handleBatchImport(PersonProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    final int count = await provider.batchImportFromExcel();
    if (count > 0) {
      messenger.showSnackBar(SnackBar(content: Text('$count명의 데이터가 등록되었습니다.')));
    }
  }

  Future<void> _exportToExcel(List<Person> dataList) async {
    if (dataList.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheetObject = excel['인원리스트'];
      excel.rename('Sheet1', '인원리스트');
      final metaKeys = _extractAvailableMetaKeys(dataList);
      final headers = ['성명', '사번/코드', '부서/소속', 'RFID EPC', '비고', ...metaKeys];

      for (int i = 0; i < headers.length; i++) {
        sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = excel_pkg.TextCellValue(headers[i]);
      }
      for (int rowIdx = 0; rowIdx < dataList.length; rowIdx++) {
        final p = dataList[rowIdx];
        final rowData = [p.name, p.code, p.department, p.tagId, p.remarks];
        for (final key in metaKeys) rowData.add(_getMetaValue(p, key));
        for (int colIdx = 0; colIdx < rowData.length; colIdx++) {
          sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIdx + 1))
              .value = excel_pkg.TextCellValue(rowData[colIdx]);
        }
      }
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '엑셀 파일 저장 위치 선택',
        fileName: '인원관리_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (outputFile != null) {
        final bytes = excel.encode();
        if (bytes != null) {
          await File(outputFile).writeAsBytes(bytes);
          messenger.showSnackBar(const SnackBar(content: Text('엑셀 파일이 저장되었습니다.')));
        }
      }
    } catch (e) { messenger.showSnackBar(SnackBar(content: Text('저장 오류: $e'))); }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PersonProvider>();
    final columns = provider.selectedColumns;

    final filteredList = provider.list.where((p) {
      final matchesFilter = _currentFilter == '전체' ||
          (_currentFilter == '정상 등록' ? p.tagId.isNotEmpty : p.tagId.isEmpty);
      final matchesSearch = HangulUtils.matches(_currentSearchQuery, p.name) ||
          p.code.toLowerCase().contains(_currentSearchQuery.toLowerCase()) ||
          p.department.toLowerCase().contains(_currentSearchQuery.toLowerCase());
      return matchesFilter && matchesSearch;
    }).toList();

    if (widget.isMobile) {
      return _buildMobileLayout(provider, filteredList);
    } else {
      return _buildDesktopLayout(provider, filteredList, columns);
    }
  }

  // --- 데스크톱 레이아웃 (반응형 컬럼 적용) ---
  Widget _buildDesktopLayout(PersonProvider provider, List<Person> filteredList, List<String> columns) {
    return LayoutBuilder(
        builder: (context, constraints) {
          final double width = constraints.maxWidth;

          return Container(
            color: Colors.white,
            child: Column(
              children: [
                _buildCustomAppBar(provider, filteredList, width),
                SizedBox(
                  height: 2,
                  child: (provider.isSaving || provider.isParsing)
                      ? const LinearProgressIndicator(color: Colors.indigo)
                      : const SizedBox.shrink(),
                ),
                _buildFilterToggle(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 40),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 15, offset: const Offset(0, 5))
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _buildHeader(columns, width),
                          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                          Expanded(
                            child: provider.isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : RepaintBoundary(
                              child: _buildListView(filteredList, provider, columns, width),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
    );
  }

  // --- 모바일 레이아웃 ---
  Widget _buildMobileLayout(PersonProvider provider, List<Person> filteredList) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          _buildMobileTopBar(provider, filteredList),
          _buildFilterToggle(),
          if (provider.isSaving || provider.isParsing) const LinearProgressIndicator(minHeight: 2, color: Colors.indigo),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : RepaintBoundary(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: filteredList.length,
                itemBuilder: (ctx, idx) => _buildMobileCard(filteredList[idx], provider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTopBar(PersonProvider provider, List<Person> filteredList) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('인원 관리', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF1E293B))),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.refresh, color: Colors.indigo, size: 22), onPressed: () => provider.fetchData()),
                  IconButton(icon: const Icon(Icons.add_circle, color: Colors.indigo, size: 26), onPressed: () => _showForm(context, provider, null)),
                ],
              )
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _currentSearchQuery = val),
              decoration: InputDecoration(
                hintText: '성명 또는 사번 검색...',
                prefixIcon: const Icon(Icons.search, size: 20, color: Colors.indigo),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCard(Person p, PersonProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: InkWell(
        onTap: () => _showForm(context, provider, p),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              _buildAvatar(p),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B))),
                    const SizedBox(height: 4),
                    Text('${p.department} | ${p.code}', style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.tagId.isEmpty ? Colors.orange.withValues(alpha: 0.1) : Colors.indigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        p.tagId.isEmpty ? 'RFID 미등록' : 'EPC: ${p.tagId}',
                        style: TextStyle(
                            fontSize: 11,
                            color: p.tagId.isEmpty ? Colors.orange.shade800 : Colors.indigo.shade800,
                            fontWeight: FontWeight.w700
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                onPressed: () => _confirmDelete(context, provider, p),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 공용 위젯 ---

  Widget _buildCustomAppBar(PersonProvider provider, List<Person> filtered, double width) {
    final bool isNarrow = width < 800;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _currentSearchQuery = val),
                style: const TextStyle(fontFamily: _fontPretendard, fontSize: 14),
                decoration: InputDecoration(
                  hintText: isNarrow ? '검색...' : '성명, 사번, 부서 통합 검색...',
                  prefixIcon: const Icon(Icons.search, color: Colors.indigo, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          _buildAppBarIcon(Icons.delete_sweep_outlined, Colors.redAccent, "전체 초기화", () => _showResetConfirmationDialog(provider)),
          _buildAppBarIcon(FontAwesomeIcons.fileExcel, const Color(0xFF1D6F42), "엑셀 업로드", () => _handleBatchImport(provider), isFA: true),
          _buildAppBarIcon(FontAwesomeIcons.fileArrowDown, const Color(0xFF1D6F42), "엑셀 다운로드", () => _exportToExcel(filtered), isFA: true),
          _buildAppBarIcon(Icons.refresh, Colors.indigo, "새로고침", () => provider.fetchData()),
          _buildAppBarIcon(Icons.settings_suggest_outlined, Colors.indigo, "컬럼 설정", () => _showColumnSelectionDialog(provider)),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _showForm(context, provider, null),
            icon: const Icon(Icons.add, size: 18),
            label: Text(isNarrow ? "추가" : "인원 추가"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarIcon(IconData icon, Color color, String tooltip, VoidCallback onTap, {bool isFA = false}) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: isFA ? FaIcon(icon, color: color, size: 18) : Icon(icon, color: color, size: 22),
    );
  }

  Widget _buildFilterToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: ['전체', '정상 등록', '미등록'].map((m) {
          final isSelected = _currentFilter == m;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(m, style: TextStyle(fontFamily: _fontPretendard, fontSize: 13, color: isSelected ? Colors.white : Colors.black87)),
              selected: isSelected,
              onSelected: (val) { if (val) setState(() => _currentFilter = m); },
              selectedColor: Colors.indigo,
              backgroundColor: const Color(0xFFF1F5F9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              side: BorderSide.none,
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeader(List<String> columns, double width) {
    const headerStyle = TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54);

    return Container(
      height: _rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          const SizedBox(width: _colImgWidth, child: Text('사진', style: headerStyle)),
          const Expanded(flex: _flexName, child: Text('성명', style: headerStyle)),

          if (width > 1000)
            for (final colName in columns)
              Expanded(flex: _flexDynamic, child: Text(colName, style: headerStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),

          if (width > 700)
            const Expanded(flex: _flexDept, child: Text('부서 / 소속', style: headerStyle)),

          if (width > 500)
            const Expanded(flex: _flexCode, child: Text('사번', style: headerStyle)),

          const Expanded(flex: _flexRFID, child: Text('RFID EPC', style: headerStyle)),
          const SizedBox(width: _colActionWidth, child: Text('관리', textAlign: TextAlign.center, style: headerStyle)),
        ],
      ),
    );
  }

  Widget _buildListView(List<Person> list, PersonProvider provider, List<String> columns, double width) {
    if (list.isEmpty) return const Center(child: Text("표시할 데이터가 없습니다."));

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (ctx, idx) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
      itemBuilder: (context, index) {
        final item = list[index];
        return InkWell(
          onTap: () => _showForm(context, provider, item),
          child: Container(
            height: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SizedBox(width: _colImgWidth, child: Align(alignment: Alignment.centerLeft, child: _buildAvatar(item))),
                Expanded(
                    flex: _flexName,
                    child: Text(item.name,
                        style: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF1E293B)),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),

                if (width > 1000)
                  for (final colName in columns)
                    Expanded(flex: _flexDynamic, child: Text(_getMetaValue(item, colName), style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),

                if (width > 700)
                  Expanded(flex: _flexDept, child: Text(item.department, style: const TextStyle(fontSize: 12, color: Colors.blueGrey), maxLines: 1, overflow: TextOverflow.ellipsis)),

                if (width > 500)
                  Expanded(flex: _flexCode, child: Text(item.code, style: const TextStyle(fontSize: 12))),

                Expanded(flex: _flexRFID, child: Text(item.tagId.isEmpty ? "미등록" : item.tagId, style: const TextStyle(fontSize: 12, color: Colors.indigo, fontWeight: FontWeight.w600))),
                SizedBox(width: _colActionWidth, child: Center(child: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), onPressed: () => _confirmDelete(context, provider, item)))),
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
      width: 44, height: 44,
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black.withValues(alpha: 0.05))),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.grey))
          : const Icon(Icons.camera_alt_outlined, color: Colors.grey, size: 18),
    );
  }

  void _showColumnSelectionDialog(PersonProvider provider) {
    final availableKeys = _extractAvailableMetaKeys(provider.list);
    final List<String> tempSelection = List.from(provider.selectedColumns);
    final nav = Navigator.of(context);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setDlgState) => AlertDialog(
            title: const Text("표시 항목 설정"),
            content: SizedBox(
              width: 400,
              child: availableKeys.isEmpty ? const Text("필드가 없습니다.") : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: availableKeys.map((key) => CheckboxListTile(title: Text(key), value: tempSelection.contains(key), onChanged: (val) {
                  setDlgState(() { if (val == true) { if (tempSelection.length < 5) tempSelection.add(key); } else { tempSelection.remove(key); } });
                })).toList()),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
              ElevatedButton(onPressed: () async { await provider.saveRemoteSettings(tempSelection); nav.pop(); }, child: const Text("적용")),
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
          labelStyle: const TextStyle(fontSize: 12, color: Colors.indigo, fontWeight: FontWeight.bold),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
          filled: true,
          fillColor: Colors.grey.withValues(alpha: 0.02)),
    );
  }

  Future<void> _showForm(BuildContext context, PersonProvider provider, Person? p) async {
    final nav = Navigator.of(context);
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
      for (final key in p.metadata.keys) {
        if (key != 'original_row_data' && key != 'import_source') metaControllers[key] = TextEditingController(text: p.metadata[key]?.toString() ?? "");
      }
      final dynamic nested = p.metadata['original_row_data'];
      if (nested is Map) {
        for (final key in nested.keys) {
          final keyStr = key.toString();
          if (!metaControllers.containsKey(keyStr)) metaControllers[keyStr] = TextEditingController(text: nested[key]?.toString() ?? "");
        }
      }
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
        Widget imageWidget = const Icon(Icons.camera_alt_outlined, color: Colors.grey, size: 40);
        if (previewBytes != null) {
          imageWidget = ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(previewBytes!, fit: BoxFit.cover));
        } else if (p?.image != null && p!.image!.isNotEmpty) {
          final url = p.getImageUrl(widget.baseUrl);
          if (url != null) imageWidget = ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, fit: BoxFit.cover));
        }
        return AlertDialog(
          title: Text(p == null ? '신규 등록' : '정보 수정'),
          content: SizedBox(width: 700, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(children: [
                GestureDetector(onTap: () async {
                  final img = await ImagePicker().pickImage(source: ImageSource.gallery);
                  if (img != null) { final b = await img.readAsBytes(); setDialogState(() { pickedFile = img; previewBytes = b; }); }
                }, child: Container(width: 140, height: 160, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)), child: Center(child: imageWidget))),
                const SizedBox(height: 12),
                Row(children: [ const Text("활성", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), Switch(value: isActive, onChanged: (v) => setDialogState(() => isActive = v)) ]),
              ]),
              const SizedBox(width: 20),
              Expanded(child: Column(children: [ _buildField("성명", nameC), const SizedBox(height: 12), _buildField("부서", deptC), const SizedBox(height: 12), _buildField("사번", codeC), const SizedBox(height: 12), _buildField("RFID 태그", tagC), const SizedBox(height: 12), _buildField("비고", remarksC) ])),
            ]),
            if (metaControllers.isNotEmpty) ...[ const SizedBox(height: 20), const Divider(), const Align(alignment: Alignment.centerLeft, child: Text("추가 정보")), Wrap(spacing: 12, runSpacing: 12, children: metaControllers.entries.map((e) => SizedBox(width: 210, child: _buildField(e.key, e.value))).toList()) ]
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
            ElevatedButton(onPressed: provider.isSaving ? null : () async {
              if (nameC.text.trim().isEmpty) return;
              final updatedMeta = Map<String, dynamic>.from(p?.metadata ?? {});
              final originalRow = updatedMeta['original_row_data'] is Map ? Map<String, dynamic>.from(updatedMeta['original_row_data']) : <String, dynamic>{};
              metaControllers.forEach((k, v) { if (originalRow.containsKey(k)) { originalRow[k] = v.text.trim(); } else { updatedMeta[k] = v.text.trim(); } });
              if (originalRow.isNotEmpty) updatedMeta['original_row_data'] = originalRow;
              final data = {
                'name': nameC.text.trim(),
                'code': codeC.text.trim(),
                'tag_id': tagC.text.trim(), // tag_id 에러 해결
                'department': deptC.text.trim(),
                'is_active': isActive,
                'remarks': remarksC.text.trim(),
                'metadata': updatedMeta
              };
              final success = await provider.handleSave(p: p, data: data, imageXFile: pickedFile);
              if (success) nav.pop();
            }, child: Text(provider.isSaving ? "저장 중..." : "저장")),
          ],
        );
      }),
    );
  }

  void _confirmDelete(BuildContext context, PersonProvider provider, Person p) {
    final nav = Navigator.of(context);
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("삭제 확인"), content: Text("${p.name}님의 정보를 삭제하시겠습니까?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")),
        ElevatedButton(onPressed: () async { final success = await provider.deletePerson(p.id); if (success) nav.pop(); }, child: const Text("삭제")),
      ],
    ),
    );
  }
}