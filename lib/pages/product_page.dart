import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/products.dart';
import '../providers/product_provider.dart';
import '../providers/person_provider.dart';
import '../theme/app_theme.dart';

/// [UI 설정 객체] 페이지 전체의 일관된 디자인 톤 관리
class ProductUiConfig {
  final TextStyle hintStyle;
  final TextStyle labelStyle;
  final Color inputFillColor;
  final Color inputFocusColor;
  final Color inputBorderColor;
  final double buttonElevation;
  final Color surfaceColor;
  final double outlineWidth;

  const ProductUiConfig({
    this.hintStyle = AppTheme.inputHintStyle,
    this.labelStyle = AppTheme.inputLabelStyle,
    this.inputFillColor = AppTheme.inputFillColor,
    this.inputFocusColor = AppTheme.inputFocusColor,
    this.inputBorderColor = AppTheme.inputBorderColor,
    this.buttonElevation = 0,
    this.surfaceColor = AppTheme.surface,
    this.outlineWidth = 2.0,
  });
}

class ProductPage extends StatefulWidget {
  final String searchQuery;
  final bool isMobile;
  final String baseUrl;
  final ProductUiConfig uiConfig;

  const ProductPage({
    super.key,
    required this.searchQuery,
    required this.isMobile,
    required this.baseUrl,
    this.uiConfig = const ProductUiConfig(),
  });

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  final TextEditingController _searchController = TextEditingController();
  String _currentQuery = "";
  String _groupByMode = 'item';
  String? _selectedGroupKey;

  String _activeMetricFilter = "전체";
  final String _sortCriteria = 'name';

  static const double _colImgSize = 65.0;
  static const double _colActionWidth = 220.0;

  static const Set<String> _inboundStatuses = {
    '보유중', '수동입고', '자동입고', '생산입고', '구매입고', '적치완료', '회수/반납'
  };

  static const Set<String> _processStatuses = {
    '정보등록', '공정투입', '생산중', '생산완료', '이송중', '피킹중', '패킹완료', '출하대기'
  };

  static const Set<String> _outboundStatuses = {
    '수동출고', '자동출고', '판매/배송출고', '대여출고', '수리출고', '현장투입'
  };

  static const Set<String> _exceptionStatuses = {'폐기', '분실'};

  static final Map<String, IconData> _statusIcons = {
    '보유중': Icons.inventory,
    '수동입고': Icons.input,
    '자동입고': Icons.nfc,
    '생산입고': Icons.factory_outlined,
    '구매입고': Icons.shopping_cart,
    '적치완료': Icons.shelves,
    '회수/반납': Icons.assignment_return,
    '정보등록': Icons.app_registration,
    '공정투입': Icons.login_outlined,
    '생산중': Icons.settings_suggest,
    '생산완료': Icons.fact_check,
    '이송중': Icons.local_shipping,
    '피킹중': Icons.hail,
    '패킹완료': Icons.inventory_2,
    '출하대기': Icons.warehouse,
    '수동출고': Icons.outbox,
    '자동출고': Icons.sensors,
    '판매/배송출고': Icons.sell,
    '대여출고': Icons.handshake,
    '수리출고': Icons.build,
    '현장투입': Icons.precision_manufacturing,
    '폐기': Icons.delete_forever,
    '분실': Icons.search_off,
  };

  static const Set<String> _excludedSystemKeys = {
    'excel_row', 'import_date', 'import_data', 'is_auto_tag', 'is_auto_atg',
    'excel_row_internal', 'import_date_internal', 'is_auto_tag_internal',
    'origin_key_map', 'history', 'last_location_info',
    'last_handler', 'last_manual_reason', 'last_processed_at', 'last_approval_status'
  };

  @override
  void initState() {
    super.initState();
    _currentQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getChosung(String text) {
    const chosungList = ['ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'];
    String result = "";
    for (int i = 0; i < text.length; i++) {
      int code = text.codeUnitAt(i) - 0xAC00;
      if (code >= 0 && code <= 11172) {
        result += chosungList[code ~/ 588];
      } else {
        result += text[i];
      }
    }
    return result;
  }

  bool _isMatch(String target, String query) {
    final t = target.toLowerCase();
    final q = query.toLowerCase();
    if (t.contains(q)) {
      return true;
    }
    final RegExp chosungRegExp = RegExp(r'^[ㄱ-ㅎ\s]+$');
    if (chosungRegExp.hasMatch(q)) {
      return _getChosung(t).contains(q);
    }
    return false;
  }

  String _getDisplayValue(ProductModel p, String key) {
    switch (key) {
      case '품명': return p.name;
      case '태그ID': return p.tagId;
      case '위치': return p.location ?? "-";
      case '상태': return _inboundStatuses.contains(p.status) ? "보유중" : p.status;
      case '규격': return p.spec ?? "-";
      case '분류': return p.category ?? "-";
      case 'S/N': return p.serialNumber ?? "-";
      default: return p.metadata[key]?.toString() ?? "-";
    }
  }

  Map<String, dynamic> _calculateMetrics(List<ProductModel> allItems) {
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0; int todayOut = 0; int currentStock = 0;

    for (final item in allItems) {
      final lastDate = item.updated ?? item.created ?? "";
      if (lastDate.startsWith(todayStr)) {
        if (_inboundStatuses.contains(item.status)) {
          todayIn++;
        }
        if (_outboundStatuses.contains(item.status) || _exceptionStatuses.contains(item.status)) {
          todayOut++;
        }
      }
      if (!_outboundStatuses.contains(item.status) && !_exceptionStatuses.contains(item.status)) {
        currentStock++;
      }
    }
    return {'prev': currentStock - todayIn + todayOut, 'in': todayIn, 'out': todayOut, 'stock': currentStock};
  }

  Future<void> _processAssetAccess(ProductProvider provider, ProductModel p, String type) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _ManualInoutDialog(type: type, product: p, uiConfig: widget.uiConfig, statusIcons: _statusIcons),
    );

