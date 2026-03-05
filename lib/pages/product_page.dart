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

/// RFID 물품 및 자산 관리를 담당하는 메인 페이지 클래스입니다.
/// 생산, 물류, 창고, 의료 등 다양한 공정 현장에서 자산의 위치와 상태를 실시간으로 추적하고 관리합니다.
class ProductPage extends StatefulWidget {
  final String searchQuery; // 상위 페이지(MainPage 등)에서 전달받는 초기 검색어
  final bool isMobile;      // 화면 레이아웃을 모바일/PC용으로 분기하기 위한 플래그
  final String baseUrl;     // 이미지 처리 및 API 통신에 사용되는 백엔드 서버 주소

  const ProductPage({
    super.key,
    required this.searchQuery,
    required this.isMobile,
    required this.baseUrl,
  });

  @override
  State<ProductPage> createState() => _ProductPageState();
}

/// ProductPage의 상태 관리 및 실질적인 비즈니스 로직을 처리하는 State 클래스입니다.
class _ProductPageState extends State<ProductPage> {
  // --- UI 제어용 컨트롤러 및 상태 변수 ---

  /// 검색바의 텍스트 입력을 제어하는 컨트롤러입니다.
  final TextEditingController _searchController = TextEditingController();

  /// 사용자가 입력한 현재 검색어 상태를 보관합니다.
  String _currentQuery = "";

  /// 리스트 좌측(또는 메인)에 표시될 데이터의 그룹화 기준입니다. ('item': 품명별, 'location': 위치별, 'category': 분류별)
  String _groupByMode = 'item';

  /// 현재 사용자가 클릭하여 선택한 그룹의 키(이름)입니다. 이 값을 기준으로 우측에 상세 리스트가 표시됩니다.
  String? _selectedGroupKey;

  /// 상단 대시보드(통계 버튼)에서 선택된 현재 필터링 상태입니다. (예: "전체", "금일 입고" 등)
  String _activeMetricFilter = "전체";

  /// 데이터 정렬 기준입니다. 현재는 품명(name)을 기준으로 가나다순 정렬하도록 고정되어 있습니다.
  final String _sortCriteria = 'name';

  // --- 성능 최적화 및 캐싱 변수 ---

  /// 검색어 연속 입력 시마다 필터링이 도는 것을 막아주는(디바운스) 타이머입니다.
  Timer? _debounceTimer;

  /// 원본 데이터를 필터링한 결과물을 임시 보관하는 캐시 리스트입니다.
  List<ProductModel> _filteredCache = [];

  /// Provider에서 받아온 원본 데이터의 개수입니다. 데이터 추가/삭제 시 리빌드를 판단하는 기준이 됩니다.
  int _lastRawItemCount = -1;

  /// 이전 통계 필터 상태입니다. 필터 변경 시 리빌드를 판단하는 기준이 됩니다.
  String _lastActiveFilter = "";

  // --- UI 규격 상수 ---

  /// 리스트 내 썸네일 이미지의 가로/세로 기본 크기입니다.
  static const double _colImgSize = 70.0;

  /// 상세 리스트 우측의 액션 버튼(이력, 입고, 출고, 삭제)들이 차지할 총 가로 너비입니다.
  static const double _colActionWidth = 240.0;

  // --- FA/RFID 공정 단계별 상태 분류 세트 ---
  // 아래 세트들은 자산의 현재 상태가 시스템 흐름상 어느 단계에 속하는지 판별하는 핵심 비즈니스 룰입니다.

  /// 1. 입고 및 자산 확보 단계에 해당하는 상태값들입니다.
  static const Set<String> _inboundStatuses = {
    '보유중', '수동입고', '자동입고', '생산입고', '구매입고', '적치완료', '회수/반납'
  };

  /// 2. 공정 진행 및 작업 중 단계에 해당하는 상태값들입니다.
  static const Set<String> _processStatuses = {
    '정보등록', '공정투입', '생산중', '생산완료', '이송중', '피킹중', '패킹완료', '출하대기'
  };

  /// 3. 출고 및 외부 반출 완료 단계에 해당하는 상태값들입니다.
  static const Set<String> _outboundStatuses = {
    '수동출고', '자동출고', '판매/배송출고', '대여출고', '수리출고', '현장투입'
  };

  /// 4. 일반적인 관리 프로세스에서 제외되는 예외 상태값들입니다.
  static const Set<String> _exceptionStatuses = {'폐기', '분실'};

  /// 자산의 상태 텍스트에 맞춰 UI(팝업 등)에 표시할 직관적인 아이콘들을 매핑해둔 데이터입니다.
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

  /// 시스템 내부적으로만 사용하고, 사용자가 보는 상세 항목(표시 컬럼, 폼)에서는 가려야 할 메타데이터 키 목록입니다.
  static const Set<String> _excludedSystemKeys = {
    'id', 'collectionId', 'collectionName', 'created', 'updated',
    'excel_row', 'import_date', 'import_data', 'is_auto_tag', 'is_auto_atg',
    'origin_key_map', 'history', 'last_location_info', 'is_approved',
    'last_handler', 'last_manual_reason', 'last_processed_at', 'last_approval_status'
  };

  @override
  void initState() {
    super.initState();
    // 위젯이 생성될 때 전달받은 초기 검색어를 변수와 컨트롤러에 세팅합니다.
    _currentQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
  }

