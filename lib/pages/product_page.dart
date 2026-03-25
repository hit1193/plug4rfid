import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/product_model.dart';
import '../models/user_model.dart';
import '../providers/product_provider.dart';
import '../providers/user_provider.dart';
import '../models/device_model.dart';
import '../providers/device_provider.dart';
import '../theme/app_theme.dart';
import '../core/erp_sync_helper.dart';
import '../core/ai_search_helper.dart';
import '../widgets/column_selection_dialog.dart';
import '../widgets/bulk_edit_dialog.dart';

/// ---------------------------------------------------------------------------
/// 안전한 문자열 변환 유틸리티
/// 데이터베이스의 null 값이나 빈 문자열을 안전하게 처리하여 UI 에러를 방지합니다.
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
/// [RFID 물품 관리 페이지 (ProductPage)]
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
  State<ProductPage> createState() {
    return _ProductPageState();
  }
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
  List<ProductModel>? _lastRawItems;
  String _lastActiveFilter = "";

  final Set<String> _selectedItemIds = {};
  bool _isSelectionMode = false;
  bool _isFullScreenLoading = false;

  List<String>? _aiFilteredIds;
  bool _isAiSearching = false;

  // 🔥 [동시성 제어 및 채터링 방지 2중 방어벽]
  // C++의 Mutex와 하드웨어 인터럽트 Debounce 개념을 플러터 상태에 적용합니다.
  final Set<String> _lockedItemIds = {}; // 1. 현재 DB 트랜잭션이 진행 중인 자산 ID (비동기 락)
  final Map<String, DateTime> _itemCooldowns = {}; // 2. 자산별 마지막 처리 시간 (채터링 무시용 쿨다운)

  static const double _colImgSize = 70.0;
  static const double _colActionWidth = 300.0; // 버튼 추가로 인한 넓이 확장

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

  /// AI 스마트 검색 실행
  Future<void> _performAiSearch(List<ProductModel> allItems, ThemeData theme) async {
    final String query = _searchController.text.trim();

    if (query.isEmpty) {
      _showInfoDialog("AI 검색 안내", "검색창에 찾고 싶은 조건을 자연어(문장)로 입력해 주세요.\n예: '입고 대기장에 있는 노트북 찾아줘'", theme);
      return;
    }

    setState(() {
      _isAiSearching = true;
      _aiFilteredIds = null;
    });

    try {
      final List<String> resultIds = await AiSearchHelper.searchProducts(query, allItems);

      if (!mounted) {
        return;
      }

      setState(() {
        _aiFilteredIds = resultIds;
      });

      if (resultIds.isEmpty) {
        _showInfoDialog("AI 검색 결과", "입력하신 조건과 일치하는 자산을 찾을 수 없습니다.", theme);
      }

      _syncFiltering(allItems);

    } catch (e) {
      if (!mounted) {
        return;
      }
      _showInfoDialog("AI 검색 오류", e.toString(), theme);
    } finally {
      if (mounted) {
        setState(() {
          _isAiSearching = false;
        });
      }
    }
  }

  /// 검색어 변경 핸들러 (디바운싱 적용)
  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
    }

    final ProductProvider provider = context.read<ProductProvider>();

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentQuery = query;
        _syncFiltering(provider.items);
      });
    });
  }

  /// 데이터 필터링 동기화 (메모리에서 즉시 처리)
  /// 🔥 [개선된 검색 로직]: 공백으로 구분된 여러 키워드를 AND 조건으로 처리합니다.
  void _syncFiltering(List<ProductModel> rawItems) {
    final String q = _currentQuery.trim().toLowerCase();
    final DateTime now = DateTime.now();

    List<ProductModel> result = rawItems.where((ProductModel p) {
      if (_aiFilteredIds != null) {
        if (!_aiFilteredIds!.contains(p.id)) {
          return false;
        }
      } else {
        bool isMatch = true;
        if (q.isNotEmpty) {
          // 1. 검색어를 공백 단위로 쪼개어 키워드 리스트를 만듭니다.
          final List<String> keywords = q.split(' ').where((s) => s.isNotEmpty).toList();

          // 2. 모든 키워드가 항목의 어떤 필드에서든 발견되어야 함 (AND 연산)
          isMatch = keywords.every((String kw) {
            final String nameStr = p.name.toLowerCase();
            final String tagIdStr = p.tagId.toLowerCase();
            final String tagEpcStr = p.tagEpc.toLowerCase();
            final String locStr = _safeStr(p.location).toLowerCase();
            final String catStr = _safeStr(p.category).toLowerCase();
            final String snStr = _safeStr(p.serialNumber).toLowerCase();

            // 현재 키워드가 기본 필드 중 하나라도 포함되어 있는지 확인
            bool foundInBase = nameStr.contains(kw) ||
                tagIdStr.contains(kw) ||
                tagEpcStr.contains(kw) ||
                locStr.contains(kw) ||
                catStr.contains(kw) ||
                snStr.contains(kw);

            if (foundInBase) return true;

            // 기본 필드에 없으면 메타데이터 루프 검색
            for (final dynamic value in p.metadata.values) {
              if (value != null && value.toString().toLowerCase().contains(kw)) {
                return true;
              }
            }
            return false;
          });

          if (!isMatch) {
            return false;
          }
        }
      }

      if (_activeMetricFilter == "전체") {
        return true;
      }

      final String upStr = _safeStr(p.updated);
      final String crStr = _safeStr(p.created);
      final String lastDateStr = upStr.isNotEmpty ? upStr : crStr;

      bool isToday = false;
      if (lastDateStr.isNotEmpty) {
        DateTime? parsedDate = DateTime.tryParse(lastDateStr)?.toLocal();
        if (parsedDate != null) {
          if (parsedDate.year == now.year &&
              parsedDate.month == now.month &&
              parsedDate.day == now.day) {
            isToday = true;
          }
        }
      }

      final bool isOut = _outboundStatuses.contains(p.status) || _exceptionStatuses.contains(p.status);

      if (_activeMetricFilter == "금일 입고") {
        return isToday && _inboundStatuses.contains(p.status);
      }
      if (_activeMetricFilter == "금일 출고") {
        return isToday && isOut;
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
    _lastRawItems = rawItems;
    _lastActiveFilter = _activeMetricFilter;

    _selectedItemIds.retainWhere((String id) {
      return _filteredCache.any((ProductModel p) => p.id == id);
    });
  }

  /// 대시보드 지표 계산기
  Map<String, dynamic> _calculateMetrics(List<ProductModel> allItems) {
    final DateTime now = DateTime.now();
    int todayIn = 0;
    int todayOut = 0;
    int currentStock = 0;

    for (final ProductModel item in allItems) {
      final String upStr = _safeStr(item.updated);
      final String crStr = _safeStr(item.created);
      final String lastDateStr = upStr.isNotEmpty ? upStr : crStr;

      bool isToday = false;
      if (lastDateStr.isNotEmpty) {
        DateTime? parsedDate = DateTime.tryParse(lastDateStr)?.toLocal();
        if (parsedDate != null) {
          if (parsedDate.year == now.year &&
              parsedDate.month == now.month &&
              parsedDate.day == now.day) {
            isToday = true;
          }
        }
      }

      final bool isOut = _outboundStatuses.contains(item.status) || _exceptionStatuses.contains(item.status);

      if (isToday) {
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

  /// 물품의 속성값 문자열 반환기
  String _getAttributeValue(String label, ProductModel p) {
    switch (label) {
      case '품명':
        return p.name;
      case '태그ID':
        return p.tagId;
      case 'EPC':
        return p.tagEpc;
      case '위치':
        return _safeStr(p.location, defaultVal: "-");
      case '상태':
        return p.status;
      case '규격':
        return _safeStr(p.spec, defaultVal: "-");
      case '분류':
        return _safeStr(p.category, defaultVal: "-");
      case 'S/N':
        return _safeStr(p.serialNumber, defaultVal: "-");
      default:
        return _safeStr(p.metadata[label], defaultVal: "-");
    }
  }

  /// 상태값에 따른 테마 색상 반환
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

  /// ERP 외부 시스템 연동 호출
  void _triggerErpSync(ThemeData theme) {
    final ProductProvider provider = context.read<ProductProvider>();

    ErpSyncHelper.fetchAndSync(
      context: context,
      theme: theme,
      moduleName: "물품 마스터 (REST API 동적 매핑)",
      endpoint: 'posts?_limit=5',
      targetCollection: 'products',
      dataMapper: (Map<String, dynamic> erpItem) {
        String parsedName = "이름없음";
        String parsedTagId = "TAG_${DateTime.now().millisecondsSinceEpoch}";
        String parsedLocation = "입고 대기장";
        String parsedStatus = "보유중";
        String parsedCategory = "ERP 자동분류";
        String parsedSpec = "";
        String parsedSn = "";

        Map<String, dynamic> dynamicMetadata = {};

        erpItem.forEach((String key, dynamic value) {
          if (value == null) {
            return;
          }

          final String lowerKey = key.toLowerCase();
          final String strValue = value.toString().trim();

          if (lowerKey.contains('name') || lowerKey.contains('title') || lowerKey == '품명') {
            parsedName = strValue;
          } else if (lowerKey.contains('tag') || lowerKey.contains('rfid') || lowerKey.contains('epc')) {
            parsedTagId = strValue;
          } else if (lowerKey.contains('loc') || lowerKey == '위치') {
            parsedLocation = strValue;
          } else if (lowerKey.contains('status') || lowerKey == '상태') {
            parsedStatus = strValue;
          } else if (lowerKey.contains('category') || lowerKey == '분류') {
            parsedCategory = strValue;
          } else if (lowerKey.contains('spec') || lowerKey == '규격') {
            parsedSpec = strValue;
          } else if (lowerKey.contains('serial') || lowerKey == 'sn' || lowerKey == '시리얼') {
            parsedSn = strValue;
          } else {
            if (strValue.isNotEmpty && strValue != "null") {
              dynamicMetadata[key] = strValue;
            }
          }
        });

        return {
          'name': '[ERP] $parsedName',
          'tag_id': parsedTagId,
          'location': parsedLocation,
          'status': parsedStatus,
          'category': parsedCategory,
          'spec': parsedSpec,
          'serial_number': parsedSn,
          'safety_stock': 5,
          'is_approved': true,
          'metadata': dynamicMetadata,
        };
      },
      onLoadingStart: () {
        if (mounted) {
          setState(() {
            _isFullScreenLoading = true;
          });
        }
      },
      onLoadingComplete: () {
        if (mounted) {
          setState(() {
            _isFullScreenLoading = false;
          });
        }
      },
      onSuccess: () {
        provider.fetchData();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ProductProvider provider = context.watch<ProductProvider>();
    final ThemeData theme = Theme.of(context);

    if (_lastRawItems != provider.items || _lastActiveFilter != _activeMetricFilter) {
      _syncFiltering(provider.items);
    }

    final Map<String, dynamic> metrics = _calculateMetrics(provider.items);
    final Map<String, List<ProductModel>> groupedMap = _getGroupedData(provider.items);
    final List<String> groupKeys = groupedMap.keys.toList()..sort();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              _buildDashboard(metrics, provider.items.length, theme),
              Divider(height: 1, color: theme.dividerTheme.color ?? Colors.grey.withValues(alpha: 0.2)),
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
          if ((provider.isParsing || provider.isSaving || _isFullScreenLoading) && !_isFullScreenLoading) ...[
            _buildGlobalLoadingOverlay(provider, theme),
          ],
          if (_isFullScreenLoading) ...[
            _buildGlobalLoadingOverlay(provider, theme, customMessage: "데이터 대량 처리 중..."),
          ]
        ],
      ),
    );
  }

  /// 상단 요약 대시보드
  Widget _buildDashboard(Map<String, dynamic> m, int totalCount, ThemeData theme) {
    if (widget.isMobile) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: theme.scaffoldBackgroundColor,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildStatTile("자산 마스터", totalCount, Icons.list_alt, Colors.blueGrey, theme, filterKey: "전체")),
                const SizedBox(width: 12),
                Expanded(child: _buildStatTile("금일 입고", m['in'] as int, Icons.add_business_outlined, AppTheme.success, theme, filterKey: "금일 입고")),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatTile("금일 출고", m['out'] as int, Icons.local_shipping_outlined, AppTheme.warning, theme, filterKey: "금일 출고")),
                const SizedBox(width: 12),
                Expanded(child: _buildStatTile("현재 실재고", m['stock'] as int, Icons.inventory_2_outlined, AppTheme.primary, theme, filterKey: "현재 실재고")),
              ],
            ),
          ],
        ),
      );
    }

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

  /// 대시보드의 개별 타일 위젯
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
          color: isSelected ? color.withValues(alpha: isDark ? 0.15 : 0.08) : theme.cardColor,
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

  /// 화면 분할에 필요한 그룹 데이터 생성기
  Map<String, List<ProductModel>> _getGroupedData(List<ProductModel> items) {
    final Map<String, List<ProductModel>> grouped = {};
    for (final ProductModel i in _filteredCache) {
      final String key = _groupByMode == 'item'
          ? i.name
          : (_groupByMode == 'location'
          ? _safeStr(i.location, defaultVal: "미지정")
          : _safeStr(i.category, defaultVal: "미정"));

      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(i);
    }
    return grouped;
  }

  /// 데스크톱/태블릿용 스플릿 레이아웃
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
        VerticalDivider(width: 1, color: theme.dividerTheme.color ?? Colors.grey.withValues(alpha: 0.2)),
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

  /// 모바일용 단일 레이아웃
  Widget _buildMobileLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys, ThemeData theme) {
    if (_selectedGroupKey != null) {
      return Column(
        children: [
          _buildHeader(provider, theme),
          Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 8, top: 4, bottom: 8),
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedGroupKey = null;
                  _selectedItemIds.clear();
                });
              },
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              label: const Text("그룹 목록으로 돌아가기", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 15)),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ),
          Expanded(
            child: _buildDetailView(provider, _selectedGroupKey!, groupedMap[_selectedGroupKey] ?? [], theme),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildHeader(provider, theme),
        _buildFilterBar(theme),
        Expanded(
          child: groupKeys.isEmpty
              ? _buildEmptyState("검색 결과가 없습니다.")
              : ListView.separated(
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

  /// 로딩 상태 오버레이
  Widget _buildGlobalLoadingOverlay(ProductProvider provider, ThemeData theme, {String? customMessage}) {
    return Container(
      color: Colors.black.withValues(alpha: 0.1),
      child: Center(
        child: Card(
          elevation: 10,
          color: theme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 5),
                const SizedBox(height: 25),
                Text(
                  customMessage ?? (provider.isParsing ? "데이터 분석 중..." : "데이터베이스 통신 중..."),
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

  /// 컨트롤 헤더 및 버튼 영역
  Widget _buildHeader(ProductProvider provider, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: widget.isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildActionIconButton(Icons.refresh, "새로고침", () {
                      provider.fetchData();
                    }, theme),
                    _buildActionIconButton(
                      _isSelectionMode ? Icons.close_fullscreen_rounded : Icons.checklist_rtl_rounded,
                      _isSelectionMode ? "다중 선택 끄기" : "다중 선택 켜기",
                          () {
                        setState(() {
                          _isSelectionMode = !_isSelectionMode;
                          if (!_isSelectionMode) {
                            _selectedItemIds.clear();
                          }
                        });
                      },
                      theme,
                      color: _isSelectionMode ? AppTheme.primary : null,
                    ),
                    _buildActionIconButton(Icons.sync_alt_rounded, "ERP 연동 (가져오기)", () {
                      _triggerErpSync(theme);
                    }, theme, color: Colors.teal),
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
                    _buildActionIconButton(Icons.post_add_rounded, "신규 등록", () {
                      _showForm(provider, null, theme);
                    }, theme, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _searchController,
            onChanged: (String v) {
              setState(() {
                _aiFilteredIds = null;
              });
              _onSearchChanged(v);
            },
            style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
            decoration: AppTheme.inputDecoration(label: "품명, 위치 등 일반 검색 또는 문장 작성 후 AI 버튼 클릭...", context: context, prefixIcon: Icons.search).copyWith(
                suffixIcon: _isAiSearching
                    ? const Padding(
                  padding: EdgeInsets.all(14.0),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.deepPurpleAccent)
                  ),
                )
                    : IconButton(
                  icon: const Icon(Icons.auto_awesome_rounded, color: Colors.deepPurpleAccent),
                  tooltip: "AI 자연어 스마트 검색 (예: A창고에 있는 모니터 찾아줘)",
                  onPressed: () {
                    _performAiSearch(provider.items, theme);
                  },
                )
            ),
          ),
        ],
      ),
    );
  }

  /// 개별 액션 아이콘 버튼 디자인
  Widget _buildActionIconButton(IconData icon, String tip, VoidCallback onTap, ThemeData theme, {Color? color, bool isLarge = false}) {
    final Color iconColor = color ?? theme.iconTheme.color ?? Colors.grey.shade600;

    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconColor.withValues(alpha: 0.08),
            border: Border.all(color: iconColor.withValues(alpha: 0.15), width: 1.5),
          ),
          child: Icon(icon, color: iconColor, size: isLarge ? 28 : 22),
        ),
      ),
    );
  }

  /// 그룹핑 모드 스위처
  Widget _buildFilterBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppTheme.primary,
            selectedForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            textStyle: const TextStyle(
              fontFamily: AppTheme.fontPretendard,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
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
              _selectedItemIds.clear();
            });
          },
        ),
      ),
    );
  }

  /// 상세 리스트 영역 (RepaintBoundary 최적화 포함)
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
              Expanded(
                  child: Text(
                    groupName,
                    style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w800, fontSize: 20, color: AppTheme.dataColor(theme.brightness == Brightness.dark), letterSpacing: -0.4),
                    overflow: TextOverflow.ellipsis,
                  )
              ),
            ],
          ),
        ),

        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _isSelectionMode
              ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text('${_selectedItemIds.length}개 선택됨', style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.wifi_tethering, size: 18),
                    label: const Text("태그 일괄 발급", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, elevation: 0),
                    onPressed: () {
                      final deviceProvider = context.read<DeviceProvider>();
                      showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (BuildContext ctx) {
                            return _BulkTagIssueDialog(
                              selectedProducts: items.where((ProductModel p) {
                                return _selectedItemIds.contains(p.id);
                              }).toList(),
                              provider: provider,
                              deviceProvider: deviceProvider,
                              theme: theme,
                              onSuccessItem: (String pid) {
                                setState(() {
                                  _selectedItemIds.remove(pid);
                                  if (_selectedItemIds.isEmpty) {
                                    _isSelectionMode = false;
                                  }
                                });
                              },
                              onWriteComplete: (String originalTag) {
                                debugPrint("태그 일괄 발급 완료 (원본): $originalTag");
                              },
                            );
                          }
                      );
                    },
                  ),
                  const SizedBox(width: 8),
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
                  Container(width: 1, height: 24, color: theme.dividerColor),
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
            ),
          )
              : Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('총 ${items.length}개 항목', style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13)),
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (BuildContext ctx, int idx) {
              final ProductModel p = items[idx];
              final bool isSelected = _selectedItemIds.contains(p.id);
              final Color statusColor = _getStatusColor(p.status);

              return RepaintBoundary(
                key: ValueKey('product_${p.id}_${p.updated}'),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
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
                              padding: const EdgeInsets.all(4.0),
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

                      Expanded(
                        child: InkWell(
                          onTap: () {
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
                              child: widget.isMobile
                                  ? _buildMobileListItem(p, provider, items, statusColor, theme)
                                  : _buildDesktopListItem(p, provider, items, statusColor, theme)
                          ),
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

  /// 데스크탑용 개별 아이템 위젯
  Widget _buildDesktopListItem(ProductModel p, ProductProvider provider, List<ProductModel> items, Color statusColor, ThemeData theme) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => _handleGroupImageUpdate(provider, items, theme),
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              _buildThumbnail(p, theme, size: _colImgSize),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.cardColor, width: 2),
                ),
                child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                  children: [
                    Flexible(
                      child: Text(p.name, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 19), overflow: TextOverflow.ellipsis),
                    ),
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
              _buildCircleAction(Icons.nfc_rounded, Colors.indigo, "개별 태그 발행", () {
                final deviceProvider = context.read<DeviceProvider>();
                showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (BuildContext ctx) {
                      return _BulkTagIssueDialog(
                          selectedProducts: [p],
                          provider: provider,
                          deviceProvider: deviceProvider,
                          theme: theme,
                          onSuccessItem: (String pid) {
                            setState(() {
                              _selectedItemIds.remove(pid);
                              if (_selectedItemIds.isEmpty) _isSelectionMode = false;
                            });
                          }
                      );
                    }
                );
              }),
              const SizedBox(width: 12),
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
    );
  }

  /// 모바일용 개별 아이템 위젯
  Widget _buildMobileListItem(ProductModel p, ProductProvider provider, List<ProductModel> items, Color statusColor, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _handleGroupImageUpdate(provider, items, theme),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  _buildThumbnail(p, theme, size: _colImgSize),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.cardColor, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                      children: [
                        Expanded(
                            child: Text(p.name,
                              style: AppTheme.itemValueStyle(context).copyWith(fontSize: 19),
                              overflow: TextOverflow.ellipsis,
                            )
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(p.status),
                        if (!p.isApproved)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18),
                          ),
                      ]
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16, runSpacing: 8,
          children: provider.selectedColumns
              .where((String col) => col != '품명')
              .map((String col) {
            return SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(col, style: AppTheme.itemLabelStyle(context)),
                  Text(_getAttributeValue(col, p), style: AppTheme.itemValueStyle(context).copyWith(fontSize: 14), overflow: TextOverflow.ellipsis),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Divider(color: theme.dividerTheme.color?.withValues(alpha: 0.5) ?? Colors.grey.withValues(alpha: 0.2)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 12,
          alignment: WrapAlignment.spaceEvenly,
          children: [
            _buildCircleAction(Icons.nfc_rounded, Colors.indigo, "개별 태그 발행", () {
              final deviceProvider = context.read<DeviceProvider>();
              showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext ctx) {
                    return _BulkTagIssueDialog(
                        selectedProducts: [p],
                        provider: provider,
                        deviceProvider: deviceProvider,
                        theme: theme,
                        onSuccessItem: (String pid) {
                          setState(() {
                            _selectedItemIds.remove(pid);
                            if (_selectedItemIds.isEmpty) _isSelectionMode = false;
                          });
                        }
                    );
                  }
              );
            }),
            _buildCircleAction(Icons.history, Colors.blueGrey, "이력", () {
              _showHistoryDialog(p, theme);
            }),
            _buildCircleAction(Icons.login, AppTheme.success, "입고", () {
              _processAssetAccess(provider, p, '수기입고', theme);
            }),
            _buildCircleAction(Icons.logout, AppTheme.warning, "출고", () {
              _processAssetAccess(provider, p, '수기출고', theme);
            }),
            _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () {
              _confirmIndividualDelete(provider, p, theme);
            }),
          ],
        ),
      ],
    );
  }

  /// 그룹 이미지 일괄 갱신 핸들러 (비동기 Lint 원천 차단 적용)
  Future<void> _handleGroupImageUpdate(ProductProvider provider, List<ProductModel> groupItems, ThemeData theme) async {
    if (groupItems.isEmpty) {
      return;
    }

    final String targetName = groupItems.first.name;
    final List<ProductModel> targetItems = provider.items.where((ProductModel p) => p.name == targetName).toList();

    if (targetItems.isEmpty) {
      return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (image == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
            title: AppTheme.dialogTitle("대표 이미지 일괄 적용", Icons.photo_camera_front),
            content: Text(
                "선택하신 이미지를 '$targetName' 품명을 가진 모든 자산(${targetItems.length}개)에 일괄 적용하시겠습니까?\n\n(개별적으로 등록했던 특수 이미지가 있다면 덮어씌워집니다.)",
                style: const TextStyle(fontFamily: AppTheme.fontPretendard)
            ),
            actions: [
              AppTheme.actionButton(
                  label: "취소",
                  color: Colors.transparent,
                  textColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  onPressed: () => Navigator.pop(ctx, false)
              ),
              AppTheme.actionButton(
                  label: "일괄 변경",
                  color: AppTheme.primary,
                  onPressed: () => Navigator.pop(ctx, true)
              ),
            ]
        )
    );

    if (confirm != true) {
      return;
    }

    if (!mounted) {
      return;
    }

    final NavigatorState nav = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ValueNotifier<int> currentCountNotifier = ValueNotifier<int>(0);

    setState(() {
      _isFullScreenLoading = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (BuildContext ctx) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            elevation: 10,
            color: theme.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 40),
              child: ValueListenableBuilder<int>(
                valueListenable: currentCountNotifier,
                builder: (BuildContext buildCtx, int currentCount, Widget? child) {
                  final double progress = targetItems.isNotEmpty ? currentCount / targetItems.length : 0.0;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: CircularProgressIndicator(
                              value: progress,
                              color: AppTheme.primary,
                              backgroundColor: theme.dividerColor.withValues(alpha: 0.3),
                              strokeWidth: 8,
                            ),
                          ),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 25),
                      const Text(
                        "이미지 일괄 적용 중...",
                        style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "총 ${targetItems.length}건 중 $currentCount건 처리 완료\n(창을 닫지 마세요)",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    int successCount = 0;
    int failCount = 0;

    try {
      for (ProductModel p in targetItems) {
        final Map<String, dynamic> data = {
          'name': p.name,
          'tag_id': p.tagId,
          'location': p.location,
          'spec': p.spec,
          'category': p.category,
          'serial_number': p.serialNumber,
          'safety_stock': p.safetyStock,
          'status': p.status,
          'is_approved': p.isApproved,
          'metadata': p.metadata,
        };

        bool ok = await provider.handleSave(product: p, data: data, imageXFile: image);
        if (ok) {
          successCount++;
        } else {
          failCount++;
        }
        currentCountNotifier.value++;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFullScreenLoading = false;
        });
      }
      nav.pop();
    }

    if (!mounted) {
      return;
    }

    _syncFiltering(provider.items);

    messenger.showSnackBar(SnackBar(
        content: Text("일괄 적용 완료: 총 ${targetItems.length}개의 자산 중 ✅ $successCount개 적용 성공 ❌ $failCount개 적용 실패", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
        elevation: 0
    ));
  }

  /// 좌측 그룹핑 타일
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
            color: isSelected ? AppTheme.primary.withValues(alpha: 0.05) : theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSelected ? AppTheme.primary : (theme.brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.12)),
                width: isSelected ? 2.0 : 1.0
            )
        ),
        child: Row(
            children: [
              GestureDetector(
                onTap: () => _handleGroupImageUpdate(provider, items, theme),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    _buildThumbnail(items.isNotEmpty ? items.first : null, theme, size: 52),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.cardColor, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),
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

  /// 썸네일 이미지 빌더
  Widget _buildThumbnail(ProductModel? p, ThemeData theme, {double size = 44}) {
    final bool isDark = theme.brightness == Brightness.dark;

    if (p == null) {
      return Container(
          width: size, height: size,
          decoration: BoxDecoration(
              color: isDark ? theme.dividerColor.withValues(alpha: 0.1) : const Color(0xFFF1F3F5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.dividerTheme.color ?? Colors.grey.withValues(alpha: 0.3), width: 1.0)
          ),
          child: const Icon(Icons.inventory_2_outlined, color: Colors.black12, size: 24)
      );
    }

    final String url = p.getImageUrl(widget.baseUrl, thumb: '100x100');

    if (url.isEmpty) {
      return Container(
          width: size, height: size,
          decoration: BoxDecoration(
              color: isDark ? theme.dividerColor.withValues(alpha: 0.1) : const Color(0xFFF1F3F5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.dividerTheme.color ?? Colors.grey.withValues(alpha: 0.3), width: 1.0)
          ),
          child: const Icon(Icons.inventory_2_outlined, color: Colors.black12, size: 24)
      );
    }

    final String connector = url.contains('?') ? '&' : '?';
    final int timeStamp = p.updated.millisecondsSinceEpoch;
    final String fullUrl = "$url${connector}t=$timeStamp";

    return Container(
        key: ValueKey('thumb_${p.id}_$timeStamp'),
        width: size, height: size,
        decoration: BoxDecoration(
            color: isDark ? theme.dividerColor.withValues(alpha: 0.1) : const Color(0xFFF1F3F5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey.withValues(alpha: 0.3), width: 1.0)
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
            fullUrl,
            fit: BoxFit.cover,
            cacheWidth: (size * 2).toInt(),
            errorBuilder: (BuildContext ctx, Object err, StackTrace? stack) => const Icon(Icons.broken_image, size: 18, color: Colors.black12),
            loadingBuilder: (BuildContext ctx, Widget child, ImageChunkEvent? loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
              return const Center(child: SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)));
            }
        )
    );
  }

  /// 상태값 표시 뱃지
  Widget _buildStatusBadge(String status) {
    final Color color = _getStatusColor(status);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(status, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: color, fontSize: 11, fontWeight: FontWeight.w900))
    );
  }

  /// 키-값 표시 유틸리티
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

  /// 원형 액션 버튼 (호버 및 툴팁 제공)
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

  /// 빈 상태 안내 화면
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

  /// 안내 다이얼로그
  void _showInfoDialog(String title, String msg, ThemeData theme) {
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle(title, Icons.info_outline),
              content: Text(msg, style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
              actions: [
                AppTheme.actionButton(
                    label: "확인",
                    onPressed: () {
                      Navigator.pop(ctx);
                    }
                )
              ]
          );
        }
    );
  }

  /// 표시 항목 설정 (Column Selection) 다이얼로그 호출
  void _showColumnSelectionDialog(ProductProvider provider, ThemeData theme) {
    final List<String> baseFields = ['품명', '태그ID', 'EPC', '위치', '상태', '규격', '분류', 'S/N'];
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

  /// 전체 데이터 리셋 확인 다이얼로그
  void _showResetDialog(ProductProvider provider, ThemeData theme) {
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("전체 초기화", Icons.delete_forever, color: AppTheme.danger),
              content: const Text("모든 정보를 삭제하시겠습니까?\n이 작업은 되돌릴 수 편집할 수 없습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)),
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
                      final NavigatorState nav = Navigator.of(ctx);
                      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

                      nav.pop();

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
                      messenger.showSnackBar(const SnackBar(content: Text('전체 초기화가 완료되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard))));
                    }
                )
              ]
          );
        }
    );
  }

  /// 일괄 삭제 확인 다이얼로그
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
                      final NavigatorState nav = Navigator.of(ctx);
                      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

                      nav.pop();

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
                        _isSelectionMode = false;
                      });

                      _syncFiltering(provider.items);
                      messenger.showSnackBar(const SnackBar(content: Text("선택한 항목들이 일괄 삭제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
                    }
                )
              ]
          );
        }
    );
  }

  /// 개별 항목 삭제 확인 다이얼로그
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
                      final NavigatorState nav = Navigator.of(ctx);
                      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

                      nav.pop();

                      await provider.deleteMultipleProducts([p.id]);

                      if (!mounted) {
                        return;
                      }

                      setState(() {
                        _selectedItemIds.remove(p.id);
                      });

                      _syncFiltering(provider.items);
                      messenger.showSnackBar(const SnackBar(content: Text("삭제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
                    }
                )
              ]
          );
        }
    );
  }

  /// 그룹 일괄 삭제 확인 다이얼로그
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
                      final NavigatorState nav = Navigator.of(ctx);
                      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

                      nav.pop();

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
                      messenger.showSnackBar(const SnackBar(content: Text("일괄 삭제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
                    }
                )
              ]
          );
        }
    );
  }

  /// 수기 입출고 처리 프로세스 연동
  Future<void> _processAssetAccess(ProductProvider provider, ProductModel p, String type, ThemeData theme) async {
    // 1. [Lock 검사] 이미 DB 저장 트랜잭션이 진행 중이면 즉시 차단 (Race Condition 방지)
    if (_lockedItemIds.contains(p.id)) {
      debugPrint('[${p.name}] 현재 다른 프로세스가 처리 중입니다. (Lock 적용됨)');
      return;
    }

    // 2. [채터링 방지] 최근 3초 이내에 처리된 이력이 있다면 무시 (디바운스/쿨다운)
    if (_itemCooldowns.containsKey(p.id)) {
      final int elapsedMs = DateTime.now().difference(_itemCooldowns[p.id]!).inMilliseconds;
      if (elapsedMs < 3000) { // 3000ms = 3초
        debugPrint('[${p.name}] 쿨다운 타임 적용 중입니다. ($elapsedMs ms 경과)');
        return;
      }
    }

    // Lock 획득
    setState(() {
      _lockedItemIds.add(p.id);
    });

    try {
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      final userProvider = context.read<UserProvider>();

      final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (BuildContext ctx) {
            return _ManualInoutDialog(
              type: type,
              product: p,
              statusIcons: _statusIcons,
              userList: userProvider.list,
            );
          }
      );

      if (result == null) {
        return; // 사용자가 취소한 경우 (finally 블록에서 자동으로 Lock 해제됨)
      }

      // [상태 중복 방지 최적화]
      if (p.status == result['status'] && _safeStr(p.location) == result['location']) {
        messenger.showSnackBar(SnackBar(
            content: Text('[${p.name}] 자산은 이미 [${p.status}] 상태이며 위치가 동일합니다. (저장 무시)', style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
            backgroundColor: Colors.blueGrey,
            elevation: 0,
            duration: const Duration(seconds: 2)
        ));
        return;
      }

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

        // 🔥 성공 시 쿨다운 타임 기록 (이 시점부터 3초간 동일 항목 재처리 불가)
        _itemCooldowns[p.id] = DateTime.now();

        messenger.showSnackBar(SnackBar(
            content: Text('[${p.name}] 처리 완료', style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
            backgroundColor: AppTheme.success,
            elevation: 0,
            duration: const Duration(seconds: 1)
        ));
      }
    } finally {
      // 예외가 발생하든 정상 종료되든 반드시 Lock 반환
      if (mounted) {
        setState(() {
          _lockedItemIds.remove(p.id);
        });
      }
    }
  }

  /// 상세 이력 보기 다이얼로그
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
                  separatorBuilder: (BuildContext c, int i) => Divider(height: 24, color: theme.dividerTheme.color?.withValues(alpha: 0.5)),
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

  /// 일괄 편집 다이얼로그
  void _showBulkEditDialog(ProductProvider provider, List<ProductModel> visibleItems, ThemeData theme) async {
    final List<ProductModel> selectedProducts = visibleItems.where((ProductModel p) => _selectedItemIds.contains(p.id)).toList();
    if (selectedProducts.isEmpty) {
      return;
    }

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

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
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

    if (resultValues == null) {
      return;
    }

    setState(() {
      _isFullScreenLoading = true;
    });

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

    if (!mounted) {
      return;
    }

    setState(() {
      _isFullScreenLoading = false;
      _selectedItemIds.clear();
      _isSelectionMode = false;
    });

    _syncFiltering(provider.items);

    messenger.showSnackBar(SnackBar(
        content: Text("일괄 편집 완료: 선택하신 ${selectedProducts.length}개의 항목이 성공적으로 업데이트 되었습니다.", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
        elevation: 0
    ));
  }

  /// 자산 신규 등록 및 수정 폼
  void _showForm(ProductProvider provider, ProductModel? p, ThemeData theme) async {
    final TextEditingController nameC = TextEditingController(text: p?.name ?? "");
    final TextEditingController tagC = TextEditingController(text: p?.tagId ?? "");
    final TextEditingController locC = TextEditingController(text: p != null ? _safeStr(p.location) : "");
    final TextEditingController specC = TextEditingController(text: p != null ? _safeStr(p.spec) : "");
    final TextEditingController catC = TextEditingController(text: p != null ? _safeStr(p.category) : "");
    final TextEditingController snC = TextEditingController(text: p != null ? _safeStr(p.serialNumber) : "");
    final TextEditingController safeC = TextEditingController(text: p != null ? p.safetyStock.toString() : "5");

    final TextEditingController bulkCountC = TextEditingController(text: "1");

    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    bool isApproved = p?.isApproved ?? true;

    XFile? file;
    Uint8List? preview;
    bool isImageDeleted = false;

    final Map<String, TextEditingController> metaC = {};
    final Set<String> allMetaKeys = {};

    for (final ProductModel item in provider.items) {
      for (final String key in item.metadata.keys) {
        final dynamic val = item.metadata[key];
        if (!_excludedSystemKeys.contains(key) && !key.endsWith('_internal') && val is! Map && val is! List) {
          allMetaKeys.add(key);
        }
      }
    }

    if (p != null) {
      p.metadata.forEach((String key, dynamic val) {
        if (!_excludedSystemKeys.contains(key) && !key.endsWith('_internal') && val is! Map && val is! List) {
          allMetaKeys.add(key);
        }
      });
    }

    final List<String> sortedMetaKeys = allMetaKeys.toList()..sort();
    for (final String key in sortedMetaKeys) {
      final String initialValue = p != null ? _safeStr(p.metadata[key]) : "";
      metaC[key] = TextEditingController(text: initialValue);
    }

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogCtx) {
          return StatefulBuilder(
              builder: (BuildContext innerCtx, StateSetter setS) {

                Widget imagePickerWidget = _buildImagePickerBox(
                  context,
                  p,
                  preview,
                  isImageDeleted,
                      (XFile pickedFile, Uint8List pickedBytes) {
                    setS(() {
                      file = pickedFile;
                      preview = pickedBytes;
                      isImageDeleted = false;
                    });
                  },
                      () {
                    setS(() {
                      file = null;
                      preview = null;
                      isImageDeleted = true;
                    });
                  },
                  theme,
                );

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
                                              imagePickerWidget,
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

                                                  IntrinsicHeight(
                                                    child: Row(
                                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                                      children: [
                                                        Expanded(child: _buildTextField(tagC, "태그ID / 바코드 (원본 식별자)", theme, context)),
                                                        const SizedBox(width: 12),
                                                        ElevatedButton.icon(
                                                          onPressed: () {
                                                            showDialog(
                                                                context: context,
                                                                barrierDismissible: false,
                                                                builder: (BuildContext ctx) {
                                                                  return _BulkTagIssueDialog(
                                                                    selectedProducts: p != null ? [p] : [],
                                                                    provider: provider,
                                                                    deviceProvider: context.read<DeviceProvider>(),
                                                                    theme: theme,
                                                                    onSuccessItem: (String pid) {
                                                                      setState(() {
                                                                        _selectedItemIds.remove(pid);
                                                                      });
                                                                    },
                                                                    onWriteComplete: (String originalTag) {
                                                                      setS(() {
                                                                        // 신규 자산 등록 시에만(입력값이 없을 때) 자동 생성된 태그를 반영
                                                                        if (p == null && tagC.text.isEmpty) {
                                                                          tagC.text = originalTag;
                                                                        }
                                                                      });
                                                                    },
                                                                  );
                                                                }
                                                            );
                                                          },
                                                          icon: const Icon(Icons.nfc_rounded),
                                                          label: const Text("장비로 기록", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 15)),
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor: Colors.indigo,
                                                            foregroundColor: Colors.white,
                                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),

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

                                  if (p == null) ...[
                                    const SizedBox(height: 40),
                                    _buildSectionHeader(Icons.library_add_check_rounded, "다중 자산 일괄 생성 (Bulk Create)", AppTheme.primary),
                                    const SizedBox(height: 20),
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text("동시 생성 수량", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.dataColor(theme.brightness == Brightness.dark))),
                                                const SizedBox(height: 8),
                                                const Text("입력한 수량만큼 태그ID와 S/N에 순번(_1, _2...)이 붙어 자동으로 여러 개가 생성됩니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            width: 150,
                                            child: _buildTextField(bulkCountC, "수량 (개)", theme, context),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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
                              ScaffoldMessenger.of(dialogCtx).showSnackBar(const SnackBar(content: Text("품명은 필수 입력 사항입니다.")));
                              return;
                            }

                            final Map<String, dynamic> meta = Map<String, dynamic>.from(p?.metadata ?? {});
                            metaC.forEach((String k, TextEditingController c) {
                              meta[k] = c.text.trim();
                            });

                            int bulkCount = 1;
                            if (p == null) {
                              bulkCount = int.tryParse(bulkCountC.text.trim()) ?? 1;
                              if (bulkCount < 1) {
                                bulkCount = 1;
                              }
                            }

                            final NavigatorState nav = Navigator.of(dialogCtx);
                            final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

                            if (bulkCount <= 1) {
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
                                'status': p?.status ?? '보유중',
                              };

                              final bool ok = await provider.handleSave(product: p, data: data, imageXFile: file);
                              if (!dialogCtx.mounted) {
                                return;
                              }
                              if (ok) {
                                _syncFiltering(provider.items);
                                nav.pop();
                                messenger.showSnackBar(
                                    const SnackBar(content: Text("마스터 정보가 성공적으로 반영되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)))
                                );
                              }
                            } else {
                              nav.pop();
                              setState(() {
                                _isFullScreenLoading = true;
                              });

                              int successCount = 0;

                              for (int i = 0; i < bulkCount; i++) {
                                String currentTagId = tagC.text.trim();
                                String currentSn = snC.text.trim();

                                if (currentTagId.isNotEmpty) {
                                  currentTagId = "${currentTagId}_${i + 1}";
                                }
                                if (currentSn.isNotEmpty) {
                                  currentSn = "${currentSn}_${i + 1}";
                                }

                                if (currentTagId.isEmpty) {
                                  currentTagId = "TAG_${DateTime.now().millisecondsSinceEpoch}_$i";
                                }

                                final Map<String, dynamic> data = {
                                  'name': nameC.text.trim(),
                                  'tag_id': currentTagId,
                                  'location': locC.text.trim(),
                                  'spec': specC.text.trim(),
                                  'category': catC.text.trim(),
                                  'serial_number': currentSn,
                                  'safety_stock': int.tryParse(safeC.text.trim()) ?? 5,
                                  'is_approved': isApproved,
                                  'metadata': meta,
                                  'status': '보유중',
                                };

                                bool ok = await provider.handleSave(product: null, data: data, imageXFile: file);
                                if (ok) {
                                  successCount++;
                                }
                              }

                              if (!mounted) {
                                return;
                              }

                              setState(() {
                                _isFullScreenLoading = false;
                              });
                              _syncFiltering(provider.items);

                              messenger.showSnackBar(
                                  SnackBar(content: Text("총 $successCount개의 마스터 정보가 벌크(일괄) 생성되었습니다.", style: const TextStyle(fontFamily: AppTheme.fontPretendard)))
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

  Widget _buildImagePickerBox(
      BuildContext context,
      ProductModel? p,
      Uint8List? preview,
      bool isDeleted,
      Function(XFile, Uint8List) onPicked,
      VoidCallback onDeleted,
      ThemeData theme
      ) {
    final String url = p != null ? p.getImageUrl(widget.baseUrl, thumb: '200x200') : '';
    final bool hasImage = preview != null || (url.isNotEmpty && !isDeleted);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () async {
            final ImagePicker picker = ImagePicker();
            final XFile? img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
            if (img != null) {
              final Uint8List b = await img.readAsBytes();
              onPicked(img, b);
            }
          },
          child: Container(
            width: 220, height: 250,
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 2)
            ),
            child: Center(
              child: preview != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(preview, fit: BoxFit.cover))
                  : (hasImage
                  ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network("$url?t=${p?.updated.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}", fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)))
                  : const Icon(Icons.camera_alt, size: 50, color: Colors.grey)),
            ),
          ),
        ),

        if (hasImage)
          Positioned(
            top: -10,
            right: -10,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onDeleted,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: AppTheme.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 2.5),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2))
                      ]
                  ),
                  child: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
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

  /// 엑셀 기반 대량 일괄 임포트 프로세스
  Future<void> _handleBatchImport(ProductProvider provider, ThemeData theme) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState mainNav = Navigator.of(context);

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
      if (result == null) {
        return;
      }

      Uint8List? bytes = result.files.single.bytes;
      if (bytes == null && result.files.single.path != null) {
        bytes = await File(result.files.single.path!).readAsBytes();
      }

      if (bytes == null) {
        return;
      }

      final excel_pkg.Excel excel = excel_pkg.Excel.decodeBytes(bytes);
      String targetSheet = excel.tables.keys.first;

      if (excel.tables.keys.contains('물품리스트')) {
        targetSheet = '물품리스트';
      }

      final excel_pkg.Sheet? sheet = excel.tables[targetSheet];
      if (sheet == null || sheet.maxRows <= 1) {
        return;
      }

      final List<String> headers = [];
      if (sheet.rows.isNotEmpty) {
        for (final excel_pkg.Data? cell in sheet.rows.first) {
          headers.add(_extractString(cell));
        }
      }

      int actualValidRows = 0;
      for (int i = 1; i < sheet.maxRows; i++) {
        bool hasData = false;
        for (final excel_pkg.Data? cell in sheet.row(i)) {
          if (_extractString(cell).isNotEmpty) {
            hasData = true;
            break;
          }
        }
        if (hasData) {
          actualValidRows++;
        }
      }

      if (!mounted) {
        return;
      }

      final ValueNotifier<int> currentCountNotifier = ValueNotifier<int>(0);

      setState(() {
        _isFullScreenLoading = true;
      });

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return PopScope(
            canPop: false,
            child: Center(
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 40),
                  child: ValueListenableBuilder<int>(
                    valueListenable: currentCountNotifier,
                    builder: (BuildContext context, int currentCount, Widget? child) {
                      final double progress = actualValidRows > 0 ? currentCount / actualValidRows : 0.0;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(width: 80, height: 80, child: CircularProgressIndicator(value: progress, color: AppTheme.primary, strokeWidth: 8)),
                              Text('${(progress * 100).toInt()}%', style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 25),
                          const Text("물품 대량 전송 중...", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 18)),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      );

      for (int i = 1; i < sheet.maxRows; i++) {
        final List<excel_pkg.Data?> row = sheet.row(i);
        if (row.isEmpty) {
          continue;
        }

        String name = "", tagId = "", tagEpc = "", location = "", category = "", status = "";
        final Map<String, dynamic> metadata = {};
        bool hasRowData = false;

        for (int colIdx = 0; colIdx < row.length; colIdx++) {
          if (colIdx >= headers.length) {
            break;
          }

          final String rawHeader = headers[colIdx];
          final String cleanHeader = rawHeader.replaceAll(RegExp(r'[\s_\-()]+'), '').toLowerCase();
          final String val = _extractString(row[colIdx]);

          if (val.isNotEmpty) {
            hasRowData = true;
          }

          if (cleanHeader.contains('품명') || cleanHeader.contains('이름')) {
            name = val;
          } else if (cleanHeader.contains('태그id') || cleanHeader.contains('uid')) {
            tagId = val;
          } else if (cleanHeader.contains('epc')) {
            tagEpc = val;
          } else if (cleanHeader.contains('위치')) {
            location = val;
          } else if (cleanHeader.contains('분류')) {
            category = val;
          } else if (cleanHeader.contains('상태')) {
            status = val;
          } else if (rawHeader.isNotEmpty && val.isNotEmpty) {
            metadata[rawHeader] = val;
          }
        }

        if (!hasRowData) {
          continue;
        }

        if (name.isEmpty) {
          name = "형식에 맞지 않는 건";
        }
        if (tagId.isEmpty) {
          tagId = "TAG_${DateTime.now().millisecondsSinceEpoch}_$i";
        }
        if (location.isEmpty) {
          location = "미지정";
        }
        if (category.isEmpty) {
          category = "미지정";
        }
        if (status.isEmpty) {
          status = "보유중";
        }

        final Map<String, dynamic> data = {
          'name': name,
          'tag_id': tagId,
          'tag_epc': tagEpc,
          'location': location,
          'category': category,
          'status': status,
          'is_active': true,
          'metadata': metadata
        };

        await provider.handleSave(product: null, data: data);
        currentCountNotifier.value++;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isFullScreenLoading = false;
      });
      mainNav.pop();
      messenger.showSnackBar(const SnackBar(content: Text('✅ 엑셀 임포트가 성공적으로 완료되었습니다.')));

    } catch (e) {
      if (mounted) {
        setState(() {
          _isFullScreenLoading = false;
        });
      }
    }
  }

  /// 엑셀 데이터 파싱 보조 함수
  String _extractString(excel_pkg.Data? cell) {
    if (cell == null || cell.value == null) {
      return "";
    }
    return cell.value.toString().trim().replaceAll(RegExp(r'^[a-zA-Z]+CellValue\((.*)\)$'), r'$1').replaceAll('"', '');
  }

  /// 엑셀 파일 내보내기 (Export)
  Future<void> _exportToExcel(List<ProductModel> list) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      final excel_pkg.Excel excel = excel_pkg.Excel.createExcel();
      final String defaultSheet = excel.tables.keys.first;
      excel.rename(defaultSheet, '물품리스트');

      // 🔥 [Null-Safety 최적화]
      // 최신 엑셀 패키지에서 excel['시트명']은 시트가 없으면 자동으로 생성 후 반환하므로
      // 절대 Null이 되지 않습니다. 따라서 불필요한 '!' 강제 언래핑을 제거했습니다.
      final excel_pkg.Sheet sheet = excel['물품리스트'];

      final List<String> baseHeaders = ['품명', '태그ID', 'EPC', '위치', '상태', '규격', '분류', 'S/N'];

      final Set<String> metaKeySet = {};
      for (final ProductModel p in list) {
        for (final String k in p.metadata.keys) {
          if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal')) {
            metaKeySet.add(k);
          }
        }
      }
      final List<String> metaFields = metaKeySet.toList()..sort();
      final List<String> allHeaders = [...baseHeaders, ...metaFields];

      sheet.appendRow(allHeaders.map((String h) => excel_pkg.TextCellValue(h)).toList());

      for (final ProductModel i in list) {
        final List<excel_pkg.CellValue> rowData = [
          excel_pkg.TextCellValue(i.name),
          excel_pkg.TextCellValue(i.tagId),
          excel_pkg.TextCellValue(i.tagEpc),
          excel_pkg.TextCellValue(_safeStr(i.location)),
          excel_pkg.TextCellValue(i.status),
          excel_pkg.TextCellValue(_safeStr(i.spec)),
          excel_pkg.TextCellValue(_safeStr(i.category)),
          excel_pkg.TextCellValue(_safeStr(i.serialNumber)),
        ];

        for (final String metaKey in metaFields) {
          rowData.add(excel_pkg.TextCellValue(_safeStr(i.metadata[metaKey])));
        }

        sheet.appendRow(rowData);
      }

      final String? path = await FilePicker.platform.saveFile(
          fileName: 'Inventory_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx']
      );

      if (path != null) {
        // 🔥 [Null-Safety 대응] 최신 패키지에 맞춰 excel.encode() 호출을 유지합니다.
        await File(path).writeAsBytes(excel.encode()!);
        messenger.showSnackBar(const SnackBar(
            content: Text('✅ 데이터 내보내기 성공', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
            elevation: 0
        ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ 내보내기 실패: $e')));
    }
  }
}

/// ---------------------------------------------------------------------------
/// 🔥 태그 일괄 발행 통합 다이얼로그 (Bulk Tag Issue)
/// ---------------------------------------------------------------------------
class _BulkTagIssueDialog extends StatefulWidget {
  final List<ProductModel> selectedProducts;
  final ProductProvider provider;
  final DeviceProvider deviceProvider;
  final ThemeData theme;
  final Function(String)? onWriteComplete;

  /// 발급에 성공한 자산의 ID를 메인 화면으로 전달하여 자동 선택 해제 처리용 콜백
  final Function(String)? onSuccessItem;

  const _BulkTagIssueDialog({
    required this.selectedProducts,
    required this.provider,
    required this.deviceProvider,
    required this.theme,
    this.onWriteComplete,
    this.onSuccessItem,
  });

  @override
  State<_BulkTagIssueDialog> createState() => _BulkTagIssueDialogState();
}

class _BulkTagIssueDialogState extends State<_BulkTagIssueDialog> {
  String? _selectedDeviceId;
  bool _isLoadingReaders = true;
  bool _isHexMode = false;

  int _issueCount = 1;
  bool _isProcessing = false;
  bool _isCompleted = false;
  double _progressValue = 0.0;
  String _progressText = "";

  @override
  void initState() {
    super.initState();
    if (widget.selectedProducts.isEmpty) {
      _progressText = '대상을 알 수 없는 신규 단일 건입니다.\n데이터를 자동으로 생성하여 기록합니다.';
    } else {
      _progressText = '선택된 총 ${widget.selectedProducts.length}건에 대한 정보를 발급합니다.\n리더기와 발급 횟수를 설정하고 [발행 시작]을 눌러주세요.';
    }
    _fetchRegisteredReaders();
  }

  Future<void> _fetchRegisteredReaders() async {
    try {
      if (widget.deviceProvider.list.isEmpty) {
        await widget.deviceProvider.fetchData();
      } else {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (mounted) {
        setState(() {
          _isLoadingReaders = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingReaders = false;
        });
      }
    }
  }

  String _formatDataToTargetSize(String inputData, int targetByteSize, bool isHex) {
    String hexString = "";

    if (isHex) {
      hexString = inputData.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    } else {
      List<int> utf8Bytes = utf8.encode(inputData);
      StringBuffer hexBuffer = StringBuffer();
      for (int i = 0; i < utf8Bytes.length; i++) {
        hexBuffer.write(utf8Bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
      }
      hexString = hexBuffer.toString();
    }

    int targetHexLength = targetByteSize * 2;

    if (hexString.length < targetHexLength) {
      return hexString.padRight(targetHexLength, '0');
    } else if (hexString.length > targetHexLength) {
      return hexString.substring(0, targetHexLength);
    } else {
      return hexString;
    }
  }

  Future<void> _startBulkIssue() async {
    DeviceModel? targetDevice;
    try {
      targetDevice = widget.deviceProvider.list.firstWhere((d) => d.id == _selectedDeviceId);
    } catch (e) {
      targetDevice = null;
    }

    if (targetDevice == null) {
      setState(() {
        _progressText = '❌ 리더기를 선택해주세요.';
      });
      return;
    }

    final DeviceModel device = targetDevice;

    if (device.status.toLowerCase() != 'online') {
      setState(() {
        _progressText = '❌ 선택한 리더기(${device.name})가 미연결 상태입니다. 장치관리에서 먼저 연결해주세요.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _progressValue = 0.0;
    });

    try {
      if (widget.selectedProducts.isEmpty) {
        String randomTag = _isHexMode
            ? "EEEE${DateTime.now().millisecondsSinceEpoch % 100000000}"
            : "NEW_TAG_${DateTime.now().millisecondsSinceEpoch % 100000}";

        int memorySize = 12;

        for (int j = 0; j < _issueCount; j++) {
          if (!mounted || !_isProcessing) throw Exception("사용자에 의해 발급이 중단되었습니다.");

          String hexData = _formatDataToTargetSize(randomTag, memorySize, _isHexMode);
          bool isSuccess = false;

          setState(() {
            _progressValue = j / _issueCount;
            _progressText = "⏳ 신규 자동 태그 대기 중 (${j + 1}/$_issueCount)...\n리더기 안테나 위에 발급할 태그를 올려주세요.";
          });

          // 하드웨어 통신 대기
          try {
            isSuccess = await widget.deviceProvider.writeTagData(device.id, hexData, isHexMode: true);
          } catch(e) {
            isSuccess = false;
          }

          if (!isSuccess || !_isProcessing) {
            throw Exception("사용자에 의해 중단되었거나 장치 통신 오류가 발생했습니다.");
          }

          // 🔥 신규 태그 연속 발급 시 대기 시간 부여
          // 마지막 발급이 아닌 경우에만 3초 대기합니다.
          bool isLastOperation = (j == _issueCount - 1);

          if (!isLastOperation) {
            setState(() {
              _progressValue = (j + 1) / _issueCount;
              _progressText = "✅ 신규 자동 태그(${j + 1}) 발급 성공!\n👉 다음 태그를 안테나에 올려주세요. (3초 대기 중...)";
            });
            // 작업자가 다음 태그를 준비할 수 있도록 3초 대기합니다.
            await Future.delayed(const Duration(seconds: 3));
          } else {
            setState(() {
              _progressValue = (j + 1) / _issueCount;
              _progressText = "✅ 신규 자동 태그(${j + 1}) 발급 성공!";
            });
            await Future.delayed(const Duration(milliseconds: 500));
          }

          if (widget.onWriteComplete != null && j == _issueCount - 1) {
            widget.onWriteComplete!(randomTag);
          }
        }
      } else {
        int totalProducts = widget.selectedProducts.length;
        int currentOperationCount = 0;
        int totalOperations = totalProducts * _issueCount;
        int memorySize = 12;

        for (int i = 0; i < totalProducts; i++) {
          ProductModel product = widget.selectedProducts[i];

          // 원본 문자열인 tagId 필드를 최우선으로 사용하여 문제를 차단합니다.
          String tagData = product.tagId.isNotEmpty ? product.tagId : (product.serialNumber ?? "");
          if (tagData.isEmpty) {
            tagData = product.name;
          }

          for (int j = 0; j < _issueCount; j++) {
            if (!mounted || !_isProcessing) throw Exception("사용자에 의해 발급이 중단되었습니다.");

            currentOperationCount++;
            String hexData = _formatDataToTargetSize(tagData, memorySize, _isHexMode);
            bool isSuccess = false;

            setState(() {
              _progressValue = (currentOperationCount - 1) / totalOperations;
              _progressText = "⏳ [${product.name}] 태그 대기 중 (${j + 1}/$_issueCount)...\n리더기 안테나 위에 발급할 태그를 올려주세요.";
            });

            // 하드웨어 통신 대기
            try {
              isSuccess = await widget.deviceProvider.writeTagData(device.id, hexData, isHexMode: true);
            } catch (e) {
              isSuccess = false;
            }

            if (!isSuccess || !_isProcessing) {
              throw Exception("사용자에 의해 중단되었거나 장치 통신 오류가 발생했습니다.");
            }

            // 모든 자산과 모든 반복 횟수의 제일 마지막인지 판단합니다.
            bool isLastOperationOverall = (i == totalProducts - 1) && (j == _issueCount - 1);

            // 🔥 여러 건을 발급할 때 물리적인 교체 시간을 확보해 줍니다.
            if (!isLastOperationOverall) {
              setState(() {
                _progressValue = currentOperationCount / totalOperations;
                _progressText = "✅ [${product.name}] 발급 성공!\n👉 다음 태그를 안테나에 올려주세요. (3초 대기 중...)";
              });
              // 작업자가 기존 태그를 내리고 새 태그를 올려놓을 수 있게 3초 대기합니다.
              await Future.delayed(const Duration(seconds: 3));
            } else {
              setState(() {
                _progressValue = currentOperationCount / totalOperations;
                _progressText = "✅ [${product.name}] 발급 성공!";
              });
              await Future.delayed(const Duration(milliseconds: 500));
            }

            // 모든 횟수 발급이 끝난 마지막 바퀴에만 DB 저장 및 콜백 발생
            if (j == _issueCount - 1) {
              await widget.provider.handleSave(product: product, data: {
                'tag_id': product.tagId.isNotEmpty ? product.tagId : tagData,  // Hex로 덮어쓰기 금지 (원본 문자열 보존)
                'tag_epc': hexData  // 실제 리더기에 기록된 Hex 데이터
              });

              if (widget.onSuccessItem != null) {
                widget.onSuccessItem!(product.id);
              }

              if (widget.onWriteComplete != null && totalProducts == 1) {
                widget.onWriteComplete!(tagData); // UI로 돌려보낼 때도 변환된 Hex가 아닌 원본 문자열만 반환
              }
            }
          }
        }
      }

      if (mounted && _isProcessing) {
        setState(() {
          _isCompleted = true;
          _progressValue = 1.0;
          _progressText = '🎉 설정하신 모든 태그의 발행 작업이 완벽하게 완료되었습니다.';
          _isProcessing = false;
        });

        await Future.delayed(const Duration(milliseconds: 2000));
        if (mounted) {
          Navigator.pop(context);
        }
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _progressText = '❌ 취소됨: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: AppTheme.dialogTitle('RFID 태그 일괄 발급', Icons.wifi_tethering, color: Colors.indigo),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('1. 발급 대상 리더기', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.bold, color: widget.theme.colorScheme.onSurface)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(10),
                  color: widget.theme.cardTheme.color,
                ),
                child: ListenableBuilder(
                    listenable: widget.deviceProvider,
                    builder: (context, child) {
                      if (_isLoadingReaders) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.0),
                          child: Center(
                              child: SizedBox(
                                  width: 24, height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.indigo)
                              )
                          ),
                        );
                      }

                      final devices = widget.deviceProvider.list;

                      if (devices.isEmpty) {
                        return DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: null,
                              hint: const Text('등록된 리더기가 없습니다. 장치관리에서 먼저 등록해주세요.', style: TextStyle(color: Colors.redAccent, fontFamily: AppTheme.fontPretendard)),
                              items: const [],
                              onChanged: null,
                            )
                        );
                      }

                      String? displayId = _selectedDeviceId;
                      if (displayId == null || !devices.any((d) => d.id == displayId)) {
                        final onlineDevice = devices.where((d) => d.status.toLowerCase() == 'online').firstOrNull;
                        displayId = onlineDevice?.id ?? devices.first.id;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _selectedDeviceId != displayId) {
                            setState(() { _selectedDeviceId = displayId; });
                          }
                        });
                      }

                      return DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: displayId,
                          icon: const Icon(Icons.arrow_drop_down_circle, color: Colors.indigo),
                          style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w600, color: widget.theme.colorScheme.onSurface),
                          onChanged: _isProcessing ? null : (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedDeviceId = newValue;
                              });
                            }
                          },
                          items: devices.map<DropdownMenuItem<String>>((DeviceModel d) {
                            bool isOnline = d.status.toLowerCase() == 'online';
                            return DropdownMenuItem<String>(
                              value: d.id,
                              child: Row(
                                children: [
                                  Icon(Icons.router, size: 20, color: isOnline ? Colors.indigo : Colors.grey),
                                  const SizedBox(width: 12),
                                  Text(
                                      '${d.name} (${isOnline ? '연결됨' : '미연결'})',
                                      style: TextStyle(
                                          color: isOnline ? widget.theme.colorScheme.onSurface : Colors.grey,
                                          fontFamily: AppTheme.fontPretendard
                                      )
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }
                ),
              ),
              const SizedBox(height: 24),

              Text('2. 데이터 기록 모드 (변환 방식)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.bold, color: widget.theme.colorScheme.onSurface)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(10),
                  color: widget.theme.cardTheme.color,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                          _isHexMode ? "입력값을 그대로 헥사(Hex)로 기록" : "문자열(ASCII)을 헥사로 자동 변환하여 기록",
                          style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 13)
                      ),
                    ),
                    const SizedBox(width: 8),
                    ToggleButtons(
                      constraints: const BoxConstraints(minHeight: 32, minWidth: 90),
                      borderRadius: BorderRadius.circular(8),
                      isSelected: [!_isHexMode, _isHexMode],
                      onPressed: _isProcessing ? null : (int index) {
                        setState(() {
                          _isHexMode = index == 1;
                        });
                      },
                      children: const [
                        Text("일반(ASCII)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text("헥사값(HEX)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Text('3. 동일 정보 반복 발급 횟수 (1~99)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.bold, color: widget.theme.colorScheme.onSurface)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(10),
                  color: widget.theme.cardTheme.color,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 36, color: Colors.blueGrey),
                      onPressed: _isProcessing ? null : () {
                        if (_issueCount > 1) {
                          setState(() { _issueCount--; });
                        }
                      },
                    ),
                    const SizedBox(width: 20),
                    Container(
                      width: 80,
                      alignment: Alignment.center,
                      child: Text(
                          '$_issueCount',
                          style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 32, fontWeight: FontWeight.w900, color: Colors.indigo)
                      ),
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 36, color: Colors.indigo),
                      onPressed: _isProcessing ? null : () {
                        if (_issueCount < 99) {
                          setState(() { _issueCount++; });
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: _isCompleted ? AppTheme.success.withValues(alpha: 0.1) : widget.theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: _progressText.contains('❌') ? AppTheme.danger : (_isCompleted ? AppTheme.success : Colors.grey.withValues(alpha: 0.3))),
                ),
                child: Column(
                  children: [
                    Text(
                      _progressText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontSize: 15.0,
                        height: 1.5,
                        color: _progressText.contains('❌') ? AppTheme.danger : (_isCompleted ? AppTheme.success : Colors.blueGrey.shade800),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    (_isProcessing || _isCompleted) ? Column(
                        children: [
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: _progressValue,
                              minHeight: 12,
                              backgroundColor: Colors.grey.withValues(alpha: 0.2),
                              color: _progressText.contains('❌') ? AppTheme.danger : (_isCompleted ? AppTheme.success : Colors.indigo),
                            ),
                          ),
                        ]
                    ) : const SizedBox.shrink()
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppTheme.actionButton(
            label: _isProcessing && !_isCompleted ? "발행 중단" : "돌아가기 (취소)",
            color: Colors.transparent,
            textColor: _isProcessing && !_isCompleted ? AppTheme.danger : widget.theme.colorScheme.onSurface.withValues(alpha: 0.5),
            onPressed: () {
              if (_isProcessing && !_isCompleted) {
                setState(() {
                  _isProcessing = false;
                  _progressText = '❌ 사용자에 의해 발행이 중단되었습니다. (무한 대기망 강제 해제 중...)';
                });
                if (_selectedDeviceId != null) {
                  widget.deviceProvider.disconnectDevice(_selectedDeviceId!);
                }
              } else {
                Navigator.pop(context);
              }
            }
        ),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: (_isProcessing || _isCompleted || _isLoadingReaders || _selectedDeviceId == null) ? null : _startBulkIssue,
            icon: const Icon(Icons.play_circle_fill, size: 20),
            label: const Text('발행 시작', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
            ),
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// [수동 입출고 다이얼로그]
/// ---------------------------------------------------------------------------
class _ManualInoutDialog extends StatefulWidget {
  final String type;
  final ProductModel product;
  final Map<String, IconData> statusIcons;
  final List<UserModel> userList;

  const _ManualInoutDialog({
    required this.type,
    required this.product,
    required this.statusIcons,
    required this.userList,
  });

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
    final List<String> workerList = widget.userList.map((UserModel p) => "${p.name} (${p.code})").toList();

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
                InputDecorator(
                  decoration: AppTheme.inputDecoration(label: "작업 상세 선택", context: context),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                        value: _selS,
                        isDense: true,
                        items: (isIn ? ['보유중', '수동입고', '회수/반납', '생산입고', '구매입고'] : ['수동출고', '판매/배송출고', '대여출고', '수리출고', '폐기', '분실']).map((String v) {
                          return DropdownMenuItem<String>(
                              value: v,
                              child: Row(
                                children: [
                                  Icon(widget.statusIcons[v] ?? Icons.help_outline, size: 18, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
                                  const SizedBox(width: 8),
                                  Text(v, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                                ],
                              )
                          );
                        }).toList(),
                        onChanged: (String? v) {
                          if (v != null) {
                            setState(() {
                              _selS = v;
                            });
                          }
                        }
                    ),
                  ),
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
                          decoration: AppTheme.inputDecoration(label: "담당 작업자 (자동완성)", context: context, hasFocus: fN.hasFocus)
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