import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
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
        }
        if (lastType == '퇴장') {
          todayOut++;
        }
      }
      if (lastType == '입장') {
        currentRemained++;
      }
    }

    return {
      'prev': currentRemained - todayIn + todayOut,
      'in': todayIn,
      'out': todayOut,
      'current': currentRemained
    };
  }

  Future<void> _processAccessWithLocation(PersonProvider provider, Person p, String type) async {
    final messenger = ScaffoldMessenger.of(context);
    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _LocationSelectionDialog(
        type: type,
        existingPersons: provider.list,
      ),
    );

    if (result == null) {
      return;
    }

    final String now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final String building = result['building']?.trim() ?? "미지정";
    final String gate = result['gate']?.trim() ?? "미지정";
    final bool isApproved = result['is_approved'] ?? true;

    final updatedMeta = Map<String, dynamic>.from(p.metadata);
    updatedMeta['last_access_type'] = type;
    updatedMeta['last_access_time'] = now;
    updatedMeta['last_approval_status'] = isApproved;
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
      'is_approved': isApproved,
      'location': {'building': building, 'gate': gate}
    });

    if (history.length > 50) {
      history = history.sublist(0, 50);
    }
    updatedMeta['access_history'] = history;

    final success = await provider.handleSave(p: p, data: {
      'is_approved': isApproved,
      'metadata': updatedMeta
    });

    if (success) {
      messenger.showSnackBar(SnackBar(
        content: Text('[${p.name}]님 $type 처리 완료 (${isApproved ? "승인" : "미승인"})'),
        backgroundColor: isApproved ? AppTheme.success : AppTheme.danger,
        duration: const Duration(seconds: 1),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PersonProvider>();
    final metrics = _calculateMetrics(provider.list);
    final List<String> currentColumns = provider.selectedColumns;

    final filteredList = provider.list.where((p) {
      final matchesFilter = _currentFilter == '전체' ||
          (_currentFilter == '등록' ? p.tagId.isNotEmpty : p.tagId.isEmpty);
      final matchesSearch = HangulUtils.matches(_currentSearchQuery, p.name) ||
          p.code.toLowerCase().contains(_currentSearchQuery.toLowerCase()) ||
          p.department.toLowerCase().contains(_currentSearchQuery.toLowerCase());

      if (!matchesFilter || !matchesSearch) {
        return false;
      }

      if (_activeMetricFilter == "전체") {
        return true;
      }

      final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final String lastType = p.metadata['last_access_type'] ?? "";
      final String lastTime = p.metadata['last_access_time'] ?? "";

      if (_activeMetricFilter == "당일 입장") {
        return lastType == '입장' && lastTime.startsWith(todayStr);
      }
      if (_activeMetricFilter == "당일 퇴장") {
        return lastType == '퇴장' && lastTime.startsWith(todayStr);
      }
      if (_activeMetricFilter == "현재 잔류") {
        return lastType == '입장';
      }

      return true;
    }).toList();

    return Theme(
      data: AppTheme.lightTheme.copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: AppTheme.fontPretendard),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _buildDashboard(metrics, provider),
            const Divider(height: 1),
            _buildHeader(provider, filteredList),
            const SizedBox(height: 16),
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _buildListView(filteredList, provider, currentColumns),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(Map<String, dynamic> m, PersonProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: Colors.white,
      child: LayoutBuilder(builder: (ctx, constraints) {
        bool isWide = constraints.maxWidth > 850;
        if (isWide) {
          return Row(
            children: [
              Expanded(child: _buildStatTile("전체 보기", provider.list.length, Icons.people, Colors.blueGrey, filterKey: "전체")),
              const SizedBox(width: 12),
              Expanded(child: _buildStatTile("당일 입장", m['in'], Icons.login, Colors.green, filterKey: "당일 입장")),
              const SizedBox(width: 12),
              Expanded(child: _buildStatTile("당일 퇴장", m['out'], Icons.logout, Colors.orange, filterKey: "당일 퇴장")),
              const SizedBox(width: 12),
              Expanded(child: _buildStatTile("현재 잔류", m['current'], Icons.person_search, AppTheme.primary, filterKey: "현재 잔류")),
            ],
          );
        } else {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildStatTile("전체 보기", provider.list.length, Icons.people, Colors.blueGrey, filterKey: "전체")),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatTile("당일 입장", m['in'], Icons.login, Colors.green, filterKey: "당일 입장")),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildStatTile("당일 퇴장", m['out'], Icons.logout, Colors.orange, filterKey: "당일 퇴장")),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatTile("현재 잔류", m['current'], Icons.person_search, AppTheme.primary, filterKey: "현재 잔류")),
                ],
              ),
            ],
          );
        }
      }),
    );
  }

  Widget _buildStatTile(String label, int val, IconData icon, Color color, {required String filterKey}) {
    final bool isSelected = _activeMetricFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _activeMetricFilter = _activeMetricFilter == filterKey ? "전체" : filterKey),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.3),
              width: isSelected ? 3.0 : 2.0
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4))]
              : [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
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

  Widget _buildHeader(PersonProvider provider, List<Person> filtered) {
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
                    _buildActionIcon(Icons.refresh, "새로고침", () => provider.fetchData()),
                    _buildActionIcon(FontAwesomeIcons.fileArrowUp, "엑셀 업로드", () => _handleBatchImport(provider), color: Colors.indigo),
                    _buildActionIcon(FontAwesomeIcons.fileArrowDown, "엑셀 다운로드", () => _exportToExcel(filtered), color: Colors.green),
                    _buildActionIcon(Icons.settings_outlined, "표시 설정", () => _showColumnSelectionDialog(provider)),
                    _buildActionIcon(Icons.delete_sweep_outlined, "초기화", () => _showResetConfirmationDialog(provider), color: AppTheme.danger),
                  ],
                ),
              ),
              _buildActionIcon(Icons.person_add_alt_1, "신규 등록", () => _showForm(context, provider, null), color: AppTheme.primary, isLarge: true),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _currentSearchQuery = val),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '성명, 사번, 부서 또는 초성 검색...',
              hintStyle: const TextStyle(color: Colors.black26, fontSize: 16),
              prefixIcon: const Icon(Icons.search, size: 24),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: const BorderSide(color: Color(0xFFE9ECEF), width: 2.0),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, String tip, VoidCallback onTap, {Color? color, bool isLarge = false}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          child: Icon(icon, color: color ?? Colors.black45, size: isLarge ? 34 : 24),
        ),
      ),
    );
  }

  Widget _buildListView(List<Person> list, PersonProvider provider, List<String> columns) {
    if (list.isEmpty) {
      return _buildEmptyState(_activeMetricFilter == "전체" ? "표시할 인원 정보가 없습니다." : "$_activeMetricFilter 인원이 없습니다.");
    }
    return ListView.separated(
      cacheExtent: 500,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: list.length,
      separatorBuilder: (ctx, idx) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = list[index];
        final String currentStatus = item.metadata['last_access_type'] ?? "미확인";
        final bool isSelected = _selectedPersonId == item.id;
        final bool isApproved = item.isApproved;

        String locationDisplay = "위치 정보 없음";
        final locInfo = item.metadata['last_location_info'];
        if (locInfo is Map) {
          locationDisplay = locInfo['full_name'] ?? locationDisplay;
        }

        final Color cardBorderColor = isSelected ? AppTheme.primary : (currentStatus == '입장' ? AppTheme.success : (currentStatus == '퇴장' ? AppTheme.warning : Colors.black.withValues(alpha: 0.1)));
        final double currentOutlineWidth = isSelected ? AppTheme.outlineWidth + 1.5 : AppTheme.outlineWidth;

        return InkWell(
          key: ValueKey(item.id),
          onTap: () {
            setState(() => _selectedPersonId = item.id);
            _showForm(context, provider, item);
          },
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppTheme.cardRadius), border: Border.all(color: cardBorderColor, width: currentOutlineWidth), color: isSelected ? AppTheme.primary.withValues(alpha: 0.02) : Colors.white),
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              _buildAvatar(item, size: _colImgSize),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                      const SizedBox(width: 12),
                      _buildStatusBadge(currentStatus),
                      if (!isApproved) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18),
                      ]
                    ]),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      children: columns.map((col) => SizedBox(width: 140, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(col, style: const TextStyle(fontSize: 12, color: Colors.black26, fontWeight: FontWeight.bold)), Text(_getMetaValue(item, col), style: const TextStyle(fontSize: 15, color: Colors.blueGrey, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)]))).toList(),
                    ),
                    const SizedBox(height: 8),
                    Text(locationDisplay, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              SizedBox(
                width: _colActionWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildCircleAction(Icons.history, Colors.blueGrey, "출입 기록", () => _showHistoryDialog(context, item)),
                    const SizedBox(width: 12),
                    _buildCircleAction(Icons.login, AppTheme.success, "입장", () => _processAccessWithLocation(provider, item, '입장')),
                    const SizedBox(width: 12),
                    _buildCircleAction(Icons.logout, AppTheme.warning, "퇴장", () => _processAccessWithLocation(provider, item, '퇴장')),
                    const SizedBox(width: 12),
                    _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () => _confirmDelete(context, provider, item)),
                  ],
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildCircleAction(IconData icon, Color color, String tip, VoidCallback onTap) {
    return Tooltip(message: tip, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(25), child: Container(width: 50, height: 50, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 24))));
  }

  Widget _buildAvatar(Person item, {double size = 44}) {
    final url = item.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(width: size, height: size, decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black.withValues(alpha: 0.05), width: 1.5)), clipBehavior: Clip.antiAlias, child: url != null ? Image.network(url, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.black12)) : const Icon(Icons.person_outline, color: Colors.black12, size: 30));
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == '입장' ? AppTheme.success : (status == '퇴장' ? AppTheme.warning : Colors.grey);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)));
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people_outline, size: 100, color: Colors.grey[300]), const SizedBox(height: 20), Text(msg, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 18))]));
  }

  Widget _buildFlatButton({required String text, required VoidCallback onPressed, Color? bgColor, Color? textColor}) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onPressed, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14), decoration: BoxDecoration(color: bgColor ?? AppTheme.primary, borderRadius: BorderRadius.circular(8)), child: Text(text, style: TextStyle(color: textColor ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))));
  }

  void _showHistoryDialog(BuildContext context, Person p) {
    final List<dynamic> history = p.metadata['access_history'] is List ? List.from(p.metadata['access_history']) : [];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.history, color: Colors.blueGrey, size: 28), const SizedBox(width: 12), Text('[${p.name}]님 출입 히스토리', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20))]),
        content: SizedBox(
          width: 550,
          height: 600,
          child: history.isEmpty
              ? _buildEmptyState("출입 기록이 존재하지 않습니다.")
              : ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: history.length,
            separatorBuilder: (c, i) => const Divider(height: 24, color: Color(0xFFF1F3F5)),
            itemBuilder: (c, i) {
              final log = history[i];
              final String type = log['type'] ?? "-";
              final String time = log['time'] ?? "-";
              final String mode = log['mode'] ?? "자동";
              final bool approved = log['is_approved'] ?? true;
              final Map loc = log['location'] is Map ? log['location'] : {};
              final String building = loc['building'] ?? "미지정";
              final String gate = loc['gate'] ?? "미정";
              Color statusColor = type == '입장' ? AppTheme.success : AppTheme.warning;
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6, right: 16), decoration: BoxDecoration(color: approved ? statusColor : AppTheme.danger, shape: BoxShape.circle)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(time, style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                        Row(children: [
                          if (!approved) ...[const Icon(Icons.error_outline, color: AppTheme.danger, size: 16), const SizedBox(width: 4), const Text("미승인", style: TextStyle(color: AppTheme.danger, fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(width: 8)],
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text(type, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12))),
                        ]),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey), const SizedBox(width: 4), Text('$building - $gate', style: const TextStyle(color: Colors.blueGrey, fontSize: 14, fontWeight: FontWeight.w600)), const SizedBox(width: 12), const Icon(Icons.settings_input_antenna, size: 14, color: Colors.grey), const SizedBox(width: 4), Text(mode, style: const TextStyle(color: Colors.grey, fontSize: 13))]),
                    ],
                  ),
                ),
              ]);
            },
          ),
        ),
        actions: [_buildFlatButton(text: "닫기", bgColor: Colors.blueGrey, onPressed: () => Navigator.pop(ctx))],
      ),
    );
  }

  void _showColumnSelectionDialog(PersonProvider provider) {
    final availableKeys = _extractAvailableMetaKeys(provider.list);
    final List<String> tempSelection = List.from(provider.selectedColumns);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("표시 항목 설정", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          actionsAlignment: MainAxisAlignment.center,
          content: SizedBox(
            width: 450,
            child: availableKeys.isEmpty
                ? const Text("추가 필드가 없습니다.")
                : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: availableKeys
                    .map((key) => CheckboxListTile(
                    title: Text(key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    activeColor: AppTheme.primary,
                    value: tempSelection.contains(key),
                    onChanged: (val) {
                      setDlgState(() {
                        if (val == true) {
                          if (tempSelection.length < 5) {
                            tempSelection.add(key);
                          }
                        } else {
                          if (tempSelection.length > 1) {
                            tempSelection.remove(key);
                          }
                        }
                      });
                    }))
                    .toList(),
              ),
            ),
          ),
          actions: [
            _buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () => Navigator.pop(ctx)),
            const SizedBox(width: 12),
            _buildFlatButton(
                text: "설정 적용",
                onPressed: () async {
                  await provider.saveRemoteSettings(tempSelection);
                  if (context.mounted) {
                    Navigator.pop(ctx);
                  }
                }),
          ],
        ),
      ),
    );
  }

  Future<void> _showResetConfirmationDialog(PersonProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    final bool? confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), actionsAlignment: MainAxisAlignment.center, title: const Row(children: [Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 28), SizedBox(width: 10), Text("데이터 전체 초기화", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.danger, fontSize: 20))]), content: const Text("서버의 모든 인원 정보가 영구 삭제됩니다.\n이 작업은 되돌릴 수 없습니다. 진행하시겠습니까?", style: TextStyle(fontSize: 16)), actions: [_buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () => Navigator.pop(ctx, false)), const SizedBox(width: 12), _buildFlatButton(text: "전체 삭제 실행", bgColor: AppTheme.danger, onPressed: () => Navigator.pop(ctx, true))]));
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
      final path = await FilePicker.platform.saveFile(dialogTitle: '엑셀 파일 저장 위치 선택', fileName: '인원관리_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx']);
      if (path != null) {
        final bytes = excel.encode();
        if (bytes != null) {
          await File(path).writeAsBytes(bytes);
          messenger.showSnackBar(const SnackBar(content: Text('✅ 엑셀 파일이 저장되었습니다.')));
        }
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('저장 오류: $e')));
    }
  }

  String _getMetaValue(Person item, String key) {
    if (key == '성명') {
      return item.name;
    }
    if (key == '사번' || key == '사번/코드') {
      return item.code;
    }
    if (key == '부서' || key == '부서/소속') {
      return item.department;
    }
    if (key == 'RFID EPC' || key == '태그ID') {
      return item.tagId;
    }
    if (key == '비고') {
      return item.remarks;
    }
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
    keySet.addAll(['성명', '사번', '부서', 'RFID EPC', '비고']);
    const systemKeys = {'import_source', 'original_row_data', 'id', 'created', 'updated', 'collectionId', 'collectionName', 'last_access_type', 'last_access_time', 'access_history', 'last_location_info', 'is_approved', 'last_approval_status'};
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

  Widget _buildStyledField(String label, TextEditingController ctrl, {TextInputType keyboardType = TextInputType.text, String? hint}) {
    return StatefulBuilder(builder: (context, setStateField) => Focus(onFocusChange: (hasFocus) => setStateField(() {}), child: Builder(builder: (ctx) {
      final bool hasFocus = Focus.of(ctx).hasFocus;
      return TextField(controller: ctrl, keyboardType: keyboardType, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), decoration: InputDecoration(labelText: label, labelStyle: AppTheme.inputLabelStyle.copyWith(fontSize: 14), hintText: hint, hintStyle: AppTheme.inputHintStyle.copyWith(fontSize: 15), filled: true, fillColor: hasFocus ? AppTheme.inputFocusColor : AppTheme.inputFillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: hasFocus ? AppTheme.primary : AppTheme.inputBorderColor, width: 2.0)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.inputBorderColor, width: 1.5)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 2.5)), contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18)));
    })));
  }

  Future<void> _showForm(BuildContext context, PersonProvider provider, Person? p) async {
    final navigator = Navigator.of(context);
    final nameC = TextEditingController(text: p?.name ?? ""), codeC = TextEditingController(text: p?.code ?? ""), tagC = TextEditingController(text: p?.tagId ?? ""), deptC = TextEditingController(text: p?.department ?? ""), remarksC = TextEditingController(text: p?.remarks ?? "");

    bool isApproved = p?.isApproved ?? true;

    XFile? pickedFile;
    Uint8List? previewBytes;
    final Map<String, TextEditingController> metaControllers = {};
    if (p != null) {
      const sysKeys = {'original_row_data', 'import_source', 'last_access_type', 'last_access_time', 'access_history', 'last_location_info', 'id', 'created', 'updated', 'collectionId', 'collectionName', 'image', 'name', 'code', 'department', 'tag_id', 'is_active', 'remarks', 'is_approved', 'last_approval_status'};
      p.metadata.forEach((key, value) {
        if (!sysKeys.contains(key) && value is! Map && value is! List) {
          metaControllers[key] = TextEditingController(text: value?.toString() ?? "");
        }
      });
      final dynamic nested = p.metadata['original_row_data'];
      if (nested is Map) {
        nested.forEach((key, value) {
          final keyStr = key.toString();
          if (!metaControllers.containsKey(keyStr) && !sysKeys.contains(keyStr)) {
            metaControllers[keyStr] = TextEditingController(text: value?.toString() ?? "");
          }
        });
      }
    }
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(builder: (dialogCtx, setDialogState) {
          Widget imageWidget = const Icon(Icons.camera_alt_outlined, color: Colors.grey, size: 50);
          if (previewBytes != null) {
            imageWidget = ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(previewBytes!, fit: BoxFit.cover));
          } else if (p?.image != null && p!.image!.isNotEmpty) {
            final url = p.getImageUrl(widget.baseUrl);
            if (url != null) {
              imageWidget = ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(url, fit: BoxFit.cover));
            }
          }

          return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              actionsAlignment: MainAxisAlignment.center,
              title: Text(p == null ? '신규 인원 등록' : '정보 수정 및 데이터 편집', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
              content: SizedBox(
                  width: 900,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Column(children: [
                            GestureDetector(
                                onTap: () async {
                                  final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
                                  if (img != null) {
                                    final bytes = await img.readAsBytes();
                                    setDialogState(() {
                                      pickedFile = img;
                                      previewBytes = bytes;
                                    });
                                  }
                                },
                                child: Stack(children: [
                                  Container(width: 180, height: 210, decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black12, width: 2)), child: Center(child: imageWidget)),
                                  Positioned(bottom: 12, right: 12, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle), child: const Icon(Icons.edit, color: Colors.white, size: 18)))
                                ])),
                            const SizedBox(height: 16),
                            Row(children: [
                              const Text("출입 승인", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Switch(
                                  value: isApproved,
                                  activeTrackColor: AppTheme.success.withValues(alpha: 0.5),
                                  activeThumbColor: AppTheme.success,
                                  onChanged: (v) => setDialogState(() => isApproved = v)
                              )
                            ])
                          ]),
                          const SizedBox(width: 30),
                          Expanded(
                              child: Column(children: [
                                _buildStyledField("성명 (필수)", nameC, hint: "성함을 입력하세요"),
                                const SizedBox(height: 16),
                                _buildStyledField("담당부서/소속", deptC, hint: "소속 부서"),
                                const SizedBox(height: 16),
                                _buildStyledField("사번/ID", codeC, hint: "사번 또는 관리 코드"),
                                const SizedBox(height: 16),
                                _buildStyledField("RFID 태그 EPC", tagC, hint: "EPC 코드 직접 입력 가능"),
                                const SizedBox(height: 16),
                                _buildStyledField("기본 비고", remarksC, hint: "특이 사항 기록")
                              ]))
                        ]),
                        if (metaControllers.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          const Row(children: [Icon(Icons.table_view_rounded, size: 22, color: Colors.blueGrey), SizedBox(width: 10), Text("추가 유입 정보 (엑셀 데이터 편집)", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.blueGrey, fontSize: 15)), SizedBox(width: 10), Expanded(child: Divider(thickness: 1.5))]),
                          const SizedBox(height: 20),
                          Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: metaControllers.entries.map((e) => SizedBox(width: 360, child: _buildStyledField(e.key, e.value))).toList())
                        ]
                      ]))),
              actions: [
                _buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () => Navigator.pop(dialogCtx)),
                const SizedBox(width: 16),
                _buildFlatButton(
                    text: "데이터 통합 저장",
                    onPressed: () async {
                      if (nameC.text.trim().isEmpty) {
                        return;
                      }
                      final updatedMeta = Map<String, dynamic>.from(p?.metadata ?? {});
                      metaControllers.forEach((key, ctrl) {
                        updatedMeta[key] = ctrl.text.trim();
                      });
                      final dynamic nested = updatedMeta['original_row_data'];
                      if (nested is Map) {
                        final newNested = Map<String, dynamic>.from(nested);
                        metaControllers.forEach((key, ctrl) {
                          if (newNested.containsKey(key)) {
                            newNested[key] = ctrl.text.trim();
                          }
                        });
                        updatedMeta['original_row_data'] = newNested;
                      }

                      final data = {
                        'name': nameC.text.trim(),
                        'code': codeC.text.trim(),
                        'tag_id': tagC.text.trim(),
                        'department': deptC.text.trim(),
                        'is_approved': isApproved,
                        'remarks': remarksC.text.trim(),
                        'metadata': updatedMeta
                      };

                      final success = await provider.handleSave(p: p, data: data, imageXFile: pickedFile);
                      if (success) {
                        navigator.pop();
                      }
                    })
              ]);
        }));
  }

  void _confirmDelete(BuildContext context, PersonProvider provider, Person p) {
    showDialog(context: context, builder: (c) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), actionsAlignment: MainAxisAlignment.center, title: const Text("정보 삭제 확인", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)), content: Text("[${p.name}]님의 모든 정보를 삭제하시겠습니까?", style: const TextStyle(fontSize: 16)), actions: [_buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () => Navigator.pop(c)), const SizedBox(width: 12), _buildFlatButton(text: "삭제 실행", bgColor: AppTheme.danger, onPressed: () async { final navigator = Navigator.of(c); final success = await provider.deletePerson(p.id); if (success) navigator.pop(); })]));
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
  final TextEditingController _buildingController = TextEditingController(), _gateController = TextEditingController();
  bool _isApproved = true;
  @override
  void initState() {
    super.initState();
    final Set<String> buildings = {'본관A', '공장B', '물류창고C', '연구소D'}, gates = {'정문G1', '후문G2', '하차장G3', '비상구G4'};
    for (var p in widget.existingPersons) {
      final locInfo = p.metadata['last_location_info'];
      if (locInfo is Map) {
        final b = locInfo['building']?.toString(), g = locInfo['gate']?.toString();
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

  Widget _buildFlatButton({required String text, required VoidCallback onPressed, Color? bgColor, Color? textColor}) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onPressed, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12), decoration: BoxDecoration(color: bgColor ?? AppTheme.primary, borderRadius: BorderRadius.circular(8)), child: Text(text, style: TextStyle(color: textColor ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 15)))));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actionsAlignment: MainAxisAlignment.center,
        title: Row(children: [Icon(widget.type == '입장' ? Icons.login : Icons.logout, color: AppTheme.primary, size: 28), const SizedBox(width: 12), Text('${widget.type} 위치 선택', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20))]),
        content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _buildComboField('건물명 (Building)', _buildingController, _buildingOptions),
              const SizedBox(height: 24),
              _buildComboField('출입구 (GATE)', _gateController, _gateOptions),
              const SizedBox(height: 24),
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: _isApproved ? AppTheme.success.withValues(alpha: 0.05) : AppTheme.danger.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: _isApproved ? AppTheme.success.withValues(alpha: 0.2) : AppTheme.danger.withValues(alpha: 0.2))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_isApproved ? "출입 승인됨" : "출입 미승인", style: TextStyle(fontWeight: FontWeight.bold, color: _isApproved ? AppTheme.success : AppTheme.danger)), Switch(value: _isApproved, activeTrackColor: AppTheme.success.withValues(alpha: 0.5), activeThumbColor: AppTheme.success, onChanged: (v) => setState(() => _isApproved = v))]))
            ])),
        actions: [_buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () => Navigator.pop(context)), const SizedBox(width: 12), _buildFlatButton(text: "위치 확정", onPressed: () => Navigator.pop(context, {'building': _buildingController.text, 'gate': _gateController.text, 'is_approved': _isApproved}))]);
  }

  Widget _buildComboField(String label, TextEditingController controller, List<String> options) {
    return Autocomplete<String>(
        optionsBuilder: (val) => val.text == '' ? options : options.where((opt) => opt.contains(val.text)),
        onSelected: (sel) => controller.text = sel,
        fieldViewBuilder: (ctx, textC, focusN, onSubmit) {
          textC.text = controller.text;
          textC.addListener(() => controller.text = textC.text);
          return StatefulBuilder(builder: (context, setFieldState) {
            focusN.addListener(() {
              if (mounted) {
                setFieldState(() {});
              }
            });
            return TextField(
                controller: textC,
                focusNode: focusN,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                    labelText: label,
                    labelStyle: AppTheme.inputLabelStyle.copyWith(fontSize: 14, color: focusN.hasFocus ? AppTheme.primary : Colors.black38),
                    filled: true,
                    fillColor: focusN.hasFocus ? AppTheme.inputFocusColor : AppTheme.inputFillColor,
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.inputBorderColor, width: 1.5)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 2.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18)
                )
            );
          });
        });
  }
}