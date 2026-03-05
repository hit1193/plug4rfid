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

/// ---------------------------------------------------------------------------
/// [물품 관리 페이지]
/// 메인 화면(MainPage)의 우측 영역에 표출되는 물품 관리 통합 관제 화면입니다.
/// ProductProvider를 구독하여 데이터를 화면에 렌더링하고,
/// 미니멀리즘 디자인을 기반으로 다양한 필터링 및 엑셀 입출력 기능을 제공합니다.
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
  // UI 상태 관리를 위한 컨트롤러 및 변수들
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

  // 스크린 전체를 덮는 다이얼로그(초기화, 엑셀) 실행 중일 때
  // 기존의 부분 오버레이(Stack)가 중복으로 표출되는 것을 막는 플래그입니다.
  bool _isFullScreenLoading = false;

  // 레이아웃 고정 치수 상수 정의 (미니멀 디자인 규격)
  static const double _colImgSize = 70.0;
  static const double _colActionWidth = 240.0;

  // FA/RFID 공정 단계별 상태 분류 세트 (Enum Set과 유사한 역할)
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

  // 상태별 아이콘 매핑
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

  // 시스템 내부 관리용 키 정의 (사용자 UI 노출 제외 목록)
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

  /// ---------------------------------------------------------------------------
  /// [실시간 검색 및 필터링 엔진]
  /// 사용자의 입력을 감지하여 데이터를 즉시 필터링합니다. (Debounce 적용)
  /// ---------------------------------------------------------------------------
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

      // 상단 대시보드(지표) 필터 검증
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

    // 기본 이름 오름차순 정렬
    if (_sortCriteria == 'name') {
      result.sort((a, b) => a.name.compareTo(b.name));
    }
    _filteredCache = result;
    _lastRawItemCount = rawItems.length;
    _lastActiveFilter = _activeMetricFilter;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();
    final theme = Theme.of(context);

    // 원본 데이터가 변경되었거나 필터가 변경된 경우 캐시 동기화
    if (_lastRawItemCount != provider.items.length || _lastActiveFilter != _activeMetricFilter) {
      _syncFiltering(provider.items);
    }

    // 그룹화 및 지표 계산
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
                  builder: (ctx, constraints) {
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

          // 단일 수정 등 가벼운 작업 시에만 표출되는 우측 영역 한정 오버레이
          // 전체 화면(풀스크린) 다이얼로그가 떠 있을 때는 이중 표출되지 않도록 차단합니다.
          if ((provider.isParsing || provider.isSaving) && !_isFullScreenLoading)
            _buildGlobalLoadingOverlay(provider, theme),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [설정된 컬럼에 따른 데이터 매핑 로직]
  /// ---------------------------------------------------------------------------
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

  /// ---------------------------------------------------------------------------
  /// [상세 리스트 뷰 영역] - (좌측 정렬 완벽 개선 패치 적용)
  /// ---------------------------------------------------------------------------
  Widget _buildDetailView(ProductProvider provider, String groupName, List<ProductModel> items, ThemeData theme) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Container(width: 4, height: 20, color: AppTheme.primary),
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
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (ctx, idx) => const SizedBox(height: 12),
            itemBuilder: (ctx, idx) {
              final p = items[idx];
              final statusColor = _getStatusColor(p.status);

              return InkWell(
                onTap: () => _showForm(provider, p, theme),
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: AppTheme.listItemDecoration(context, isSelected: false, statusColor: statusColor),
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
                                Text(
                                    p.name,
                                    style: AppTheme.itemValueStyle(context).copyWith(
                                        fontSize: 19,
                                        color: p.name == '형식에 맞지 않는 건' ? AppTheme.danger : null
                                    )
                                ),
                                const SizedBox(width: 12),
                                _buildStatusBadge(p.status),
                                if (!p.isApproved)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // [핵심 개선 포인트] Wrap의 자식에서 크기가 0인 항목이 spacing을 먹어버리는 버그 방지
                            Wrap(
                              spacing: 20,
                              runSpacing: 10,
                              alignment: WrapAlignment.start,
                              crossAxisAlignment: WrapCrossAlignment.start,
                              // '품명'은 제외(필터링)한 뒤 화면에 그립니다.
                              children: provider.selectedColumns
                                  .where((colName) => colName != '품명')
                                  .map((colName) => _buildKeyValue(colName, _getAttributeValue(colName, p), context))
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

  /// ---------------------------------------------------------------------------
  /// [통합 등록 및 수정 폼 다이얼로그]
  /// ---------------------------------------------------------------------------
  void _showForm(ProductProvider provider, ProductModel? p, ThemeData theme) async {
    final nameC = TextEditingController(text: p?.name ?? "");
    final tagC = TextEditingController(text: p?.tagId ?? "");
    final locC = TextEditingController(text: p?.location ?? "");
    final specC = TextEditingController(text: p?.spec ?? "");
    final catC = TextEditingController(text: p?.category ?? "");
    final snC = TextEditingController(text: p?.serialNumber ?? "");
    final safeC = TextEditingController(text: p?.safetyStock.toString() ?? "5");
    final qtyC = TextEditingController(text: "1");

    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    final Set<String> availableMetaKeys = {};
    for (var item in provider.items.take(100)) {
      for (var key in item.metadata.keys) {
        if (!_excludedSystemKeys.contains(key) && !key.endsWith('_internal')) {
          availableMetaKeys.add(key);
        }
      }
    }

    final Map<String, TextEditingController> metaControllers = {};
    if (p != null) {
      p.metadata.forEach((k, v) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal') && v is! Map && v is! List) {
          metaControllers[k] = TextEditingController(text: v?.toString() ?? "");
        }
      });
    } else {
      for (var k in availableMetaKeys) {
        metaControllers[k] = TextEditingController(text: "");
      }
    }

    bool isApproved = p?.isApproved ?? true;
    XFile? file;
    Uint8List? preview;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setS) => AlertDialog(
          title: AppTheme.dialogTitle(
              p == null ? '자산 마스터 신규 등록' : '정보 수정 및 제원 편집',
              p == null ? Icons.add_box : Icons.edit
          ),
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
                  _buildSectionHeader(Icons.settings_input_component_rounded, "기본 제원 및 운영 정보", Colors.blueAccent),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: [
                      SizedBox(width: 460, child: _buildTextField(snC, "시리얼 번호 (S/N)", theme, context)),
                      SizedBox(width: 460, child: _buildTextField(safeC, "안전 재고 임계치 (숫자만 입력)", theme, context)),
                      if (p == null)
                        SizedBox(width: 460, child: _buildTextField(qtyC, "생성 수량 (일괄 생성 개수)", theme, context)),
                    ],
                  ),
                  const SizedBox(height: 40),
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
                  if (nameC.text.isEmpty) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(const SnackBar(content: Text("품명은 필수 입력 사항입니다.")));
                    return;
                  }

                  final updatedMeta = Map<String, dynamic>.from(p?.metadata ?? {});
                  metaControllers.forEach((k, v) {
                    updatedMeta[k] = v.text.trim();
                  });

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
                    'status': p?.status ?? '보유중'
                  };

                  final navigator = Navigator.of(dialogCtx);
                  final messenger = ScaffoldMessenger.of(context);

                  bool ok = true;
                  if (p == null) {
                    int count = int.tryParse(qtyC.text.trim()) ?? 1;
                    for (int i = 0; i < count; i++) {
                      String finalTag = tagC.text.trim();
                      if (count > 1) {
                        finalTag = "${finalTag}_${i + 1}";
                      }
                      if (!await provider.handleSave(product: null, data: {...baseData, 'tag_id': finalTag}, imageXFile: file)) {
                        ok = false;
                      }
                    }
                  } else {
                    ok = await provider.handleSave(product: p, data: baseData, imageXFile: file);
                  }

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

  // --- 보조 UI 빌더 메서드 ---

  /// [핵심 개선 2] 텍스트가 어떤 해상도에서도 절대 우측이나 중앙으로 흔들리지 않게 Align으로 강제 고정
  Widget _buildKeyValue(String label, String value, BuildContext ctx) {
    return SizedBox(
      width: 150, // 글자 크기가 커짐에 따라 텍스트가 잘리지 않도록 할당 너비를 살짝 넓혔습니다 (140 -> 150)
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            // 라벨의 폰트 사이즈도 명시적으로 13으로 고정하여 비율을 맞춥니다
            child: Text(label, style: AppTheme.itemLabelStyle(ctx).copyWith(fontSize: 13), textAlign: TextAlign.left),
          ),
          const SizedBox(height: 2), // 라벨과 값 사이의 시각적 여유 공간 추가
          Align(
            alignment: Alignment.centerLeft,
            // 실제 데이터 값의 폰트 사이즈를 기존 14에서 16으로 시원하게 키우고, 굵기도 살짝 보강했습니다
            child: Text(value, style: AppTheme.itemValueStyle(ctx).copyWith(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis, textAlign: TextAlign.left),
          ),
        ],
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
        VerticalDivider(width: 1, color: theme.dividerTheme.color),
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

  /// ---------------------------------------------------------------------------
  /// [상단 헤더 툴바 생성]
  /// ---------------------------------------------------------------------------
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
                    _buildActionIconButton(FontAwesomeIcons.fileArrowUp, "엑셀 일괄 임포트", () => _handleBatchImport(provider, theme), theme, color: Colors.indigo),
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
          onSelectionChanged: (v) {
            setState(() {
              _groupByMode = v.first;
              _selectedGroupKey = null;
            });
          },
        ),
      ),
    );
  }

  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, ThemeData theme) {
    final double healthRatio = items.isEmpty ? 0.0 : items.where((i) => !i.status.contains('출고')).length / items.length;
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
            _buildThumbnail(items.first, theme, size: 52),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold, fontSize: 15, color: isSelected ? AppTheme.primary : null))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: hCol.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Text('${items.length}', style: TextStyle(fontFamily: AppTheme.fontPretendard, color: hCol, fontWeight: FontWeight.w900, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: AppTheme.danger, size: 22),
              onPressed: () => _confirmGroupDelete(context, provider, title, items, theme),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _buildThumbnail(ProductModel p, ThemeData theme, {double size = 44}) {
    final String url = p.getImageUrl(widget.baseUrl, thumb: '100x100');
    final Uri? uri = Uri.tryParse(url);
    final bool isDark = theme.brightness == Brightness.dark;
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

  Widget _buildStatusBadge(String status) {
    final Color color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(status, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: color, fontSize: 11, fontWeight: FontWeight.w900)),
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

  Widget _buildTextField(TextEditingController ctrl, String label, ThemeData theme, BuildContext ctx) {
    return TextField(
        controller: ctrl,
        style: AppTheme.itemValueStyle(ctx).copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        decoration: AppTheme.inputDecoration(label: label, context: ctx)
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

  Future<void> _processAssetAccess(ProductProvider provider, ProductModel p, String type, ThemeData theme) async {
    final messenger = ScaffoldMessenger.of(context);

    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _ManualInoutDialog(type: type, product: p, statusIcons: _statusIcons),
    );

    if (result == null || !context.mounted) {
      return;
    }

    final String now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final bool isApproved = result['is_approved'] ?? true;

    List<dynamic> history = p.metadata['history'] is List ? List.from(p.metadata['history']) : [];
    history.insert(0, {
      'time': now,
      'type': result['status'],
      'location': result['location'],
      'handler': result['handler'],
      'reason': result['reason'],
      'is_approved': isApproved
    });

    final bool success = await provider.handleSave(product: p, data: {
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

  Future<void> _exportToExcel(BuildContext context, List<ProductModel> list) async {
    final messenger = ScaffoldMessenger.of(context);
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

      if (path != null && context.mounted) {
        await File(path).writeAsBytes(excel.encode()!);
        messenger.showSnackBar(const SnackBar(
            content: Text('✅ 데이터 내보내기 성공', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
            elevation: 0
        ));
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('❌ 내보내기 실패: $e')));
      }
    }
  }

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
                  onPressed: () => Navigator.pop(ctx)
              )
            ]
        )
    );
  }

  void _showColumnSelectionDialog(ProductProvider provider, ThemeData theme) {
    final List<String> baseFields = ['품명', '태그ID', '위치', '상태', '규격', '분류', 'S/N'];
    final Set<String> metaKeySet = {};
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    for (var item in provider.items.take(100)) {
      for (var entry in item.metadata.entries) {
        final k = entry.key;
        final v = entry.value;
        if (!_excludedSystemKeys.contains(k) &&
            !k.endsWith('_internal') &&
            v is! Map &&
            v is! List) {
          metaKeySet.add(k);
        }
      }
    }

    final List<String> metaFields = metaKeySet.toList()..sort();
    final List<String> temp = List.from(provider.selectedColumns);

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
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
                              setS(() {});
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

  Widget _buildColumnGroupHeader(String title) {
    return Row(
        children: [
          Container(width: 4, height: 16, decoration: BoxDecoration(color: Colors.blueGrey, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, color: Colors.blueGrey, fontSize: 14, letterSpacing: -0.5))
        ]
    );
  }

  Widget _buildSelectionListItem(String label, List<String> currentList, Function(void) onChanged, ThemeData theme) {
    final bool isSelected = currentList.contains(label);
    final bool isDark = theme.brightness == Brightness.dark;
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
                    Navigator.pop(ctx);
                    final messenger = ScaffoldMessenger.of(context);

                    setState(() { _isFullScreenLoading = true; });
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      barrierColor: Colors.black.withValues(alpha: 0.5),
                      builder: (loadingCtx) => PopScope(
                        canPop: false,
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
                                  const CircularProgressIndicator(color: AppTheme.danger, strokeWidth: 5),
                                  const SizedBox(height: 25),
                                  const Text(
                                    "안전 데이터베이스 초기화 중...\n(창을 닫지 마세요)",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 15),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );

                    try {
                      await provider.resetAllProducts();
                    } finally {
                      if (mounted) {
                        setState(() {
                          _isFullScreenLoading = false;
                          _selectedGroupKey = null;
                          _currentQuery = "";
                        });
                        _searchController.clear();
                        Navigator.of(context).pop();
                      }
                    }

                    if (mounted) {
                      _syncFiltering(provider.items);
                      messenger.showSnackBar(const SnackBar(content: Text('전체 초기화가 완료되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard))));
                    }
                  }
              )
            ]
        )
    );
  }

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
                    await provider.deleteMultipleProducts([p.id]);
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
                    await provider.deleteMultipleProducts(items.map((e) => e.id).toList());
                    if (context.mounted) {
                      setState(() {
                        if (_selectedGroupKey == name) {
                          _selectedGroupKey = null;
                        }
                      });
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

  Map<String, dynamic> _calculateMetrics(List<ProductModel> allItems) {
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0;
    int todayOut = 0;
    int currentStock = 0;

    for (final item in allItems) {
      final String lastDate = item.updated ?? item.created ?? "";
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

  Future<void> _handleBatchImport(ProductProvider provider, ThemeData theme) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || !context.mounted) return;

      Uint8List? bytes = result.files.single.bytes;
      if (bytes == null && result.files.single.path != null) {
        bytes = await File(result.files.single.path!).readAsBytes();
      }

      if (bytes == null) {
        if (context.mounted) _showInfoDialog("오류", "파일을 읽을 수 없습니다.", theme);
        return;
      }

      final excel = excel_pkg.Excel.decodeBytes(bytes);
      String targetSheet = excel.tables.keys.first;

      if (excel.tables.keys.contains('물품리스트')) {
        targetSheet = '물품리스트';
      } else if (excel.tables.keys.contains('Sheet1')) {
        targetSheet = 'Sheet1';
      }

      final sheet = excel.tables[targetSheet];
      if (sheet == null || sheet.maxRows <= 1) {
        if (context.mounted) _showInfoDialog("알림", "데이터가 없거나 헤더만 존재합니다.", theme);
        return;
      }

      List<String> headers = [];
      final headerRow = sheet.row(0);
      for (var cell in headerRow) {
        headers.add(_extractString(cell));
      }

      bool hasNameHeader = false;
      for (String h in headers) {
        String ch = h.replaceAll(RegExp(r'[\s\_\-\(\)]+'), '').toLowerCase();
        if (ch.contains('품명') || ch.contains('제품명') || ch.contains('자산명') ||
            ch.contains('이름') || ch.contains('명칭') || ch.contains('물품명') ||
            ch.contains('품목명') || ch.contains('기기명') || ch.contains('장비명') ||
            ch.contains('관리대상')) {
          hasNameHeader = true;
          break;
        }
      }

      if (!hasNameHeader) {
        if (context.mounted) {
          _showInfoDialog(
              "엑셀 양식 오류 (헤더 누락)",
              "엑셀 파일의 1번째 줄(Row 1)에서 '품명', '제품명', '관리대상' 등의 필수 항목명을 찾을 수 없습니다.\n\n"
                  "💡 [해결 방법]\n"
                  "데이터 영역만 복사하신 경우, 1번째 줄에 항목명(예: 품명, 위치, 규격 등)을 반드시 타이핑해 넣으신 뒤 다시 업로드해 주세요.",
              theme
          );
        }
        return;
      }

      int actualValidRows = 0;
      for (int i = 1; i < sheet.maxRows; i++) {
        bool hasData = false;
        for (var cell in sheet.row(i)) {
          if (_extractString(cell).isNotEmpty) {
            hasData = true;
            break;
          }
        }
        if (hasData) actualValidRows++;
      }

      ValueNotifier<int> currentCountNotifier = ValueNotifier<int>(0);

      setState(() { _isFullScreenLoading = true; });

      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        builder: (ctx) => PopScope(
          canPop: false,
          child: Center(
            child: Card(
              elevation: 10,
              color: theme.cardTheme.color,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 40),
                child: ValueListenableBuilder<int>(
                  valueListenable: currentCountNotifier,
                  builder: (context, currentCount, child) {
                    final double progress = actualValidRows > 0 ? currentCount / actualValidRows : 0.0;
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
                                backgroundColor: theme.dividerTheme.color?.withValues(alpha: 0.3),
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
                          "대량 데이터 전송 중...",
                          style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "총 $actualValidRows건 중 $currentCount건 처리 완료\n(창을 닫거나 새로고침하지 마세요)",
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
      int errorCount = 0;
      int failCount = 0;
      int totalCount = 0;

      bool hasCriticalError = false;
      String criticalErrorMsg = "";

      try {
        for (int i = 1; i < sheet.maxRows; i++) {
          final row = sheet.row(i);
          if (row.isEmpty) continue;

          String name = "";
          String tagId = "";
          String loc = "미지정";
          String spec = "";
          String cat = "";
          String sn = "";
          Map<String, dynamic> metadata = {};

          bool hasData = false;

          for (int colIdx = 0; colIdx < row.length; colIdx++) {
            if (colIdx >= headers.length) break;

            String rawHeader = headers[colIdx];
            String cleanHeader = rawHeader.replaceAll(RegExp(r'[\s\_\-\(\)]+'), '').toLowerCase();

            String val = _extractString(row[colIdx]);
            if (val.isNotEmpty) hasData = true;

            if (cleanHeader.contains('품명') || cleanHeader.contains('제품명') || cleanHeader.contains('자산명') ||
                cleanHeader.contains('이름') || cleanHeader.contains('명칭') || cleanHeader.contains('물품명') ||
                cleanHeader.contains('품목명') || cleanHeader.contains('기기명') || cleanHeader.contains('장비명') ||
                cleanHeader.contains('관리대상')) {
              name = val;
            } else if (cleanHeader.contains('태그') || cleanHeader.contains('rfid') || cleanHeader.contains('epc') || cleanHeader.contains('tag')) {
              tagId = val;
            } else if (cleanHeader.contains('위치') || cleanHeader.contains('로케이션') || cleanHeader.contains('장소') || cleanHeader.contains('보관') || cleanHeader.contains('구역')) {
              loc = val;
            } else if (cleanHeader.contains('규격') || cleanHeader.contains('사양') || cleanHeader.contains('스펙') || cleanHeader.contains('spec') || cleanHeader.contains('모델')) {
              spec = val;
            } else if (cleanHeader.contains('분류') || cleanHeader.contains('카테고리') || cleanHeader.contains('종류') || cleanHeader.contains('그룹') || cleanHeader.contains('유형')) {
              cat = val;
            } else if (cleanHeader.contains('시리얼') || cleanHeader.contains('s/n') || cleanHeader.contains('일련번호') || cleanHeader.contains('serial')) {
              sn = val;
            } else {
              if (rawHeader.isNotEmpty && val.isNotEmpty) {
                metadata[rawHeader] = val;
              }
            }
          }

          if (!hasData) continue;

          bool isFormatError = false;

          if (name.isEmpty) {
            name = "형식에 맞지 않는 건";
            metadata['import_source'] = 'excel_error';
            metadata['error_reason'] = '품명/명칭/관리대상 항목 누락';
            errorCount++;
            isFormatError = true;
          } else {
            metadata['import_source'] = 'excel';
          }

          if (tagId.isEmpty) {
            tagId = "PTAG_${DateTime.now().millisecondsSinceEpoch}_$i";
          }

          final data = {
            'name': name,
            'tag_id': tagId,
            'location': loc,
            'spec': spec,
            'category': cat,
            'serial_number': sn,
            'safety_stock': 5,
            'status': name == "형식에 맞지 않는 건" ? '수기입고' : '보유중',
            'is_approved': true,
            'metadata': metadata
          };

          bool ok = await provider.handleSave(product: null, data: data, imageXFile: null);

          if (ok) {
            if (!isFormatError) successCount++;
          } else {
            failCount++;
            if (isFormatError) errorCount--;
          }

          currentCountNotifier.value++;
        }

      } catch (e) {
        hasCriticalError = true;
        criticalErrorMsg = e.toString();
      } finally {
        if (mounted) {
          setState(() { _isFullScreenLoading = false; });
          Navigator.of(context).pop();
        }
      }

      if (mounted) {
        if (hasCriticalError) {
          if (criticalErrorMsg.contains('numFmtId')) {
            _showInfoDialog(
                "엑셀 서식 호환성 오류",
                "해당 엑셀 파일에 지원되지 않는 특수 셀 서식이 포함되어 있습니다.\n\n"
                    "💡 [빠른 해결 방법]\n"
                    "새 엑셀 파일의 A1 셀에 '값만 붙여넣기'로 데이터를 옮긴 후 다시 업로드해주세요.",
                theme
            );
          } else {
            _showInfoDialog("오류", "엑셀 파싱 중 예기치 않은 오류가 발생했습니다: $criticalErrorMsg", theme);
          }
        } else {
          _syncFiltering(provider.items);
          totalCount = successCount + errorCount + failCount;
          _showInfoDialog(
              "엑셀 데이터 임포트 완료",
              "총 $totalCount건의 데이터 처리가 종료되었습니다.\n\n"
                  "✅ 정상 등록됨: $successCount건\n"
                  "⚠️ 형식 오류 (이름 누락): $errorCount건\n"
                  "❌ 서버 저장 실패: $failCount건\n\n"
                  "(저장 실패가 발생한 경우, 엑셀 내부에 태그ID가 중복되어 있거나 서버의 제약조건 때문일 수 있습니다.)",
              theme
          );
        }
      }

    } catch (e) {
      if (mounted) {
        _showInfoDialog("오류", "파일 처리 중 치명적 오류가 발생했습니다.", theme);
      }
    }
  }

  String _extractString(excel_pkg.Data? cell) {
    if (cell == null || cell.value == null) return "";
    String str = cell.value.toString();

    RegExp regExp = RegExp(r'^[a-zA-Z]+CellValue\((.*)\)$', dotAll: true);
    Match? match = regExp.firstMatch(str);

    if (match != null && match.groupCount >= 1) {
      String extracted = match.group(1) ?? "";
      if (extracted.startsWith('"') && extracted.endsWith('"') && extracted.length >= 2) {
        extracted = extracted.substring(1, extracted.length - 1);
      }
      return extracted.trim();
    }
    return str.trim();
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
  String _selectedHandler = "관리자";

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
    final theme = Theme.of(context);
    final personProvider = context.watch<PersonProvider>();
    final workerList = personProvider.list.map((p) => "${p.name} (${p.code})").toList();
    final isIn = widget.type == '수기입고';

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
            TextField(controller: _locC, style: AppTheme.itemValueStyle(context), decoration: AppTheme.inputDecoration(label: "처리 위치", context: context)),
            const SizedBox(height: 16),
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
      actions: [
        AppTheme.actionButton(
            label: "취소",
            color: Colors.transparent,
            textColor: cancelColor,
            onPressed: () => Navigator.pop(context)
        ),
        AppTheme.actionButton(
            label: "처리 확정",
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