    if (result == null || !mounted) {
      return;
    }

    final String now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final bool isApproved = result['is_approved'] ?? true;

    final String finalStatus = (result['status'] == null || result['status'].toString().isEmpty)
        ? (type == '수기입고' ? '수동입고' : '수동출고')
        : result['status'];
    final String finalLocation = (result['location'] == null || result['location'].toString().trim().isEmpty)
        ? "미지정 위치" : result['location'];
    final String finalHandler = (result['handler'] == null || result['handler'].toString().trim().isEmpty)
        ? "현장 담당자" : result['handler'];
    final String finalReason = (result['reason'] == null || result['reason'].toString().trim().isEmpty)
        ? "기본 프로세스 처리" : result['reason'];

    List<dynamic> history = p.metadata['history'] is List ? List.from(p.metadata['history']) : [];
    history.insert(0, {
      'time': now,
      'type': finalStatus,
      'location': finalLocation,
      'handler': finalHandler,
      'reason': finalReason,
      'is_approved': isApproved
    });
    if (history.length > 50) {
      history = history.sublist(0, 50);
    }

    final success = await provider.handleSave(
      p: p,
      data: {
        'status': finalStatus,
        'location': finalLocation,
        'is_approved': isApproved,
        'metadata': {
          ...p.metadata,
          'history': history,
          'last_approval_status': isApproved,
          'last_manual_reason': finalReason,
          'last_handler': finalHandler,
          'last_processed_at': now,
        }
      },
    );

