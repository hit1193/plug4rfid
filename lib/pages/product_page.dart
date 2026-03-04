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

import '../models/products.dart';
import '../providers/product_provider.dart';
import '../providers/person_provider.dart';
import '../theme/app_theme.dart';

class ProductPage extends StatefulWidget {
  final String searchQuery;
  final bool isMobile;
  final String baseUrl;

  const ProductPage({
    super.key,
    required this.searchQuery,
    required this.isMobile,
    required this.baseUrl,
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

  Timer? _debounceTimer;
  List<ProductModel> _filteredCache = [];
  int _lastRawItemCount = -1;
  String _lastActiveFilter = "";

  static const double _colImgSize = 65.0;
  static const double _colActionWidth = 230.0;

  // [상태 정의] FA/RFID 공정 단계별 상태 상수
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
    '보유중': Icons.inventory, '수동입고': Icons.input, '자동입고': Icons.nfc,
    '생산입고': Icons.factory_outlined, '구매입고': Icons.shopping_cart, '적치완료': Icons.shelves,
    '회수/반납': Icons.assignment_return, '정보등록': Icons.app_registration, '공정투입': Icons.login_outlined,
    '생산중': Icons.settings_suggest, '생산완료': Icons.fact_check, '이송중': Icons.local_shipping,
    '피킹중': Icons.hail, '패킹완료': Icons.inventory_2, '출하대기': Icons.warehouse,
    '수동출고': Icons.outbox, '자동출고': Icons.sensors, '판매/배송출고': Icons.sell,
    '대여출고': Icons.handshake, '수리출고': Icons.build, '현장투입': Icons.precision_manufacturing,
    '폐기': Icons.delete_forever, '분실': Icons.search_off,
  };

  static const Set<String> _excludedSystemKeys = {
    'id', 'collectionId', 'collectionName', 'created', 'updated',
    'excel_row', 'import_date', 'import_data', 'is_auto_tag', 'is_auto_atg',
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
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _currentQuery = query;
          _syncFiltering(context.read<ProductProvider>().items);
        });
      }
    });
  }

  void _syncFiltering(List<ProductModel> rawItems) {
    final String q = _currentQuery.trim().toLowerCase();
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    List<ProductModel> result = rawItems.where((p) {
      bool isMatch = true;
      if (q.isNotEmpty) {
        isMatch = p.name.toLowerCase().contains(q) ||
            p.tagId.toLowerCase().contains(q) ||
            (p.location?.toLowerCase().contains(q) ?? false) ||
            (p.category?.toLowerCase().contains(q) ?? false) ||
            (p.serialNumber?.toLowerCase().contains(q) ?? false);

        if (!isMatch) {
          for (var value in p.metadata.values) {
            if (value != null && value.toString().toLowerCase().contains(q)) {
              isMatch = true;
              break;
            }
          }
        }
      }

      if (!isMatch) {
        return false;
      }

      if (_activeMetricFilter == "전체") {
        return true;
      }

      final String lastDate = p.updated ?? p.created ?? "";
      final bool isOut = _outboundStatuses.contains(p.status) || _exceptionStatuses.contains(p.status);

      if (_activeMetricFilter == "금일 입고") {
        return lastDate.startsWith(todayStr) && _inboundStatuses.contains(p.status);
      }
      if (_activeMetricFilter == "금일 출고") {
        return lastDate.startsWith(todayStr) && isOut;
      }
      if (_activeMetricFilter == "현재 실재고") {
        return !isOut;
      }
      return true;
    }).toList();

    if (_sortCriteria == 'name') {
      result.sort((a, b) {
        return a.name.compareTo(b.name);
      });
    }

    _filteredCache = result;
    _lastRawItemCount = rawItems.length;
    _lastActiveFilter = _activeMetricFilter;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();

    if (_lastRawItemCount != provider.items.length || _lastActiveFilter != _activeMetricFilter) {
      _syncFiltering(provider.items);
    }

    final Map<String, dynamic> metrics = _calculateMetrics(provider.items);
    final Map<String, List<ProductModel>> groupedMap = _getGroupedData(_filteredCache);
    final List<String> groupKeys = groupedMap.keys.toList()..sort();

    return Theme(
      data: AppTheme.lightTheme,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Column(
              children: [
                _buildDashboard(metrics, provider.items.length),
                const Divider(height: 1, color: Colors.black12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      if (constraints.maxWidth > 950 && !widget.isMobile) {
                        return _buildSplitLayout(provider, groupedMap, groupKeys, _filteredCache);
                      }
                      return _buildMobileLayout(provider, groupedMap, groupKeys);
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
            if (provider.isParsing || provider.isSaving) ...[
              _buildGlobalLoadingOverlay(provider),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalLoadingOverlay(ProductProvider provider) {
    return Container(
      color: Colors.black.withValues(alpha: 0.1),
      child: Center(
        child: Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            side: const BorderSide(color: Colors.black12, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppTheme.primary),
                const SizedBox(height: 20),
                Text(
                  provider.isParsing ? "데이터 분석 중..." : "저장 중...",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(Map<String, dynamic> m, int totalCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(child: _buildStatTile("자산 마스터", totalCount, Icons.list_alt, Colors.blueGrey, filterKey: "전체")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("금일 입고", m['in'] as int, Icons.add_business_outlined, AppTheme.success, filterKey: "금일 입고")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("금일 출고", m['out'] as int, Icons.local_shipping_outlined, AppTheme.warning, filterKey: "금일 출고")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("현재 실재고", m['stock'] as int, Icons.inventory_2_outlined, AppTheme.primary, filterKey: "현재 실재고")),
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, int val, IconData icon, Color color, {required String filterKey}) {
    final bool isSelected = _activeMetricFilter == filterKey;
    return InkWell(
      onTap: () {
        setState(() {
          _activeMetricFilter = _activeMetricFilter == filterKey ? "전체" : filterKey;
          _selectedGroupKey = null;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? color : Colors.black12, width: isSelected ? 2.5 : 1.5),
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
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7), fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$val',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 420,
          color: Colors.white,
          child: Column(
            children: [
              _buildHeader(provider, filtered),
              _buildFilterBar(),
              Expanded(
                child: groupKeys.isEmpty
                    ? _buildEmptyState("검색 결과가 없습니다.")
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  itemCount: groupKeys.length,
                  separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
                  itemBuilder: (ctx, idx) => _buildGroupTile(provider, groupKeys[idx], groupedMap[groupKeys[idx]]!, _selectedGroupKey == groupKeys[idx], false),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: Colors.black12),
        Expanded(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.only(left: 12),
            child: _selectedGroupKey == null
                ? _buildEmptyState("항목을 선택하여 상세 정보를 확인하세요.")
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
          child: groupKeys.isEmpty
              ? _buildEmptyState("항목이 없습니다.")
              : ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 50),
            itemCount: groupKeys.length,
            separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
            itemBuilder: (ctx, idx) => _buildGroupTile(provider, groupKeys[idx], groupedMap[groupKeys[idx]]!, false, true),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ProductProvider provider, List<ProductModel> filtered) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildActionIconButton(Icons.refresh, "새로고침", () {
                      provider.fetchData();
                    }),
                    _buildActionIconButton(FontAwesomeIcons.fileArrowUp, "임포트", () async {
                      final Map<String, int> res = await provider.batchImportFromExcel();
                      if (mounted && (res['total'] ?? 0) > 0) {
                        _showInfoDialog("임포트 완료", "성공: ${res['success']} / 전체: ${res['total']}");
                      }
                    }, color: Colors.indigo),
                    _buildActionIconButton(FontAwesomeIcons.fileArrowDown, "엑스포트", () {
                      _exportToExcel(context, filtered);
                    }, color: Colors.green),
                    _buildActionIconButton(Icons.settings_outlined, "표시 설정", () {
                      _showColumnSelectionDialog(provider);
                    }),
                    _buildActionIconButton(Icons.delete_sweep_outlined, "리셋", () {
                      _showResetDialog(provider);
                    }, color: AppTheme.danger),
                  ],
                ),
              ),
              _buildActionIconButton(Icons.add_box, "신규 등록", () {
                _showForm(context, provider, null);
              }, color: AppTheme.primary, isLarge: true),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.dataColor(Theme.of(context).brightness == Brightness.dark)),
            decoration: AppTheme.inputDecoration(label: "품명, 위치, 분류 또는 상세내용 검색...", context: context, prefixIcon: Icons.search),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIconButton(IconData icon, String tip, VoidCallback onTap, {Color? color, bool isLarge = false}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(icon, color: color ?? Colors.black54, size: isLarge ? 30 : 22),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 20),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          style: SegmentedButton.styleFrom(backgroundColor: Colors.white, selectedBackgroundColor: AppTheme.primary, selectedForegroundColor: Colors.white, elevation: 0),
          segments: const [
            ButtonSegment(value: 'item', label: Text('품명별')),
            ButtonSegment(value: 'location', label: Text('위치별')),
            ButtonSegment(value: 'category', label: Text('분류별')),
          ],
          selected: {_groupByMode},
          onSelectionChanged: (Set<String> v) {
            setState(() {
              _groupByMode = v.first;
              _selectedGroupKey = null;
            });
          },
        ),
      ),
    );
  }

  Widget _buildDetailView(ProductProvider provider, String groupName, List<ProductModel> items, {Key? key}) {
    final List<String> cols = provider.selectedColumns;
    return Column(
      key: key,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Container(width: 4, height: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(groupName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 70),
            itemCount: items.length,
            separatorBuilder: (ctx, idx) => const SizedBox(height: 12),
            itemBuilder: (ctx, idx) {
              final ProductModel p = items[idx];
              final Color statusColor = _getStatusColor(p.status);

              return InkWell(
                onTap: () {
                  _showForm(context, provider, p);
                },
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                child: Container(
                  decoration: AppTheme.listItemDecoration(context, isSelected: false, statusColor: statusColor),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _buildThumbnail(p, size: _colImgSize),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(p.name, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 16)),
                                const SizedBox(width: 12),
                                _buildStatusBadge(p.status),
                                if (!p.isApproved) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18),
                                ]
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 20,
                              runSpacing: 8,
                              children: cols.where((c) => c != '품명').map((c) {
                                return SizedBox(
                                  width: 140,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(c, style: AppTheme.itemLabelStyle(context)),
                                      Text(_getDisplayValue(p, c), style: AppTheme.itemValueStyle(context).copyWith(fontSize: 14), overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              p.metadata['last_location_info']?['full_name'] ?? "위치 정보 없음",
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
                            _buildCircleAction(Icons.history, Colors.blueGrey, "이력", () {
                              _showHistoryDialog(context, p);
                            }),
                            const SizedBox(width: 8),
                            _buildCircleAction(Icons.login, AppTheme.success, "입고", () {
                              _processAssetAccess(provider, p, '수기입고');
                            }),
                            const SizedBox(width: 8),
                            _buildCircleAction(Icons.logout, AppTheme.warning, "출고", () {
                              _processAssetAccess(provider, p, '수기출고');
                            }),
                            const SizedBox(width: 8),
                            _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () {
                              _confirmIndividualDelete(context, provider, p);
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, bool isMobile) {
    final double healthRatio = items.isEmpty ? 0.0 : items.where((i) => !i.status.contains('출고')).length / items.length;
    final Color hCol = healthRatio == 1.0 ? AppTheme.success : (healthRatio > 0.4 ? AppTheme.warning : AppTheme.danger);

    return InkWell(
      onTap: () {
        if (isMobile) {
          _showMobileGroupDetail(provider, title, items);
        } else {
          setState(() => _selectedGroupKey = title);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(AppTheme.cardRadius), border: Border.all(color: isSelected ? AppTheme.primary : Colors.black12, width: isSelected ? 2.5 : 1.5)),
        child: Row(
          children: [
            _buildThumbnail(items.first, size: 48),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: hCol.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)), child: Text('${items.length}', style: TextStyle(color: hCol, fontWeight: FontWeight.w900, fontSize: 13))),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: AppTheme.danger, size: 22),
              onPressed: () {
                _confirmGroupDelete(context, provider, title, items);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getDisplayValue(ProductModel p, String key) {
    switch (key) {
      case '품명':
        return p.name;
      case '태그ID':
        return p.tagId;
      case '위치':
        return p.location ?? "-";
      case '상태':
        return p.status;
      case '규격':
        return p.spec ?? "-";
      case '분류':
        return p.category ?? "-";
      case 'S/N':
        return p.serialNumber ?? "-";
      default:
        return p.metadata[key]?.toString() ?? "-";
    }
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
    return AppTheme.warning;
  }

  Widget _buildStatusBadge(String status) {
    final String label = _inboundStatuses.contains(status) ? "보유중" : status;
    final Color color = _inboundStatuses.contains(status) ? AppTheme.success : (_processStatuses.contains(status) ? Colors.blueAccent : ((_outboundStatuses.contains(status) || _exceptionStatuses.contains(status)) ? Colors.blueGrey : AppTheme.warning));
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)));
  }

  Future<void> _exportToExcel(BuildContext context, List<ProductModel> list) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel_pkg.Excel excel = excel_pkg.Excel.createExcel();
      final excel_pkg.Sheet sheet = excel['Inventory'];
      sheet.appendRow([excel_pkg.TextCellValue('품명'), excel_pkg.TextCellValue('태그ID'), excel_pkg.TextCellValue('로케이션'), excel_pkg.TextCellValue('상태')]);

      for (final ProductModel i in list) {
        sheet.appendRow([excel_pkg.TextCellValue(i.name), excel_pkg.TextCellValue(i.tagId), excel_pkg.TextCellValue(i.location ?? ""), excel_pkg.TextCellValue(i.status)]);
      }

      final String? path = await FilePicker.platform.saveFile(fileName: 'Inventory_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx']);

      if (path != null) {
        await File(path).writeAsBytes(excel.encode()!);
        if (mounted) {
          messenger.showSnackBar(const SnackBar(content: Text('✅ 데이터 내보내기 성공'), elevation: 0));
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('❌ 내보내기 실패: $e'), elevation: 0));
      }
    }
  }

  Future<void> _processAssetAccess(ProductProvider provider, ProductModel p, String type) async {
    final messenger = ScaffoldMessenger.of(context);
    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _ManualInoutDialog(type: type, product: p, statusIcons: _statusIcons),
    );

    if (result == null || !mounted) {
      return;
    }

    final String now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final bool isApproved = result['is_approved'] ?? true;

    List<dynamic> history = p.metadata['history'] is List ? List.from(p.metadata['history']) : [];
    history.insert(0, {'time': now, 'type': result['status'], 'location': result['location'], 'handler': result['handler'], 'reason': result['reason'], 'is_approved': isApproved});

    final bool success = await provider.handleSave(
      p: p,
      data: {
        'status': result['status'],
        'location': result['location'],
        'is_approved': isApproved,
        'metadata': {...p.metadata, 'history': history, 'last_approval_status': isApproved, 'last_processed_at': now}
      },
    );

    if (success && mounted) {
      _syncFiltering(provider.items);
      messenger.showSnackBar(SnackBar(content: Text('[${p.name}] 처리 완료'), backgroundColor: isApproved ? AppTheme.success : AppTheme.danger, elevation: 0, duration: const Duration(seconds: 1)));
    }
  }

  void _confirmGroupDelete(BuildContext ctx, ProductProvider provider, String name, List<ProductModel> items) {
    final navigator = Navigator.of(ctx);
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: AppTheme.dialogTitle("그룹 일괄 삭제", Icons.warning, color: AppTheme.danger),
        content: Text("[$name] 그룹의 모든 자산(${items.length}개)을 삭제하시겠습니까?"),
        actions: [
          AppTheme.actionButton(
            label: "취소",
            color: Colors.transparent,
            textColor: Colors.black54,
            onPressed: () {
              navigator.pop();
            },
          ),
          const SizedBox(width: 8),
          AppTheme.actionButton(
            label: "일괄 삭제",
            color: AppTheme.danger,
            onPressed: () async {
              await provider.deleteMultipleProducts(items.map((e) => e.id).toList());
              if (mounted) {
                _syncFiltering(provider.items);
                navigator.pop();
              }
            },
          ),
        ],
      ),
    );
  }

  void _confirmIndividualDelete(BuildContext ctx, ProductProvider provider, ProductModel p) {
    final navigator = Navigator.of(ctx);
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: AppTheme.dialogTitle("삭제 확인", Icons.delete),
        content: Text("[${p.name}] 자산을 삭제하시겠습니까?"),
        actions: [
          AppTheme.actionButton(
            label: "취소",
            color: Colors.transparent,
            textColor: Colors.black54,
            onPressed: () {
              navigator.pop();
            },
          ),
          const SizedBox(width: 8),
          AppTheme.actionButton(
            label: "삭제",
            color: AppTheme.danger,
            onPressed: () async {
              await provider.deleteMultipleProducts([p.id]);
              if (mounted) {
                _syncFiltering(provider.items);
                navigator.pop();
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showForm(BuildContext context, ProductProvider provider, ProductModel? p, {String? initialTag}) async {
    final nameC = TextEditingController(text: p?.name ?? ""),
        tagC = TextEditingController(text: initialTag ?? p?.tagId ?? ""),
        locC = TextEditingController(text: p?.location ?? ""),
        catC = TextEditingController(text: p?.category ?? ""),
        specC = TextEditingController(text: p?.spec ?? ""),
        snC = TextEditingController(text: p?.serialNumber ?? ""),
        safeC = TextEditingController(text: p?.safetyStock.toString() ?? "5"),
        qtyC = TextEditingController(text: "1");

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final Map<String, TextEditingController> metaC = {};
    if (p != null) {
      p.metadata.forEach((k, v) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal') && v is! Map && v is! List) {
          metaC[k] = TextEditingController(text: v?.toString() ?? "");
        }
      });
    }

    String selStatus = p?.status ?? "보유중";
    bool isApproved = p?.isApproved ?? true;
    XFile? file;
    Uint8List? preview;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setS) => AlertDialog(
          title: AppTheme.dialogTitle(p == null ? '자산 마스터 신규 등록' : '마스터 제원 상세 수정', p == null ? Icons.add_box : Icons.edit),
          content: SizedBox(
            width: MediaQuery.of(ctx).size.width > 850 ? 800 : 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          GestureDetector(
                            onTap: () async {
                              final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
                              if (img != null) {
                                final b = await img.readAsBytes();
                                setS(() {
                                  file = img;
                                  preview = b;
                                });
                              }
                            },
                            child: Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black12, width: 2)),
                              clipBehavior: Clip.antiAlias,
                              child: Center(
                                child: preview != null
                                    ? Image.memory(preview!, fit: BoxFit.cover)
                                    : (p != null && p.getImageUrl(widget.baseUrl).isNotEmpty
                                    ? Image.network("${p.getImageUrl(widget.baseUrl)}?t=${p.updated}", fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image))
                                    : const Icon(Icons.camera_alt, size: 40, color: Colors.grey)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Text("승인 상태", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Switch(value: isApproved, activeTrackColor: AppTheme.success.withValues(alpha: 0.5), activeThumbColor: AppTheme.success, onChanged: (v) => setS(() => isApproved = v)),
                            ],
                          )
                        ],
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          children: [
                            TextField(controller: nameC, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: AppTheme.inputDecoration(label: "품명 (필수)", hint: "제품명을 입력하세요", context: context)),
                            const SizedBox(height: 16),
                            TextField(controller: tagC, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: AppTheme.inputDecoration(label: "태그ID (RFID EPC)", context: context)),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader(Icons.star, "기본 제원 정보", Colors.blue),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(width: 370, child: TextField(controller: locC, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: AppTheme.inputDecoration(label: "로케이션", context: context))),
                      SizedBox(width: 370, child: TextField(controller: catC, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: AppTheme.inputDecoration(label: "자산 카테고리", context: context))),
                      SizedBox(width: 370, child: TextField(controller: specC, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: AppTheme.inputDecoration(label: "모델 규격", context: context))),
                      SizedBox(width: 370, child: TextField(controller: safeC, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: AppTheme.inputDecoration(label: "안전재고수량", context: context))),
                      SizedBox(width: 370, child: TextField(controller: snC, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: AppTheme.inputDecoration(label: "S/N", context: context))),
                      SizedBox(width: 370, child: _buildIconicDropdown(label: "현재 물류 상태", initialValue: selStatus, items: _statusIcons.keys.toList(), statusIcons: _statusIcons, onChanged: (v) { if (v != null) setS(() => selStatus = v); })),
                    ],
                  ),
                  if (metaC.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    _buildSectionHeader(Icons.table_view, "추가 메타데이터", Colors.green),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: metaC.entries.map((e) {
                        return SizedBox(width: 370, child: TextField(controller: e.value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: AppTheme.inputDecoration(label: e.key, context: context)));
                      }).toList(),
                    ),
                  ],
                  if (p == null) ...[
                    const SizedBox(height: 32),
                    _buildSectionHeader(Icons.copy_all, "벌크 생성", AppTheme.warning),
                    const SizedBox(height: 20),
                    SizedBox(width: 370, child: TextField(controller: qtyC, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: AppTheme.inputDecoration(label: "등록 수량", hint: "한 번에 생성할 개수", context: context))),
                  ]
                ],
              ),
            ),
          ),
          actions: [
            AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: Colors.black54, onPressed: () { navigator.pop(); }),
            const SizedBox(width: 12),
            AppTheme.actionButton(
              label: "통합 저장",
              onPressed: () async {
                final meta = Map<String, dynamic>.from(p?.metadata ?? {});
                metaC.forEach((k, c) {
                  meta[k] = c.text.trim();
                });
                final baseData = {
                  'name': nameC.text.trim(),
                  'location': locC.text.trim(),
                  'category': catC.text.trim(),
                  'spec': specC.text.trim(),
                  'serial_number': snC.text.trim(),
                  'status': selStatus,
                  'safety_stock': int.tryParse(safeC.text.trim()) ?? 5,
                  'is_approved': isApproved,
                  'metadata': meta
                };

                bool ok = true;
                if (p == null) {
                  final int loop = int.tryParse(qtyC.text.trim()) ?? 1;
                  for (int i = 0; i < loop; i++) {
                    String tid = tagC.text.trim().isEmpty ? "TAG_NONE" : tagC.text.trim();
                    if (loop > 1 && tid != "TAG_NONE") {
                      tid = "${tid}_${i + 1}";
                    }
                    final bool success = await provider.handleSave(p: null, data: {...baseData, 'tag_id': tid}, imageXFile: file);
                    if (!success) {
                      ok = false;
                    }
                  }
                } else {
                  ok = await provider.handleSave(p: p, data: {...baseData, 'tag_id': tagC.text.trim()}, imageXFile: file);
                }

                if (ok && mounted) {
                  _syncFiltering(provider.items);
                  navigator.pop();
                  messenger.showSnackBar(const SnackBar(content: Text("성공적으로 저장되었습니다."), elevation: 0));
                }
              },
            )
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 80, color: Colors.black12),
          const SizedBox(height: 16),
          Text(msg, style: const TextStyle(color: Colors.black26, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  // [해결] Host specified 오류 방지를 위한 썸네일 빌더 보정
  Widget _buildThumbnail(ProductModel p, {double size = 44}) {
    final String url = p.getImageUrl(widget.baseUrl, thumb: '100x100');
    final Uri? uri = Uri.tryParse(url);

    // URL이 비어있거나, 파싱이 안되거나, Host 정보가 없는 경우 폴백 아이콘 반환
    if (url.isEmpty || uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black12, width: 1)),
        child: const Icon(Icons.inventory_2_outlined, color: Colors.black12, size: 22),
      );
    }

    final String connector = url.contains('?') ? '&' : '?';
    final String fullUrl = "$url${connector}t=${p.updated ?? p.created ?? DateTime.now().millisecondsSinceEpoch}";

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black12, width: 1)),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        fullUrl,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, size: 18),
      ),
    );
  }

  void _showResetDialog(ProductProvider provider) {
    final navigator = Navigator.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: AppTheme.dialogTitle("전체 초기화", Icons.delete_forever, color: AppTheme.danger),
        content: const Text("모든 정보를 삭제하시겠습니까?"),
        actions: [
          AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: Colors.black54, onPressed: () => navigator.pop()),
          AppTheme.actionButton(
            label: "삭제",
            color: AppTheme.danger,
            onPressed: () async {
              await provider.resetAllProducts();
              if (mounted) {
                _syncFiltering(provider.items);
                navigator.pop();
              }
            },
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(String title, String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius), side: const BorderSide(color: Colors.black12, width: 1.5)),
        title: AppTheme.dialogTitle(title, Icons.info_outline),
        content: Text(msg),
        actions: [
          AppTheme.actionButton(
            label: "확인",
            onPressed: () {
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  void _showMobileGroupDetail(ProductProvider provider, String group, List<ProductModel> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        height: MediaQuery.of(context).size.height * 0.85,
        child: _buildDetailView(provider, group, items),
      ),
    );
  }

  void _showHistoryDialog(BuildContext context, ProductModel p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: AppTheme.dialogTitle('[${p.name}] 상세 추적 이력', Icons.history, color: Colors.blueGrey),
        content: SizedBox(
          width: 550,
          height: 600,
          child: p.history.isEmpty
              ? _buildEmptyState("이력이 없습니다.")
              : ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: p.history.length,
            separatorBuilder: (c, i) => const SizedBox(height: 10),
            itemBuilder: (c, i) {
              final log = p.history[i];
              final String type = log['type'] ?? "-";
              final String time = log['time'] ?? "-";
              final bool approved = log['is_approved'] ?? true;
              final Color statusColor = approved ? _getStatusColor(type) : AppTheme.danger;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: statusColor.withValues(alpha: 0.15), width: 1.0)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6, right: 16), decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(time, style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text(type, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text("위치: ${log['location'] ?? '-'} | 담당: ${log['handler'] ?? '-'}", style: const TextStyle(color: Colors.blueGrey, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          AppTheme.actionButton(
            label: "닫기",
            color: Colors.transparent,
            textColor: Colors.black54,
            onPressed: () {
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  void _showColumnSelectionDialog(ProductProvider provider) {
    final List<String> baseFields = ['품명', '태그ID', '위치', '상태', '규격', '분류', 'S/N'];
    final Set<String> metaKeySet = {};
    for (var item in provider.items.take(100)) {
      metaKeySet.addAll(item.metadata.keys);
    }
    final List<String> metaFields = metaKeySet.where((k) => !_excludedSystemKeys.contains(k)).toList()..sort();
    final List<String> temp = List.from(provider.selectedColumns);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setS) {
          final navigator = Navigator.of(ctx);
          return AlertDialog(
            title: AppTheme.dialogTitle("표시 항목 설정", Icons.view_column_rounded),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _buildColumnGroupHeader("기본 제원 정보"),
                    const SizedBox(height: 12),
                    ...baseFields.map((k) => _buildSelectionListItem(k, temp, (v) => setS(() => v))),
                    const SizedBox(height: 32),
                    _buildColumnGroupHeader("추가 확장 정보"),
                    const SizedBox(height: 12),
                    if (metaFields.isEmpty) ...[
                      const Text("추가된 메타데이터가 없습니다."),
                    ] else ...[
                      ...metaFields.map((k) => _buildSelectionListItem(k, temp, (v) => setS(() => v))),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              AppTheme.actionButton(
                label: "취소",
                color: Colors.transparent,
                textColor: Colors.black54,
                onPressed: () {
                  navigator.pop();
                },
              ),
              AppTheme.actionButton(
                label: "설정 적용",
                onPressed: () async {
                  await provider.saveRemoteSettings(temp);
                  if (mounted) {
                    navigator.pop();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSelectionListItem(String label, List<String> currentList, Function(void) onChanged) {
    final bool isSelected = currentList.contains(label);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          if (isSelected) {
            if (currentList.length > 1) {
              currentList.remove(label);
            }
          } else {
            if (currentList.length < 5) {
              currentList.add(label);
            }
          }
          onChanged(null);
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppTheme.primary : Colors.black12,
              width: isSelected ? 2.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                size: 20,
                color: isSelected ? AppTheme.primary : Colors.black26,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? AppTheme.primary : Colors.black45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColumnGroupHeader(String title) {
    return Row(
      children: [
        Container(width: 4, height: 16, decoration: BoxDecoration(color: Colors.blueGrey, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.blueGrey, fontSize: 14, letterSpacing: -0.5)),
      ],
    );
  }

  Widget _buildCircleAction(IconData icon, Color color, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  Map<String, List<ProductModel>> _getGroupedData(List<ProductModel> items) {
    final Map<String, List<ProductModel>> grouped = {};
    for (var i in items) {
      String key = _groupByMode == 'item' ? i.name : (_groupByMode == 'location' ? (i.location ?? "미지정") : (i.category ?? "미정"));
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(i);
    }
    return grouped;
  }

  Map<String, dynamic> _calculateMetrics(List<ProductModel> allItems) {
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0, todayOut = 0, currentStock = 0;
    for (final item in allItems) {
      final lastDate = item.updated ?? item.created ?? "";
      final isOut = _outboundStatuses.contains(item.status) || _exceptionStatuses.contains(item.status);
      if (lastDate.startsWith(todayStr)) {
        if (!isOut) {
          todayIn++;
        } else {
          todayOut++;
        }
      }
      if (!isOut) {
        currentStock++;
      }
    }
    return {'in': todayIn, 'out': todayOut, 'stock': currentStock};
  }

  Widget _buildIconicDropdown({required String label, required String initialValue, required List<String> items, required Map<String, IconData> statusIcons, required ValueChanged<String?> onChanged}) {
    final List<String> safeItems = List.from(items);
    if (!safeItems.contains(initialValue)) {
      safeItems.add(initialValue);
    }
    return DropdownButtonFormField<String>(
      initialValue: initialValue,
      decoration: AppTheme.inputDecoration(label: label, context: context),
      items: safeItems.map((v) {
        return DropdownMenuItem(
          value: v,
          child: Row(
            children: [
              Icon(statusIcons[v] ?? Icons.help_outline, size: 18),
              const SizedBox(width: 12),
              Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 13)),
          ],
        ),
        const Divider(color: Colors.black12),
      ],
    );
  }
}

class _ManualInoutDialog extends StatefulWidget {
  final String type;
  final ProductModel product;
  final Map<String, IconData> statusIcons;
  const _ManualInoutDialog({required this.type, required this.product, required this.statusIcons});
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
    _locC = TextEditingController(text: widget.product.location ?? "미지정");
    _reasonC = TextEditingController(text: "현장 수동 처리");
    _selS = widget.type == '수기입고' ? '보유중' : '수동출고';
  }

  @override
  void dispose() {
    _locC.dispose();
    _reasonC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final personProvider = context.watch<PersonProvider>();
    final workerList = personProvider.list.map((p) => "${p.name} (${p.code})").toList();

    return AlertDialog(
      title: AppTheme.dialogTitle(widget.product.name, widget.type == '수기입고' ? Icons.login : Icons.logout),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _selS,
              decoration: AppTheme.inputDecoration(label: "작업 선택", context: context),
              items: (widget.type == '수기입고' ? ['보유중', '수동입고', '회수/반납'] : ['수동출고', '판매/배송출고', '폐기']).map((v) {
                return DropdownMenuItem(value: v, child: Text(v));
              }).toList(),
              onChanged: (v) {
                setState(() => _selS = v!);
              },
            ),
            const SizedBox(height: 16),
            TextField(controller: _locC, decoration: AppTheme.inputDecoration(label: "위치", context: context)),
            const SizedBox(height: 16),
            Autocomplete<String>(
              optionsBuilder: (val) {
                return workerList.where((o) => o.contains(val.text));
              },
              onSelected: (s) {
                _selectedHandler = s;
              },
              fieldViewBuilder: (ctx, ctrl, focus, __) {
                return TextField(controller: ctrl, focusNode: focus, decoration: AppTheme.inputDecoration(label: "담당 작업자", context: context));
              },
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_isApproved ? "승인됨" : "미승인", style: TextStyle(color: _isApproved ? AppTheme.success : AppTheme.danger, fontWeight: FontWeight.bold)),
                Switch(
                  value: _isApproved,
                  activeThumbColor: AppTheme.success,
                  activeTrackColor: AppTheme.success.withValues(alpha: 0.5),
                  onChanged: (v) => setState(() => _isApproved = v),
                )
              ],
            ),
          ],
        ),
      ),
      actions: [
        AppTheme.actionButton(
          label: "취소",
          color: Colors.transparent,
          textColor: Colors.black54,
          onPressed: () => Navigator.pop(context),
        ),
        AppTheme.actionButton(
          label: "처리 확정",
          onPressed: () {
            Navigator.pop(context, {'status': _selS, 'location': _locC.text, 'handler': _selectedHandler, 'reason': _reasonC.text, 'is_approved': _isApproved});
          },
        ),
      ],
    );
  }
}