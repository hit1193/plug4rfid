import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/persons.dart';
import '../utils/hangul_utils.dart';
import '../providers/person_provider.dart';

/// 전역 폰트 및 스타일 상수
const String _fontPretendard = 'Pretendard';
const Color _primaryColor = Color(0xFF6366F1);
const Color _successColor = Color(0xFF10B981);
const Color _warningColor = Color(0xFFF59E0B);

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

  static const double _rowHeight = 56.0;
  static const double _colImgWidth = 70.0;
  static const double _colActionWidth = 120.0;
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

  Future<void> _processAccessWithLocation(PersonProvider provider, Person p, String type) async {
    final messenger = ScaffoldMessenger.of(context);

    final Map<String, String>? location = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _LocationSelectionDialog(
        type: type,
        existingPersons: provider.list,
      ),
    );

    if (!mounted || location == null) {
      return;
    }

    final String now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final String building = location['building']?.trim() ?? "미지정";
    final String gate = location['gate']?.trim() ?? "미지정";

    final updatedMeta = Map<String, dynamic>.from(p.metadata);
    updatedMeta['last_access_type'] = type;
    updatedMeta['last_access_time'] = now;
    updatedMeta['last_location_info'] = {
      'building': building,
      'gate': gate,
      'full_name': "$building - $gate"
    };

    List<dynamic> history = updatedMeta['access_history'] is List
        ? List.from(updatedMeta['access_history'])
        : [];

    history.insert(0, {
      'time': now,
      'type': type,
      'mode': '수동',
      'location': {'building': building, 'gate': gate}
    });

    if (history.length > 20) {
      history = history.sublist(0, 20);
    }
    updatedMeta['access_history'] = history;

    final data = {'metadata': updatedMeta};
    final success = await provider.handleSave(p: p, data: data);

    if (!mounted) {
      return;
    }
    if (success) {
      messenger.showSnackBar(SnackBar(
        content: Text('[${p.name}]님 $building $gate $type 처리 완료'),
        backgroundColor: type == '입장' ? _successColor : _warningColor,
        duration: const Duration(seconds: 1),
      ));
    }
  }

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
      'import_source', 'original_row_data', 'id', 'created', 'updated', 'collectionId', 'collectionName',
      'last_access_type', 'last_access_time', 'access_history', 'last_location_info'
    };
    for (final p in list) {
      for (final key in p.metadata.keys) {
        if (!systemKeys.contains(key)) {
          keySet.add(key);
        }
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
    if (!mounted || confirm != true) {
      return;
    }
    await provider.resetAllPersons();
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('데이터가 초기화되었습니다.')));
  }

  Future<void> _handleBatchImport(PersonProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    final int count = await provider.batchImportFromExcel();
    if (!mounted) {
      return;
    }
    if (count > 0) {
      messenger.showSnackBar(SnackBar(content: Text('$count명의 데이터가 등록되었습니다.')));
    }
  }

  Future<void> _exportToExcel(List<Person> dataList) async {
    if (dataList.isEmpty) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheetObject = excel['인원리스트'];
      excel.rename('Sheet1', '인원리스트');
      final metaKeys = _extractAvailableMetaKeys(dataList);
      final headers = ['성명', '사번/코드', '부서/소속', 'RFID EPC', '비고', ...metaKeys];
      for (int i = 0; i < headers.length; i++) {
        sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = excel_pkg.TextCellValue(headers[i]);
      }
      for (int rowIdx = 0; rowIdx < dataList.length; rowIdx++) {
        final p = dataList[rowIdx];
        final rowData = [p.name, p.code, p.department, p.tagId, p.remarks];
        for (final key in metaKeys) {
          rowData.add(_getMetaValue(p, key));
        }
        for (int colIdx = 0; colIdx < rowData.length; colIdx++) {
          sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIdx + 1)).value = excel_pkg.TextCellValue(rowData[colIdx]);
        }
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '엑셀 파일 저장 위치 선택',
        fileName: '인원관리_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (!mounted || path == null) {
        return;
      }
      final bytes = excel.encode();
      if (bytes != null) {
        await File(path).writeAsBytes(bytes);
        if (!mounted) {
          return;
        }
        messenger.showSnackBar(const SnackBar(content: Text('엑셀 파일이 저장되었습니다.')));
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('저장 오류: $e')));
    }
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

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: _fontPretendard),
      ),
      child: widget.isMobile
          ? _buildMobileLayout(provider, filteredList)
          : _buildDesktopLayout(provider, filteredList, columns),
    );
  }

  Widget _buildDesktopLayout(PersonProvider provider, List<Person> filteredList, List<String> columns) {
    return LayoutBuilder(builder: (context, constraints) {
      final double width = constraints.maxWidth;
      return Container(
        color: Colors.white,
        child: Column(
          children: [
            _buildCustomAppBar(provider, filteredList, width),
            _buildFilterToggle(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _buildHeader(columns, width),
                      const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                      Expanded(
                        child: provider.isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _buildListView(filteredList, provider, columns, width),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildMobileLayout(PersonProvider provider, List<Person> filteredList) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          _buildMobileTopBar(provider, filteredList),
          _buildFilterToggle(),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: filteredList.length,
              itemBuilder: (ctx, idx) => _buildMobileCard(filteredList[idx], provider),
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
              const Text('인원 관리', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              Row(children: [
                IconButton(icon: const Icon(Icons.refresh, color: _primaryColor), onPressed: () => provider.fetchData()),
                IconButton(icon: const Icon(Icons.add_circle, color: _primaryColor, size: 26), onPressed: () => _showForm(context, provider, null)),
              ])
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, _) {
                return TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _currentSearchQuery = val),
                  decoration: InputDecoration(
                    hintText: '성명 또는 사번 검색...',
                    hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.3)),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    // [수정됨] 모바일 취소 아이콘 크기 및 제약사항 조정
                    suffixIcon: value.text.isNotEmpty
                        ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.clear, size: 22, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _currentSearchQuery = "");
                        },
                      ),
                    )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                );
              }
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCard(Person p, PersonProvider provider) {
    final String currentStatus = p.metadata['last_access_type'] ?? "미확인";
    String locationText = "위치 정보 없음";
    final locInfo = p.metadata['last_location_info'];
    if (locInfo is Map) {
      locationText = locInfo['full_name'] ?? locationText;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
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
                    Row(
                      children: [
                        Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(width: 8),
                        _buildStatusBadge(currentStatus),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${p.department} | ${p.code}', style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(locationText, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.login, color: _successColor, size: 20), onPressed: () => _processAccessWithLocation(provider, p, '입장')),
                      IconButton(icon: const Icon(Icons.logout, color: _warningColor, size: 20), onPressed: () => _processAccessWithLocation(provider, p, '퇴장')),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18), onPressed: () => _confirmDelete(context, provider, p)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.grey;
    if (status == '입장') {
      color = _successColor;
    }
    if (status == '퇴장') {
      color = _warningColor;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCustomAppBar(PersonProvider provider, List<Person> filtered, double width) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, value, _) {
                  return TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _currentSearchQuery = val),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '성명, 사번, 부서 검색...',
                      hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.3), fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: _primaryColor),
                      // [핵심 수정] 데스크톱 취소 아이콘이 가려지지 않도록 제약사항 및 패딩 제거
                      suffixIcon: value.text.isNotEmpty
                          ? Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.clear, size: 20, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _currentSearchQuery = "");
                          },
                        ),
                      )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  );
                }
            ),
          ),
          const SizedBox(width: 16),
          _buildAppBarIcon(Icons.delete_sweep_outlined, Colors.redAccent, "전체 초기화", () => _showResetConfirmationDialog(provider)),
          _buildAppBarIcon(FontAwesomeIcons.fileExcel, const Color(0xFF1D6F42), "엑셀 업로드", () => _handleBatchImport(provider), isFA: true),
          _buildAppBarIcon(FontAwesomeIcons.fileArrowDown, const Color(0xFF1D6F42), "엑셀 다운로드", () => _exportToExcel(filtered), isFA: true),
          _buildAppBarIcon(Icons.refresh, _primaryColor, "새로고침", () => provider.fetchData()),
          _buildAppBarIcon(Icons.settings_suggest_outlined, _primaryColor, "컬럼 설정", () => _showColumnSelectionDialog(provider)),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _showForm(context, provider, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text("인원 추가"),
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarIcon(IconData icon, Color color, String tooltip, VoidCallback onTap, {bool isFA = false}) {
    return IconButton(onPressed: onTap, tooltip: tooltip, icon: isFA ? FaIcon(icon, color: color, size: 18) : Icon(icon, color: color, size: 22));
  }

  void _showColumnSelectionDialog(PersonProvider provider) {
    final availableKeys = _extractAvailableMetaKeys(provider.list);
    final List<String> tempSelection = List.from(provider.selectedColumns);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setDlgState) => AlertDialog(
            title: const Text("표시 항목 설정"),
            content: SizedBox(
              width: 400,
              child: availableKeys.isEmpty
                  ? const Text("추가 필드가 없습니다.")
                  : SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: availableKeys.map((key) => CheckboxListTile(
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
                        }
                    )).toList()
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
              ElevatedButton(onPressed: () async {
                await provider.saveRemoteSettings(tempSelection);
                if (!context.mounted) {
                  return;
                }
                Navigator.pop(ctx);
              }, child: const Text("적용")),
            ],
          )
      ),
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
              label: Text(m, style: TextStyle(fontSize: 13, color: isSelected ? Colors.white : Colors.black87)),
              selected: isSelected,
              onSelected: (bool selected) {
                if (selected) {
                  setState(() => _currentFilter = m);
                }
              },
              selectedColor: _primaryColor,
              backgroundColor: const Color(0xFFF1F5F9),
              showCheckmark: false,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)), side: BorderSide.none),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeader(List<String> columns, double width) {
    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54);
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          const SizedBox(width: _colImgWidth, child: Text('사진', style: headerStyle)),
          const Expanded(flex: _flexName, child: Text('성명/상태', style: headerStyle)),
          if (width > 900)
            for (var colName in columns)
              Expanded(flex: _flexDynamic, child: Text(colName, style: headerStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (width > 700)
            const Expanded(flex: _flexDept, child: Text('부서', style: headerStyle)),
          if (width > 500)
            const Expanded(flex: _flexCode, child: Text('사번', style: headerStyle)),
          const Expanded(flex: _flexRFID, child: Text('RFID EPC', style: headerStyle)),
          const SizedBox(width: _colActionWidth, child: Text('관리', textAlign: TextAlign.center, style: headerStyle)),
        ],
      ),
    );
  }

  Widget _buildListView(List<Person> list, PersonProvider provider, List<String> columns, double width) {
    if (list.isEmpty) {
      return const Center(child: Text("표시할 데이터가 없습니다."));
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (ctx, idx) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
      itemBuilder: (context, index) {
        final item = list[index];
        final String currentStatus = item.metadata['last_access_type'] ?? "미확인";
        String locationDisplay = "-";
        final locInfo = item.metadata['last_location_info'];
        if (locInfo is Map) {
          locationDisplay = locInfo['full_name'] ?? "-";
        }

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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        const SizedBox(width: 8),
                        _buildStatusBadge(currentStatus),
                      ]),
                      Text(locationDisplay, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ),
                if (width > 900)
                  for (var colName in columns)
                    Expanded(flex: _flexDynamic, child: Text(_getMetaValue(item, colName), style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (width > 700)
                  Expanded(flex: _flexDept, child: Text(item.department, style: const TextStyle(fontSize: 12, color: Colors.blueGrey), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (width > 500)
                  Expanded(flex: _flexCode, child: Text(item.code, style: const TextStyle(fontSize: 12))),
                Expanded(flex: _flexRFID, child: Text(item.tagId.isEmpty ? "미등록" : item.tagId, style: const TextStyle(fontSize: 12, color: _primaryColor, fontWeight: FontWeight.w600))),
                SizedBox(
                  width: _colActionWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(icon: const Icon(Icons.login, color: _successColor, size: 18), onPressed: () => _processAccessWithLocation(provider, item, '입장'), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                      const SizedBox(width: 8),
                      IconButton(icon: const Icon(Icons.logout, color: _warningColor, size: 18), onPressed: () => _processAccessWithLocation(provider, item, '퇴장'), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                      const SizedBox(width: 8),
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18), onPressed: () => _confirmDelete(context, provider, item), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                    ],
                  ),
                ),
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

  Widget _buildField(String label, TextEditingController c, {String? hint}) {
    return TextField(
      controller: c,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal, color: Colors.grey),
        labelStyle: const TextStyle(fontSize: 12, color: _primaryColor, fontWeight: FontWeight.bold),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade400, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _primaryColor, width: 2.0),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Future<void> _showForm(BuildContext context, PersonProvider provider, Person? p) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

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
      const sysKeys = {'original_row_data', 'import_source', 'last_access_type', 'last_access_time', 'access_history', 'last_location_info'};
      for (final key in p.metadata.keys) {
        if (!sysKeys.contains(key)) {
          metaControllers[key] = TextEditingController(text: p.metadata[key]?.toString() ?? "");
        }
      }
      final dynamic nested = p.metadata['original_row_data'];
      if (nested is Map) {
        for (final key in nested.keys) {
          final keyStr = key.toString();
          if (!sysKeys.contains(keyStr) && !metaControllers.containsKey(keyStr)) {
            metaControllers[keyStr] = TextEditingController(text: nested[key]?.toString() ?? "");
          }
        }
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (dialogCtx, setDialogState) {
        Widget imageWidget = const Icon(Icons.camera_alt_outlined, color: Colors.grey, size: 40);
        if (previewBytes != null) {
          imageWidget = ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(previewBytes!, fit: BoxFit.cover));
        } else if (p?.image != null && p!.image!.isNotEmpty) {
          final url = p.getImageUrl(widget.baseUrl);
          if (url != null) {
            imageWidget = ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, fit: BoxFit.cover));
          }
        }

        Future<void> handlePhotoSelection() async {
          final source = await showModalBottomSheet<String>(
            context: dialogCtx,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (ctx) => SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.camera_alt, color: _primaryColor),
                    title: const Text('카메라로 촬영', style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => Navigator.pop(ctx, 'camera'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library, color: Colors.green),
                    title: const Text('갤러리/파일에서 선택', style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => Navigator.pop(ctx, 'gallery'),
                  ),
                ],
              ),
            ),
          );

          if (!dialogCtx.mounted || source == null) {
            return;
          }

          if (source == 'camera') {
            if (Platform.isWindows) {
              try {
                final cameras = await availableCameras();
                if (cameras.isEmpty) {
                  throw Exception("인식된 카메라 장치가 없습니다.");
                }
                if (!dialogCtx.mounted) {
                  return;
                }

                final XFile? result = await showDialog<XFile>(
                  context: dialogCtx,
                  builder: (ctx) => _CameraCaptureDialog(cameras: cameras),
                );

                if (!dialogCtx.mounted || result == null) {
                  return;
                }
                final bytes = await result.readAsBytes();
                setDialogState(() { pickedFile = result; previewBytes = bytes; });
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('카메라 오류: $e')));
              }
            } else {
              final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
              if (!dialogCtx.mounted || img == null) {
                return;
              }
              final bytes = await img.readAsBytes();
              setDialogState(() { pickedFile = img; previewBytes = bytes; });
            }
          } else {
            final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
            if (!dialogCtx.mounted || img == null) {
              return;
            }
            final bytes = await img.readAsBytes();
            setDialogState(() { pickedFile = img; previewBytes = bytes; });
          }
        }

        return AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)), side: BorderSide.none),
          title: Text(p == null ? '신규 등록' : '정보 수정', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
              width: 700,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(children: [
                                GestureDetector(
                                    onTap: handlePhotoSelection,
                                    child: Stack(
                                      children: [
                                        Container(width: 140, height: 160, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)), child: Center(child: imageWidget)),
                                        Positioned(bottom: 8, right: 8, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 14))),
                                      ],
                                    )
                                ),
                                const SizedBox(height: 12),
                                Row(children: [
                                  const Text("활성", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  Switch(value: isActive, activeTrackColor: _primaryColor.withValues(alpha: 0.5), activeThumbColor: _primaryColor, onChanged: (v) => setDialogState(() => isActive = v)),
                                ]),
                              ]),
                              const SizedBox(width: 20),
                              Expanded(child: Column(children: [
                                _buildField("성명", nameC, hint: "성함을 입력하세요"), const SizedBox(height: 12),
                                _buildField("부서", deptC, hint: "소속 부서"), const SizedBox(height: 12),
                                _buildField("사번", codeC, hint: "사번 또는 관리 코드"), const SizedBox(height: 12),
                                _buildField("RFID 태그", tagC, hint: "EPC 코드 직접 입력 가능"), const SizedBox(height: 12),
                                _buildField("비고", remarksC, hint: "특이 사항 기록")
                              ])),
                            ]
                        ),
                        if (metaControllers.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Divider(),
                          const Align(alignment: Alignment.centerLeft, child: Text("추가 정보", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                          const SizedBox(height: 12),
                          Wrap(spacing: 12, runSpacing: 12, children: metaControllers.entries.map((e) => SizedBox(width: 210, child: _buildField(e.key, e.value))).toList())
                        ]
                      ]
                  )
              )
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text("취소")),
            ElevatedButton(
                onPressed: provider.isSaving ? null : () async {
                  if (nameC.text.trim().isEmpty) {
                    return;
                  }
                  final updatedMeta = Map<String, dynamic>.from(p?.metadata ?? {});
                  metaControllers.forEach((k, v) => updatedMeta[k] = v.text.trim());
                  final data = {
                    'name': nameC.text.trim(),
                    'code': codeC.text.trim(),
                    'tag_id': tagC.text.trim(),
                    'department': deptC.text.trim(),
                    'is_active': isActive,
                    'remarks': remarksC.text.trim(),
                    'metadata': updatedMeta,
                  };
                  final success = await provider.handleSave(p: p, data: data, imageXFile: pickedFile);
                  if (!mounted) {
                    return;
                  }
                  if (success) {
                    navigator.pop();
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
                child: Text(provider.isSaving ? "저장 중..." : "저장")
            ),
          ],
        );
      }),
    );
  }

  void _confirmDelete(BuildContext context, PersonProvider provider, Person p) {
    final navigator = Navigator.of(context);
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("삭제 확인"), content: Text("${p.name}님의 정보를 삭제하시습니까?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")),
        ElevatedButton(onPressed: () async {
          final success = await provider.deletePerson(p.id);
          if (!mounted) {
            return;
          }
          if (success) {
            navigator.pop();
          }
        }, child: const Text("삭제")),
      ],
    ));
  }
}