    if (success && mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text('[${p.name}] 처리 완료'),
        backgroundColor: isApproved ? AppTheme.success : AppTheme.danger,
        duration: const Duration(seconds: 1),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();

    final filtered = provider.items.where((p) {
      final q = _currentQuery.trim();
      bool matchesSearch = q.isEmpty || _isMatch(p.name, q) || _isMatch(p.location ?? "", q) || _isMatch(p.category ?? "", q);
      if (!matchesSearch) {
        return false;
      }
      if (_activeMetricFilter == "전체") {
        return true;
      }

      final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final lastDate = p.updated ?? p.created ?? "";

      if (_activeMetricFilter == "금일 입고") {
        return lastDate.startsWith(todayStr) && _inboundStatuses.contains(p.status);
      }
      if (_activeMetricFilter == "금일 출고") {
        return lastDate.startsWith(todayStr) && (_outboundStatuses.contains(p.status) || _exceptionStatuses.contains(p.status));
      }
      if (_activeMetricFilter == "현재 실재고") {
        return !_outboundStatuses.contains(p.status) && !_exceptionStatuses.contains(p.status);
      }

      return true;
    }).toList();

    if (_sortCriteria == 'name') {
      filtered.sort((a, b) => a.name.compareTo(b.name));
    } else {
      filtered.sort((a, b) => a.status.compareTo(b.status));
    }

    final metrics = _calculateMetrics(provider.items);
    final groupedMap = _getGroupedData(filtered);
    final groupKeys = groupedMap.keys.toList()..sort();

    return Theme(
      data: AppTheme.lightTheme.copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: AppTheme.fontPretendard),
      ),
      child: Scaffold(
        backgroundColor: widget.uiConfig.surfaceColor,
        body: Stack(
          children: [
            Column(
              children: [
                _buildDashboard(metrics, provider.items.length),
                const Divider(height: 1),
                Expanded(
                  child: LayoutBuilder(builder: (ctx, constraints) {
                    if (constraints.maxWidth > 950 && !widget.isMobile) {
                      return _buildSplitLayout(provider, groupedMap, groupKeys, filtered);
                    }
                    return _buildMobileLayout(provider, groupedMap, groupKeys);
                  }),
                ),
                const SizedBox(height: 20),
              ],
            ),
            if (provider.isParsing || provider.isSaving) ...[
              _buildGlobalLoadingOverlay(provider)
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalLoadingOverlay(ProductProvider provider) {
    return Container(
      color: Colors.black26,
      child: Center(
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppTheme.primary),
                const SizedBox(height: 20),
                Text(provider.isParsing ? "데이터 분석 중..." : "저장 중...",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<String, List<ProductModel>> _getGroupedData(List<ProductModel> items) {
    final Map<String, List<ProductModel>> grouped = {};
    for (final item in items) {
      String key;
      if (_groupByMode == 'item') {
        key = item.name;
      } else if (_groupByMode == 'location') {
        key = item.location ?? "미지정";
      } else {
        key = item.category ?? "미정";
      }

      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(item);
    }
    return grouped;
  }

  Widget _buildDashboard(Map<String, dynamic> m, int totalCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: Colors.white,
      child: LayoutBuilder(builder: (ctx, constraints) {
        if (constraints.maxWidth > 850) {
          return Row(
            children: [
              Expanded(child: _buildStatTile("자산 마스터", totalCount, Icons.list_alt, Colors.blueGrey, filterKey: "전체")),
              const SizedBox(width: 12),
              Expanded(child: _buildStatTile("금일 입고/보유", m['in'], Icons.add_business_outlined, Colors.green, filterKey: "금일 입고")),
              const SizedBox(width: 12),
              Expanded(child: _buildStatTile("금일 출하/이탈", m['out'], Icons.local_shipping_outlined, Colors.orange, filterKey: "금일 출고")),
              const SizedBox(width: 12),
              Expanded(child: _buildStatTile("현재 실가용고", m['stock'], Icons.inventory_2_outlined, AppTheme.primary, filterKey: "현재 실재고")),
            ],
          );
        } else {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildStatTile("자산 마스터", totalCount, Icons.list_alt, Colors.blueGrey, filterKey: "전체")),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatTile("금일 입고/보유", m['in'], Icons.add_business_outlined, Colors.green, filterKey: "금일 입고")),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildStatTile("금일 출하/이탈", m['out'], Icons.local_shipping_outlined, Colors.orange, filterKey: "금일 출고")),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatTile("현재 실가용고", m['stock'], Icons.inventory_2_outlined, AppTheme.primary, filterKey: "현재 실재고")),
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
      onTap: () => setState(() { _activeMetricFilter = _activeMetricFilter == filterKey ? "전체" : filterKey; _selectedGroupKey = null; }),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.3), width: isSelected ? 3 : 2),
          boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))] : null,
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

  Widget _buildSplitLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys, List<ProductModel> filtered) {
    return Row(
      children: [
        Container(
          width: 420, color: Colors.white,
          child: Column(
            children: [
              _buildHeader(provider, filtered),
              _buildFilterBar(),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  itemCount: groupKeys.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, idx) => _buildGroupTile(provider, groupKeys[idx], groupedMap[groupKeys[idx]]!, _selectedGroupKey == groupKeys[idx], false),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Container(
            color: widget.uiConfig.surfaceColor,
            padding: const EdgeInsets.only(left: 12),
            child: _selectedGroupKey == null
                ? _buildEmptyState("항목을 선택하여 상세 자산 정보를 확인하세요.")
                : _buildDetailView(provider, _selectedGroupKey!, groupedMap[_selectedGroupKey] ?? [], key: ValueKey('detail_$_selectedGroupKey')),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys) {
    return Column(
      children: [
        _buildHeader(provider, provider.items),
        _buildFilterBar(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 50),
            itemCount: groupKeys.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, idx) => _buildGroupTile(provider, groupKeys[idx], groupedMap[groupKeys[idx]]!, false, true),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ProductProvider provider, List<ProductModel> filtered) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 4, runSpacing: 4,
                  children: [
                    _buildActionIcon(Icons.refresh, "새로고침", () => provider.fetchData()),
                    _buildActionIcon(FontAwesomeIcons.fileArrowUp, "임포트", () async {
                      final res = await provider.batchImportFromExcel();
                      if (res['total']! > 0) {
                        _showInfoDialog("임포트 완료", "성공: ${res['success']} / 전체: ${res['total']}");
                      }
                    }, color: Colors.indigo),
                    _buildActionIcon(FontAwesomeIcons.fileArrowDown, "엑스포트", () => _exportToExcel(context, filtered), color: Colors.green),
                    _buildActionIcon(Icons.settings_outlined, "표시 설정", () => _showColumnSelectionDialog(provider)),
                    _buildActionIcon(Icons.delete_sweep_outlined, "리셋", () => _showResetDialog(provider), color: AppTheme.danger),
                  ],
                ),
              ),
              _buildActionIcon(Icons.add_box, "신규 등록", () => _showForm(context, provider, null), color: AppTheme.primary, isLarge: true),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _currentQuery = v),
            decoration: InputDecoration(
              hintText: '품명, 로케이션, 분류 또는 초성 검색...',
              hintStyle: widget.uiConfig.hintStyle,
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true, fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Color(0xFFE9ECEF), width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, String tip, VoidCallback onTap, {Color? color, bool isLarge = false}) {
    return Tooltip(message: tip, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: Container(width: 44, height: 44, alignment: Alignment.center, child: Icon(icon, color: color ?? Colors.black54, size: isLarge ? 30 : 20))));
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 20),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          style: SegmentedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          segments: const [
            ButtonSegment(value: 'item', label: Text('품명별', style: TextStyle(fontWeight: FontWeight.bold))),
            ButtonSegment(value: 'location', label: Text('위치별', style: TextStyle(fontWeight: FontWeight.bold))),
            ButtonSegment(value: 'category', label: Text('분류별', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          selected: {_groupByMode},
          onSelectionChanged: (Set<String> v) => setState(() { _groupByMode = v.first; _selectedGroupKey = null; }),
        ),
      ),
    );
  }

  Widget _buildDetailView(ProductProvider provider, String groupName, List<ProductModel> items, {Key? key}) {
    final cols = provider.selectedColumns;

    return Column(
      key: key,
      children: [
        Container(
          padding: const EdgeInsets.all(16), color: Colors.white,
          child: Row(children: [Container(width: 4, height: 18, color: AppTheme.primary), const SizedBox(width: 8), Text(groupName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))]),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 70),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, idx) {
              final p = items[idx];
              final bool isApproved = p.isApproved;
              return InkWell(
                onTap: () => _showForm(context, provider, p),
                child: Container(
                  decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      border: Border.all(color: _getStatusColor(p.status), width: AppTheme.outlineWidth),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))]
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _buildThumbnail(p, size: _colImgSize),
                        const SizedBox(width: 16),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              const SizedBox(width: 12),
                              _buildStatusBadge(p.status),
                              if (!isApproved) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18),
                              ]
                            ]),
                            const SizedBox(height: 10),
                            Wrap(spacing: 20, runSpacing: 8, children: cols.where((c) => c != '품명').map((c) => SizedBox(width: 130, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c, style: const TextStyle(fontSize: 10, color: Colors.black26, fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text(_getDisplayValue(p, c), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87), overflow: TextOverflow.ellipsis)]))).toList()),
                          ],
                        )),
                        SizedBox(width: _colActionWidth, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          _buildCircleAction(Icons.history, Colors.blueGrey, "이력", () => _showHistoryDialog(context, p)),
                          const SizedBox(width: 8),
                          _buildCircleAction(Icons.login, AppTheme.success, "입고", () => _processAssetAccess(provider, p, '수기입고')),
                          const SizedBox(width: 8),
                          _buildCircleAction(Icons.logout, AppTheme.warning, "출고", () => _processAssetAccess(provider, p, '수기출고')),
                          const SizedBox(width: 8),
                          _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () => _confirmIndividualDelete(context, provider, p)),
                        ])),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    if (_inboundStatuses.contains(status)) {
      return AppTheme.success;
    }
    if (_exceptionStatuses.contains(status)) {
      return AppTheme.danger;
    }
    if (_outboundStatuses.contains(status)) {
      return Colors.grey;
    }
    return Colors.orange;
  }

  Widget _buildStatusBadge(String status) {
    String label = _inboundStatuses.contains(status) ? "보유중" : status;
    Color color = _inboundStatuses.contains(status) ? AppTheme.success
        : (_processStatuses.contains(status) ? Colors.blueAccent
        : ((_outboundStatuses.contains(status) || _exceptionStatuses.contains(status)) ? Colors.blueGrey : Colors.orange));

    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900))
    );
  }

  void _showHistoryDialog(BuildContext context, ProductModel p) {
    final List<dynamic> history = p.metadata['history'] is List ? List.from(p.metadata['history']) : [];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.history, color: Colors.blueGrey), const SizedBox(width: 12), Text('[${p.name}] 상세 추적 이력', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20))]),
        content: SizedBox(
          width: 550, height: 600,
          child: history.isEmpty
              ? _buildEmptyState("이력이 없습니다.")
              : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: history.length,
              separatorBuilder: (c, i) => const Divider(height: 24, color: Color(0xFFF1F3F5)),
              itemBuilder: (c, i) {
                final log = history[i];
                final String type = log['type'] ?? "-";
                final String time = log['time'] ?? "-";
                final bool approved = log['is_approved'] ?? true;
                Color statusColor = _getStatusColor(type);

                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6, right: 16), decoration: BoxDecoration(color: approved ? statusColor : AppTheme.danger, shape: BoxShape.circle)),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(time, style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                      Row(children: [
                        if (!approved) ...[
                          const Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 14),
                          const SizedBox(width: 4),
                          const Text("미승인", style: TextStyle(color: AppTheme.danger, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                        ],
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text(type, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11))),
                      ])
                    ]),
                    const SizedBox(height: 4),
                    Text("위치: ${log['location'] ?? '-'} | 담당: ${log['handler'] ?? '-'}", style: const TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.w600)),
                    if (log['reason']?.toString().isNotEmpty == true) ...[
                      Text("상세비고: ${log['reason']}", style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
                    ]
                  ]))
                ]);
              }
          ),
        ),
        actions: [_buildFlatButton(text: "닫기", bgColor: Colors.blueGrey, onPressed: () => Navigator.pop(ctx))],
      ),
    );
  }

  Widget _buildCircleAction(IconData icon, Color color, String tip, VoidCallback onTap) {
    return Tooltip(message: tip, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: 0.08), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20))));
  }

  Future<void> _exportToExcel(BuildContext context, List<ProductModel> list) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['Inventory'];
      sheet.appendRow([excel_pkg.TextCellValue('품명'), excel_pkg.TextCellValue('태그ID'), excel_pkg.TextCellValue('로케이션'), excel_pkg.TextCellValue('상태')]);
      for (final i in list) {
        sheet.appendRow([excel_pkg.TextCellValue(i.name), excel_pkg.TextCellValue(i.tagId), excel_pkg.TextCellValue(i.location ?? ""), excel_pkg.TextCellValue(i.status)]);
      }
      final path = await FilePicker.platform.saveFile(fileName: 'Inventory_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx']);
      if (path != null) {
        await File(path).writeAsBytes(excel.encode()!);
        if (mounted) {
          messenger.showSnackBar(const SnackBar(content: Text('✅ 데이터 내보내기 성공')));
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('❌ 내보내기 실패: $e')));
      }
    }
  }

  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, bool isMobile) {
    final healthRatio = items.isEmpty ? 0.0 : items.where((i) => _inboundStatuses.contains(i.status)).length / items.length;
    Color hCol = healthRatio == 1.0 ? AppTheme.success : (healthRatio > 0.4 ? Colors.orange : AppTheme.danger);

    return InkWell(
      onTap: () { if (isMobile) { _showMobileGroupDetail(provider, title, items); } else { setState(() => _selectedGroupKey = title); } },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: isSelected ? AppTheme.primary : hCol.withValues(alpha: 0.5), width: isSelected ? 3.0 : 2.0),
            boxShadow: isSelected ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 10)] : null
        ),
        child: Row(children: [
          _buildThumbnail(items.first, size: 48), const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: hCol.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: hCol.withValues(alpha: 0.4), width: 1.2)),
              child: Text('${items.length}', style: TextStyle(color: hCol, fontWeight: FontWeight.w900, fontSize: 13))
          ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.delete_sweep_rounded, color: AppTheme.danger, size: 22), onPressed: () => _confirmGroupDelete(context, provider, title, items)),
        ]),
      ),
    );
  }

  Widget _buildThumbnail(ProductModel p, {double size = 44}) {
    final url = p.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(width: size, height: size, decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(10)), clipBehavior: Clip.antiAlias, child: url != null ? Image.network("$url?t=${p.updated}", fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 18, color: Colors.black12)) : const Icon(Icons.inventory_2_outlined, color: Colors.black12, size: 22));
  }

  Widget _buildFlatButton({required String text, required VoidCallback onPressed, Color? bgColor, Color? textColor}) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onPressed, borderRadius: BorderRadius.circular(28), child: Container(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), decoration: BoxDecoration(color: bgColor ?? AppTheme.primary, borderRadius: BorderRadius.circular(8)), child: Text(text, style: TextStyle(color: textColor ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 14)))));
  }

  Future<void> _showForm(BuildContext context, ProductProvider provider, ProductModel? p, {String? initialTag}) async {
    final nameC = TextEditingController(text: p?.name ?? ""), tagC = TextEditingController(text: initialTag ?? p?.tagId ?? ""), locC = TextEditingController(text: p?.location ?? ""), catC = TextEditingController(text: p?.category ?? ""), specC = TextEditingController(text: p?.spec ?? ""), snC = TextEditingController(text: p?.serialNumber ?? ""), safeC = TextEditingController(text: p?.safetyStock.toString() ?? "5"), qtyC = TextEditingController(text: "1");
    String selStatus = p?.status ?? "보유중";
    bool isApproved = p?.isApproved ?? true; XFile? file; Uint8List? preview;
    final Map<String, TextEditingController> metaC = {};
    if (p != null) {
      p.metadata.forEach((k, v) { if (!_excludedSystemKeys.contains(k)) metaC[k] = TextEditingController(text: v?.toString() ?? ""); });
    } else {
      for (var k in provider.items.expand((i) => i.metadata.keys).toSet()) { if (!_excludedSystemKeys.contains(k)) metaC[k] = TextEditingController(); }
    }

    await showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (dialogCtx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(p == null ? "자산 마스터 신규 등록" : "마스터 제원 상세 수정", style: const TextStyle(fontWeight: FontWeight.bold)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20), actionsAlignment: MainAxisAlignment.center,
        content: SizedBox(width: MediaQuery.of(ctx).size.width > 850 ? 800 : 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              GestureDetector(onTap: () async { final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70); if (img != null) { final b = await img.readAsBytes(); setS(() { file = img; preview = b; }); } }, child: Container(width: 140, height: 140, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black12)), clipBehavior: Clip.antiAlias, child: preview != null ? Image.memory(preview!, fit: BoxFit.cover) : (p?.getImageUrl(widget.baseUrl) != null ? Image.network("${p!.getImageUrl(widget.baseUrl)}?t=${p.updated}", fit: BoxFit.cover) : const Icon(Icons.camera_alt, size: 40, color: Colors.grey)))),
              const SizedBox(height: 16),
              Row(children: [const Text("승인 상태", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), const SizedBox(width: 8), Switch(value: isApproved, activeTrackColor: AppTheme.success.withValues(alpha: 0.5), activeThumbColor: AppTheme.success, onChanged: (v) => setS(() => isApproved = v))]),
            ]),
            const SizedBox(width: 24),
            Expanded(child: Column(children: [_buildStyledField("품명 (필수)", nameC), const SizedBox(height: 16), _buildStyledField("태그ID (RFID EPC)", tagC)]))
          ]),
          const SizedBox(height: 24), _buildSectionHeader(Icons.star, "기본 제원 정보", Colors.blue), const SizedBox(height: 20),
          Wrap(spacing: 16, runSpacing: 16, children: [
            SizedBox(width: 370, child: _buildStyledField("로케이션", locC)), SizedBox(width: 370, child: _buildStyledField("자산 카테고리", catC)), SizedBox(width: 370, child: _buildStyledField("모델 규격", specC)), SizedBox(width: 370, child: _buildStyledField("안전재고수량", safeC, keyboardType: TextInputType.number)), SizedBox(width: 370, child: _buildStyledField("S/N", snC)),
            SizedBox(width: 370, child: _buildIconicDropdown(label: "현재 물류 상태", initialValue: selStatus, items: _statusIcons.keys.toList(), statusIcons: _statusIcons, onChanged: (v) { if (v != null) setS(() => selStatus = v); })),
          ]),
          if (metaC.isNotEmpty) ...[
            const SizedBox(height: 32), _buildSectionHeader(Icons.table_view, "추가 메타데이터", Colors.green), const SizedBox(height: 20),
            Wrap(spacing: 16, runSpacing: 16, children: metaC.entries.map((e) => SizedBox(width: 370, child: _buildStyledField(e.key, e.value))).toList())
          ],
          if (p == null) ...[
            const SizedBox(height: 32), _buildSectionHeader(Icons.copy_all, "벌크 생성", Colors.orange), const SizedBox(height: 20),
            SizedBox(width: 370, child: _buildStyledField("등록 수량", qtyC, keyboardType: TextInputType.number))
          ],
        ]))),
        actions: [_buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () => Navigator.pop(dialogCtx)), const SizedBox(width: 12), _buildFlatButton(text: "통합 저장", onPressed: () async {
          final String finalName = nameC.text.trim().isEmpty ? "임시 품명_${DateFormat('HHmm').format(DateTime.now())}" : nameC.text.trim();
          final String finalTag = tagC.text.trim().isEmpty ? "TAG_NONE" : tagC.text.trim();
          final String finalLoc = locC.text.trim().isEmpty ? "미지정" : locC.text.trim();
          final nav = Navigator.of(dialogCtx); final int loop = int.tryParse(qtyC.text.trim()) ?? 1; final meta = Map<String, dynamic>.from(p?.metadata ?? {});
          metaC.forEach((k, v) { meta[k] = v.text.trim().isEmpty ? "미기입" : v.text.trim(); });
          bool ok = true;
          if (p == null) { for (int i = 0; i < loop; i++) { String tid = finalTag; if (loop > 1 && tid != "TAG_NONE") { tid = "${tid}_${i + 1}"; } final res = await provider.handleSave(p: null, data: {'name': finalName, 'tag_id': tid, 'location': finalLoc, 'category': catC.text.trim(), 'spec': specC.text.trim(), 'serial_number': snC.text.trim(), 'status': selStatus, 'safety_stock': int.tryParse(safeC.text.trim()) ?? 5, 'is_approved': isApproved, 'metadata': meta}, imageXFile: file); if (!res) { ok = false; } } }
          else { ok = await provider.handleSave(p: p, data: {'name': finalName, 'tag_id': finalTag, 'location': finalLoc, 'category': catC.text.trim(), 'spec': specC.text.trim(), 'serial_number': snC.text.trim(), 'status': selStatus, 'safety_stock': int.tryParse(safeC.text.trim()) ?? 5, 'is_approved': isApproved, 'metadata': meta}, imageXFile: file); }
          if (ok && mounted) { nav.pop(); }
        }), ],
      )),
    );
  }

  Widget _buildIconicDropdown({required String label, required String initialValue, required List<String> items, required Map<String, IconData> statusIcons, required ValueChanged<String?> onChanged}) {
    return StatefulBuilder(builder: (context, setS) => Focus(onFocusChange: (hasFocus) => setS(() {}), child: Builder(builder: (ctx) {
      final bool hasFocus = Focus.of(ctx).hasFocus;
      return DropdownButtonFormField<String>(initialValue: initialValue, decoration: InputDecoration(labelText: label, labelStyle: widget.uiConfig.labelStyle.copyWith(color: hasFocus ? AppTheme.primary : Colors.black38), filled: true, fillColor: hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor, enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.uiConfig.inputBorderColor)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primary, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)), items: items.map((val) => DropdownMenuItem(value: val, child: Row(children: [Icon(statusIcons[val] ?? Icons.help_outline, size: 18, color: AppTheme.primary.withValues(alpha: 0.7)), const SizedBox(width: 12), Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))]))).toList(), onChanged: onChanged);
    })));
  }

  void _showColumnSelectionDialog(ProductProvider provider) {
    final base = ['품명', '태그ID', '위치', '상태', '규격', '분류', 'S/N'];
    final Set<String> metaKeySet = {};
    int count = provider.items.length > 100 ? 100 : provider.items.length;
    for (int i = 0; i < count; i++) { metaKeySet.addAll(provider.items[i].metadata.keys); }
    final metaKeys = metaKeySet.where((k) => !_excludedSystemKeys.contains(k)).toList()..sort();
    final all = [...base, ...metaKeys]; List<String> temp = List.from(provider.selectedColumns);
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setS) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text("표시 항목 설정", style: TextStyle(fontWeight: FontWeight.bold)), content: SizedBox(width: 350, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: all.map((k) => CheckboxListTile(title: Text(k, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), activeColor: AppTheme.primary, value: temp.contains(k), onChanged: (v) { setS(() { if (v == true) { if (temp.length < 5) { temp.add(k); } } else { if (temp.length > 1) { temp.remove(k); } } }); })).toList()))), actions: [_buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () => Navigator.pop(ctx)), const SizedBox(width: 8), _buildFlatButton(text: "적용", onPressed: () async { final nav = Navigator.of(ctx); await provider.saveRemoteSettings(temp); if (mounted) { nav.pop(); } })])));
  }

  void _confirmGroupDelete(BuildContext ctx, ProductProvider provider, String name, List<ProductModel> items) {
    showDialog(context: ctx, builder: (c) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text("그룹 일괄 삭제"), content: Text("[$name] 그룹의 모든 자산(${items.length}개)을 삭제하시겠습니까?"), actions: [_buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () => Navigator.pop(c)), const SizedBox(width: 8), _buildFlatButton(text: "일괄 삭제", bgColor: AppTheme.danger, onPressed: () async { final nav = Navigator.of(c); await provider.deleteMultipleProducts(items.map((e) => e.id).toList()); setState(() => _selectedGroupKey = null); if (mounted) { nav.pop(); } })]));
  }

  void _showResetDialog(ProductProvider provider) {
    showDialog(context: context, builder: (ctx) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text("전체 초기화"), content: const Text("모든 정보를 삭제하고 설정을 리셋하시겠습니까?"), actions: [_buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () => Navigator.pop(ctx)), const SizedBox(width: 8), _buildFlatButton(text: "삭제", bgColor: AppTheme.danger, onPressed: () async { final nav = Navigator.of(ctx); await provider.resetAllProducts(); setState(() => _selectedGroupKey = null); if (mounted) { nav.pop(); } })]));
  }

  void _confirmIndividualDelete(BuildContext ctx, ProductProvider provider, ProductModel p) {
    showDialog(context: ctx, builder: (c) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: const Text("삭제 확인"), content: Text("[${p.name}] 자산을 삭제하시겠습니까?"), actions: [_buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () => Navigator.pop(c)), const SizedBox(width: 8), _buildFlatButton(text: "삭제", bgColor: AppTheme.danger, onPressed: () async { final nav = Navigator.of(c); await provider.deleteMultipleProducts([p.id]); if (mounted) { nav.pop(); } })]));
  }

  void _showInfoDialog(String title, String msg) {
    showDialog(context: context, builder: (ctx) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), content: Text(msg), actions: [_buildFlatButton(text: "확인", onPressed: () => Navigator.pop(ctx))]));
  }

  void _showMobileGroupDetail(ProductProvider provider, String group, List<ProductModel> items) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => Container(decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))), height: MediaQuery.of(context).size.height * 0.85, child: _buildDetailView(provider, group, items)));
  }

  Widget _buildSectionHeader(IconData icon, String title, Color color) {
    return Column(children: [Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 8), Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 13))]), const Divider()]);
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.touch_app_outlined, size: 80, color: Colors.grey[300]), const SizedBox(height: 16), Text(msg, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))]));
  }

  Widget _buildStyledField(String label, TextEditingController ctrl, {TextInputType keyboardType = TextInputType.text}) {
    return StatefulBuilder(builder: (context, setS) => Focus(onFocusChange: (hasFocus) => setS(() {}), child: Builder(builder: (ctx) {
      final bool hasFocus = Focus.of(ctx).hasFocus;
      return TextField(controller: ctrl, keyboardType: keyboardType, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: InputDecoration(labelText: label, labelStyle: widget.uiConfig.labelStyle.copyWith(color: hasFocus ? AppTheme.primary : Colors.black38), filled: true, fillColor: hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor, enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.uiConfig.inputBorderColor)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primary, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)));
    })));
  }
}

