import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // 날짜 포맷팅 및 비교를 위해 추가
import 'dart:async';
import 'dart:convert';

// 상위 시스템에서 정의한 중앙 집중형 테마와 데이터 모델을 임포트합니다.
import '../theme/app_theme.dart';
import '../models/detection_model.dart';
import '../core/pocketbase_client.dart';

/// RFID 게이트의 운영 모드를 정의하는 열거형입니다.
enum GateScanMode {
  personnelOnly, // 인원 출입 전용 모드
  itemWorkerMatch // 물품 + 작업자 매칭 모드 (자산 통제)
}

/// ---------------------------------------------------------------------------
/// [실시간 입/출고 감시 키오스크 화면 - 반응형 통합 버전]
///
/// [주요 특징]
/// 1. Windows FHD(1920x1080)부터 모바일(Android/iOS)까지 지원하는 반응형 레이아웃.
/// 2. 미니멀리즘 디자인 유지 및 키오스크 감성 강화.
/// 3. 모든 비즈니스 로직(타이머, DB 연동, 실시간 구독) 포함.
/// ---------------------------------------------------------------------------
class KioskView extends StatefulWidget {
  final VoidCallback onDismiss;

  const KioskView({super.key, required this.onDismiss});

  @override
  State<KioskView> createState() {
    return _KioskViewState();
  }
}

class _KioskViewState extends State<KioskView> {
  // -------------------------------------------------------------------------
  // [상태 제어 변수 및 타이머]
  // -------------------------------------------------------------------------
  Timer? _clockTimer;
  Timer? _standbyTimer;
  Timer? _slideshowTimer;
  Timer? _autoSaveTimer;

  String _currentTime = "";
  Duration _timeOffset = Duration.zero;

  bool _useStandbyMode = true;
  bool _isStandbyActive = false;

  bool _requireWorkerMatch = true;
  int _simCount = 0; // 시뮬레이션용 분기 카운터

  final int _standbyTimeoutSeconds = 10;
  final int _autoSaveDurationSeconds = 10;
  int _autoSaveCountdown = 0;

  GateScanMode _currentScanMode = GateScanMode.itemWorkerMatch;

  // -------------------------------------------------------------------------
  // [DB 실 연동 집계 데이터 변수]
  // -------------------------------------------------------------------------
  int _prevDayStay = 0;
  int _todayEntry = 0;
  int _todayExit = 0;
  int _currentStay = 0;

  int _prevDayStock = 0;
  int _todayIn = 0;
  int _todayOut = 0;
  int _currentStock = 0;

  // -------------------------------------------------------------------------
  // [슬라이드쇼 배경 이미지 목록]
  // -------------------------------------------------------------------------
  final List<String> _backgroundImages = [
    "https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?q=80&w=2000&auto=format&fit=crop",
    "https://images.unsplash.com/photo-1504328345606-18bbc8c9d7d1?q=80&w=2000&auto=format&fit=crop",
    "https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d?q=80&w=2000&auto=format&fit=crop",
  ];
  int _currentImageIndex = 0;

  // [수정] 기존 하드코딩된 텍스트 대신, DB에서 불러올 때까지 표시할 기본 안내 문구로 변경하고 변수(String)로 만들었습니다.
  String _noticeText = "최신 공지사항을 불러오는 중입니다...";

  final List<DetectionModel> _realtimeLogs = [];