  @override
  void dispose() {
    // 위젯이 화면에서 사라질 때 실행 중인 타이머와 컨트롤러를 메모리에서 해제합니다.
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // --- 실시간 검색 및 필터링 엔진 로직 ---

  /// 검색바에 텍스트가 입력될 때마다 호출됩니다.
  /// 매번 즉시 처리하지 않고 300ms를 대기하여(Debounce), 입력이 끝났을 때만 필터링을 수행해 부하를 줄입니다.
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

  /// 원본 데이터(rawItems)를 받아 검색어와 대시보드 통계 필터 조건에 맞춰 데이터를 걸러내는 핵심 엔진입니다.
  void _syncFiltering(List<ProductModel> rawItems) {
    final String q = _currentQuery.trim().toLowerCase();
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now()); // 금일 입출고 판별용 오늘 날짜

    // 조건에 맞는 데이터만 필터링하여 result 리스트에 담습니다.
    List<ProductModel> result = rawItems.where((p) {
      bool isMatch = true;

      // 1. 검색어가 있는 경우 텍스트 매칭 확인
      if (q.isNotEmpty) {
        // 품명, 태그ID, 위치, 분류, 시리얼 번호 중 하나라도 검색어를 포함하면 통과
        isMatch = p.name.toLowerCase().contains(q) ||
            p.tagId.toLowerCase().contains(q) ||
            (p.location?.toLowerCase().contains(q) ?? false) ||
            (p.category?.toLowerCase().contains(q) ?? false) ||
            (p.serialNumber?.toLowerCase().contains(q) ?? false);

        // 위 기본 속성에서 못 찾았을 경우, 동적 확장 속성(metadata) 내부도 모두 뒤져서 검색합니다.
        if (!isMatch) {
          for (var value in p.metadata.values) {
            if (value != null && value.toString().toLowerCase().contains(q)) {
              isMatch = true;
              break;
            }
          }
        }
      }
      // 검색어와 일치하지 않으면 이 항목은 버립니다.
      if (!isMatch) {
        return false;
      }

      // 2. 상단 대시보드 필터 버튼에 따른 조건 확인
      if (_activeMetricFilter == "전체") {
        return true; // 필터가 '전체'면 무조건 통과
      }

      // 최근 업데이트 일자 및 출고/예외 상태 여부 판별
      final String lastDate = p.updated ?? p.created ?? "";
      final bool isOut = _outboundStatuses.contains(p.status) || _exceptionStatuses.contains(p.status);

      if (_activeMetricFilter == "금일 입고") {
        // 최근 날짜가 오늘이고, 상태가 입고 계열일 때만 통과
        return lastDate.startsWith(todayStr) && _inboundStatuses.contains(p.status);
      }
      if (_activeMetricFilter == "금일 출고") {
        // 최근 날짜가 오늘이고, 상태가 출고 계열일 때만 통과
        return lastDate.startsWith(todayStr) && isOut;
      }
      if (_activeMetricFilter == "현재 실재고") {
        // 출고/예외 상태가 아닌 모든 자산은 실재고로 간주하여 통과
        return !isOut;
      }
      return true;
    }).toList();

    // 3. 필터링된 결과를 정렬 기준에 따라 정렬합니다. (현재는 이름순 고정)
    if (_sortCriteria == 'name') {
      result.sort((a, b) => a.name.compareTo(b.name));
    }

    // 캐시 변수를 갱신하여 UI가 새로고침 될 때 이 데이터를 사용하도록 합니다.
    _filteredCache = result;
    _lastRawItemCount = rawItems.length;
    _lastActiveFilter = _activeMetricFilter;
  }

