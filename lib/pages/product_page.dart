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

import '../models/product_model.dart';
import '../models/user_model.dart';
import '../providers/product_provider.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';

// [공용 위젯 임포트] 표시 항목 설정 및 일괄 편집 다이얼로그
import '../widgets/column_selection_dialog.dart';
import '../widgets/bulk_edit_dialog.dart';

/// ---------------------------------------------------------------------------
/// [안전한 문자열 변환 유틸리티]
/// ---------------------------------------------------------------------------
String _safeStr(dynamic value, {String defaultVal = ""}) {
  if (value == null) {
    return defaultVal;
  }
  final String str = value.toString().trim();
  if (str.isEmpty || str == "null") {
    return defaultVal;
  }
  return str;
}

/// ---------------------------------------------------------------------------
/// [물품 관리 페이지]
/// ---------------------------------------------------------------------------
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
  // ---------------------------------------------------------------------------
  // [상태 변수 선언부]
  // ---------------------------------------------------------------------------
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

  final Set<String> _selectedItemIds = {};

  // [신규 추가] 다중 선택 모드(동그라미 토글 보이기/숨기기) 활성화 플래그
  bool _isSelectionMode = false;

  bool _isFullScreenLoading = false;

  static const double _colImgSize = 70.0;
  static const double _colActionWidth = 240.0;

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
    '생산입고': Icons.factory_outlined, '구매입고': Icons.shopping_cart,
    '적치완료': Icons.shelves, '회수/반납': Icons.assignment_return,
    '정보등록': Icons.app_registration, '공정투입': Icons.login_outlined,
    '생산중': Icons.settings_suggest, '생산완료': Icons.fact_check,
    '이송중': Icons.local_shipping, '피킹중': Icons.hail,
    '패킹완료': Icons.inventory_2, '출하대기': Icons.warehouse,
    '수동출고': Icons.outbox, '자동출고': Icons.sensors,
    '판매/배송출고': Icons.sell, '대여출고': Icons.handshake,
    '수리출고': Icons.build, '현장투입': Icons.precision_manufacturing,
    '폐기': Icons.delete_forever, '분실': Icons.search_off,
  };

  static const Set<String> _excludedSystemKeys = {
    'id', 'collectionId', 'collectionName', 'created', 'updated',
    'excel_row', 'import_date', 'import_data', 'is_auto_tag', 'is_auto_atg',
    'origin_key_map', 'history', 'last_location_info', 'is_approved',
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
      if (!mounted) {
        return;
      }
      setState(() {
        _currentQuery = query;
        _syncFiltering(context.read<ProductProvider>().items);
      });
    });
  }

  void _syncFiltering(List<ProductModel> rawItems) {
    final String q = _currentQuery.trim().toLowerCase();
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    List<ProductModel> result = rawItems.where((ProductModel p) {
      bool isMatch = true;
      if (q.isNotEmpty) {
        final String locStr = _safeStr(p.location).toLowerCase();
        final String catStr = _safeStr(p.category).toLowerCase();
        final String snStr = _safeStr(p.serialNumber).toLowerCase();
        isMatch = p.name.toLowerCase().contains(q) ||
            p.tagId.toLowerCase().contains(q) ||
            locStr.contains(q) || catStr.contains(q) || snStr.contains(q);

        if (!isMatch) {
          for (final dynamic value in p.metadata.values) {
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

      final String upStr = _safeStr(p.updated);
      final String crStr = _safeStr(p.created);
      final String lastDate = upStr.isNotEmpty ? upStr : crStr;
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
      result.sort((ProductModel a, ProductModel b) => a.name.compareTo(b.name));
    }

    _filteredCache = result;
    _lastRawItemCount = rawItems.length;
    _lastActiveFilter = _activeMetricFilter;

    _selectedItemIds.retainWhere((String id) {
      return _filteredCache.any((ProductModel p) => p.id == id);
    });
  }

  Map<String, dynamic> _calculateMetrics(List<ProductModel> allItems) {
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0;
    int todayOut = 0;
    int currentStock = 0;

    for (final ProductModel item in allItems) {
      final String upStr = _safeStr(item.updated);
      final String crStr = _safeStr(item.created);
      final String lastDate = upStr.isNotEmpty ? upStr : crStr;
      final bool isOut = _outboundStatuses.contains(item.status) || _exceptionStatuses.contains(item.status);

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

  String _getAttributeValue(String label, ProductModel p) {
    switch (label) {
      case '품명': return p.name;
      case '태그ID': return p.tagId;
      case '위치': return _safeStr(p.location, defaultVal: "-");
      case '상태': return p.status;
      case '규격': return _safeStr(p.spec, defaultVal: "-");
      case '분류': return _safeStr(p.category, defaultVal: "-");
      case 'S/N': return _safeStr(p.serialNumber, defaultVal: "-");
      default: return _safeStr(p.metadata[label], defaultVal: "-");
    }
  }

  Color _getStatusColor(String status) {
    if (_inboundStatuses.contains(status)) {
      return AppTheme.success;
    }
    if (_processStatuses.contains(status)) {
      return Colors.blueAccent;
    }
    if (_exceptionStatuses.contains(status)) {
      return AppTheme.danger;
    }
    if (_outboundStatuses.contains(status)) {
      return Colors.grey;
    }
    return AppTheme.warning;
  }

  @override
  Widget build(BuildContext context) {
    final ProductProvider provider = context.watch<ProductProvider>();
    final ThemeData theme = Theme.of(context);

    if (_lastRawItemCount != provider.items.length || _lastActiveFilter != _activeMetricFilter) {
      _syncFiltering(provider.items);
    }

    final Map<String, dynamic> metrics = _calculateMetrics(provider.items);
    final Map<String, List<ProductModel>> groupedMap = _getGroupedData(_filteredCache);
    final List<String> groupKeys = groupedMap.keys.toList()..sort();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              _buildDashboard(metrics, provider.items.length, theme),
              Divider(height: 1, color: theme.dividerTheme.color),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext ctx, BoxConstraints constraints) {
                    if (constraints.maxWidth > 950 && !widget.isMobile) {
                      return _buildSplitLayout(provider, groupedMap, groupKeys, theme);
                    }
                    return _buildMobileLayout(provider, groupedMap, groupKeys, theme);
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
          if ((provider.isParsing || provider.isSaving) && !_isFullScreenLoading) ...[
            _buildGlobalLoadingOverlay(provider, theme),
          ]
        ],
      ),
    );
  }

  Widget _buildDashboard(Map<String, dynamic> m, int totalCount, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: theme.scaffoldBackgroundColor,
      child: Row(
        children: [
          Expanded(child: _buildStatTile("자산 마스터", totalCount, Icons.list_alt, Colors.blueGrey, theme, filterKey: "전체")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("금일 입고", m['in'] as int, Icons.add_business_outlined, AppTheme.success, theme, filterKey: "금일 입고")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("금일 출고", m['out'] as int, Icons.local_shipping_outlined, AppTheme.warning, theme, filterKey: "금일 출고")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("현재 실재고", m['stock'] as int, Icons.inventory_2_outlined, AppTheme.primary, theme, filterKey: "현재 실재고")),
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, int val, IconData icon, Color color, ThemeData theme, {required String filterKey}) {
    final bool isSelected = _activeMetricFilter == filterKey;
    final bool isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: () {
        setState(() {
          _activeMetricFilter = _activeMetricFilter == filterKey ? "전체" : filterKey;
          _selectedGroupKey = null;
          _selectedItemIds.clear();
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: isDark ? 0.15 : 0.08) : theme.cardTheme.color,
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
                  Text(label, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  Text('$val', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 22, fontWeight: FontWeight.w900, color: color), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 420,
          color: theme.scaffoldBackgroundColor,
          child: Column(
            children: [
              _buildHeader(provider, theme),
              _buildFilterBar(theme),
              Expanded(
                child: groupKeys.isEmpty
                    ? _buildEmptyState("검색 결과가 없습니다.")
                    : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: groupKeys.length,
                  separatorBuilder: (BuildContext ctx, int idx) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext ctx, int idx) {
                    final String k = groupKeys[idx];
                    return _buildGroupTile(provider, k, groupedMap[k]!, _selectedGroupKey == k, theme);
                  },
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: theme.dividerTheme.color),
        Expanded(
          child: Container(
            color: theme.scaffoldBackgroundColor,
            padding: const EdgeInsets.only(left: 12),
            child: _selectedGroupKey == null
                ? _buildEmptyState("항목을 선택하여 상세 정보를 확인하세요.")
                : _buildDetailView(provider, _selectedGroupKey!, groupedMap[_selectedGroupKey] ?? [], theme),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ProductProvider provider, ThemeData theme) {
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
                    _buildActionIconButton(Icons.refresh, "새로고침", () {
                      provider.fetchData();
                    }, theme),
                    // [신규 기능] 다중 선택(동그라미 토글) 모드 켜기/끄기 버튼
                    _buildActionIconButton(
                      _isSelectionMode ? Icons.close_fullscreen_rounded : Icons.checklist_rtl_rounded,
                      _isSelectionMode ? "다중 선택 끄기" : "다중 선택 켜기",
                          () {
                        setState(() {
                          _isSelectionMode = !_isSelectionMode;
                          if (!_isSelectionMode) {
                            _selectedItemIds.clear(); // 모드를 끌 때는 선택 내역도 초기화
                          }
                        });
                      },
                      theme,
                      color: _isSelectionMode ? AppTheme.primary : null, // 켜져 있을 땐 색상으로 강조
                    ),
                    _buildActionIconButton(FontAwesomeIcons.fileArrowUp, "엑셀 일괄 임포트", () {
                      _handleBatchImport(provider, theme);
                    }, theme, color: Colors.indigo),
                    _buildActionIconButton(FontAwesomeIcons.fileArrowDown, "엑스포트", () {
                      _exportToExcel(provider.items);
                    }, theme, color: Colors.green),
                    _buildActionIconButton(Icons.settings_outlined, "표시 설정", () {
                      _showColumnSelectionDialog(provider, theme);
                    }, theme),
                    _buildActionIconButton(Icons.delete_sweep_outlined, "리셋", () {
                      _showResetDialog(provider, theme);
                    }, theme, color: AppTheme.danger),
                  ],
                ),
              ),
              _buildActionIconButton(Icons.add_box, "신규 등록", () {
                _showForm(provider, null, theme);
              }, theme, color: AppTheme.primary, isLarge: true),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
            decoration: AppTheme.inputDecoration(label: "품명, 위치, 분류 또는 상세내용 검색...", context: context, prefixIcon: Icons.search),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          style: SegmentedButton.styleFrom(selectedBackgroundColor: AppTheme.primary, selectedForegroundColor: Colors.white),
          segments: const [
            ButtonSegment(value: 'item', label: Text('품명별', style: TextStyle(fontFamily: AppTheme.fontPretendard))),
            ButtonSegment(value: 'location', label: Text('위치별', style: TextStyle(fontFamily: AppTheme.fontPretendard))),
            ButtonSegment(value: 'category', label: Text('분류별', style: TextStyle(fontFamily: AppTheme.fontPretendard))),
          ],
          selected: {_groupByMode},
          onSelectionChanged: (Set<String> v) {
            setState(() {
              _groupByMode = v.first;
              _selectedGroupKey = null;
              _selectedItemIds.clear();
            });
          },
        ),
      ),
    );
  }

  Widget _buildDetailView(ProductProvider provider, String groupName, List<ProductModel> items, ThemeData theme) {
    final bool isAllSelected = items.isNotEmpty && items.every((ProductModel p) => _selectedItemIds.contains(p.id));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Container(width: 4, height: 20, color: AppTheme.primary),
              const SizedBox(width: 12),
              Text(groupName, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w800, fontSize: 20, color: AppTheme.dataColor(theme.brightness == Brightness.dark), letterSpacing: -0.4)),
            ],
          ),
        ),

        // [신규 UI] 다중 선택 모드가 활성화되었을 때만 스르륵 나타나는 일괄 처리 액션 바
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _isSelectionMode
              ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text('${_selectedItemIds.length}개 선택됨', style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text("일괄 편집", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, elevation: 0),
                  onPressed: () {
                    _showBulkEditDialog(provider, items, theme);
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: const Text("일괄 삭제", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white, elevation: 0),
                  onPressed: () {
                    _confirmBulkDelete(provider, theme);
                  },
                ),
                const SizedBox(width: 16),
                Container(width: 1, height: 24, color: theme.dividerTheme.color),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all, size: 18),
                  label: Text(isAllSelected ? "선택 해제" : "전체 선택", style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isAllSelected ? Colors.grey : AppTheme.primary,
                    side: BorderSide(color: isAllSelected ? Colors.grey.withValues(alpha: 0.5) : AppTheme.primary.withValues(alpha: 0.5)),
                  ),
                  onPressed: () {
                    setState(() {
                      if (isAllSelected) {
                        _selectedItemIds.clear();
                      } else {
                        for (final ProductModel e in items) {
                          _selectedItemIds.add(e.id);
                        }
                      }
                    });
                  },
                ),
              ],
            ),
          )
              : Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('총 ${items.length}개 항목', style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13)),
          ),
        ),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (BuildContext ctx, int idx) => const SizedBox(height: 12),
            itemBuilder: (BuildContext ctx, int idx) {
              final ProductModel p = items[idx];
              final bool isSelected = _selectedItemIds.contains(p.id);
              final Color statusColor = _getStatusColor(p.status);

              return Row(
                children: [
                  // [신규 UI] AnimatedSize를 적용하여 선택 모드일 때만 체크박스가 스르륵 등장합니다.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.centerLeft,
                    child: _isSelectionMode
                        ? Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedItemIds.remove(p.id);
                            } else {
                              _selectedItemIds.add(p.id);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? AppTheme.primary : Colors.transparent,
                              border: Border.all(
                                color: isSelected ? AppTheme.primary : Colors.grey.withValues(alpha: 0.5),
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.check,
                                size: 16,
                                color: isSelected ? Colors.white : Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                        : const SizedBox.shrink(),
                  ),

                  // 기존 카드 영역
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        // 다중 선택 모드일 땐 카드를 클릭해도 체크되도록 UX를 향상시켰습니다.
                        if (_isSelectionMode) {
                          setState(() {
                            if (isSelected) {
                              _selectedItemIds.remove(p.id);
                            } else {
                              _selectedItemIds.add(p.id);
                            }
                          });
                        } else {
                          _showForm(provider, p, theme);
                        }
                      },
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: AppTheme.listItemDecoration(context, isSelected: isSelected, statusColor: statusColor),
                        child: Row(
                          children: [
                            _buildThumbnail(p, theme, size: _colImgSize),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                      children: [
                                        Text(p.name, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 19)),
                                        const SizedBox(width: 12),
                                        _buildStatusBadge(p.status),
                                        if (!p.isApproved)
                                          const Padding(
                                            padding: EdgeInsets.only(left: 8),
                                            child: Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18),
                                          ),
                                      ]
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 20, runSpacing: 10,
                                    children: provider.selectedColumns
                                        .where((String col) => col != '품명')
                                        .map((String col) => _buildKeyValue(col, _getAttributeValue(col, p), context))
                                        .toList(),
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
                                    _showHistoryDialog(p, theme);
                                  }),
                                  const SizedBox(width: 12),
                                  _buildCircleAction(Icons.login, AppTheme.success, "입고", () {
                                    _processAssetAccess(provider, p, '수기입고', theme);
                                  }),
                                  const SizedBox(width: 12),
                                  _buildCircleAction(Icons.logout, AppTheme.warning, "출고", () {
                                    _processAssetAccess(provider, p, '수기출고', theme);
                                  }),
                                  const SizedBox(width: 12),
                                  _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () {
                                    _confirmIndividualDelete(provider, p, theme);
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, ThemeData theme) {
    final double healthRatio = items.isEmpty ? 0.0 : items.where((ProductModel i) => !i.status.contains('출고')).length / items.length;
    final Color hCol = healthRatio == 1.0 ? AppTheme.success : (healthRatio > 0.4 ? AppTheme.warning : AppTheme.danger);
    return InkWell(
      onTap: () {
        setState(() {
          _selectedGroupKey = title;
          _selectedItemIds.clear();
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary.withValues(alpha: 0.05) : theme.cardTheme.color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? AppTheme.primary : hCol.withValues(alpha: 0.4), width: isSelected ? 2.5 : 1.8)
        ),
        child: Row(
            children: [
              _buildThumbnail(items.isNotEmpty ? items.first : null, theme, size: 52),
              const SizedBox(width: 16),
              Expanded(child: Text(title, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold, fontSize: 15, color: isSelected ? AppTheme.primary : null))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: hCol.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Text('${items.length}', style: TextStyle(fontFamily: AppTheme.fontPretendard, color: hCol, fontWeight: FontWeight.w900, fontSize: 13))),
              const SizedBox(width: 8),
              IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded, color: AppTheme.danger, size: 22),
                  onPressed: () {
                    _confirmGroupDelete(provider, title, items, theme);
                  }
              ),
            ]
        ),
      ),
    );
  }

  Widget _buildThumbnail(ProductModel? p, ThemeData theme, {double size = 44}) {
    final String url = p != null ? p.getImageUrl(widget.baseUrl, thumb: '100x100') : '';
    final bool isDark = theme.brightness == Brightness.dark;

    if (url.isEmpty) {
      return Container(
          width: size, height: size,
          decoration: BoxDecoration(
              color: isDark ? theme.dividerTheme.color?.withValues(alpha: 0.1) : const Color(0xFFF1F3F5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 1.5)
          ),
          child: const Icon(Icons.inventory_2_outlined, color: Colors.black12, size: 24)
      );
    }

    final String connector = url.contains('?') ? '&' : '?';
    final String upStr = p != null ? _safeStr(p.updated) : '';
    final String crStr = p != null ? _safeStr(p.created) : '';
    final String timeStamp = upStr.isNotEmpty ? upStr : (crStr.isNotEmpty ? crStr : DateTime.now().millisecondsSinceEpoch.toString());

    final String fullUrl = "$url${connector}t=$timeStamp";

    return Container(
        width: size, height: size,
        decoration: BoxDecoration(
            color: isDark ? theme.dividerTheme.color?.withValues(alpha: 0.1) : const Color(0xFFF1F3F5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 1.5)
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(fullUrl, fit: BoxFit.cover, errorBuilder: (BuildContext ctx, Object err, StackTrace? stack) => const Icon(Icons.broken_image, size: 18, color: Colors.black12))
    );
  }

  Widget _buildStatusBadge(String status) {
    final Color color = _getStatusColor(status);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(status, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: color, fontSize: 11, fontWeight: FontWeight.w900))
    );
  }

  // ---------------------------------------------------------------------------
  // [신규 연동] 다중 선택 항목 일괄 편집 (공용 BulkEditDialog 연동)
  // 물품 관리의 기본 항목과 추가 확장 항목(Metadata)을 모두 수집하여 공용 위젯에 넘깁니다.
  // ---------------------------------------------------------------------------
  void _showBulkEditDialog(ProductProvider provider, List<ProductModel> visibleItems, ThemeData theme) async {
    final List<ProductModel> selectedProducts = visibleItems.where((ProductModel p) => _selectedItemIds.contains(p.id)).toList();
    if (selectedProducts.isEmpty) return;

    List<BulkEditField> fields = [
      BulkEditField(key: 'location', label: '새로운 위치 (로케이션)', type: BulkEditFieldType.text),
      BulkEditField(key: 'category', label: '새로운 자산 분류', type: BulkEditFieldType.text),
      BulkEditField(key: 'spec', label: '새로운 규격 및 사양', type: BulkEditFieldType.text),
      BulkEditField(
          key: 'status',
          label: '새로운 상태 변경',
          type: BulkEditFieldType.dropdown,
          options: ['보유중', '수동입고', '폐기', '분실', '수리출고'],
          initialValue: '보유중'
      ),
      BulkEditField(key: 'is_approved', label: '승인 여부 일괄 변경', type: BulkEditFieldType.toggle, initialValue: true),
    ];

    final Set<String> metaKeySet = {};
    for (final ProductModel p in provider.items.take(100)) {
      for (final String k in p.metadata.keys) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal')) {
          metaKeySet.add(k);
        }
      }
    }
    final List<String> metaFields = metaKeySet.toList()..sort();

    for (String metaKey in metaFields) {
      fields.add(BulkEditField(key: metaKey, label: '추가항목: $metaKey', type: BulkEditFieldType.text));
    }

    final Map<String, dynamic>? resultValues = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return BulkEditDialog(
            title: '${selectedProducts.length}개 자산 일괄 편집',
            fields: fields,
          );
        }
    );

    if (resultValues == null || !mounted) return;

    setState(() { _isFullScreenLoading = true; });

    for (final ProductModel p in selectedProducts) {
      final Map<String, dynamic> data = {};
      final Map<String, dynamic> updatedMeta = Map<String, dynamic>.from(p.metadata);

      resultValues.forEach((String key, dynamic value) {
        if (key == 'location') {
          data['location'] = value;
        } else if (key == 'category') {
          data['category'] = value;
        } else if (key == 'spec') {
          data['spec'] = value;
        } else if (key == 'status') {
          data['status'] = value;
        } else if (key == 'is_approved') {
          data['is_approved'] = value;
        } else {
          updatedMeta[key] = value;
        }
      });

      data['metadata'] = updatedMeta;

      await provider.handleSave(product: p, data: data);
    }

    if (!mounted) return;

    setState(() {
      _isFullScreenLoading = false;
      _selectedItemIds.clear();
      // 팁: 편집이 끝난 후 다중 선택 모드를 자동으로 꺼주면 UX가 더 깔끔합니다.
      _isSelectionMode = false;
    });

    _syncFiltering(provider.items);
    _showInfoDialog("일괄 편집 완료", "선택하신 ${selectedProducts.length}개의 항목이 성공적으로 업데이트 되었습니다.", theme);
  }

  void _showForm(ProductProvider provider, ProductModel? p, ThemeData theme) async {
    final TextEditingController nameC = TextEditingController(text: p?.name ?? "");
    final TextEditingController tagC = TextEditingController(text: p?.tagId ?? "");
    final TextEditingController locC = TextEditingController(text: p != null ? _safeStr(p.location) : "");
    final TextEditingController specC = TextEditingController(text: p != null ? _safeStr(p.spec) : "");
    final TextEditingController catC = TextEditingController(text: p != null ? _safeStr(p.category) : "");
    final TextEditingController snC = TextEditingController(text: p != null ? _safeStr(p.serialNumber) : "");
    final TextEditingController safeC = TextEditingController(text: p != null ? p.safetyStock.toString() : "5");

    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    bool isApproved = p?.isApproved ?? true;
    XFile? file;
    Uint8List? preview;

    final Map<String, TextEditingController> metaC = {};
    if (p != null) {
      p.metadata.forEach((String k, dynamic v) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal')) {
          metaC[k] = TextEditingController(text: _safeStr(v));
        }
      });
    } else {
      final Set<String> availableMetaKeys = {};
      for (final ProductModel item in provider.items.take(100)) {
        for (final String key in item.metadata.keys) {
          if (!_excludedSystemKeys.contains(key) && !key.endsWith('_internal')) {
            availableMetaKeys.add(key);
          }
        }
      }
      for (final String k in availableMetaKeys) {
        metaC[k] = TextEditingController(text: "");
      }
    }

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogCtx) {
          return StatefulBuilder(
              builder: (BuildContext innerCtx, StateSetter setS) {
                return AlertDialog(
                    title: AppTheme.dialogTitle(p == null ? '자산 마스터 신규 등록' : '정보 수정 및 제원 편집', p == null ? Icons.add_box : Icons.edit),
                    content: SizedBox(
                        width: 1000,
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
                                                    final ImagePicker picker = ImagePicker();
                                                    final XFile? img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                                                    if (img != null) {
                                                      final Uint8List b = await img.readAsBytes();
                                                      setS(() {
                                                        file = img;
                                                        preview = b;
                                                      });
                                                    }
                                                  },
                                                  child: Container(
                                                      width: 220,
                                                      height: 250,
                                                      decoration: BoxDecoration(
                                                          color: theme.cardTheme.color,
                                                          borderRadius: BorderRadius.circular(15),
                                                          border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 2)
                                                      ),
                                                      child: Center(
                                                          child: preview != null
                                                              ? Image.memory(preview!, fit: BoxFit.cover)
                                                              : (p != null && p.getImageUrl(widget.baseUrl).isNotEmpty
                                                              ? Image.network("${p.getImageUrl(widget.baseUrl)}?t=${p.updated}", fit: BoxFit.cover, errorBuilder: (BuildContext c, Object e, StackTrace? s) => const Icon(Icons.broken_image))
                                                              : const Icon(Icons.camera_alt, size: 50, color: Colors.grey)
                                                          )
                                                      )
                                                  )
                                              ),
                                              const SizedBox(height: 16),
                                              Row(
                                                  children: [
                                                    const Text("승인 상태", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 14, fontWeight: FontWeight.bold)),
                                                    const SizedBox(width: 12),
                                                    Switch(
                                                        value: isApproved,
                                                        activeThumbColor: AppTheme.success,
                                                        activeTrackColor: AppTheme.success.withValues(alpha: 0.5),
                                                        onChanged: (bool v) {
                                                          setS(() {
                                                            isApproved = v;
                                                          });
                                                        }
                                                    )
                                                  ]
                                              )
                                            ]
                                        ),
                                        const SizedBox(width: 40),
                                        Expanded(
                                            child: Column(
                                                children: [
                                                  _buildTextField(nameC, "품명 (필수)", theme, context),
                                                  const SizedBox(height: 16),
                                                  _buildTextField(tagC, "태그ID (RFID EPC)", theme, context),
                                                  const SizedBox(height: 16),
                                                  _buildTextField(catC, "자산 분류 (Category)", theme, context),
                                                  const SizedBox(height: 16),
                                                  Row(
                                                    children: [
                                                      Expanded(child: _buildTextField(locC, "로케이션 (위치)", theme, context)),
                                                      const SizedBox(width: 16),
                                                      Expanded(child: _buildTextField(specC, "규격 및 상세 사양", theme, context)),
                                                    ],
                                                  ),
                                                ]
                                            )
                                        )
                                      ]
                                  ),
                                  const SizedBox(height: 40),
                                  _buildSectionHeader(Icons.settings_input_component_rounded, "기본 제원 및 운영 정보", Colors.blueAccent),
                                  const SizedBox(height: 20),
                                  Wrap(
                                    spacing: 20, runSpacing: 20,
                                    children: [
                                      SizedBox(width: 460, child: _buildTextField(snC, "시리얼 번호 (S/N)", theme, context)),
                                      SizedBox(width: 460, child: _buildTextField(safeC, "안전 재고 임계치 (숫자만 입력)", theme, context)),
                                    ],
                                  ),
                                  const SizedBox(height: 40),
                                  _buildSectionHeader(Icons.add_to_photos_rounded, "추가 확장 정보 (Metadata)", Colors.green),
                                  const SizedBox(height: 20),
                                  if (metaC.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 20),
                                      child: Text("표시할 추가 속성 정보가 없습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey)),
                                    ),
                                  Wrap(
                                      spacing: 20,
                                      runSpacing: 20,
                                      children: metaC.entries.map((MapEntry<String, TextEditingController> e) {
                                        return SizedBox(
                                            width: 460,
                                            child: _buildTextField(e.value, e.key, theme, context)
                                        );
                                      }).toList()
                                  ),
                                  const SizedBox(height: 30),
                                ]
                            )
                        )
                    ),
                    actions: [
                      AppTheme.actionButton(
                          label: "취소",
                          color: Colors.transparent,
                          textColor: cancelColor,
                          onPressed: () {
                            Navigator.pop(dialogCtx);
                          }
                      ),
                      AppTheme.actionButton(
                          label: p == null ? "자산 신규 생성" : "변경사항 저장",
                          onPressed: () async {
                            if (nameC.text.isEmpty) {
                              if (dialogCtx.mounted) {
                                ScaffoldMessenger.of(dialogCtx).showSnackBar(const SnackBar(content: Text("품명은 필수 입력 사항입니다.")));
                              }
                              return;
                            }

                            final Map<String, dynamic> meta = Map<String, dynamic>.from(p?.metadata ?? {});
                            metaC.forEach((String k, TextEditingController c) {
                              meta[k] = c.text.trim();
                            });

                            final Map<String, dynamic> data = {
                              'name': nameC.text.trim(),
                              'tag_id': tagC.text.trim(),
                              'location': locC.text.trim(),
                              'spec': specC.text.trim(),
                              'category': catC.text.trim(),
                              'serial_number': snC.text.trim(),
                              'safety_stock': int.tryParse(safeC.text.trim()) ?? 5,
                              'is_approved': isApproved,
                              'metadata': meta,
                              'status': p?.status ?? '보유중'
                            };

                            final bool ok = await provider.handleSave(product: p, data: data, imageXFile: file);
                            if (!mounted) {
                              return;
                            }
                            if (ok) {
                              _syncFiltering(provider.items);
                              if (dialogCtx.mounted) {
                                Navigator.pop(dialogCtx);
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("마스터 정보가 성공적으로 반영되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)))
                              );
                            }
                          }
                      )
                    ]
                );
              }
          );
        }
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, ThemeData theme, BuildContext ctx, {bool enabled = true}) {
    return TextField(
        controller: ctrl,
        enabled: enabled,
        style: AppTheme.itemValueStyle(ctx).copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: enabled ? AppTheme.dataColor(theme.brightness == Brightness.dark) : Colors.grey,
        ),
        decoration: AppTheme.inputDecoration(label: label, context: ctx).copyWith(enabled: enabled)
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Text(
                title,
                style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    fontWeight: FontWeight.w900,
                    color: color,
                    fontSize: 15,
                    letterSpacing: -0.5
                )
            )
          ],
        ),
        const SizedBox(height: 8),
        Divider(color: color.withValues(alpha: 0.2), thickness: 2),
      ],
    );
  }

  Future<void> _handleBatchImport(ProductProvider provider, ThemeData theme) async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
      if (!mounted) {
        return;
      }
      if (result == null) {
        return;
      }

      Uint8List? bytes = result.files.single.bytes;
      if (bytes == null && result.files.single.path != null) {
        bytes = await File(result.files.single.path!).readAsBytes();
      }

      if (!mounted) {
        return;
      }
      if (bytes == null) {
        _showInfoDialog("오류", "파일을 읽을 수 없습니다.", theme);
        return;
      }

      final excel_pkg.Excel excel = excel_pkg.Excel.decodeBytes(bytes);
      final String targetSheet = excel.tables.keys.first;
      final excel_pkg.Sheet? sheet = excel.tables[targetSheet];
      if (sheet == null || sheet.maxRows <= 1) {
        _showInfoDialog("알림", "데이터가 없거나 헤더만 존재합니다.", theme);
        return;
      }

      setState(() {
        _isFullScreenLoading = true;
      });

      final List<String> headers = [];
      if (sheet.rows.isNotEmpty) {
        for (final excel_pkg.Data? cell in sheet.rows.first) {
          headers.add(_extractString(cell));
        }
      }

      int successCount = 0;
      int failCount = 0;

      for (int i = 1; i < sheet.maxRows; i++) {
        final List<excel_pkg.Data?> row = sheet.row(i);
        if (row.isEmpty) {
          continue;
        }

        String name = "";
        String tagId = "";
        String loc = "미지정";
        final Map<String, dynamic> metadata = {};

        for (int colIdx = 0; colIdx < row.length; colIdx++) {
          if (colIdx >= headers.length) {
            break;
          }
          final String cleanHeader = headers[colIdx].replaceAll(RegExp(r'[\s\_\-\(\)]+'), '').toLowerCase();
          final String val = _extractString(row[colIdx]);

          if (cleanHeader.contains('품명') || cleanHeader.contains('이름')) {
            name = val;
          } else if (cleanHeader.contains('태그') || cleanHeader.contains('rfid')) {
            tagId = val;
          } else if (cleanHeader.contains('위치')) {
            loc = val;
          } else if (headers[colIdx].isNotEmpty && val.isNotEmpty) {
            metadata[headers[colIdx]] = val;
          }
        }

        if (name.isEmpty && tagId.isEmpty) {
          continue;
        }
        if (name.isEmpty) {
          name = "이름없음";
        }
        if (tagId.isEmpty) {
          tagId = "TAG_${DateTime.now().millisecondsSinceEpoch}_$i";
        }

        final Map<String, dynamic> data = {
          'name': name,
          'tag_id': tagId,
          'location': loc,
          'status': '보유중',
          'metadata': metadata
        };

        bool ok = await provider.handleSave(product: null, data: data);
        if (ok) {
          successCount++;
        } else {
          failCount++;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _isFullScreenLoading = false;
      });
      _syncFiltering(provider.items);
      _showInfoDialog("엑셀 임포트 완료", "총 ${successCount + failCount}건의 데이터 처리가 종료되었습니다.\n\n✅ 성공: $successCount건\n❌ 실패: $failCount건", theme);

    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isFullScreenLoading = false;
      });
      _showInfoDialog("오류", "엑셀 파싱 중 오류가 발생했습니다.", theme);
    }
  }

  void _confirmBulkDelete(ProductProvider provider, ThemeData theme) {
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("선택 항목 일괄 삭제", Icons.warning, color: AppTheme.danger),
              content: Text("선택하신 ${_selectedItemIds.length}개의 자산을 모두 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
              actions: [
                AppTheme.actionButton(
                    label: "취소",
                    color: Colors.transparent,
                    textColor: cancelColor,
                    onPressed: () {
                      Navigator.pop(ctx);
                    }
                ),
                AppTheme.actionButton(
                    label: "일괄 삭제",
                    color: AppTheme.danger,
                    onPressed: () async {
                      Navigator.pop(ctx);
                      setState(() {
                        _isFullScreenLoading = true;
                      });

                      await provider.deleteMultipleProducts(_selectedItemIds.toList());

                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _selectedItemIds.clear();
                        _isFullScreenLoading = false;
                        _isSelectionMode = false; // 삭제 후 모드 자동 종료
                      });
                      _syncFiltering(provider.items);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("선택한 항목들이 일괄 삭제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
                    }
                )
              ]
          );
        }
    );
  }

  void _confirmIndividualDelete(ProductProvider provider, ProductModel p, ThemeData theme) {
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("삭제 확인", Icons.delete),
              content: Text("[${p.name}] 자산을 삭제하시겠습니까?", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
              actions: [
                AppTheme.actionButton(
                    label: "취소",
                    color: Colors.transparent,
                    textColor: cancelColor,
                    onPressed: () {
                      Navigator.pop(ctx);
                    }
                ),
                AppTheme.actionButton(
                    label: "삭제",
                    color: AppTheme.danger,
                    onPressed: () async {
                      Navigator.pop(ctx);

                      await provider.deleteMultipleProducts([p.id]);

                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _selectedItemIds.remove(p.id);
                      });
                      _syncFiltering(provider.items);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("삭제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
                    }
                )
              ]
          );
        }
    );
  }

  void _confirmGroupDelete(ProductProvider provider, String name, List<ProductModel> items, ThemeData theme) {
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("그룹 일괄 삭제", Icons.warning, color: AppTheme.danger),
              content: Text("[$name] 그룹의 모든 자산(${items.length}개)을 삭제하시겠습니까?", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
              actions: [
                AppTheme.actionButton(
                    label: "취소",
                    color: Colors.transparent,
                    textColor: cancelColor,
                    onPressed: () {
                      Navigator.pop(ctx);
                    }
                ),
                AppTheme.actionButton(
                    label: "일괄 삭제",
                    color: AppTheme.danger,
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final List<String> ids = items.map((ProductModel e) => e.id).toList();

                      await provider.deleteMultipleProducts(ids);

                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        if (_selectedGroupKey == name) {
                          _selectedGroupKey = null;
                          _selectedItemIds.clear();
                        }
                      });
                      _syncFiltering(provider.items);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("일괄 삭제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
                    }
                )
              ]
          );
        }
    );
  }

  Future<void> _processAssetAccess(ProductProvider provider, ProductModel p, String type, ThemeData theme) async {
    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (BuildContext ctx) {
          return _ManualInoutDialog(type: type, product: p, statusIcons: _statusIcons);
        }
    );
    if (!mounted) {
      return;
    }
    if (result != null) {
      final String now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      List<dynamic> history = p.metadata['history'] is List ? List.from(p.metadata['history']) : [];
      history.insert(0, {
        'time': now,
        'type': result['status'],
        'location': result['location'],
        'handler': result['handler'],
        'reason': result['reason'],
        'is_approved': result['is_approved']
      });

      final bool success = await provider.handleSave(product: p, data: {
        'status': result['status'],
        'location': result['location'],
        'metadata': {
          ...p.metadata,
          'history': history,
        }
      });
      if (!mounted) {
        return;
      }
      if (success) {
        _syncFiltering(provider.items);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('[${p.name}] 처리 완료', style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
            backgroundColor: AppTheme.success,
            elevation: 0,
            duration: const Duration(seconds: 1)
        ));
      }
    }
  }

  void _showHistoryDialog(ProductModel p, ThemeData theme) {
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("자산 상세 이력 추적", Icons.history),
              content: SizedBox(
                width: 550,
                height: 600,
                child: (p.metadata['history'] == null || (p.metadata['history'] as List).isEmpty)
                    ? _buildEmptyState("이력이 없습니다.")
                    : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: (p.metadata['history'] as List).length,
                  separatorBuilder: (BuildContext c, int i) => const Divider(height: 24),
                  itemBuilder: (BuildContext context, int idx) {
                    final dynamic log = (p.metadata['history'] as List)[idx];
                    final String type = log['type'] ?? "-";
                    final String time = log['time'] ?? "-";
                    final bool approved = log['is_approved'] ?? true;
                    final Color statusColor = approved ? _getStatusColor(type) : AppTheme.danger;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: theme.cardTheme.color,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: statusColor.withValues(alpha: 0.15), width: 1.0)
                      ),
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
                                    Text(time, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 14)),
                                    Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                        child: Text(type, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: statusColor, fontWeight: FontWeight.bold, fontSize: 12))
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                RichText(
                                    text: TextSpan(
                                        style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 14, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
                                        children: [
                                          TextSpan(text: '위치: ', style: AppTheme.itemLabelStyle(context)),
                                          TextSpan(text: '${log['location'] ?? '-'}  ', style: const TextStyle(fontWeight: FontWeight.w600)),
                                          TextSpan(text: '담당: ', style: AppTheme.itemLabelStyle(context)),
                                          TextSpan(
                                              text: '${log['handler'] ?? '-'}',
                                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.blueGrey)
                                          ),
                                        ]
                                    )
                                ),
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
                    textColor: cancelColor,
                    onPressed: () {
                      Navigator.pop(ctx);
                    }
                )
              ]
          );
        }
    );
  }

  /// ---------------------------------------------------------------------------
  /// [공용 다이얼로그 호출] - 표시 항목 설정
  /// ---------------------------------------------------------------------------
  void _showColumnSelectionDialog(ProductProvider provider, ThemeData theme) {
    final List<String> baseFields = ['품명', '태그ID', '위치', '상태', '규격', '분류', 'S/N'];
    final Set<String> metaKeySet = {};

    for (final ProductModel p in provider.items.take(100)) {
      for (final String k in p.metadata.keys) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal')) {
          metaKeySet.add(k);
        }
      }
    }

    final List<String> metaFields = metaKeySet.toList()..sort();

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return ColumnSelectionDialog(
          title: "표시 항목 설정 (물품)",
          baseFields: baseFields,
          metaFields: metaFields,
          initialSelection: provider.selectedColumns,
          onSave: (List<String> newColumns) async {
            await provider.saveRemoteSettings(newColumns);
          },
        );
      },
    );
  }

  void _showResetDialog(ProductProvider provider, ThemeData theme) {
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("전체 초기화", Icons.delete_forever, color: AppTheme.danger),
              content: const Text("모든 정보를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)),
              actions: [
                AppTheme.actionButton(
                    label: "취소",
                    color: Colors.transparent,
                    textColor: cancelColor,
                    onPressed: () {
                      Navigator.pop(ctx);
                    }
                ),
                AppTheme.actionButton(
                    label: "초기화 진행",
                    color: AppTheme.danger,
                    onPressed: () async {
                      Navigator.pop(ctx);
                      setState(() {
                        _isFullScreenLoading = true;
                      });

                      await provider.resetAllProducts();

                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _isFullScreenLoading = false;
                        _selectedGroupKey = null;
                        _currentQuery = "";
                        _selectedItemIds.clear();
                      });
                      _searchController.clear();
                      _syncFiltering(provider.items);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('전체 초기화가 완료되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard))));
                    }
                )
              ]
          );
        }
    );
  }

  void _showInfoDialog(String title, String msg, ThemeData theme) {
    showDialog(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
            title: AppTheme.dialogTitle(title, Icons.info_outline),
            content: Text(msg, style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
            actions: [
              AppTheme.actionButton(label: "확인", onPressed: () => Navigator.pop(ctx))
            ]
        )
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 48, color: Colors.black12),
              const SizedBox(height: 16),
              Text(msg, style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.black26, fontWeight: FontWeight.bold))
            ]
        )
    );
  }

  Widget _buildKeyValue(String label, String value, BuildContext ctx) {
    return SizedBox(
        width: 150,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTheme.itemLabelStyle(ctx).copyWith(fontSize: 13)),
              Text(value, style: AppTheme.itemValueStyle(ctx).copyWith(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)
            ]
        )
    );
  }

  Widget _buildCircleAction(IconData icon, Color color, String tip, VoidCallback onTap) {
    return Tooltip(
        message: tip,
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(25),
            child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24)
            )
        )
    );
  }

  Widget _buildActionIconButton(IconData icon, String tip, VoidCallback onTap, ThemeData theme, {Color? color, bool isLarge = false}) {
    return Tooltip(
        message: tip,
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                child: Icon(icon, color: color ?? theme.iconTheme.color?.withValues(alpha: 0.6), size: isLarge ? 34 : 24)
            )
        )
    );
  }

  Widget _buildMobileLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys, ThemeData theme) {
    return Column(
      children: [
        _buildHeader(provider, theme),
        _buildFilterBar(theme),
        Expanded(
          child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: groupKeys.length,
              separatorBuilder: (BuildContext ctx, int idx) => const SizedBox(height: 10),
              itemBuilder: (BuildContext ctx, int idx) {
                final String k = groupKeys[idx];
                return _buildGroupTile(provider, k, groupedMap[k]!, false, theme);
              }
          ),
        ),
      ],
    );
  }

  Widget _buildGlobalLoadingOverlay(ProductProvider provider, ThemeData theme) {
    return Container(
      color: Colors.black.withValues(alpha: 0.1),
      child: Center(
        child: Card(
          elevation: 10,
          color: theme.cardTheme.color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 5),
                const SizedBox(height: 25),
                Text(
                  provider.isParsing ? "데이터 분석 중..." : "데이터베이스 통신 중...",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _extractString(excel_pkg.Data? cell) {
    if (cell == null || cell.value == null) {
      return "";
    }
    return cell.value.toString().trim().replaceAll(RegExp(r'^[a-zA-Z]+CellValue\((.*)\)$'), r'$1').replaceAll('"', '');
  }

  Future<void> _exportToExcel(List<ProductModel> list) async {
    try {
      final excel_pkg.Excel excel = excel_pkg.Excel.createExcel();
      final excel_pkg.Sheet sheet = excel['Inventory'];
      sheet.appendRow([
        excel_pkg.TextCellValue('품명'),
        excel_pkg.TextCellValue('태그ID'),
        excel_pkg.TextCellValue('로케이션'),
        excel_pkg.TextCellValue('상태'),
        excel_pkg.TextCellValue('규격')
      ]);
      for (final ProductModel i in list) {
        sheet.appendRow([
          excel_pkg.TextCellValue(i.name),
          excel_pkg.TextCellValue(i.tagId),
          excel_pkg.TextCellValue(i.location ?? ""),
          excel_pkg.TextCellValue(i.status),
          excel_pkg.TextCellValue(i.spec ?? "")
        ]);
      }
      final String? path = await FilePicker.platform.saveFile(
          fileName: 'Inventory_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx']
      );
      if (path != null) {
        await File(path).writeAsBytes(excel.encode()!);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ 데이터 내보내기 성공', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
            elevation: 0
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 내보내기 실패: $e')));
      }
    }
  }

  Map<String, List<ProductModel>> _getGroupedData(List<ProductModel> items) {
    final Map<String, List<ProductModel>> grouped = {};
    for (final ProductModel i in items) {
      final String key = _groupByMode == 'item' ? i.name : (_groupByMode == 'location' ? _safeStr(i.location, defaultVal: "미지정") : _safeStr(i.category, defaultVal: "미정"));
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(i);
    }
    return grouped;
  }
}

/// ---------------------------------------------------------------------------
/// [수동 입출고 다이얼로그]
/// 담당 작업자 검색을 위해 UserProvider를 사용하여 키오스크 스타일로 구성했습니다.
/// ---------------------------------------------------------------------------
class _ManualInoutDialog extends StatefulWidget {
  final String type;
  final ProductModel product;
  final Map<String, IconData> statusIcons;

  const _ManualInoutDialog({required this.type, required this.product, required this.statusIcons});

  @override
  State<_ManualInoutDialog> createState() => _ManualInoutDialogState();
}

class _ManualInoutDialogState extends State<_ManualInoutDialog> {
  late String _selS;
  final TextEditingController _locC = TextEditingController();
  final TextEditingController _reasonC = TextEditingController();
  String _selectedHandler = "관리자";

  @override
  void initState() {
    super.initState();
    _selS = widget.type == '수기입고' ? '보유중' : '수동출고';
    _locC.text = _safeStr(widget.product.location, defaultVal: "미지정");
    _reasonC.text = "현장 수동 처리";
  }

  @override
  void dispose() {
    _locC.dispose();
    _reasonC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final UserProvider userProvider = context.watch<UserProvider>();
    final List<String> workerList = userProvider.list.map((UserModel p) => "${p.name} (${p.code})").toList();
    final bool isIn = widget.type == '수기입고';
    final ThemeData theme = Theme.of(context);
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return AlertDialog(
      title: AppTheme.dialogTitle('${widget.type} - ${widget.product.name}', isIn ? Icons.login : Icons.logout),
      content: SizedBox(
          width: 450,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                    initialValue: _selS,
                    decoration: AppTheme.inputDecoration(label: "작업 상세 선택", context: context),
                    items: (isIn ? ['보유중', '수동입고', '회수/반납', '생산입고', '구매입고'] : ['수동출고', '판매/배송출고', '대여출고', '수리출고', '폐기', '분실']).map((String v) {
                      return DropdownMenuItem<String>(value: v, child: Text(v, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)));
                    }).toList(),
                    onChanged: (String? v) {
                      setState(() {
                        if (v != null) {
                          _selS = v;
                        }
                      });
                    }
                ),
                const SizedBox(height: 16),
                TextField(
                    controller: _locC,
                    style: AppTheme.itemValueStyle(context),
                    decoration: AppTheme.inputDecoration(label: "처리 위치", context: context)
                ),
                const SizedBox(height: 16),
                Autocomplete<String>(
                    optionsBuilder: (TextEditingValue val) {
                      return workerList.where((String o) => o.contains(val.text));
                    },
                    onSelected: (String s) {
                      _selectedHandler = s;
                    },
                    fieldViewBuilder: (BuildContext ctx, TextEditingController tC, FocusNode fN, VoidCallback onFieldSubmitted) {
                      return TextField(
                          controller: tC,
                          focusNode: fN,
                          style: AppTheme.itemValueStyle(context).copyWith(fontWeight: FontWeight.bold),
                          decoration: AppTheme.inputDecoration(label: "담당 작업자 (UserProvider 연동)", context: context, hasFocus: fN.hasFocus)
                      );
                    }
                ),
                const SizedBox(height: 20),
              ]
          )
      ),
      actions: [
        AppTheme.actionButton(
            label: "취소",
            color: Colors.transparent,
            textColor: cancelColor,
            onPressed: () {
              Navigator.pop(context);
            }
        ),
        AppTheme.actionButton(
            label: "처리 확정",
            onPressed: () {
              Navigator.pop(context, {
                'status': _selS,
                'location': _locC.text,
                'handler': _selectedHandler,
                'reason': _reasonC.text,
                'is_approved': true
              });
            }
        )
      ],
    );
  }
}