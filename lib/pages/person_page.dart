import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/persons.dart';
import '../utils/hangul_utils.dart';
import '../providers/person_provider.dart';
import '../theme/app_theme.dart';

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

  String _activeMetricFilter = "전체";
  String? _selectedPersonId;

  static const double _colImgSize = 70.0;
  static const double _colActionWidth = 240.0;

  // PocketBase 시스템 필드 및 관리용 데이터 차단 리스트
  static const Set<String> _excludedSystemKeys = {
    'import_source', 'original_row_data', 'id', 'created', 'updated',
    'collectionId', 'collectionName', 'last_access_type', 'last_access_time',
    'access_history', 'last_location_info', 'is_approved', 'last_approval_status',
    'image', 'name', 'code', 'department', 'tag_id', 'is_active', 'remarks',
    'excel_row', 'import_date', 'import_data', 'is_auto_tag', 'is_auto_atg',
    'excel_row_internal', 'import_data_internal', 'is_auto_tag_internal'
  };

  @override
  void initState() {
    super.initState();
    _currentFilter = widget.filter == '정상 등록' ? '등록' : widget.filter;
    _currentSearchQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- FA 대시보드용 통계 계산 ---
  Map<String, dynamic> _calculateMetrics(List<Person> list) {
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0;
    int todayOut = 0;
    int currentRemained = 0;

    for (final p in list) {
      final String lastType = p.metadata['last_access_type'] ?? "";
      final String lastTime = p.metadata['last_access_time'] ?? "";

      if (lastTime.startsWith(todayStr)) {
        if (lastType == '입장') {
          todayIn++;
        } else if (lastType == '퇴장') {
          todayOut++;
        }
      }
      if (lastType == '입장') {
        currentRemained++;
      }
    }
    return {'in': todayIn, 'out': todayOut, 'current': currentRemained};
  }

  // --- 비동기 안전(Async Gap) 출입 처리 로직 ---
  Future<void> _processAccessWithLocation(PersonProvider provider, Person p, String type) async {
    final messenger = ScaffoldMessenger.of(context);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _LocationSelectionDialog(type: type, existingPersons: provider.list),
    );

    if (result == null || !mounted) {
      return;
    }

    final String now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final bool isApproved = result['is_approved'] ?? true;

    final updatedMeta = Map<String, dynamic>.from(p.metadata);
    updatedMeta['last_access_type'] = type;
    updatedMeta['last_access_time'] = now;
    updatedMeta['last_approval_status'] = isApproved;
    updatedMeta['last_location_info'] = {
      'building': result['building']?.trim() ?? "미지정",
      'gate': result['gate']?.trim() ?? "미지정",
      'full_name': "${result['building']} - ${result['gate']}"
    };

    List<dynamic> history = updatedMeta['access_history'] is List ? List.from(updatedMeta['access_history']) : [];
    history.insert(0, {
      'time': now,
      'type': type,
      'mode': '수동',
      'is_approved': isApproved,
      'location': updatedMeta['last_location_info']
    });

    if (history.length > 50) {
      history = history.sublist(0, 50);
    }
    updatedMeta['access_history'] = history;

    final success = await provider.handleSave(p: p, data: {'is_approved': isApproved, 'metadata': updatedMeta});

    if (success && mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text('[${p.name}]님 $type 처리 완료'),
        backgroundColor: isApproved ? AppTheme.success : AppTheme.danger,
        elevation: 0,
        duration: const Duration(seconds: 1),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PersonProvider>();
    final theme = Theme.of(context);
    final metrics = _calculateMetrics(provider.list);

    final filteredList = provider.list.where((p) {
      final matchesFilter = _currentFilter == '전체' || (_currentFilter == '등록' ? p.tagId.isNotEmpty : p.tagId.isEmpty);
      final matchesSearch = HangulUtils.matches(_currentSearchQuery, p.name) || p.code.contains(_currentSearchQuery) || p.department.contains(_currentSearchQuery);

      if (!matchesFilter || !matchesSearch) {
        return false;
      }
      if (_activeMetricFilter == "전체") {
        return true;
      }

      final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final lastTime = p.metadata['last_access_time'] ?? "";
      if (_activeMetricFilter == "당일 입장") {
        return (p.metadata['last_access_type'] == '입장' && lastTime.startsWith(todayStr));
      }
      if (_activeMetricFilter == "당일 퇴장") {
        return (p.metadata['last_access_type'] == '퇴장' && lastTime.startsWith(todayStr));
      }
      if (_activeMetricFilter == "현재 잔류") {
        return p.metadata['last_access_type'] == '입장';
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildDashboard(metrics, provider, theme),
          Divider(height: 1, color: theme.dividerTheme.color),
          _buildHeader(provider, filteredList, theme),
          const SizedBox(height: 16),
          Expanded(
            child: provider.isLoading
                ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                : _buildListView(filteredList, provider, provider.selectedColumns, theme),
          ),
        ],
      ),
    );
  }

  // --- UI 컴포넌트 섹션 ---

  Widget _buildDashboard(Map<String, dynamic> m, PersonProvider provider, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.scaffoldBackgroundColor,
      child: Row(
        children: [
          Expanded(child: _buildStatTile("전체 보기", provider.list.length, Icons.people, Colors.blueGrey, theme, filterKey: "전체")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("당일 입장", m['in'], Icons.login, AppTheme.success, theme, filterKey: "당일 입장")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("당일 퇴장", m['out'], Icons.logout, AppTheme.warning, theme, filterKey: "당일 퇴장")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("현재 잔류", m['current'], Icons.person_search, theme.colorScheme.primary, theme, filterKey: "현재 잔류")),
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, int val, IconData icon, Color color, ThemeData theme, {required String filterKey}) {
    final bool isSelected = _activeMetricFilter == filterKey;
    return InkWell(
      onTap: () {
        setState(() {
          _activeMetricFilter = _activeMetricFilter == filterKey ? "전체" : filterKey;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: theme.brightness == Brightness.dark ? 0.15 : 0.08) : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.4), width: isSelected ? 3.0 : 1.8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7), fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  Text('$val', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(PersonProvider provider, List<Person> filtered, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildActionIcon(Icons.refresh, "새로고침", () => provider.fetchData(), theme),
                    _buildActionIcon(FontAwesomeIcons.fileArrowUp, "엑셀 업로드", () => _handleBatchImport(provider), theme, color: Colors.indigo),
                    _buildActionIcon(FontAwesomeIcons.fileArrowDown, "엑스포트", () => _exportToExcel(filtered), theme, color: Colors.green),
                    _buildActionIcon(Icons.settings_outlined, "표시 설정", () => _showColumnSelectionDialog(provider, theme), theme),
                    _buildActionIcon(Icons.delete_sweep_outlined, "초기화", () => _showResetConfirmationDialog(provider, theme), theme, color: AppTheme.danger),
                  ],
                ),
              ),
              _buildActionIcon(Icons.person_add_alt_1, "신규 등록", () => _showForm(provider, null, theme), theme, color: theme.colorScheme.primary, isLarge: true),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _currentSearchQuery = v),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
            decoration: AppTheme.inputDecoration(label: "성명, 사번, 부서 또는 상세내용 검색...", context: context, prefixIcon: Icons.search),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, String tip, VoidCallback onTap, ThemeData theme, {Color? color, bool isLarge = false}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          child: Icon(icon, color: color ?? theme.iconTheme.color?.withValues(alpha: 0.6), size: isLarge ? 34 : 24),
        ),
      ),
    );
  }

  Widget _buildListView(List<Person> list, PersonProvider provider, List<String> columns, ThemeData theme) {
    if (list.isEmpty) {
      return _buildEmptyState("데이터가 없습니다.");
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, idx) {
        final item = list[idx];
        final bool isSelected = _selectedPersonId == item.id;
        final status = item.metadata['last_access_type'] ?? "미확인";
        final statusColor = (status == '입장' ? AppTheme.success : (status == '퇴장' ? AppTheme.warning : theme.dividerTheme.color ?? Colors.grey));

        return InkWell(
          onTap: () {
            setState(() => _selectedPersonId = item.id);
            _showForm(provider, item, theme);
          },
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: AppTheme.listItemDecoration(context, isSelected: isSelected, statusColor: statusColor),
            child: Row(
              children: [
                _buildAvatar(item, theme, size: _colImgSize),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // [수정] 성명 글자 크기를 19px로 상향 조정
                          Text(
                            item.name,
                            style: AppTheme.itemValueStyle(context).copyWith(fontSize: 19),
                          ),
                          const SizedBox(width: 12),
                          _buildStatusBadge(status),
                          if (!item.isApproved)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: const Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 20,
                        runSpacing: 8,
                        children: columns.map((col) {
                          return SizedBox(
                            width: 140,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(col, style: AppTheme.itemLabelStyle(context)),
                                Text(_getMetaValue(item, col), style: AppTheme.itemValueStyle(context)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.metadata['last_location_info']?['full_name'] ?? "위치 정보 없음",
                        style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: _colActionWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildCircleAction(Icons.history, Colors.blueGrey, "기록", () => _showHistoryDialog(context, item, theme)),
                      const SizedBox(width: 12),
                      _buildCircleAction(Icons.login, AppTheme.success, "입장", () => _processAccessWithLocation(provider, item, '입장')),
                      const SizedBox(width: 12),
                      _buildCircleAction(Icons.logout, AppTheme.warning, "퇴장", () => _processAccessWithLocation(provider, item, '퇴장')),
                      const SizedBox(width: 12),
                      _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () => _confirmDelete(provider, item, theme)),
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

  // --- 유틸리티 및 보조 UI ---

  Widget _buildCircleAction(IconData icon, Color color, String tip, VoidCallback onTap) {
    return Tooltip(message: tip, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(25), child: Container(width: 50, height: 50, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 24))));
  }

  Widget _buildAvatar(Person item, ThemeData theme, {double size = 44}) {
    final url = item.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(width: size, height: size, decoration: BoxDecoration(color: theme.dividerTheme.color?.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 1.5)), clipBehavior: Clip.antiAlias, child: (url != null) ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.black12)) : const Icon(Icons.person_outline, color: Colors.black12, size: 30));
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == '입장' ? AppTheme.success : (status == '퇴장' ? AppTheme.warning : Colors.grey);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)));
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people_outline, size: 100, color: Colors.grey[300]), const SizedBox(height: 20), Text(msg, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 18))]));
  }

  String _getMetaValue(Person item, String key) {
    final baseFields = {'성명': item.name, '사번': item.code, '부서': item.department, '태그ID': item.tagId};
    if (baseFields.containsKey(key)) {
      return baseFields[key]!;
    }
    return item.metadata[key]?.toString() ?? "-";
  }

  void _showHistoryDialog(BuildContext context, Person p, ThemeData theme) {
    final history = p.metadata['access_history'] is List ? List.from(p.metadata['access_history']) : [];
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: AppTheme.dialogTitle('[${p.name}]님 출입 히스토리', Icons.history, color: Colors.blueGrey),
          content: SizedBox(
              width: 550,
              height: 600,
              child: history.isEmpty
                  ? _buildEmptyState("기록 없음")
                  : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (c, i) {
                    final log = history[i];
                    final String type = log['type'] ?? "-";
                    final bool approved = log['is_approved'] ?? true;
                    Color col = approved ? (type == '입장' ? AppTheme.success : AppTheme.warning) : AppTheme.danger;
                    return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: theme.cardTheme.color, borderRadius: BorderRadius.circular(10), border: Border.all(color: col.withValues(alpha: 0.15))),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6, right: 16), decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Text(log['time'] ?? "-", style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: col.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text(type, style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 12))),
                                ]),
                                const SizedBox(height: 6),
                                Text('${log['location']?['building'] ?? "미지정"} - ${log['location']?['gate'] ?? "미정"}', style: const TextStyle(color: Colors.blueGrey, fontSize: 14, fontWeight: FontWeight.w600)),
                              ])),
                            ]
                        )
                    );
                  }
              )
          ),
          actions: [AppTheme.actionButton(label: "닫기", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () => Navigator.pop(ctx))],
        )
    );
  }

  void _showColumnSelectionDialog(PersonProvider provider, ThemeData theme) {
    final Set<String> keySet = {};
    for (final p in provider.list) {
      for (final k in p.metadata.keys) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal')) {
          keySet.add(k);
        }
      }
    }
    final available = keySet.toList()..sort();
    final List<String> temp = List.from(provider.selectedColumns);
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (context, setS) => AlertDialog(
              title: AppTheme.dialogTitle("표시 항목 설정", Icons.view_column_rounded),
              content: SizedBox(
                  width: 480,
                  child: available.isEmpty
                      ? const Text("추가 필드 없음")
                      : SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: available.map((key) {
                            final bool sel = temp.contains(key);
                            return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: InkWell(
                                    onTap: () => setS(() => sel ? (temp.length > 1 ? temp.remove(key) : null) : (temp.length < 5 ? temp.add(key) : null)),
                                    borderRadius: BorderRadius.circular(8),
                                    child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(color: sel ? theme.colorScheme.primary.withValues(alpha: 0.05) : Colors.transparent, borderRadius: BorderRadius.circular(8), border: Border.all(color: sel ? theme.colorScheme.primary : Colors.black.withValues(alpha: 0.15), width: sel ? 2.5 : 1.0)),
                                        child: Row(children: [Icon(sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 20, color: sel ? theme.colorScheme.primary : Colors.black26), const SizedBox(width: 16), Expanded(child: Text(key, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: sel ? theme.colorScheme.primary : Colors.black45)))])
                                    )
                                )
                            );
                          }).toList()
                      )
                  )
              ),
              actions: [
                AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () => Navigator.pop(ctx)),
                AppTheme.actionButton(label: "설정 적용", onPressed: () async {
                  await provider.saveRemoteSettings(temp);
                  if (mounted) Navigator.pop(ctx);
                })
              ],
            )
        )
    );
  }

  Future<void> _showResetConfirmationDialog(PersonProvider provider, ThemeData theme) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
            title: AppTheme.dialogTitle("삭제 확인", Icons.warning, color: AppTheme.danger),
            content: const Text("서버의 모든 정보를 영구 삭제하시겠습니까?"),
            actions: [
              AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () => Navigator.pop(ctx, false)),
              AppTheme.actionButton(label: "삭제 실행", color: AppTheme.danger, onPressed: () => Navigator.pop(ctx, true))
            ]
        )
    );
    if (confirm == true && mounted) {
      await provider.resetAllPersons();
      messenger.showSnackBar(const SnackBar(content: Text('초기화 완료')));
    }
  }

  Future<void> _handleBatchImport(PersonProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    final count = await provider.batchImportFromExcel();
    if (count > 0 && mounted) {
      messenger.showSnackBar(SnackBar(content: Text('$count명 등록 완료')));
    }
  }

  Future<void> _exportToExcel(List<Person> dataList) async {
    if (dataList.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['인원리스트'];
      excel.rename('Sheet1', '인원리스트');
      final headers = ['성명', '사번', '부서', '태그ID'];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = excel_pkg.TextCellValue(headers[i]);
      }
      for (int r = 0; r < dataList.length; r++) {
        final p = dataList[r];
        final row = [p.name, p.code, p.department, p.tagId];
        for (int c = 0; c < row.length; c++) {
          sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value = excel_pkg.TextCellValue(row[c]);
        }
      }
      final path = await FilePicker.platform.saveFile(fileName: 'Person_Export_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx']);
      if (path != null) {
        await File(path).writeAsBytes(excel.encode()!);
        if (mounted) messenger.showSnackBar(const SnackBar(content: Text('✅ 엑셀 저장 완료')));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  Future<void> _showForm(PersonProvider provider, Person? p, ThemeData theme) async {
    final navigator = Navigator.of(context);
    final nameC = TextEditingController(text: p?.name ?? "");
    final codeC = TextEditingController(text: p?.code ?? "");
    final tagC = TextEditingController(text: p?.tagId ?? "");
    final deptC = TextEditingController(text: p?.department ?? "");
    final remarksC = TextEditingController(text: p?.remarks ?? "");
    bool approved = p?.isApproved ?? true;
    XFile? file;
    Uint8List? preview;
    final Map<String, TextEditingController> metaC = {};
    if (p != null) {
      p.metadata.forEach((k, v) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal') && v is! Map && v is! List) {
          metaC[k] = TextEditingController(text: v?.toString() ?? "");
        }
      });
    }

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
            builder: (dialogCtx, setS) => AlertDialog(
                title: AppTheme.dialogTitle(p == null ? '신규 인원 등록' : '정보 수정 및 편집', p == null ? Icons.person_add : Icons.edit),
                content: SizedBox(
                    width: 900,
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 20),
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Column(
                                        children: [
                                          GestureDetector(
                                              onTap: () async {
                                                final img = await ImagePicker().pickImage(source: ImageSource.gallery);
                                                if (img != null) {
                                                  final b = await img.readAsBytes();
                                                  setS(() { file = img; preview = b; });
                                                }
                                              },
                                              child: Container(
                                                  width: 180,
                                                  height: 210,
                                                  decoration: BoxDecoration(color: theme.cardTheme.color, borderRadius: BorderRadius.circular(15), border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 2)),
                                                  child: Center(
                                                      child: preview != null
                                                          ? Image.memory(preview!, fit: BoxFit.cover)
                                                          : (p?.getImageUrl(widget.baseUrl) != null
                                                          ? Image.network(p!.getImageUrl(widget.baseUrl)!, fit: BoxFit.cover)
                                                          : const Icon(Icons.camera_alt, size: 40, color: Colors.grey))
                                                  )
                                              )
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                              children: [
                                                const Text("출입 승인", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                                const SizedBox(width: 8),
                                                Switch(value: approved, activeThumbColor: AppTheme.success, activeTrackColor: AppTheme.success.withValues(alpha: 0.5), onChanged: (v) => setS(() => approved = v))
                                              ]
                                          )
                                        ]
                                    ),
                                    const SizedBox(width: 30),
                                    Expanded(
                                        child: Column(
                                            children: [
                                              _buildTextField(nameC, "성명 (필수)", theme), const SizedBox(height: 16),
                                              _buildTextField(deptC, "담당부서/소속", theme), const SizedBox(height: 16),
                                              _buildTextField(codeC, "사번/ID", theme), const SizedBox(height: 16),
                                              _buildTextField(tagC, "RFID 태그 EPC", theme), const SizedBox(height: 16),
                                              _buildTextField(remarksC, "비고", theme),
                                            ]
                                        )
                                    )
                                  ]
                              ),
                              if (metaC.isNotEmpty) ...[
                                const SizedBox(height: 32),
                                const Divider(),
                                const SizedBox(height: 16),
                                Wrap(
                                    spacing: 16,
                                    runSpacing: 16,
                                    children: metaC.entries.map((e) => SizedBox(width: 360, child: _buildTextField(e.value, e.key, theme))).toList()
                                )
                              ]
                            ]
                        )
                    )
                ),
                actions: [
                  AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () => Navigator.pop(dialogCtx)),
                  AppTheme.actionButton(label: "통합 저장", onPressed: () async {
                    final meta = Map<String, dynamic>.from(p?.metadata ?? {});
                    metaC.forEach((k, c) => meta[k] = c.text.trim());
                    final data = {'name': nameC.text.trim(), 'code': codeC.text.trim(), 'tag_id': tagC.text.trim(), 'department': deptC.text.trim(), 'is_approved': approved, 'remarks': remarksC.text.trim(), 'metadata': meta};
                    if (await provider.handleSave(p: p, data: data, imageXFile: file) && mounted) {
                      navigator.pop();
                    }
                  })
                ]
            )
        )
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, ThemeData theme) {
    return TextField(controller: ctrl, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)), decoration: AppTheme.inputDecoration(label: label, context: context));
  }

  void _confirmDelete(PersonProvider provider, Person p, ThemeData theme) {
    final nav = Navigator.of(context);
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
            title: AppTheme.dialogTitle("삭제 확인", Icons.delete),
            content: Text("[${p.name}] 정보를 삭제하시겠습니까?"),
            actions: [
              AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () => Navigator.pop(c)),
              AppTheme.actionButton(label: "삭제 실행", color: AppTheme.danger, onPressed: () async {
                if (await provider.deletePerson(p.id) && mounted) {
                  nav.pop();
                }
              })
            ]
        )
    );
  }
}