class _ManualInoutDialog extends StatefulWidget {
  final String type;
  final ProductModel product;
  final ProductUiConfig uiConfig;
  final Map<String, IconData> statusIcons;
  const _ManualInoutDialog({required this.type, required this.product, required this.uiConfig, required this.statusIcons});
  @override
  State<_ManualInoutDialog> createState() => _ManualInoutDialogState();
}

class _ManualInoutDialogState extends State<_ManualInoutDialog> {
  late TextEditingController _locC, _reasonC;
  late String _selS;
  bool _isApproved = true;
  String _selectedHandler = "";

  @override
  void initState() {
    super.initState();
    _locC = TextEditingController(text: widget.product.location ?? "미지정 로케이션");
    _reasonC = TextEditingController(text: "현장 수동 처리");
    _selS = widget.type == '수기입고' ? '보유중' : '수동출고';
  }

  @override
  void dispose() { _locC.dispose(); _reasonC.dispose(); super.dispose(); }

  Widget _buildStyledField(String label, TextEditingController ctrl) {
    return StatefulBuilder(builder: (context, setS) => Focus(onFocusChange: (hasFocus) => setS(() {}), child: Builder(builder: (ctx) {
      final bool hasFocus = Focus.of(ctx).hasFocus;
      return TextField(controller: ctrl, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: InputDecoration(labelText: label, labelStyle: widget.uiConfig.labelStyle.copyWith(color: hasFocus ? AppTheme.primary : Colors.black38), filled: true, fillColor: hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor, enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.uiConfig.inputBorderColor)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primary, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)));
    })));
  }

  Widget _buildIconicDropdown({required String label, required String initialValue, required List<String> items, required Map<String, IconData> statusIcons, required ValueChanged<String?> onChanged}) {
    return StatefulBuilder(builder: (context, setS) => Focus(onFocusChange: (hasFocus) => setS(() {}), child: Builder(builder: (ctx) {
      final bool hasFocus = Focus.of(ctx).hasFocus;
      return DropdownButtonFormField<String>(initialValue: initialValue, decoration: InputDecoration(labelText: label, labelStyle: widget.uiConfig.labelStyle.copyWith(color: hasFocus ? AppTheme.primary : Colors.black38), filled: true, fillColor: hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor, enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.uiConfig.inputBorderColor)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primary, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)), items: items.map((val) => DropdownMenuItem(value: val, child: Row(children: [Icon(statusIcons[val] ?? Icons.help_outline, size: 18, color: AppTheme.primary.withValues(alpha: 0.7)), const SizedBox(width: 12), Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))]))).toList(), onChanged: onChanged);
    })));
  }

  @override
  Widget build(BuildContext context) {
    final isIn = widget.type == '수기입고';
    final items = isIn
        ? ['보유중', '수동입고', '자동입고', '생산입고', '구매입고', '적치완료', '회수/반납']
        : ['수동출고', '자동출고', '판매/배송출고', '대여출고', '수리출고', '현장투입', '폐기', '분실'];

    final personProvider = context.watch<PersonProvider>();
    final List<String> workerInfoList = personProvider.list.map((p) => "${p.name} (${p.code} / ${p.department})").toList();

    return Theme(
      data: AppTheme.lightTheme,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(isIn ? Icons.login : Icons.logout, color: isIn ? AppTheme.success : AppTheme.warning),
          const SizedBox(width: 12),
          Expanded(child: Text('${widget.type} - ${widget.product.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), overflow: TextOverflow.ellipsis))
        ]),
        content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      _buildIconicDropdown(label: "수행할 작업 선택", initialValue: _selS, items: items, statusIcons: widget.statusIcons, onChanged: (v) { if (v != null) { setState(() => _selS = v); } }),
                      const SizedBox(height: 16),
                      _buildStyledField("로케이션 (위치 정보)", _locC),
                      const SizedBox(height: 16),
                      _buildWorkerSelectionField(personProvider.isLoading ? "작업자 로드 중..." : "담당 작업자 선택 (미지정 시 '현장 담당자')", workerInfoList),
                      const SizedBox(height: 16),
                      _buildStyledField("상세 사유 및 비고", _reasonC),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: _isApproved ? AppTheme.success.withValues(alpha: 0.05) : AppTheme.danger.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: _isApproved ? AppTheme.success.withValues(alpha: 0.2) : AppTheme.danger.withValues(alpha: 0.2))),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_isApproved ? "처리 승인됨" : "처리 미승인", style: TextStyle(fontWeight: FontWeight.bold, color: _isApproved ? AppTheme.success : AppTheme.danger)),
                            Switch(value: _isApproved, activeTrackColor: AppTheme.success.withValues(alpha: 0.5), activeThumbColor: AppTheme.success, onChanged: (v) => setState(() => _isApproved = v)),
                          ],
                        ),
                      )
                    ]
                )
            )
        ),
        actions: [
          _buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () => Navigator.pop(context)),
          const SizedBox(width: 12),
          _buildFlatButton(text: "처리 확정", onPressed: () {
            Navigator.pop(context, {
              'status': _selS,
              'location': _locC.text.trim().isEmpty ? "미지정 위치" : _locC.text.trim(),
              'handler': _selectedHandler.isEmpty ? "현장 담당자" : _selectedHandler,
              'reason': _reasonC.text.trim().isEmpty ? "기본 프로세스 처리" : _reasonC.text.trim(),
              'is_approved': _isApproved
            });
          }),
        ],
      ),
    );
  }

  Widget _buildWorkerSelectionField(String label, List<String> options) {
    return Autocomplete<String>(
      optionsBuilder: (textVal) => textVal.text == '' ? options : options.where((opt) => opt.toLowerCase().contains(textVal.text.toLowerCase())),
      onSelected: (sel) => _selectedHandler = sel,
      fieldViewBuilder: (ctx, ctrl, focusN, onSubmitted) {
        ctrl.addListener(() => _selectedHandler = ctrl.text);
        return StatefulBuilder(builder: (ctx, setS) {
          focusN.addListener(() { if (mounted) { setS(() {}); } });
          return TextField(
            controller: ctrl, focusNode: focusN,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: label, labelStyle: widget.uiConfig.labelStyle.copyWith(color: focusN.hasFocus ? AppTheme.primary : Colors.black38),
              filled: true, fillColor: focusN.hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.uiConfig.inputBorderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          );
        });
      },
    );
  }

  Widget _buildFlatButton({required String text, required VoidCallback onPressed, Color? bgColor, Color? textColor}) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onPressed, borderRadius: BorderRadius.circular(28), child: Container(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), decoration: BoxDecoration(color: bgColor ?? AppTheme.primary, borderRadius: BorderRadius.circular(8)), child: Text(text, style: TextStyle(color: textColor ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 14)))));
  }
}