  @override
  Widget build(BuildContext context) {
    // 실시간 자산 데이터를 제공하는 Provider 구독
    final provider = context.watch<ProductProvider>();
    final theme = Theme.of(context);

    // 데이터가 추가/삭제되었거나 사용자가 필터를 바꾼 경우에만 필터링 엔진을 다시 가동합니다.
    if (_lastRawItemCount != provider.items.length || _lastActiveFilter != _activeMetricFilter) {
      _syncFiltering(provider.items);
    }

    // 화면 상단에 보여줄 통계 수치와 리스트에 표시할 그룹화 맵을 계산합니다.
    final Map<String, dynamic> metrics = _calculateMetrics(provider.items);
    final Map<String, List<ProductModel>> groupedMap = _getGroupedData(_filteredCache);
    final List<String> groupKeys = groupedMap.keys.toList()..sort();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor, // 테마의 배경색 적용
      body: Stack(
        children: [
          Column(
            children: [
              // 1. 대시보드 현황판 위젯 배치
              _buildDashboard(metrics, provider.items.length, theme),
              Divider(height: 1, color: theme.dividerTheme.color),
              // 2. 메인 화면 레이아웃 결정 부분
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    // 화면 가로 너비가 950px을 넘고 모바일 모드가 아닐 경우 PC용 2분할 뷰 제공
                    if (constraints.maxWidth > 950 && !widget.isMobile) {
                      return _buildSplitLayout(provider, groupedMap, groupKeys, theme);
                    }
                    // 그 외의 경우 모바일용 단일 리스트 뷰 제공
                    return _buildMobileLayout(provider, groupedMap, groupKeys, theme);
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
          // 엑셀 파싱이나 서버 저장 등 대규모 비동기 작업 중일 때 표시되는 로딩 화면 오버레이
          if (provider.isParsing || provider.isSaving)
            _buildGlobalLoadingOverlay(provider, theme),
        ],
      ),
    );
  }

  // --- 데이터 속성 매핑 로직 ---

  /// 자산 객체(ProductModel)에서 사용자가 보고자 하는 특정 항목(라벨)의 값을 추출합니다.
  /// 기본 필드(품명, 태그ID 등) 외의 값은 동적 메타데이터 맵에서 찾아 반환합니다.
  String _getAttributeValue(String label, ProductModel p) {
    switch (label) {
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
        return p.metadata[label]?.toString() ?? "-";
    }
  }

  // --- 화면 구성 위젯 빌더 ---

  /// PC 2분할 뷰의 우측, 또는 모바일에서 상세 보기 진입 시 노출되는 '개별 자산 상세 목록' 위젯입니다.
  Widget _buildDetailView(ProductProvider provider, String groupName, List<ProductModel> items, ThemeData theme) {
    return Column(
      children: [
        // 상단: 현재 선택된 그룹의 타이틀 및 총 항목 수 표시
        Container(
          padding: const EdgeInsets.all(20),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Container(width: 4, height: 20, color: AppTheme.primary), // 파란색 세로 장식선
              const SizedBox(width: 12),
              Text(
                groupName,
                style: TextStyle(
                  fontFamily: AppTheme.fontPretendard,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: AppTheme.dataColor(theme.brightness == Brightness.dark),
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              Text('총 ${items.length}개 항목', style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13)),
            ],
          ),
        ),
        // 하단: 해당 그룹에 속한 개별 자산들의 리스트뷰
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (ctx, idx) => const SizedBox(height: 12),
            itemBuilder: (ctx, idx) {
              final p = items[idx];
              final statusColor = _getStatusColor(p.status); // 현재 상태에 따른 색상 추출

              return InkWell(
                onTap: () => _showForm(provider, p, theme), // 카드 탭 시 정보 수정 팝업 호출
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  // 외곽선 색상을 상태색상으로 지정하여 식별성을 높임
                  decoration: AppTheme.listItemDecoration(context, isSelected: false, statusColor: statusColor),
                  child: Row(
                    children: [
                      // 좌측: 자산 썸네일 이미지
                      _buildThumbnail(p, theme, size: _colImgSize),
                      const SizedBox(width: 20),
                      // 중앙: 자산 상세 텍스트 정보
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 품명 및 상태 배지 렌더링
                            Row(
                              children: [
                                Text(p.name, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 19)),
                                const SizedBox(width: 12),
                                _buildStatusBadge(p.status),
                                // 관리자 승인이 안 된(보류된) 자산일 경우 경고 아이콘 표시
                                if (!p.isApproved)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: const Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // 사용자가 '표시 설정'에서 노출하기로 선택한 동적 컬럼들을 렌더링
                            Wrap(
                              spacing: 20,
                              runSpacing: 10,
                              children: provider.selectedColumns.map((colName) {
                                // 품명은 타이틀에 이미 나오므로 제외
                                if (colName == '품명') {
                                  return const SizedBox.shrink();
                                }
                                return _buildKeyValue(colName, _getAttributeValue(colName, p), context);
                              }).toList(),
                            ),
                            const SizedBox(height: 10),
                            // 메타데이터에 저장된 최근 이동/처리 위치 정보를 하단에 요약 표시
                            Text(
                              p.metadata['last_location_info']?['full_name'] ?? "최근 위치 기록 없음",
                              style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      // 우측: 각종 업무 액션을 위한 빠른 실행 버튼 영역
                      SizedBox(
                        width: _colActionWidth,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _buildCircleAction(Icons.history, Colors.blueGrey, "이력", () => _showHistoryDialog(context, p, theme)),
                            const SizedBox(width: 12),
                            _buildCircleAction(Icons.login, AppTheme.success, "입고", () => _processAssetAccess(provider, p, '수기입고', theme)),
                            const SizedBox(width: 12),
                            _buildCircleAction(Icons.logout, AppTheme.warning, "출고", () => _processAssetAccess(provider, p, '수기출고', theme)),
                            const SizedBox(width: 12),
                            _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () => _confirmIndividualDelete(provider, p, theme)),
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

  // --- 핵심 데이터 입력/수정 팝업 다이얼로그 로직 ---

  /// 단일 자산을 신규 등록하거나 여러 항목을 일괄 생성, 혹은 기존 데이터를 수정하는 만능 팝업 폼입니다.
  void _showForm(ProductProvider provider, ProductModel? p, ThemeData theme) async {
    // 텍스트 필드용 컨트롤러들. 수정(p != null)일 경우 기존 데이터를 세팅합니다.
    final nameC = TextEditingController(text: p?.name ?? "");
    final tagC = TextEditingController(text: p?.tagId ?? "");
    final locC = TextEditingController(text: p?.location ?? "");
    final specC = TextEditingController(text: p?.spec ?? "");
    final catC = TextEditingController(text: p?.category ?? "");
    final snC = TextEditingController(text: p?.serialNumber ?? "");
    final safeC = TextEditingController(text: p?.safetyStock.toString() ?? "5");
    final qtyC = TextEditingController(text: "1"); // 신규 등록 시 여러 개를 동시 생성할 때 사용하는 수량 필드

    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    // 폼 화면 하단에 동적 메타데이터 입력란을 만들어주기 위해 시스템에 존재하는 가용 키들을 추출합니다.
    final Set<String> availableMetaKeys = {};
    for (var item in provider.items.take(100)) {
      for (var key in item.metadata.keys) {
        // 내부 관리용 키들은 사용자가 직접 수정하지 못하게 제외시킴
        if (!_excludedSystemKeys.contains(key) && !key.endsWith('_internal')) {
          availableMetaKeys.add(key);
        }
      }
    }

    // 메타데이터 값 입력을 받을 컨트롤러 맵을 초기화합니다.
    final Map<String, TextEditingController> metaControllers = {};
    if (p != null) {
      // 기존 데이터가 있다면 그 값을 컨트롤러에 세팅
      p.metadata.forEach((k, v) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal') && v is! Map && v is! List) {
          metaControllers[k] = TextEditingController(text: v?.toString() ?? "");
        }
      });
    } else {
      // 신규 등록이라면 키 이름만 라벨로 쓰고 빈 컨트롤러 세팅
      for (var k in availableMetaKeys) {
        metaControllers[k] = TextEditingController(text: "");
      }
    }

    bool isApproved = p?.isApproved ?? true; // 사용 승인 여부 스위치 상태
    XFile? file;                             // 선택된 이미지 파일
    Uint8List? preview;                      // 화면에 보여줄 이미지 바이너리

    // 실제 화면에 다이얼로그 위젯을 띄웁니다.
    showDialog(
      context: context,
      barrierDismissible: false, // 배경 클릭으로 닫히지 않게 함
      builder: (ctx) => StatefulBuilder( // 다이얼로그 내부 상태(이미지 변경 등) 업데이트를 위한 래퍼
        builder: (dialogCtx, setS) => AlertDialog(
          title: AppTheme.dialogTitle(
              p == null ? '자산 마스터 신규 등록' : '정보 수정 및 제원 편집',
              p == null ? Icons.add_box : Icons.edit
          ),
          content: SizedBox(
            width: 1000, // 와이드 팝업
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 좌측: 사진 등록 및 상태 승인 토글 스위치
                      Column(
                        children: [
                          GestureDetector(
                            // 이미지 터치 시 갤러리 호출
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
                                    ? Image.network(
                                    "${p.getImageUrl(widget.baseUrl)}?t=${p.updated}",
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) => const Icon(Icons.broken_image)
                                )
                                    : const Icon(Icons.camera_alt, size: 50, color: Colors.grey)),
                              ),
                            ),
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
                                  onChanged: (v) => setS(() => isApproved = v)
                              )
                            ],
                          )
                        ],
                      ),
                      const SizedBox(width: 40),
                      // 우측: 데이터 기본 필드들
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
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 40),
                  // 제원 및 운영 수치 입력 섹션
                  _buildSectionHeader(Icons.settings_input_component_rounded, "기본 제원 및 운영 정보", Colors.blueAccent),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: [
                      SizedBox(width: 460, child: _buildTextField(snC, "시리얼 번호 (S/N)", theme, context)),
                      SizedBox(width: 460, child: _buildTextField(safeC, "안전 재고 임계치", theme, context)),
                      // 기존 데이터 수정이 아닌 '신규 등록'일 때만 여러 개를 동시에 만들 수 있도록 수량 필드 활성화
                      if (p == null)
                        SizedBox(width: 460, child: _buildTextField(qtyC, "생성 수량 (일괄 생성 개수)", theme, context)),
                    ],
                  ),
                  const SizedBox(height: 40),
                  // 메타데이터 (동적 추가 필드) 입력 섹션
                  _buildSectionHeader(Icons.add_to_photos_rounded, "추가 확장 정보 (Metadata)", Colors.green),
                  const SizedBox(height: 20),
                  if (metaControllers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text("표시할 추가 속성 정보가 없습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey)),
                    ),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: metaControllers.entries.map((e) {
                      return SizedBox(
                          width: 460,
                          child: _buildTextField(e.value, e.key, theme, context)
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
          // 하단 등록/수정/취소 액션 버튼들
          actions: [
            AppTheme.actionButton(
                label: "취소",
                color: Colors.transparent,
                textColor: cancelColor,
                onPressed: () => Navigator.of(dialogCtx).pop()
            ),
            AppTheme.actionButton(
                label: p == null ? "자산 신규 생성" : "변경사항 저장",
                onPressed: () async {
                  // 유효성 검사: 이름은 반드시 입력해야 함
                  if (nameC.text.isEmpty) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(const SnackBar(content: Text("품명은 필수 입력 사항입니다.")));
                    return;
                  }

                  // 동적으로 입력된 메타데이터 값들을 하나의 맵으로 합칩니다.
                  final updatedMeta = Map<String, dynamic>.from(p?.metadata ?? {});
                  metaControllers.forEach((k, v) {
                    updatedMeta[k] = v.text.trim();
                  });

                  // 저장할 최종 데이터 JSON 객체
                  final baseData = {
                    'name': nameC.text.trim(),
                    'tag_id': tagC.text.trim(),
                    'location': locC.text.trim(),
                    'spec': specC.text.trim(),
                    'category': catC.text.trim(),
                    'serial_number': snC.text.trim(),
                    'safety_stock': int.tryParse(safeC.text.trim()) ?? 5,
                    'is_approved': isApproved,
                    'metadata': updatedMeta,
                    'status': p?.status ?? '보유중' // 신규는 무조건 '보유중' 상태로 시작
                  };

                  final navigator = Navigator.of(dialogCtx);
                  final messenger = ScaffoldMessenger.of(context);

                  bool ok = true;

                  if (p == null) {
                    // 신규 생성 프로세스: 사용자가 수량을 입력했으면 그만큼 반복하여 일괄 생성
                    int count = int.tryParse(qtyC.text.trim()) ?? 1;
                    for (int i = 0; i < count; i++) {
                      String finalTag = tagC.text.trim();
                      // 여러 개일 경우 태그ID가 중복되지 않도록 뒤에 번호를 붙임
                      if (count > 1) {
                        finalTag = "${finalTag}_${i + 1}";
                      }
                      // 서버 저장 API 호출
                      if (!await provider.handleSave(p: null, data: {...baseData, 'tag_id': finalTag}, imageXFile: file)) {
                        ok = false;
                      }
                    }
                  } else {
                    // 수정 프로세스: 기존 아이디(p)를 덮어씀
                    ok = await provider.handleSave(p: p, data: baseData, imageXFile: file);
                  }

                  // 저장 완료 후 화면 갱신 및 팝업 닫기
                  if (ok && context.mounted) {
                    _syncFiltering(provider.items);
                    navigator.pop();
                    messenger.showSnackBar(
                        const SnackBar(content: Text("마스터 정보가 성공적으로 반영되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)))
                    );
                  }
                }
            ),
          ],
        ),
      ),
    );
  }

  // --- 분할 레이아웃 및 집계 타일 등 하위 위젯 렌더링 로직 ---

  /// 데이터 속성의 이름과 값을 정해진 테마 스타일로 매칭하여 출력하는 위젯입니다.
  Widget _buildKeyValue(String label, String value, BuildContext ctx) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.itemLabelStyle(ctx)),
          Text(value, style: AppTheme.itemValueStyle(ctx).copyWith(fontSize: 14), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  /// PC용 2단 분할 레이아웃 위젯을 반환합니다.
  Widget _buildSplitLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 좌측 고정 너비 컨테이너 (집계된 그룹 리스트 노출 구역)
        Container(
          width: 420,
          color: theme.scaffoldBackgroundColor,
          child: Column(
            children: [
              _buildHeader(provider, theme),
              _buildFilterBar(theme),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: groupKeys.isEmpty
                      ? _buildEmptyState("검색 결과가 없습니다.")
                      : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: groupKeys.length,
                    separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
                    itemBuilder: (ctx, idx) => _buildGroupTile(provider, groupKeys[idx], groupedMap[groupKeys[idx]]!, _selectedGroupKey == groupKeys[idx], theme),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 중앙 분리선
        VerticalDivider(width: 1, color: theme.dividerTheme.color),
        // 우측 확장 컨테이너 (좌측에서 클릭한 그룹의 상세 항목 렌더링 구역)
        Expanded(
          child: Container(
            color: theme.scaffoldBackgroundColor,
            padding: const EdgeInsets.only(left: 12),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _selectedGroupKey == null
                  ? _buildEmptyState("항목을 선택하여 상세 정보를 확인하세요.")
                  : _buildDetailView(provider, _selectedGroupKey!, groupedMap[_selectedGroupKey] ?? [], theme),
            ),
          ),
        ),
      ],
    );
  }

  /// 리스트 상단에 위치한 액션 버튼들(새로고침, 엑셀 입출력, 설정, 리셋)과 검색바를 감싸는 위젯입니다.
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
                    _buildActionIconButton(Icons.refresh, "새로고침", () => provider.fetchData(), theme),
                    _buildActionIconButton(FontAwesomeIcons.fileArrowUp, "임포트", () async {
                      // 엑셀에서 데이터를 파싱하여 대량 임포트 처리
                      final Map<String, int> res = await provider.batchImportFromExcel();
                      if (mounted && (res['total'] ?? 0) > 0) {
                        _showInfoDialog("임포트 완료", "성공: ${res['success']} / 전체: ${res['total']}", theme);
                      }
                    }, theme, color: Colors.indigo),
                    _buildActionIconButton(FontAwesomeIcons.fileArrowDown, "엑스포트", () => _exportToExcel(context, _filteredCache), theme, color: Colors.green),
                    _buildActionIconButton(Icons.settings_outlined, "표시 설정", () => _showColumnSelectionDialog(provider, theme), theme),
                    _buildActionIconButton(Icons.delete_sweep_outlined, "리셋", () => _showResetDialog(provider, theme), theme, color: AppTheme.danger),
                  ],
                ),
              ),
              _buildActionIconButton(Icons.add_box, "신규 등록", () => _showForm(provider, null, theme), theme, color: AppTheme.primary, isLarge: true),
            ],
          ),
          const SizedBox(height: 16),
          // 검색 입력 필드
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

  /// 어떤 기준으로 자산을 묶어볼지 결정하는 토글형 필터바(스위치) 위젯입니다.
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
          onSelectionChanged: (v) {
            setState(() {
              _groupByMode = v.first;
              _selectedGroupKey = null; // 기준이 바뀌면 우측 상세 패널 비우기
            });
          },
        ),
      ),
    );
  }

  /// 그룹화된 데이터의 묶음 타일 위젯입니다. 재고 건강도(출고 안 된 비율)에 따라 색상을 달리 표시합니다.
  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, ThemeData theme) {
    // 건강도 계산: 해당 그룹 내 아이템 중 상태에 '출고'라는 단어가 없는 정상 재고 비율 산출
    final double healthRatio = items.isEmpty ? 0.0 : items.where((i) => !i.status.contains('출고')).length / items.length;
    // 비율에 따라 초록색(정상), 노란색(주의), 빨간색(부족/위험) 부여
    final Color hCol = healthRatio == 1.0 ? AppTheme.success : (healthRatio > 0.4 ? AppTheme.warning : AppTheme.danger);

    return InkWell(
      onTap: () {
        setState(() {
          _selectedGroupKey = title;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.05) : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppTheme.primary : hCol.withValues(alpha: 0.4), width: isSelected ? 2.5 : 1.8),
        ),
        child: Row(
          children: [
            _buildThumbnail(items.first, theme, size: 52), // 대표 아이템 썸네일 노출
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold, fontSize: 15, color: isSelected ? AppTheme.primary : null))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: hCol.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Text('${items.length}', style: TextStyle(fontFamily: AppTheme.fontPretendard, color: hCol, fontWeight: FontWeight.w900, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            // 그룹 단위 삭제 버튼
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: AppTheme.danger, size: 22),
              onPressed: () => _confirmGroupDelete(context, provider, title, items, theme),
            ),
          ],
        ),
      ),
    );
  }

  /// 모바일 환경을 위해 단일 리스트로 모든 요소를 세로로 쌓아올린 레이아웃입니다.
  Widget _buildMobileLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys, ThemeData theme) {
    return Column(
      children: [
        _buildHeader(provider, theme),
        _buildFilterBar(theme),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: groupKeys.isEmpty
                ? _buildEmptyState("항목이 없습니다.")
                : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: groupKeys.length,
              separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
              itemBuilder: (ctx, idx) => _buildGroupTile(provider, groupKeys[idx], groupedMap[groupKeys[idx]]!, false, theme),
            ),
          ),
        ),
      ],
    );
  }

  /// 자산의 사진 이미지를 가져와 사각형 타일 형태로 화면에 그려주는 위젯입니다.
  Widget _buildThumbnail(ProductModel p, ThemeData theme, {double size = 44}) {
    final String url = p.getImageUrl(widget.baseUrl, thumb: '100x100');
    final Uri? uri = Uri.tryParse(url);
    final isDark = theme.brightness == Brightness.dark;

    // 이미지가 없거나 URL이 유효하지 않으면 빈 박스와 아이콘 출력
    if (url.isEmpty || uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isDark ? theme.dividerTheme.color?.withValues(alpha: 0.1) : const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 1.5),
        ),
        child: const Icon(Icons.inventory_2_outlined, color: Colors.black12, size: 24),
      );
    }

    // 이미지 캐시 갱신을 위해 URL 끝에 타임스탬프를 쿼리스트링으로 붙여줌
    final String connector = url.contains('?') ? '&' : '?';
    final String fullUrl = "$url${connector}t=${p.updated ?? p.created ?? DateTime.now().millisecondsSinceEpoch}";

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? theme.dividerTheme.color?.withValues(alpha: 0.1) : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(fullUrl, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, size: 18, color: Colors.black12)),
    );
  }

  /// 자산의 상태(보유중, 수동출고 등)에 알맞은 라벨 색상을 계산하여 리턴합니다.
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

  /// 자산의 현재 상태를 둥근 뱃지 모양으로 감싸서 보여주는 위젯입니다.
  Widget _buildStatusBadge(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(status, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }

  /// 빠른 액션을 위한 원형(아이콘 전용) 클릭 버튼입니다.
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

  /// 상단 툴바 등에서 사용할 사각형 액션 아이콘 버튼입니다.
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

  /// 폼 입력 화면에서 쓰이는 일관된 스타일의 텍스트 필드 위젯입니다.
  Widget _buildTextField(TextEditingController ctrl, String label, ThemeData theme, BuildContext ctx) {
    return TextField(
        controller: ctrl,
        style: AppTheme.itemValueStyle(ctx).copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        decoration: AppTheme.inputDecoration(label: label, context: ctx)
    );
  }

  /// 팝업 폼 내 구역을 나누는 헤더 컴포넌트입니다.
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

  // --- 시스템 연동 비즈니스 액션 처리 (원본 무결성 보존 구간) ---

  /// 자산을 수동으로 입고 처리하거나 출고 처리하는 전체 과정을 총괄합니다.
  Future<void> _processAssetAccess(ProductProvider provider, ProductModel p, String type, ThemeData theme) async {
    final messenger = ScaffoldMessenger.of(context);

    // 1. 수기 입/출고 다이얼로그 호출 (장소 및 상태 등 정보 취합)
    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _ManualInoutDialog(type: type, product: p, statusIcons: _statusIcons),
    );

    if (result == null || !context.mounted) {
      return; // 사용자가 취소했거나 다이얼로그 중 앱을 이탈한 경우 종료
    }

    final String now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final bool isApproved = result['is_approved'] ?? true;

    // 2. 과거 이력을 불러와 맨 앞에 새로운 이력 객체 끼워넣기 (History 구성)
    List<dynamic> history = p.metadata['history'] is List ? List.from(p.metadata['history']) : [];
    history.insert(0, {
      'time': now,
      'type': result['status'],
      'location': result['location'],
      'handler': result['handler'],
      'reason': result['reason'],
      'is_approved': isApproved
    });

    // 3. 서버 API에 상태 업데이트와 메타데이터(히스토리 포함) 갱신 요청
    final success = await provider.handleSave(p: p, data: {
      'status': result['status'],
      'location': result['location'],
      'is_approved': isApproved,
      'metadata': {
        ...p.metadata,
        'history': history,
        'last_approval_status': isApproved,
        'last_processed_at': now
      }
    });

    // 4. 완료 후 사용자 알림 피드백 및 화면 동기화
    if (success && context.mounted) {
      _syncFiltering(provider.items);
      messenger.showSnackBar(SnackBar(
          content: Text('[${p.name}] 처리 완료', style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
          backgroundColor: isApproved ? AppTheme.success : AppTheme.danger,
          elevation: 0,
          duration: const Duration(seconds: 1)
      ));
    }
  }

  /// 사용자가 조회 중인 현재 목록을 엑셀 파일 형식(.xlsx)으로 사용자 PC에 저장합니다.
  Future<void> _exportToExcel(BuildContext context, List<ProductModel> list) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel_pkg.Excel excel = excel_pkg.Excel.createExcel();
      final excel_pkg.Sheet sheet = excel['Inventory'];

      // 엑셀 1행에 헤더 라벨 기입
      sheet.appendRow([
        excel_pkg.TextCellValue('품명'),
        excel_pkg.TextCellValue('태그ID'),
        excel_pkg.TextCellValue('로케이션'),
        excel_pkg.TextCellValue('상태'),
        excel_pkg.TextCellValue('규격')
      ]);

      // 이후 리스트에 들어있는 각 자산의 정보를 행별로 추가
      for (final ProductModel i in list) {
        sheet.appendRow([
          excel_pkg.TextCellValue(i.name),
          excel_pkg.TextCellValue(i.tagId),
          excel_pkg.TextCellValue(i.location ?? ""),
          excel_pkg.TextCellValue(i.status),
          excel_pkg.TextCellValue(i.spec ?? "")
        ]);
      }

      // 운영체제 네이티브 파일 저장 다이얼로그 호출
      final String? path = await FilePicker.platform.saveFile(
          fileName: 'Inventory_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx']
      );

      if (path != null && context.mounted) {
        await File(path).writeAsBytes(excel.encode()!);
        messenger.showSnackBar(const SnackBar(
            content: Text('✅ 데이터 내보내기 성공', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
            elevation: 0
        ));
      }
    } catch (e) {
      // 엑셀 변환 또는 파일 권한 등에서 오류 발생 시 사용자 알림
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('❌ 내보내기 실패: $e')));
      }
    }
  }

  /// 자산의 누적 이동 및 상태 이력(Log)을 시간 역순으로 보여주는 팝업입니다.
  void _showHistoryDialog(BuildContext context, ProductModel p, ThemeData theme) {
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: AppTheme.dialogTitle("자산 상세 이력 추적", Icons.history),
            content: SizedBox(
              width: 550,
              height: 600,
              child: p.history.isEmpty
                  ? _buildEmptyState("이력이 없습니다.")
                  : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: p.history.length,
                separatorBuilder: (c, i) => const Divider(height: 24),
                itemBuilder: (ctx, idx) {
                  final log = p.history[idx];
                  final String type = log['type'] ?? "-";
                  final String time = log['time'] ?? "-";
                  final bool approved = log['is_approved'] ?? true;
                  // 정상 승인 이력이면 그 상태에 맞는 색상, 비승인 이력이면 빨간색을 매김
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
                        // 좌측 상태 인디케이터 점
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
                              // 해당 시간에 위치 및 담당자 정보를 리치 텍스트로 구성
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
                  onPressed: () => Navigator.pop(ctx)
              )
            ]
        )
    );
  }

  /// 테이블 리스트(상세 뷰)에 보여줄 동적 속성 항목(컬럼)을 사용자가 설정하게 해주는 다이얼로그입니다.
  void _showColumnSelectionDialog(ProductProvider provider, ThemeData theme) {
    // 1. 시스템이 기본 제공하는 제원 항목 리스트
    final List<String> baseFields = ['품명', '태그ID', '위치', '상태', '규격', '분류', 'S/N'];
    final Set<String> metaKeySet = {};
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    // 2. 현재 등록된 자산들의 메타데이터를 파싱하여 추가 확장 정보 리스트를 동적으로 만듦
    for (var item in provider.items.take(100)) {
      for (var entry in item.metadata.entries) {
        final k = entry.key;
        final v = entry.value;
        // 제외 키 및 복합 자료형은 설정 화면 노출에서 배제
        if (!_excludedSystemKeys.contains(k) &&
            !k.endsWith('_internal') &&
            v is! Map &&
            v is! List) {
          metaKeySet.add(k);
        }
      }
    }

    final List<String> metaFields = metaKeySet.toList()..sort();
    // 현재 유저 환경설정에 저장된 체크 항목을 팝업 오픈 시 불러옴
    final List<String> temp = List.from(provider.selectedColumns);

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder( // 모달 안의 체크박스 상태 변경을 위해 사용
            builder: (context, setS) => AlertDialog(
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
                            ...baseFields.map((k) => _buildSelectionListItem(k, temp, (v) {
                              setS(() {}); // 체크박스 상태 업데이트
                            }, theme)),
                            const SizedBox(height: 32),
                            _buildColumnGroupHeader("추가 확장 정보"),
                            const SizedBox(height: 12),
                            if (metaFields.isEmpty)
                              const Text("추가된 메타데이터가 없습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard))
                            else
                              ...metaFields.map((k) => _buildSelectionListItem(k, temp, (v) {
                                setS(() {});
                              }, theme))
                          ]
                      )
                  )
              ),
              actions: [
                AppTheme.actionButton(
                    label: "취소",
                    color: Colors.transparent,
                    textColor: cancelColor,
                    onPressed: () => Navigator.pop(ctx)
                ),
                AppTheme.actionButton(
                    label: "설정 적용",
                    onPressed: () async {
                      final navigator = Navigator.of(ctx);
                      // 프로바이더를 통해 사용자가 선택한 컬럼 정보를 내부 저장소에 기록
                      await provider.saveRemoteSettings(temp);
                      if (context.mounted) {
                        navigator.pop();
                      }
                    }
                )
              ],
            )
        )
    );
  }

  /// 표시 항목 설정 팝업 내에서 '기본 제원', '확장 정보' 같은 타이틀을 그리는 위젯
  Widget _buildColumnGroupHeader(String title) {
    return Row(
        children: [
          Container(width: 4, height: 16, decoration: BoxDecoration(color: Colors.blueGrey, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, color: Colors.blueGrey, fontSize: 14, letterSpacing: -0.5))
        ]
    );
  }

  /// 컬럼 설정 리스트 내부의 개별 체크박스 아이템 위젯
  Widget _buildSelectionListItem(String label, List<String> currentList, Function(void) onChanged, ThemeData theme) {
    final bool isSelected = currentList.contains(label);
    final bool isDark = theme.brightness == Brightness.dark;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InkWell(
            onTap: () {
              if (isSelected) {
                // 노출 항목이 모두 삭제되는 것을 막기 위해 최소 1개 이상일 때만 삭제 허용
                if (currentList.length > 1) {
                  currentList.remove(label);
                }
              } else {
                // UI가 너무 번잡해지는 걸 막기 위해 최대 5개까지만 노출 허용
                if (currentList.length < 5) {
                  currentList.add(label);
                }
              }
              onChanged(null); // StatefulBuilder 콜백 실행
            },
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primary.withValues(alpha: 0.05) : theme.cardTheme.color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSelected ? AppTheme.primary : (isDark ? Colors.white12 : Colors.black12), width: 2.5)
                ),
                child: Row(
                    children: [
                      Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 20, color: isSelected ? AppTheme.primary : Colors.black26),
                      const SizedBox(width: 16),
                      Expanded(child: Text(label, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 15, fontWeight: FontWeight.bold, color: isSelected ? AppTheme.primary : (isDark ? Colors.white38 : Colors.black45))))
                    ]
                )
            )
        )
    );
  }

  /// 전체 데이터 초기화 등 위험한 동작에 사용하는 다이얼로그 호출 로직
  void _showResetDialog(ProductProvider provider, ThemeData theme) {
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: AppTheme.dialogTitle("전체 초기화", Icons.delete_forever, color: AppTheme.danger),
            content: const Text("모든 정보를 삭제하시겠습니까?", style: TextStyle(fontFamily: AppTheme.fontPretendard)),
            actions: [
              AppTheme.actionButton(
                  label: "취소",
                  color: Colors.transparent,
                  textColor: cancelColor,
                  onPressed: () => Navigator.pop(ctx)
              ),
              AppTheme.actionButton(
                  label: "삭제",
                  color: AppTheme.danger,
                  onPressed: () async {
                    final navigator = Navigator.of(ctx);
                    final messenger = ScaffoldMessenger.of(context);
                    await provider.resetAllProducts(); // 백엔드 전체 삭제 요청
                    if (context.mounted) {
                      _syncFiltering(provider.items);
                      navigator.pop();
                      messenger.showSnackBar(const SnackBar(content: Text('초기화 완료', style: TextStyle(fontFamily: AppTheme.fontPretendard))));
                    }
                  }
              )
            ]
        )
    );
  }

  /// 단순 정보성 시스템 알림을 표시하는 공통 위젯입니다.
  void _showInfoDialog(String title, String msg, ThemeData theme) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: AppTheme.dialogTitle(title, Icons.info_outline),
            content: Text(msg, style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
            actions: [
              AppTheme.actionButton(label: "확인", onPressed: () => Navigator.pop(ctx))
            ]
        )
    );
  }

  /// 리스트 상에서 특정 단일 자산 항목을 삭제 요청하기 전 확인하는 팝업입니다.
  void _confirmIndividualDelete(ProductProvider provider, ProductModel p, ThemeData theme) {
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
            title: AppTheme.dialogTitle("삭제 확인", Icons.delete),
            content: Text("[${p.name}] 자산을 삭제하시겠습니까?", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
            actions: [
              AppTheme.actionButton(
                  label: "취소",
                  color: Colors.transparent,
                  textColor: cancelColor,
                  onPressed: () => Navigator.pop(c)
              ),
              const SizedBox(width: 8),
              AppTheme.actionButton(
                  label: "삭제",
                  color: AppTheme.danger,
                  onPressed: () async {
                    final navigator = Navigator.of(c);
                    final messenger = ScaffoldMessenger.of(context);
                    await provider.deleteMultipleProducts([p.id]); // 단건 리스트 형태로 삭제 전송
                    if (context.mounted) {
                      _syncFiltering(provider.items);
                      navigator.pop();
                      messenger.showSnackBar(const SnackBar(content: Text("삭제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
                    }
                  }
              )
            ]
        )
    );
  }

  /// 그룹화된 뷰 좌측에서 그룹 전체의 자산들을 일괄로 삭제할 때 사용하는 다이얼로그입니다.
  void _confirmGroupDelete(BuildContext ctx, ProductProvider provider, String name, List<ProductModel> items, ThemeData theme) {
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: ctx,
        builder: (c) => AlertDialog(
            title: AppTheme.dialogTitle("그룹 일괄 삭제", Icons.warning, color: AppTheme.danger),
            content: Text("[$name] 그룹의 모든 자산(${items.length}개)을 삭제하시겠습니까?", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
            actions: [
              AppTheme.actionButton(
                  label: "취소",
                  color: Colors.transparent,
                  textColor: cancelColor,
                  onPressed: () => Navigator.pop(c)
              ),
              const SizedBox(width: 8),
              AppTheme.actionButton(
                  label: "일괄 삭제",
                  color: AppTheme.danger,
                  onPressed: () async {
                    final navigator = Navigator.of(c);
                    final messenger = ScaffoldMessenger.of(ctx);
                    // 전체 ID 리스트를 Map/List 문법을 사용해 생성 후 서버 전송
                    await provider.deleteMultipleProducts(items.map((e) => e.id).toList());
                    if (context.mounted) {
                      _syncFiltering(provider.items);
                      navigator.pop();
                      messenger.showSnackBar(const SnackBar(content: Text("일괄 삭제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
                    }
                  }
              )
            ]
        )
    );
  }

  // --- 상단 통계 수치 및 대시보드 뷰 구성 ---

  /// 상단 대시보드 영역 레이아웃 (자산 마스터, 금일 입고, 금일 출고, 실재고 영역)
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

  /// 대시보드 내부의 각 개별 카드 타일을 정의합니다. 클릭 시 통계 필터가 적용됩니다.
  Widget _buildStatTile(String label, int val, IconData icon, Color color, ThemeData theme, {required String filterKey}) {
    final bool isSelected = _activeMetricFilter == filterKey;
    final bool isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: () {
        setState(() {
          // 토글형 동작: 선택된 타일을 다시 누르면 필터 해제(전체 조회)
          _activeMetricFilter = _activeMetricFilter == filterKey ? "전체" : filterKey;
          _selectedGroupKey = null; // 필터 변경 시 우측 뷰 리셋
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

  /// 서버와 HTTP 송수신 등 오랜 시간이 소요되는 작업 중에 화면 클릭을 차단하기 위한 로딩 창
  Widget _buildGlobalLoadingOverlay(ProductProvider provider, ThemeData theme) {
    return Container(
      color: Colors.black.withValues(alpha: 0.3),
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
                  provider.isParsing ? "데이터 분석 중..." : "서버 통신 중...",
                  style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 현재 표시할 데이터가 없을 때 노출하는 중앙의 엠프티(Empty) 표시 화면입니다.
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

  /// 목록 계산 위젯: 리스트 전체 데이터 통계 산출을 수행합니다.
  Map<String, dynamic> _calculateMetrics(List<ProductModel> allItems) {
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0;
    int todayOut = 0;
    int currentStock = 0;

    for (final item in allItems) {
      final lastDate = item.updated ?? item.created ?? "";
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

  /// 현재 선택된 _groupByMode(품명, 분류, 위치)에 따라 자산 리스트를 그룹핑하는 해시맵을 생성합니다.
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
}

// ============================================================================
// 수기 입출력 다이얼로그 전용 위젯
// ============================================================================

/// 사용자가 RFID 자동 감지가 아닌 수동 버튼 조작을 통해 아이템의 입/출고 이력을 발생시킬 때 사용합니다.
class _ManualInoutDialog extends StatefulWidget {
  final String type; // '수기입고' 또는 '수기출고' 여부를 텍스트로 전달
  final ProductModel product; // 처리 대상 자산의 모델 정보
  final Map<String, IconData> statusIcons; // 상태별 표시 아이콘 목록 참조

  const _ManualInoutDialog({required this.type, required this.product, required this.statusIcons});

  @override
  State<_ManualInoutDialog> createState() => _ManualInoutDialogState();
}

class _ManualInoutDialogState extends State<_ManualInoutDialog> {
  late TextEditingController _locC; // 처리 위치 입력을 위한 컨트롤러
  late TextEditingController _reasonC; // 입출고 사유 입력을 위한 컨트롤러
  late String _selS; // 선택된 상태값 (보유중, 판매출고 등) 드롭다운 바인딩용
  String _selectedHandler = "관리자"; // 처리를 담당한 담당자 이름 (자동완성)

  @override
  void initState() {
    super.initState();
    // 팝업 열림과 동시에 이전 위치 정보와 디폴트 상태 및 사유를 컨트롤러에 세팅
    _locC = TextEditingController(text: widget.product.location ?? "미지정");
    _reasonC = TextEditingController(text: "현장 수동 처리");
    _selS = widget.type == '수기입고' ? '보유중' : '수동출고';
  }

  @override
  void dispose() {
    // 팝업 종료 시 각 컨트롤러 파괴
    _locC.dispose();
    _reasonC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // PersonProvider를 통해 현재 시스템에 등록된 관리 인원 리스트를 가져와 담당자 자동완성에 활용
    final personProvider = context.watch<PersonProvider>();
    final workerList = personProvider.list.map((p) => "${p.name} (${p.code})").toList();
    final isIn = widget.type == '수기입고';

    // 다크모드 대응 취소 버튼 색상
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return AlertDialog(
      title: AppTheme.dialogTitle('${widget.type} - ${widget.product.name}', isIn ? Icons.login : Icons.logout),
      content: SizedBox(
        width: 450, // 팝업 사이즈 고정
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            // 작업 상태 선택 드롭다운 (입고 타입과 출고 타입에 따라 선택 가능한 목록이 다름)
            DropdownButtonFormField<String>(
              initialValue: _selS,
              decoration: AppTheme.inputDecoration(label: "작업 상세 선택", context: context),
              items: (isIn ? ['보유중', '수동입고', '회수/반납', '생산입고', '구매입고'] : ['수동출고', '판매/배송출고', '대여출고', '수리출고', '폐기', '분실']).map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _selS = v;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            // 변경할 현재 위치 입력 필드
            TextField(controller: _locC, style: AppTheme.itemValueStyle(context), decoration: AppTheme.inputDecoration(label: "처리 위치", context: context)),
            const SizedBox(height: 16),
            // 담당자 입력 시, Person 리스트와 매칭되는 이름을 팝업으로 추천해주는 자동완성 위젯
            Autocomplete<String>(
              optionsBuilder: (val) => workerList.where((o) => o.contains(val.text)),
              onSelected: (s) {
                _selectedHandler = s;
              },
              fieldViewBuilder: (ctx, ctrl, focus, __) => TextField(controller: ctrl, focusNode: focus, style: AppTheme.itemValueStyle(context).copyWith(fontWeight: FontWeight.bold), decoration: AppTheme.inputDecoration(label: "담당 작업자", context: context, hasFocus: focus.hasFocus)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      // 액션 버튼 영역 (취소, 확인)
      actions: [
        AppTheme.actionButton(
            label: "취소",
            color: Colors.transparent,
            textColor: cancelColor,
            onPressed: () => Navigator.pop(context)
        ),
        AppTheme.actionButton(
            label: "처리 확정",
            // 확인 시 맵 데이터로 묶어서 부모(await 된 지점)로 넘겨줌
            onPressed: () => Navigator.pop(context, {
              'status': _selS,
              'location': _locC.text,
              'handler': _selectedHandler,
              'reason': _reasonC.text,
              'is_approved': true
            })
        )
      ],
    );
  }
}