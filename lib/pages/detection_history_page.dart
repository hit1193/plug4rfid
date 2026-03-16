import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // 날짜 포맷팅을 위해 반드시 필요합니다.
import 'dart:async';
import 'dart:convert';

// 상위 시스템에서 정의한 중앙 집중형 테마와 모델, 통신 객체를 임포트합니다.
import '../theme/app_theme.dart';
import '../models/detection_model.dart';
import '../core/pocketbase_client.dart';

/// ---------------------------------------------------------------------------
/// [출입 기록(History) 관리자 화면]
/// 중복되는 상단 타이틀 바를 삭제하고, 직관적인 검색 및 필터 박스만 남겼습니다.
/// ---------------------------------------------------------------------------
class DetectionHistoryPage extends StatefulWidget {
  final bool isMobile;
  final String baseUrl;

  const DetectionHistoryPage({
    super.key,
    required this.isMobile,
    required this.baseUrl,
  });

  @override
  State<DetectionHistoryPage> createState() {
    return _DetectionHistoryPageState();
  }
}

class _DetectionHistoryPageState extends State<DetectionHistoryPage> {
  // -------------------------------------------------------------------------
  // [상태 제어 변수]
  // -------------------------------------------------------------------------
  bool _isLoading = false;                   // 로딩 스피너 제어용
  List<DetectionModel> _historyLogs = [];    // DB에서 불러온 원본 이력 리스트
  List<DetectionModel> _filteredLogs = [];   // 검색어로 필터링된 이력 리스트

  final TextEditingController _searchController = TextEditingController();

  // 검색 기간 상태 변수 (기본값: 최근 7일)
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    // 초기 검색 기간 세팅: 종료일은 오늘, 시작일은 7일 전으로 설정합니다.
    _endDate = DateTime.now();
    _startDate = _endDate.subtract(const Duration(days: 7));

    // 화면이 최초 생성될 때 서버에서 데이터를 비동기로 불러옵니다.
    _fetchHistoryData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 빠른 기간 선택 처리 (오늘, 1주일, 1개월)
  void _setQuickDateRange(int days) {
    setState(() {
      _endDate = DateTime.now();
      _startDate = _endDate.subtract(Duration(days: days));
    });
    // 날짜가 변경되면 즉시 데이터를 다시 불러옵니다.
    _fetchHistoryData();
  }