  @override
  void initState() {
    super.initState();
    _syncServerTime();

    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      _updateClock();
    });

    _resetStandbyTimer();

    _slideshowTimer = Timer.periodic(const Duration(seconds: 8), (Timer timer) {
      if (mounted && _useStandbyMode && _isStandbyActive) {
        setState(() {
          _currentImageIndex = (_currentImageIndex + 1) % _backgroundImages.length;
        });
      }
    });

    _fetchSummaryData();
    _fetchNotice(); // [추가됨] 화면 초기화 시점에 가장 최신 공지사항을 가져옵니다.
    _initRealtimeSubscription();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _standbyTimer?.cancel();
    _slideshowTimer?.cancel();
    _autoSaveTimer?.cancel();

    try {
      pb.realtime.unsubscribe('');
    } catch (_) {
      // 해제 시 에러 무시
    }

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // [비즈니스 로직 생략 없이 유지]
  // ---------------------------------------------------------------------------

  Future<void> _fetchSummaryData() async {
    try {
      final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // 인원 통계
      int tIn = 0; int tOut = 0; int cStay = 0;
      try {
        final userRecords = await pb.collection('users').getFullList();
        for (var record in userRecords) {
          final meta = record.data['metadata'] as Map<String, dynamic>? ?? {};
          final lastType = meta['last_access_type']?.toString() ?? '';
          final lastTime = meta['last_access_time']?.toString() ?? '';
          if (lastTime.startsWith(todayStr)) {
            if (lastType == '입장') { tIn++; }
            else if (lastType == '퇴장') { tOut++; }
          }
          if (lastType == '입장') { cStay++; }
        }
      } catch (e) { debugPrint("User 통계 에러: $e"); }

      // 물품 통계
      int totalStock = 0; int itemIn = 0; int itemOut = 0;
      try {
        final prodRecords = await pb.collection('products').getFullList();
        for (var p in prodRecords) {
          totalStock += (p.data['stock_count'] as int?) ?? 1;
        }
      } catch (e) { debugPrint("Product 통계 에러: $e"); }

      try {
        final DateTime now = DateTime.now();
        final DateTime startOfDayLocal = DateTime(now.year, now.month, now.day, 0, 0, 0);
        final DateTime endOfDayLocal = DateTime(now.year, now.month, now.day, 23, 59, 59);
        final DateFormat formatter = DateFormat("yyyy-MM-dd HH:mm:ss");
        final String startStr = formatter.format(startOfDayLocal.toUtc());
        final String endStr = formatter.format(endOfDayLocal.toUtc());

        final detRecords = await pb.collection('detections').getFullList(
            filter: 'created >= "$startStr" && created <= "$endStr" && type = "matched"'
        );

        for (var d in detRecords) {
          final isEntry = d.getBoolValue('is_entry');
          final dynamic itemsDynamic = d.data['items_json'];
          int itemsCount = 0;
          if (itemsDynamic is List) { itemsCount = itemsDynamic.length; }
          else if (itemsDynamic is String) { itemsCount = (jsonDecode(itemsDynamic) as List).length; }
          if (isEntry) { itemIn += itemsCount; } else { itemOut += itemsCount; }
        }
      } catch (e) { debugPrint("Detection 통계 에러: $e"); }

      if (mounted) {
        setState(() {
          _todayEntry = tIn; _todayExit = tOut; _currentStay = cStay;
          _prevDayStay = _currentStay - _todayEntry + _todayExit;
          _todayIn = itemIn; _todayOut = itemOut; _currentStock = totalStock;
          _prevDayStock = _currentStock - _todayIn + _todayOut;
        });
      }
    } catch (e) { debugPrint("집계 로드 실패: $e"); }
  }

  // ---------------------------------------------------------------------------
  // [신규 추가] DB에서 가장 최신 공지사항을 가져오는 로직
  // ---------------------------------------------------------------------------
  Future<void> _fetchNotice() async {
    try {
      // notices 컬렉션에서 등록일(created) 기준 가장 최신 데이터를 1건만 가져옵니다.
      final records = await pb.collection('notices').getList(
        page: 1,
        perPage: 1,
        sort: '-created',
      );

      if (records.items.isNotEmpty && mounted) {
        final data = records.items.first.data;
        // 가져온 데이터에서 제목과 내용을 조합하여 키오스크 전광판 양식으로 만듭니다.
        final String title = data['title']?.toString() ?? '사내 공지';
        final String content = data['content']?.toString() ?? '';

        setState(() {
          _noticeText = "[$title] $content";
        });
      } else if (mounted) {
        // 등록된 공지사항이 비어있을 경우의 기본 메시지입니다.
        setState(() {
          _noticeText = "현재 등록된 특별한 공지사항이 없습니다. 현장 안전에 유의하여 작업해주시기 바랍니다.";
        });
      }
    } catch (e) {
      debugPrint("공지사항 로드 실패: $e");
    }
  }

  void _initRealtimeSubscription() {
    try {
      pb.realtime.unsubscribe('');
      pb.collection('users').subscribe('*', (e) { if (mounted) { _fetchSummaryData(); } });
      pb.collection('detections').subscribe('*', (e) { if (mounted) { _fetchSummaryData(); } });
      pb.collection('products').subscribe('*', (e) { if (mounted) { _fetchSummaryData(); } });

      // [추가됨] 관리자가 공지사항을 수정하거나 추가하면 키오스크도 즉각 이를 감지하고 텍스트를 업데이트합니다.
      pb.collection('notices').subscribe('*', (e) { if (mounted) { _fetchNotice(); } });

      debugPrint("✅ 실시간 SSE 구독 설정 완료");
    } catch (e) { debugPrint("❌ 실시간 구독 중 에러: $e"); }
  }

  bool get _canSave {
    if (_realtimeLogs.isEmpty) { return false; }
    if (!_requireWorkerMatch) { return true; }
    return _realtimeLogs.first.content != '미인식 작업자';
  }

  Future<void> _syncServerTime() async {
    try { setState(() { _timeOffset = Duration.zero; }); } catch (e) { debugPrint("서버 시간 동기화 실패: $e"); }
  }

  void _updateClock() {
    final DateTime now = DateTime.now().add(_timeOffset);
    const List<String> weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    if (mounted) {
      setState(() {
        _currentTime = "${now.year}년 ${now.month.toString().padLeft(2, '0')}월 ${now.day.toString().padLeft(2, '0')}일 (${weekdays[now.weekday - 1]})   ${now.hour.toString().padLeft(2, '0')} : ${now.minute.toString().padLeft(2, '0')} : ${now.second.toString().padLeft(2, '0')}";
      });
    }
  }

  void _resetStandbyTimer() {
    _standbyTimer?.cancel();
    if (_useStandbyMode && _realtimeLogs.isEmpty) {
      _standbyTimer = Timer(Duration(seconds: _standbyTimeoutSeconds), () {
        if (mounted) { setState(() { _isStandbyActive = true; }); }
      });
    }
  }

  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _standbyTimer?.cancel();
    if (!_canSave) {
      setState(() { _autoSaveCountdown = _autoSaveDurationSeconds; });
      return;
    }
    setState(() { _autoSaveCountdown = _autoSaveDurationSeconds; });
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_autoSaveCountdown > 1) { _autoSaveCountdown--; }
          else { _executeSaveAndClear(); }
        });
      }
    });
  }

  Future<void> _executeSaveAndClear() async {
    _autoSaveTimer?.cancel();
    try {
      for (var log in _realtimeLogs) {
        final Map<String, dynamic> dbRecord = log.toJson();
        dbRecord['timestamp'] = "${log.timestamp.toUtc().toString().replaceAll('T', ' ')}Z";
        await pb.collection('detections').create(body: dbRecord);
        final userRecords = await pb.collection('users').getList(filter: 'name = "${log.content}"', perPage: 1);
        if (userRecords.items.isNotEmpty) {
          final userRecord = userRecords.items.first;
          final Map<String, dynamic> meta = Map<String, dynamic>.from(userRecord.data['metadata'] ?? {});
          String accessType = log.type == 'person' ? (log.status.contains('퇴장') ? '퇴장' : '입장') : (log.isEntry ? '입장' : '퇴장');
          meta['last_access_type'] = accessType;
          meta['last_access_time'] = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
          await pb.collection('users').update(userRecord.id, body: {'metadata': meta});
        }
      }
    } catch (e) { debugPrint("❌ DB 연동 실패: $e"); }
    if (mounted) {
      setState(() { _realtimeLogs.clear(); if (_useStandbyMode) { _isStandbyActive = true; } });
      _resetStandbyTimer();
    }
  }

  void _executeCancelAndClear() {
    _autoSaveTimer?.cancel();
    setState(() { _realtimeLogs.clear(); if (_useStandbyMode) { _isStandbyActive = true; } });
    _resetStandbyTimer();
  }

  void _simulateNewDetection() {
    if (_isStandbyActive) { _realtimeLogs.clear(); _isStandbyActive = false; }
    final DateTime detectTime = DateTime.now().add(_timeOffset);
    DetectionModel newLog;

    if (_currentScanMode == GateScanMode.personnelOnly) {
      bool isEntrySim = _simCount % 2 == 0;
      newLog = DetectionModel(
          type: 'person',
          content: isEntrySim ? '홍길동 책임' : '이작업 주임',
          imageUrl: isEntrySim ? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?q=80&w=200' : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?q=80&w=200',
          spot: 'A구역 로비 게이트',
          status: isEntrySim ? '입장(출근)' : '퇴장(퇴근)',
          isEntry: isEntrySim,
          timestamp: detectTime,
          items: []
      );
    } else {
      if (_simCount % 3 == 0) {
        newLog = DetectionModel(
            type: 'matched',
            content: '미인식 작업자',
            imageUrl: '',
            spot: 'B구역 2번 공정 게이트',
            status: '출고(대기중)',
            isEntry: false,
            timestamp: detectTime,
            items: [
              {'name': '고성능 해머 드릴 (DW-88)', 'image': 'https://images.unsplash.com/photo-1504148455328-c39c5ef21d29?q=80&w=200'},
              {'name': '안전모 (Type-A)', 'image': 'https://images.unsplash.com/photo-1599408162162-6b0af444014e?q=80&w=200'}
            ]
        );
      } else if (_simCount % 3 == 1) {
        newLog = DetectionModel(
            type: 'matched',
            content: '이작업 주임',
            imageUrl: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?q=80&w=200',
            spot: 'B구역 2번 공정 게이트',
            status: '출고(작업)',
            isEntry: false,
            timestamp: detectTime,
            items: [
              {'name': '측정기 A-type', 'image': 'https://images.unsplash.com/photo-1581092160562-40aa08e78837?q=80&w=200'},
              {'name': '개인 공구함', 'image': 'https://images.unsplash.com/photo-1530124566582-a618bc2615ad?q=80&w=200'}
            ]
        );
      } else {
        newLog = DetectionModel(
            type: 'matched',
            content: '홍길동 책임',
            imageUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?q=80&w=200',
            spot: 'B구역 1번 자재고 게이트',
            status: '입고(반납)',
            isEntry: true,
            timestamp: detectTime,
            items: [
              {'name': '전동 드릴 (DW-88)', 'image': 'https://images.unsplash.com/photo-1504148455328-c39c5ef21d29?q=80&w=200'}
            ]
        );
      }
    }
    _simCount++;
    setState(() { _realtimeLogs.insert(0, newLog); });
    _startAutoSaveTimer();
  }

  void _simulatePersonTag() {
    if (_realtimeLogs.isNotEmpty && _realtimeLogs.first.content == '미인식 작업자') {
      final oldLog = _realtimeLogs.first;
      setState(() {
        _realtimeLogs[0] = DetectionModel(
            id: oldLog.id, type: oldLog.type, content: '홍길동 책임',
            imageUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?q=80&w=200',
            spot: oldLog.spot, status: '출고(작업)', isEntry: oldLog.isEntry,
            items: oldLog.items, timestamp: oldLog.timestamp
        );
      });
      _startAutoSaveTimer();
    }
  }

  // ---------------------------------------------------------------------------
  // [반응형 레이아웃 빌드 메서드]
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 1000; // 태블릿/폰 기준

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          child: (_useStandbyMode && _isStandbyActive)
              ? _buildStandbyScreen(key: const ValueKey('standby_screen'), isDark: isDark, isSmall: isSmallScreen)
              : _buildLogScreen(key: const ValueKey('log_screen'), isDark: isDark, theme: theme, isSmall: isSmallScreen),
        ),
      ),
    );
  }

  /// 1. 대기 화면 (반응형 대응)
  Widget _buildStandbyScreen({required Key key, required bool isDark, required bool isSmall}) {
    return SizedBox(
      key: key,
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 1500),
            child: SizedBox.expand(
              key: ValueKey<int>(_currentImageIndex),
              child: Image.network(
                  _backgroundImages[_currentImageIndex],
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, lp) {
                    return lp == null ? child : const ColoredBox(color: Color(0xFF121826));
                  }
              ),
            ),
          ),
          // 시간 표시 (화면 크기에 따라 폰트 크기 조정)
          Positioned(
              top: isSmall ? 16 : 32,
              left: isSmall ? 16 : 32,
              child: Text(
                  _currentTime,
                  style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      color: Colors.white,
                      fontSize: isSmall ? 24 : 48,
                      fontWeight: AppTheme.weightMenu,
                      letterSpacing: 2.0,
                      shadows: const [Shadow(color: Colors.black87, blurRadius: 8.0, offset: Offset(2, 2))]
                  )
              )
          ),
          // 설정 및 종료 버튼 그룹
          Positioned(
              top: isSmall ? 16 : 32,
              right: isSmall ? 8 : 32,
              child: isSmall
                  ? IconButton(onPressed: widget.onDismiss, icon: const Icon(Icons.close_rounded, color: Colors.white, size: 32))
                  : Row(
                  children: [
                    _buildTestButton(isSmall: false),
                    const SizedBox(width: 30),
                    _buildModeSwitcher(isDark: isDark, forceWhiteText: true),
                    const SizedBox(width: 30),
                    _buildRequireWorkerToggle(isDark: isDark, forceWhiteText: true),
                    const SizedBox(width: 30),
                    _buildStandbyToggle(isDark: isDark, forceWhiteText: true),
                    const SizedBox(width: 20),
                    IconButton(onPressed: widget.onDismiss, icon: const Icon(Icons.close_rounded, color: Colors.white, size: 40))
                  ]
              )
          ),
          // 하단 공지사항 (여기서 _noticeText 변수를 사용하여 출력합니다)
          Positioned(
              bottom: isSmall ? 10 : 30,
              left: isSmall ? 10 : 40,
              right: isSmall ? 10 : 40,
              child: _MarqueeWidget(text: _noticeText, backgroundColor: Colors.transparent, textColor: Colors.white, forceDarkShadow: true, isSmall: isSmall)
          ),
        ],
      ),
    );
  }

  /// 2. 실시간 로그 화면 (반응형 대응)
  Widget _buildLogScreen({required Key key, required bool isDark, required ThemeData theme, required bool isSmall}) {
    return Padding(
      key: key,
      padding: EdgeInsets.all(isSmall ? 16.0 : 32.0),
      child: Column(
        children: [
          _buildHeader(isDark: isDark, isSmall: isSmall),
          const SizedBox(height: 24),
          _buildSummaryBar(isDark: isDark, isSmall: isSmall),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 20.0),
              child: _realtimeLogs.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sensor_door_rounded, size: isSmall ? 50 : 80, color: AppTheme.labelColor(isDark).withValues(alpha: 0.3)),
                    const SizedBox(height: 24),
                    Text("게이트 감지 대기 중...", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: isSmall ? 18 : 24, fontWeight: AppTheme.weightMenu, color: AppTheme.labelColor(isDark))),
                  ],
                ),
              )
                  : ListView.separated(
                itemCount: _realtimeLogs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 24),
                itemBuilder: (context, index) {
                  final DetectionModel log = _realtimeLogs[index];
                  final bool isWarning = log.content == '미인식 작업자' && _requireWorkerMatch;
                  return _LogCardWidget(
                      log: log, isDark: isDark, theme: theme,
                      isWarning: isWarning, isSmall: isSmall
                  );
                },
              ),
            ),
          ),
          if (_realtimeLogs.isNotEmpty) ...[
            _buildAutoSaveActionPanel(isDark: isDark, theme: theme, isSmall: isSmall),
          ]
        ],
      ),
    );
  }

  /// [반응형 대응] 헤더 영역
  Widget _buildHeader({required bool isDark, required bool isSmall}) {
    final Color titleColor = AppTheme.dataColor(isDark);

    // 모바일/작은 태블릿에서는 헤더를 위아래로 나눔
    if (isSmall && MediaQuery.of(context).size.width < 700) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("실시간 감지 모니터링", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: titleColor, fontSize: 24, fontWeight: FontWeight.w700)),
              IconButton(onPressed: widget.onDismiss, icon: const Icon(Icons.close_rounded, size: 32)),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTestButton(isSmall: true),
                const SizedBox(width: 12),
                _buildModeSwitcher(isDark: isDark),
              ],
            ),
          )
        ],
      );
    }

    // 일반 키오스크/데스크톱 헤더
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: isDark ? Colors.white12 : AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.sensor_door_outlined, color: isDark ? Colors.white : AppTheme.primary, size: isSmall ? 28 : 36),
            ),
            const SizedBox(width: 20),
            Text("실시간 감지 모니터링", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: titleColor, fontSize: isSmall ? 24 : 32, fontWeight: FontWeight.w700)),
          ],
        ),
        Row(
          children: [
            if (!isSmall) ...[
              _buildTestButton(isSmall: false),
              const SizedBox(width: 24),
              _buildModeSwitcher(isDark: isDark),
              const SizedBox(width: 24),
              _buildRequireWorkerToggle(isDark: isDark),
              const SizedBox(width: 24),
              _buildStandbyToggle(isDark: isDark),
            ],
            const SizedBox(width: 32),
            Text(_currentTime.split('   ').last, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: titleColor, fontSize: isSmall ? 20 : 28, fontWeight: AppTheme.weightMenu)),
            const SizedBox(width: 24),
            IconButton(onPressed: widget.onDismiss, icon: const Icon(Icons.close_rounded, size: 36))
          ],
        ),
      ],
    );
  }

  /// [반응형 대응] 요약 바 영역
  Widget _buildSummaryBar({required bool isDark, required bool isSmall}) {
    final bool isExtremeSmall = MediaQuery.of(context).size.width < 700;

    // 모바일에서는 2x2 그리드 형태로 표시
    if (isExtremeSmall) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : AppTheme.silver.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildSummaryItem(label: _currentScanMode == GateScanMode.personnelOnly ? "전일잔류" : "전일재고", count: _currentScanMode == GateScanMode.personnelOnly ? _prevDayStay : _prevDayStock, isDark: isDark, isSmall: true)),
                Expanded(child: _buildSummaryItem(label: _currentScanMode == GateScanMode.personnelOnly ? "당일입장" : "당일입고", count: _currentScanMode == GateScanMode.personnelOnly ? _todayEntry : _todayIn, isDark: isDark, isSmall: true, color: AppTheme.success)),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(child: _buildSummaryItem(label: _currentScanMode == GateScanMode.personnelOnly ? "당일퇴장" : "당일출고", count: _currentScanMode == GateScanMode.personnelOnly ? _todayExit : _todayOut, isDark: isDark, isSmall: true, color: Colors.orange.shade700)),
                Expanded(child: _buildSummaryItem(label: _currentScanMode == GateScanMode.personnelOnly ? "현재잔류" : "현재재고", count: _currentScanMode == GateScanMode.personnelOnly ? _currentStay : _currentStock, isDark: isDark, isSmall: true, color: AppTheme.primary, isHighlight: true)),
              ],
            ),
          ],
        ),
      );
    }

    // 일반 가로형 요약 바
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(color: isDark ? Colors.white12 : AppTheme.silver.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? Colors.white10 : Colors.black12)),
        child: Row(
          children: [
            Expanded(child: _buildSummaryItem(label: "전일", count: _currentScanMode == GateScanMode.personnelOnly ? _prevDayStay : _prevDayStock, isDark: isDark, isSmall: isSmall)),
            Expanded(child: _buildSummaryItem(label: "당일입", count: _currentScanMode == GateScanMode.personnelOnly ? _todayEntry : _todayIn, isDark: isDark, isSmall: isSmall, color: AppTheme.success)),
            Expanded(child: _buildSummaryItem(label: "당일출", count: _currentScanMode == GateScanMode.personnelOnly ? _todayExit : _todayOut, isDark: isDark, isSmall: isSmall, color: Colors.orange.shade700)),
            Expanded(child: _buildSummaryItem(label: "현재", count: _currentScanMode == GateScanMode.personnelOnly ? _currentStay : _currentStock, isDark: isDark, isSmall: isSmall, color: AppTheme.primary, isHighlight: true)),
          ],
        )
    );
  }

  Widget _buildSummaryItem({required String label, required int count, required bool isDark, Color color = Colors.blueGrey, bool isHighlight = false, bool isSmall = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: isSmall ? 12 : 14, color: isHighlight ? color : AppTheme.labelColor(isDark))),
        Text(count.toString(), style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: isSmall ? 20 : 28, fontWeight: FontWeight.w700, color: isHighlight ? color : AppTheme.dataColor(isDark))),
      ],
    );
  }

  /// [반응형 대응] 하단 액션 패널
  Widget _buildAutoSaveActionPanel({required bool isDark, required ThemeData theme, required bool isSmall}) {
    final bool canSave = _canSave;
    final bool isPhone = MediaQuery.of(context).size.width < 700;

    return Container(
      padding: EdgeInsets.all(isSmall ? 16 : 24),
      decoration: BoxDecoration(
        color: canSave ? (isDark ? const Color(0xFF1E293B) : Colors.white) : AppTheme.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: canSave ? Colors.white10 : AppTheme.danger, width: 2),
      ),
      child: isPhone
          ? Column(
        children: [
          Text(canSave ? "$_autoSaveCountdown초 후 자동 저장" : "인식된 작업자 없음!", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: canSave ? AppTheme.dataColor(isDark) : AppTheme.danger)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(onPressed: _executeCancelAndClear, icon: const Icon(Icons.refresh, color: AppTheme.danger)),
              ElevatedButton(onPressed: canSave ? _executeSaveAndClear : null, child: const Text("확정")),
            ],
          )
        ],
      )
          : Row(
        children: [
          CircularProgressIndicator(value: _autoSaveCountdown / _autoSaveDurationSeconds),
          const SizedBox(width: 20),
          Expanded(child: Text(canSave ? "$_autoSaveCountdown초 후 자동 저장됩니다." : "보안 경고: 신원을 확인해 주세요!", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          OutlinedButton(onPressed: _executeCancelAndClear, child: const Text("취소")),
          const SizedBox(width: 12),
          ElevatedButton(onPressed: canSave ? _executeSaveAndClear : null, child: const Text("즉시 확정")),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // [공통 컴포넌트들]
  // ---------------------------------------------------------------------------

  Widget _buildModeSwitcher({required bool isDark, bool forceWhiteText = false}) {
    return Container(
      decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.black12, borderRadius: BorderRadius.circular(30)),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeBtn(GateScanMode.personnelOnly, "인원", isDark, forceWhiteText),
          _buildModeBtn(GateScanMode.itemWorkerMatch, "매칭", isDark, forceWhiteText),
        ],
      ),
    );
  }

  Widget _buildModeBtn(GateScanMode mode, String label, bool isDark, bool forceWhite) {
    bool isSel = _currentScanMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _currentScanMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: isSel ? AppTheme.primary : Colors.transparent, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(color: isSel ? Colors.white : (forceWhite ? Colors.white70 : Colors.black54), fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildTestButton({required bool isSmall}) {
    return ElevatedButton.icon(
      onPressed: _simulateNewDetection,
      icon: const Icon(Icons.sensors, size: 18),
      label: Text(isSmall ? "테스트" : "시뮬레이터"),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: EdgeInsets.symmetric(horizontal: isSmall ? 12 : 16, vertical: 12)),
    );
  }

  Widget _buildRequireWorkerToggle({required bool isDark, bool forceWhiteText = false}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text("인원필수", style: TextStyle(color: forceWhiteText ? Colors.white : AppTheme.labelColor(isDark), fontSize: 14)),
      Switch(value: _requireWorkerMatch, onChanged: (v) => setState(() => _requireWorkerMatch = v)),
    ]);
  }

  Widget _buildStandbyToggle({required bool isDark, bool forceWhiteText = false}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text("대기화면", style: TextStyle(color: forceWhiteText ? Colors.white : AppTheme.labelColor(isDark), fontSize: 14)),
      Switch(value: _useStandbyMode, onChanged: (v) => setState(() => _useStandbyMode = v)),
    ]);
  }
}