// --- 위치 선택 다이얼로그 전용 위젯 ---

class _LocationSelectionDialog extends StatefulWidget {
  final String type;
  final List<Person> existingPersons;
  const _LocationSelectionDialog({required this.type, required this.existingPersons});
  @override State<_LocationSelectionDialog> createState() => _LocationSelectionDialogState();
}

class _LocationSelectionDialogState extends State<_LocationSelectionDialog> {
  late List<String> _buildings, _gates;
  final _bC = TextEditingController();
  final _gC = TextEditingController();
  bool _ok = true;
  @override void initState() {
    super.initState();
    final Set<String> b = {'본관A', '공장B', '물류창고C', '연구소D'};
    final Set<String> g = {'정문G1', '후문G2', '하차장G3', '비상구G4'};
    for (var p in widget.existingPersons) {
      final loc = p.metadata['last_location_info'];
      if (loc is Map) {
        if (loc['building'] != null) b.add(loc['building']);
        if (loc['gate'] != null) g.add(loc['gate']);
      }
    }
    _buildings = b.toList()..sort();
    _gates = g.toList()..sort();
    _bC.text = _buildings.first;
    _gC.text = _gates.first;
  }
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: AppTheme.dialogTitle('${widget.type}처리', widget.type == '입장' ? Icons.login : Icons.logout),
      content: SizedBox(
          width: 420,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 20),
                _buildCombo('건물명 (Building)', _bC, _buildings, theme), const SizedBox(height: 24),
                _buildCombo('출입구 (GATE)', _gC, _gates, theme), const SizedBox(height: 24),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: _ok ? AppTheme.success.withValues(alpha: 0.05) : AppTheme.danger.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: _ok ? AppTheme.success.withValues(alpha: 0.2) : AppTheme.danger.withValues(alpha: 0.2))),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_ok ? "승인됨" : "미승인", style: TextStyle(fontWeight: FontWeight.bold, color: _ok ? AppTheme.success : AppTheme.danger)),
                          Switch(value: _ok, activeThumbColor: AppTheme.success, activeTrackColor: AppTheme.success.withValues(alpha: 0.5), onChanged: (v) => setState(() => _ok = v))
                        ]
                    )
                )
              ]
          )
      ),
      actions: [
        AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () => Navigator.pop(context)),
        AppTheme.actionButton(label: "위치 확정", onPressed: () => Navigator.pop(context, {'building': _bC.text, 'gate': _gC.text, 'is_approved': _ok}))
      ],
    );
  }
  Widget _buildCombo(String label, TextEditingController ctrl, List<String> opts, ThemeData theme) {
    return Autocomplete<String>(
        optionsBuilder: (v) => v.text == '' ? opts : opts.where((o) => o.contains(v.text)),
        onSelected: (s) => ctrl.text = s,
        fieldViewBuilder: (ctx, tC, fN, __) {
          tC.text = ctrl.text; tC.addListener(() => ctrl.text = tC.text);
          return TextField(controller: tC, focusNode: fN, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)), decoration: AppTheme.inputDecoration(label: label, context: context, hasFocus: fN.hasFocus));
        }
    );
  }
}