  /// 달력 범위 선택기(Date Range Picker) 호출
  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        // 달력 다이얼로그의 색상을 앱 테마에 맞게 조정합니다.
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              onSurface: AppTheme.dataColor(Theme.of(context).brightness == Brightness.dark),
            ),
          ),
          child: child!,
        );
      },
    );

    // 사용자가 날짜 범위를 선택하고 '확인'을 누른 경우
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      // 새로운 기간으로 데이터를 다시 조회합니다.
      _fetchHistoryData();
    }
  }

  /// 현재 선택된 기간이 빠른 선택(0일, 7일, 30일)에 해당하는지 판단하여 값을 반환합니다.
  int? _getQuickDateSelection() {
    final DateTime now = DateTime.now();

    // 종료일이 오늘인지 먼저 확인합니다.
    if (_endDate.year == now.year && _endDate.month == now.month && _endDate.day == now.day) {
      // 0일 (오늘) 확인
      if (_startDate.year == now.year && _startDate.month == now.month && _startDate.day == now.day) {
        return 0;
      }
      // 7일 (1주일) 확인
      final DateTime d7 = now.subtract(const Duration(days: 7));
      if (_startDate.year == d7.year && _startDate.month == d7.month && _startDate.day == d7.day) {
        return 7;
      }
      // 30일 (1개월) 확인
      final DateTime d30 = now.subtract(const Duration(days: 30));
      if (_startDate.year == d30.year && _startDate.month == d30.month && _startDate.day == d30.day) {
        return 30;
      }
    }
    // 사용자가 달력으로 임의의 기간을 선택한 경우 null을 반환하여 선택을 해제합니다.
    return null;
  }

  /// ---------------------------------------------------------------------------
  /// [비즈니스 로직] PocketBase 서버에서 이력 데이터 가져오기
  /// ---------------------------------------------------------------------------
  Future<void> _fetchHistoryData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. 기간 필터 가공 (KST 로컬 기준을 UTC로 변환하여 시스템 필드 'created' 활용)
      final DateTime startOfDayLocal = DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0);
      final DateTime endOfDayLocal = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

      final DateFormat formatter = DateFormat("yyyy-MM-dd HH:mm:ss");
      final String startStr = formatter.format(startOfDayLocal.toUtc());
      final String endStr = formatter.format(endOfDayLocal.toUtc());

      final String queryFilter = 'created >= "$startStr" && created <= "$endStr"';

      // 2. 서버 호출 (최신 생성일순 100건 조회)
      final records = await pb.collection('detections').getList(
        page: 1,
        perPage: 100,
        sort: '-created',
        filter: queryFilter,
      );

      // 3. 받아온 JSON 데이터를 Dart 객체(모델)로 역직렬화
      final List<DetectionModel> loadedData = records.items.map((record) {
        return DetectionModel.fromJson(record.toJson());
      }).toList();

      setState(() {
        _historyLogs = loadedData;
        _filterLogs(_searchController.text); // 기존 검색어가 있다면 유지한 채로 필터링
      });

      debugPrint("✅ 이력 데이터 불러오기 성공: ${_historyLogs.length}건");
    } catch (e) {
      debugPrint("❌ 이력 데이터 불러오기 실패: $e");
      setState(() {
        _historyLogs = [];
        _filteredLogs = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 검색어(이름, 장소 등) 필터링 기능
  void _filterLogs(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredLogs = _historyLogs;
      });
      return;
    }

    final String lowerQuery = query.toLowerCase();
    setState(() {
      // 본문(이름/물품명 등) 또는 스팟(장소)에 검색어가 포함된 항목만 걸러냅니다.
      _filteredLogs = _historyLogs.where((log) {
        return log.content.toLowerCase().contains(lowerQuery) ||
            log.spot.toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  /// ---------------------------------------------------------------------------
  /// [UI 렌더링] 이미지 표시용 헬퍼 위젯
  /// ---------------------------------------------------------------------------
  Widget _buildImage(String? url, {required double size, bool isCircle = false}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.silver.withValues(alpha: 0.1),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(8),
        border: Border.all(color: AppTheme.silver.withValues(alpha: 0.3), width: 1),
      ),
      clipBehavior: Clip.hardEdge,
      child: (url != null && url.isNotEmpty)
          ? Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          // 이미지 로드 실패 시 기본 아이콘 표시
          return Icon(
            isCircle ? Icons.person : Icons.inventory_2,
            color: AppTheme.silver,
            size: size * 0.6,
          );
        },
      )
          : Icon(
        isCircle ? Icons.person : Icons.inventory_2,
        color: AppTheme.silver,
        size: size * 0.6,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🔥 [업데이트] 중복된 타이틀 영역을 삭제하고 필터 패널만 바로 호출합니다.
        _buildTopControlPanel(theme, isDark),

        // 메인 리스트 뷰 영역
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _filteredLogs.isEmpty
              ? _buildEmptyState(isDark)
              : _buildHistoryList(isDark, theme),
        ),
      ],
    );
  }

  /// ---------------------------------------------------------------------------
  /// [UI 개선] 상단 대시보드 제어 패널 (중복 타이틀 제거됨)
  /// ---------------------------------------------------------------------------
  Widget _buildTopControlPanel(ThemeData theme, bool isDark) {
    return Container(
      padding: EdgeInsets.all(widget.isMobile ? 16.0 : 24.0),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        // 화면 크기에 따라 모바일 레이아웃과 데스크톱 레이아웃을 다르게 렌더링합니다.
        child: widget.isMobile ? _buildMobileFilterLayout(isDark) : _buildDesktopFilterLayout(isDark),
      ),
    );
  }

  /// [UI 조각] 데스크톱/태블릿용 가로형 필터 레이아웃
  Widget _buildDesktopFilterLayout(bool isDark) {
    return Row(
      children: [
        // 달력 범위 선택 버튼
        _buildDatePickerButton(isDark),
        const SizedBox(width: 16),

        _buildQuickDateSegmentedButton(isDark),

        const Spacer(), // 남는 공간을 모두 차지하여 오른쪽으로 밀어냄

        // 검색어 입력창
        SizedBox(
          width: 280,
          child: TextField(
            controller: _searchController,
            onChanged: _filterLogs,
            style: TextStyle(fontFamily: AppTheme.fontPretendard, color: AppTheme.dataColor(isDark)),
            decoration: AppTheme.inputDecoration(
              label: "작업자 또는 스팟 검색...",
              context: context,
              prefixIcon: Icons.search,
            ).copyWith(
              // 검색창 높이를 약간 슬림하게 조정
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // 조회 버튼
        _buildRefreshButton(),
      ],
    );
  }

  /// [UI 조각] 모바일용 세로형 필터 레이아웃
  Widget _buildMobileFilterLayout(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1줄: 달력 범위 선택 버튼 (가로 꽉 차게)
        _buildDatePickerButton(isDark),
        const SizedBox(height: 12),

        // 2줄: 세그먼티드 버튼이 모바일에서는 가로로 꽉 차도록 배치
        _buildQuickDateSegmentedButton(isDark),
        const SizedBox(height: 16),

        // 3줄: 검색어 입력창과 조회 버튼
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: _filterLogs,
                style: TextStyle(fontFamily: AppTheme.fontPretendard, color: AppTheme.dataColor(isDark)),
                decoration: AppTheme.inputDecoration(
                  label: "검색어 입력...",
                  context: context,
                  prefixIcon: Icons.search,
                ).copyWith(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildRefreshButton(isIconOnly: true), // 모바일에서는 공간 절약을 위해 아이콘만 표시
          ],
        ),
      ],
    );
  }

  /// [UI 조각] 달력 선택을 위한 버튼 (깔끔한 Outlined 스타일)
  Widget _buildDatePickerButton(bool isDark) {
    final String startDateStr = "${_startDate.year}.${_startDate.month.toString().padLeft(2, '0')}.${_startDate.day.toString().padLeft(2, '0')}";
    final String endDateStr = "${_endDate.year}.${_endDate.month.toString().padLeft(2, '0')}.${_endDate.day.toString().padLeft(2, '0')}";

    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today_rounded, size: 18),
      label: Text(
        "$startDateStr  ~  $endDateStr",
        style: TextStyle(
          fontFamily: AppTheme.fontPretendard,
          fontWeight: AppTheme.weightOthers,
          fontSize: 15,
          color: AppTheme.dataColor(isDark),
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white,
      ),
      onPressed: () => _selectDateRange(context),
    );
  }

  /// [UI 조각] 빠른 기간 선택 세그먼티드 버튼
  Widget _buildQuickDateSegmentedButton(bool isDark) {
    final int? selectedValue = _getQuickDateSelection();

    return SegmentedButton<int>(
      showSelectedIcon: false,         // 좌측 체크 아이콘 숨김 처리 (미니멀리즘)
      emptySelectionAllowed: true,     // 사용자가 달력을 통해 임의의 날짜 지정 시 선택 해제를 허용
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppTheme.primary,
        selectedForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), // 달력 버튼과 높이를 동일하게 맞춤
        textStyle: const TextStyle(
          fontFamily: AppTheme.fontPretendard,
          fontSize: 14,
          fontWeight: FontWeight.w800, // 또렷하고 두꺼운 폰트 적용
        ),
      ),
      segments: const [
        ButtonSegment(value: 0, label: Text("오늘")),
        ButtonSegment(value: 7, label: Text("1주일")),
        ButtonSegment(value: 30, label: Text("1개월")),
      ],
      selected: selectedValue != null ? {selectedValue} : <int>{},
      onSelectionChanged: (Set<int> newSelection) {
        if (newSelection.isNotEmpty) {
          _setQuickDateRange(newSelection.first);
        }
      },
    );
  }

  /// [UI 조각] 조회(새로고침) 버튼
  Widget _buildRefreshButton({bool isIconOnly = false}) {
    return ElevatedButton(
      onPressed: _isLoading ? null : _fetchHistoryData,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: isIconOnly ? 16 : 24,
          vertical: 14,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: _isLoading
          ? const SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      )
          : Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.refresh_rounded, size: 20),
          if (!isIconOnly) ...[
            const SizedBox(width: 8),
            const Text("조회", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightMenu)),
          ]
        ],
      ),
    );
  }

  /// 데이터가 없을 때 보여줄 빈 상태(Empty State) 화면
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 80, color: AppTheme.labelColor(isDark).withValues(alpha: 0.3)),
          const SizedBox(height: 24),
          Text(
            "선택한 기간에 해당하는 감지 기록이 없습니다.",
            style: TextStyle(
              fontFamily: AppTheme.fontPretendard,
              fontSize: 20,
              fontWeight: AppTheme.weightMenu,
              color: AppTheme.labelColor(isDark),
            ),
          ),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [핵심 영역] 감지 이력 리스트뷰 (기존 디자인 유지 및 하단 여백 적용)
  /// ---------------------------------------------------------------------------
  Widget _buildHistoryList(bool isDark, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20.0), // 대표님 지시사항: 리스트뷰 하단 여백 20px 적용
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: widget.isMobile ? 16.0 : 24.0, vertical: 8.0),
        itemCount: _filteredLogs.length,
        itemBuilder: (BuildContext context, int index) {
          final DetectionModel log = _filteredLogs[index];
          final bool isMatched = log.type == 'matched';
          final bool isPerson = log.type == 'person';

          // [기능 보완] 인원일 경우 입장/퇴장, 물품일 경우 입고/출고 용어 및 색상 적용
          Color statusColor;
          String displayStatus = log.status;

          if (isPerson) {
            statusColor = log.isEntry ? AppTheme.success : Colors.orange.shade700;
            displayStatus = log.isEntry ? "입장(출근)" : "퇴장(퇴근)";
          } else {
            statusColor = log.isEntry ? AppTheme.success : AppTheme.primary;
            displayStatus = log.isEntry ? "입고(반납)" : "출고(작업)";
          }

          final DateTime localTime = log.timestamp.toLocal();
          final String dateStr = "${localTime.year}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')}";
          final String timeStr = "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}:${localTime.second.toString().padLeft(2, '0')}";

          // 행(Row) 공통 레이아웃
          Widget headerContent = Row(
            children: [
              _buildImage(log.imageUrl, size: 50, isCircle: true),
              const SizedBox(width: 20),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.content,
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontSize: 20,
                        fontWeight: AppTheme.weightMenu,
                        color: AppTheme.dataColor(isDark),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: AppTheme.labelColor(isDark)),
                        const SizedBox(width: 4),
                        Text(
                          log.spot,
                          style: TextStyle(
                            fontFamily: AppTheme.fontPretendard,
                            fontSize: 14,
                            color: AppTheme.labelColor(isDark),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontSize: 14,
                        color: AppTheme.labelColor(isDark),
                      ),
                    ),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.dataColor(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor, width: 1.5),
                ),
                child: Text(
                  displayStatus,
                  style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          );

          Widget cardChild;
          if (isMatched && log.items.isNotEmpty) {
            // 자산(물품)이 매칭된 경우 확장 타일 사용
            cardChild = Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                title: headerContent,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        "${log.items.length}건",
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.expand_more_rounded, color: Colors.grey),
                  ],
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black.withValues(alpha: 0.15) : const Color(0xFFF8FAFC),
                      border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "📦 매칭된 자산 목록",
                          style: TextStyle(
                            fontFamily: AppTheme.fontPretendard,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.labelColor(isDark),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 100,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: log.items.length,
                            separatorBuilder: (context, idx) {
                              return const SizedBox(width: 16);
                            },
                            itemBuilder: (context, itemIdx) {
                              final item = log.items[itemIdx];
                              return Container(
                                width: 250,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.cardTheme.color,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                                ),
                                child: Row(
                                  children: [
                                    _buildImage(item['image'], size: 50),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        item['name'] ?? '알 수 없음',
                                        style: TextStyle(
                                          fontFamily: AppTheme.fontPretendard,
                                          fontSize: 15,
                                          fontWeight: AppTheme.weightMenu,
                                          color: AppTheme.dataColor(isDark),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )
                                  ],
                                ),
                              );
                            },
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            );
          } else {
            // 일반 출입 이력인 경우
            cardChild = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
              child: headerContent,
            );
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            color: theme.cardTheme.color,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.12),
                width: 1.0,
              ),
            ),
            clipBehavior: Clip.hardEdge,
            child: cardChild,
          );
        },
      ),
    );
  }
}