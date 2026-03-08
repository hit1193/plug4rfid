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
/// PocketBase의 'detections' 컬렉션에 저장된 이력을 조건에 맞게 불러와 렌더링합니다.
///
/// [최종 업데이트 및 레이아웃 수정]
/// 1. Linter 규격 준수: 모든 조건문 블록화 및 문자열 보간법 적용.
/// 2. 용어 동기화: 인원(입장/퇴장)과 물품(입고/출고)의 용어를 실무에 맞게 분리.
/// 3. UI 개선: 리스트뷰 하단 20px 여백 추가 및 미니멀 외곽선 디자인 적용.
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
    _fetchHistoryData();
  }

  /// 달력 범위 선택기 호출
  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
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

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchHistoryData();
    }
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

      // 2. 서버 호출 (최신 생성일순 100건)
      final records = await pb.collection('detections').getList(
        page: 1,
        perPage: 100,
        sort: '-created',
        filter: queryFilter,
      );

      // 3. 역직렬화
      final List<DetectionModel> loadedData = records.items.map((record) {
        return DetectionModel.fromJson(record.toJson());
      }).toList();

      setState(() {
        _historyLogs = loadedData;
        _filterLogs(_searchController.text);
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

  /// 검색어 필터링 기능
  void _filterLogs(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredLogs = _historyLogs;
      });
      return;
    }

    final String lowerQuery = query.toLowerCase();
    setState(() {
      _filteredLogs = _historyLogs.where((log) {
        return log.content.toLowerCase().contains(lowerQuery) ||
            log.spot.toLowerCase().contains(lowerQuery);
      }).toList();
    });
  }

  /// ---------------------------------------------------------------------------
  /// [UI 렌더링] 이미지 헬퍼
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
        _buildTopControlPanel(theme, isDark),
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _filteredLogs.isEmpty
              ? _buildEmptyState(isDark)
              : _buildHistoryList(isDark, theme),
        ),
      ],
    );
  }

  /// 상단 대시보드 제어 패널
  Widget _buildTopControlPanel(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerTheme.color ?? Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.history_rounded, color: AppTheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "출입 및 감지 기록",
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      fontSize: 24,
                      fontWeight: AppTheme.weightMenu,
                      color: AppTheme.dataColor(isDark),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "지정된 기간 내 서버에 보관된 트랜잭션 기록입니다.",
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
          const SizedBox(height: 24),
          Row(
            children: [
              InkWell(
                onTap: () {
                  _selectDateRange(context);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(8),
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : AppTheme.primary.withValues(alpha: 0.05),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month_rounded, size: 20, color: AppTheme.primary),
                      const SizedBox(width: 12),
                      Text(
                        "${_startDate.year}.${_startDate.month.toString().padLeft(2, '0')}.${_startDate.day.toString().padLeft(2, '0')} ~ "
                            "${_endDate.year}.${_endDate.month.toString().padLeft(2, '0')}.${_endDate.day.toString().padLeft(2, '0')}",
                        style: TextStyle(
                          fontFamily: AppTheme.fontPretendard,
                          fontWeight: AppTheme.weightMenu,
                          fontSize: 15,
                          color: AppTheme.dataColor(isDark),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _buildQuickChip("오늘", 0, isDark),
              const SizedBox(width: 8),
              _buildQuickChip("1주일", 7, isDark),
              const SizedBox(width: 8),
              _buildQuickChip("1개월", 30, isDark),
              const Spacer(),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _searchController,
                  onChanged: _filterLogs,
                  style: TextStyle(fontFamily: AppTheme.fontPretendard, color: AppTheme.dataColor(isDark)),
                  decoration: AppTheme.inputDecoration(label: "작업자 또는 스팟 검색...", context: context, prefixIcon: Icons.search),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _fetchHistoryData,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text("조회", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, int daysAgo, bool isDark) {
    final DateTime targetStart = DateTime.now().subtract(Duration(days: daysAgo));
    final bool isSelected = _startDate.year == targetStart.year &&
        _startDate.month == targetStart.month &&
        _startDate.day == targetStart.day;

    return ActionChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontFamily: AppTheme.fontPretendard,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : AppTheme.dataColor(isDark),
      ),
      backgroundColor: isSelected ? AppTheme.primary : (isDark ? Colors.white10 : Colors.grey.shade200),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () {
        _setQuickDateRange(daysAgo);
      },
    );
  }

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
  /// [핵심 영역] 감지 이력 리스트뷰
  /// ---------------------------------------------------------------------------
  Widget _buildHistoryList(bool isDark, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20.0), // 대표님 지시사항: 리스트뷰 하단 여백 20px 적용
      child: ListView.builder(
        padding: const EdgeInsets.all(24.0),
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