/// ---------------------------------------------------------------------------
/// [로그 카드 위젯 - 반응형 대응]
/// ---------------------------------------------------------------------------
class _LogCardWidget extends StatelessWidget {
  final DetectionModel log; final bool isDark; final ThemeData theme; final bool isWarning; final bool isSmall;
  const _LogCardWidget({required this.log, required this.isDark, required this.theme, required this.isWarning, required this.isSmall});

  @override
  Widget build(BuildContext context) {
    final bool isMatched = log.type == 'matched';
    final Color statusColor = isWarning ? AppTheme.danger : (log.isEntry ? AppTheme.success : Colors.orange.shade700);

    return Container(
      padding: EdgeInsets.all(isSmall ? 16 : 24),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: isSmall ? 24 : 32, backgroundImage: log.imageUrl.isNotEmpty ? NetworkImage(log.imageUrl) : null, child: log.imageUrl.isEmpty ? const Icon(Icons.person) : null),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(log.content, style: TextStyle(fontSize: isSmall ? 20 : 26, fontWeight: FontWeight.bold)),
                    Text(log.spot, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: statusColor)),
                child: Text(log.status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
              )
            ],
          ),
          if (isMatched && log.items.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text("📦 감지 물품: ${log.items.length}건", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: isSmall ? 100 : 150,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: log.items.length,
                itemBuilder: (context, i) => Container(
                  width: isSmall ? 80 : 120,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      Expanded(child: Image.network(log.items[i]['image'] ?? '', fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(Icons.inventory))),
                      Text(log.items[i]['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            )
          ]
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// [공지사항 흐르는 텍스트 - 반응형 대응]
/// ---------------------------------------------------------------------------
class _MarqueeWidget extends StatefulWidget {
  final String text; final Color backgroundColor; final Color textColor; final bool forceDarkShadow; final bool isSmall;
  const _MarqueeWidget({required this.text, required this.backgroundColor, required this.textColor, this.forceDarkShadow = false, required this.isSmall});
  @override State<_MarqueeWidget> createState() => _MarqueeWidgetState();
}

class _MarqueeWidgetState extends State<_MarqueeWidget> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 25))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return Container(
        color: widget.backgroundColor,
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: ClipRect(
            child: LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedBuilder(
                      animation: _c,
                      builder: (context, child) {
                        final double offset = constraints.maxWidth - (_c.value * (constraints.maxWidth + 2000));
                        return Transform.translate(offset: Offset(offset, 0), child: child);
                      },
                      child: Text(widget.text, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: widget.textColor, fontSize: widget.isSmall ? 18 : 26, fontWeight: FontWeight.bold, shadows: widget.forceDarkShadow ? const [Shadow(color: Colors.black, blurRadius: 10)] : null), maxLines: 1, softWrap: false)
                  );
                }
            )
        )
    );
  }
}