class _CameraCaptureDialog extends StatefulWidget {
  final List<CameraDescription> cameras;
  const _CameraCaptureDialog({required this.cameras});
  @override
  State<_CameraCaptureDialog> createState() => _CameraCaptureDialogState();
}

class _CameraCaptureDialogState extends State<_CameraCaptureDialog> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.cameras.first, ResolutionPreset.medium, enableAudio: false);
    _initializeFuture = _controller!.initialize();
  }
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text("웹캠 촬영 (Windows)", style: TextStyle(fontWeight: FontWeight.bold)),
      content: Container(
        width: 480, height: 360, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<void>(
          future: _initializeFuture,
          builder: (ctx, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return CameraPreview(_controller!);
            }
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => navigator.pop(), child: const Text("취소")),
        ElevatedButton.icon(
          onPressed: () async {
            try {
              await _initializeFuture;
              final image = await _controller!.takePicture();
              if (!mounted) {
                return;
              }
              navigator.pop(image);
            } catch (e) {
              debugPrint("캡처 오류: $e");
            }
          },
          icon: const Icon(Icons.camera), label: const Text("촬영하기"),
          style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
        ),
      ],
    );
  }
}

class _LocationSelectionDialog extends StatefulWidget {
  final String type;
  final List<Person> existingPersons;
  const _LocationSelectionDialog({required this.type, required this.existingPersons});
  @override
  State<_LocationSelectionDialog> createState() => _LocationSelectionDialogState();
}

class _LocationSelectionDialogState extends State<_LocationSelectionDialog> {
  late List<String> _buildingOptions;
  late List<String> _gateOptions;
  final TextEditingController _buildingController = TextEditingController();
  final TextEditingController _gateController = TextEditingController();
  @override
  void initState() {
    super.initState();
    final Set<String> buildings = {'본관A', '공장B', '물류창고C', '연구소D'};
    final Set<String> gates = {'정문G1', '후문G2', '하차장G3', '비상구G4'};
    for (var p in widget.existingPersons) {
      final locInfo = p.metadata['last_location_info'];
      if (locInfo is Map) {
        final b = locInfo['building']?.toString();
        final g = locInfo['gate']?.toString();
        if (b != null && b.isNotEmpty) {
          buildings.add(b);
        }
        if (g != null && g.isNotEmpty) {
          gates.add(g);
        }
      }
    }
    _buildingOptions = buildings.toList()..sort();
    _gateOptions = gates.toList()..sort();
    _buildingController.text = _buildingOptions.first;
    _gateController.text = _gateOptions.first;
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)), side: BorderSide.none),
      title: Text('${widget.type} 위치 선택', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
        _buildComboField('건물명', _buildingController, _buildingOptions, hint: "건물을 선택하거나 직접 입력"),
        const SizedBox(height: 24),
        _buildComboField('출입구/GATE', _gateController, _gateOptions, hint: "GATE를 선택하거나 직접 입력"),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        ElevatedButton(onPressed: () => Navigator.pop(context, {'building': _buildingController.text, 'gate': _gateController.text}), style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white), child: const Text('확인')),
      ],
    );
  }
  Widget _buildComboField(String label, TextEditingController controller, List<String> options, {String? hint}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Autocomplete<String>(
        optionsBuilder: (val) => val.text == '' ? options : options.where((opt) => opt.contains(val.text)),
        onSelected: (sel) => controller.text = sel,
        fieldViewBuilder: (ctx, textC, focusN, onSubmit) {
          if (textC.text != controller.text && controller.text.isNotEmpty && textC.text.isEmpty) {
            textC.text = controller.text;
          }
          textC.addListener(() => controller.text = textC.text);
          return ValueListenableBuilder<TextEditingValue>(
            valueListenable: textC,
            builder: (context, value, _) => TextField(
              controller: textC, focusNode: focusN, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: label, hintText: hint, hintStyle: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.3)),
                labelStyle: const TextStyle(fontSize: 12, color: _primaryColor, fontWeight: FontWeight.bold),
                floatingLabelBehavior: FloatingLabelBehavior.always, filled: true, fillColor: Colors.white, isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade400, width: 1.0)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primaryColor, width: 2.0)),
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (value.text.isNotEmpty)
                    IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                        onPressed: () { textC.clear(); controller.clear(); }
                    ),
                  const Icon(Icons.arrow_drop_down, color: Colors.grey), const SizedBox(width: 8),
                ]),
              ),
            ),
          );
        },
        optionsViewBuilder: (ctx, onSel, opts) => Align(alignment: Alignment.topLeft, child: Material(elevation: 8.0, borderRadius: BorderRadius.circular(8), child: Container(width: 330, constraints: const BoxConstraints(maxHeight: 200), child: ListView.builder(padding: EdgeInsets.zero, shrinkWrap: true, itemCount: opts.length, itemBuilder: (ctx, idx) => ListTile(title: Text(opts.elementAt(idx), style: const TextStyle(fontSize: 13)), hoverColor: _primaryColor.withValues(alpha: 0.1), onTap: () => onSel(opts.elementAt(idx))))))),
      ),
    ]);
  }
}