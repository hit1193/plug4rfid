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
/// [실시간 입/출고 감시 키오스크 화면]
///
/// [Linter 대응 및 최종 안정화 버전]
/// 1. 모든 조건문(if)에 중괄호 블록을 적용하여 논리적 명확성을 확보했습니다.
/// 2. 문자열 결합 시 보간법(Interpolation)을 사용하여 플러터 권장사항을 준수했습니다.
/// 3. 리스트뷰 부모 컨테이너 하단에 20px 여백을 적용하여 미니멀 디자인을 완성했습니다.
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

  final String _noticeText =
      "[사내 공지] 2026년 상반기 정기 재물조사가 다음 주 월요일부터 시작됩니다. 각 부서 자산관리자는 RFID 태그 부착 상태를 점검해 주시기 바랍니다.   *** [안전 수칙] 물류 창고 진입 시 반드시 안전모를 착용해 주십시오.";

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

    // 화면 로드 시 즉시 데이터를 가져오고 실시간 감시를 시작합니다.
    _fetchSummaryData();
    _initRealtimeSubscription();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _standbyTimer?.cancel();
    _slideshowTimer?.cancel();
    _autoSaveTimer?.cancel();

    // 화면 종료 시 구독을 해제하여 메모리 누수를 방지합니다.
    try {
      pb.realtime.unsubscribe('');
    } catch (_) {
      // 해제 시 에러는 묵인합니다.
    }

    super.dispose();
  }

  /// ---------------------------------------------------------------------------
  /// [비즈니스 로직 - DB 연동] 서버에서 통계용 데이터를 가져와 계산합니다.
  /// ---------------------------------------------------------------------------
  Future<void> _fetchSummaryData() async {
    try {
      final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // 1. 인원 통계 산출 로직
      int tIn = 0;
      int tOut = 0;
      int cStay = 0;

      try {
        final userRecords = await pb.collection('users').getFullList();
        for (var record in userRecords) {
          final meta = record.data['metadata'] as Map<String, dynamic>? ?? {};
          final lastType = meta['last_access_type']?.toString() ?? '';
          final lastTime = meta['last_access_time']?.toString() ?? '';

          if (lastTime.startsWith(todayStr)) {
            if (lastType == '입장') {
              tIn++;
            } else if (lastType == '퇴장') {
              tOut++;
            }
          }
          if (lastType == '입장') {
            cStay++;
          }
        }
      } catch (e) {
        debugPrint("User 통계 에러: $e");
      }

      // 2. 물품 통계 산출 로직
      int totalStock = 0;
      int itemIn = 0;
      int itemOut = 0;

      try {
        final prodRecords = await pb.collection('products').getFullList();
        for (var p in prodRecords) {
          totalStock += (p.data['stock_count'] as int?) ?? 1;
        }
      } catch (e) {
        debugPrint("Product 통계 에러: $e");
      }

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
          if (itemsDynamic is List) {
            itemsCount = itemsDynamic.length;
          } else if (itemsDynamic is String) {
            itemsCount = (jsonDecode(itemsDynamic) as List).length;
          }

          if (isEntry) {
            itemIn += itemsCount;
          } else {
            itemOut += itemsCount;
          }
        }
      } catch (e) {
        debugPrint("Detection 통계 에러: $e");
      }

      if (mounted) {
        setState(() {
          _todayEntry = tIn;
          _todayExit = tOut;
          _currentStay = cStay;
          _prevDayStay = _currentStay - _todayEntry + _todayExit;

          _todayIn = itemIn;
          _todayOut = itemOut;
          _currentStock = totalStock;
          _prevDayStock = _currentStock - _todayIn + _todayOut;
        });
      }
    } catch (e) {
      debugPrint("집계 로드 실패: $e");
    }
  }

  /// ---------------------------------------------------------------------------
  /// [비즈니스 로직 - 실시간 소켓]
  /// subscribe 호출 시 동기적으로 나열하여 Batch 방식으로 404 에러를 방지합니다.
  /// ---------------------------------------------------------------------------
  void _initRealtimeSubscription() {
    try {
      pb.realtime.unsubscribe('');

      // 묶음 호출(Batch)을 통해 Client ID 생성 레이스 컨디션을 해결합니다.
      pb.collection('users').subscribe('*', (e) {
        if (mounted) {
          _fetchSummaryData();
        }
      });
      pb.collection('detections').subscribe('*', (e) {
        if (mounted) {
          _fetchSummaryData();
        }
      });
      pb.collection('products').subscribe('*', (e) {
        if (mounted) {
          _fetchSummaryData();
        }
      });

      debugPrint("✅ 실시간 SSE 구독 설정 완료 (Batch 모드)");
    } catch (e) {
      debugPrint("❌ 실시간 구독 중 에러: $e");
    }
  }

  /// 저장 버튼 활성화 여부를 판별합니다.
  bool get _canSave {
    if (_realtimeLogs.isEmpty) {
      return false;
    }
    if (!_requireWorkerMatch) {
      return true;
    }
    return _realtimeLogs.first.content != '미인식 작업자';
  }

  /// 서버 시간과의 동기화 로직 (보정값이 필요할 때 사용)
  Future<void> _syncServerTime() async {
    try {
      setState(() {
        _timeOffset = Duration.zero;
      });
    } catch (e) {
      debugPrint("서버 시간 동기화 실패: $e");
    }
  }

  /// 실시간 시계 업데이트 핸들러
  void _updateClock() {
    final DateTime now = DateTime.now().add(_timeOffset);
    const List<String> weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    if (mounted) {
      setState(() {
        _currentTime = "${now.year}년 ${now.month.toString().padLeft(2, '0')}월 ${now.day.toString().padLeft(2, '0')}일 (${weekdays[now.weekday - 1]})   ${now.hour.toString().padLeft(2, '0')} : ${now.minute.toString().padLeft(2, '0')} : ${now.second.toString().padLeft(2, '0')}";
      });
    }
  }

  /// 일정 시간 미사용 시 대기화면으로 전환하는 타이머를 초기화합니다.
  void _resetStandbyTimer() {
    _standbyTimer?.cancel();
    if (_useStandbyMode && _realtimeLogs.isEmpty) {
      _standbyTimer = Timer(Duration(seconds: _standbyTimeoutSeconds), () {
        if (mounted) {
          setState(() {
            _isStandbyActive = true;
          });
        }
      });
    }
  }

  /// 감지 데이터 발생 시 자동 저장 카운트다운을 시작합니다.
  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _standbyTimer?.cancel();
    if (!_canSave) {
      setState(() {
        _autoSaveCountdown = _autoSaveDurationSeconds;
      });
      return;
    }
    setState(() {
      _autoSaveCountdown = _autoSaveDurationSeconds;
    });
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_autoSaveCountdown > 1) {
            _autoSaveCountdown--;
          } else {
            _executeSaveAndClear();
          }
        });
      }
    });
  }

  /// ---------------------------------------------------------------------------
  /// [핵심 로직] 감지 내역을 DB에 저장하고 인원의 상태를 업데이트합니다.
  /// ---------------------------------------------------------------------------
  Future<void> _executeSaveAndClear() async {
    _autoSaveTimer?.cancel();
    try {
      for (var log in _realtimeLogs) {
        final Map<String, dynamic> dbRecord = log.toJson();
        // PocketBase 날짜 규격(Z)을 명시적으로 맞춰줍니다.
        dbRecord['timestamp'] = "${log.timestamp.toUtc().toString().replaceAll('T', ' ')}Z";
        await pb.collection('detections').create(body: dbRecord);

        // 실시간 인원 상태(metadata) 동기화 처리
        final userRecords = await pb.collection('users').getList(
            filter: 'name = "${log.content}"',
            perPage: 1
        );
        if (userRecords.items.isNotEmpty) {
          final userRecord = userRecords.items.first;
          final Map<String, dynamic> meta = Map<String, dynamic>.from(userRecord.data['metadata'] ?? {});

          String accessType;
          if (log.type == 'person') {
            accessType = log.status.contains('퇴장') ? '퇴장' : '입장';
          } else {
            accessType = log.isEntry ? '입장' : '퇴장';
          }

          meta['last_access_type'] = accessType;
          meta['last_access_time'] = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

          await pb.collection('users').update(userRecord.id, body: {'metadata': meta});
        }
      }
    } catch (e) {
      debugPrint("❌ DB 연동 실패: $e");
    }

    if (mounted) {
      setState(() {
        _realtimeLogs.clear();
        if (_useStandbyMode) {
          _isStandbyActive = true;
        }
      });
      _resetStandbyTimer();
    }
  }

  /// 전체 취소 버튼 액션
  void _executeCancelAndClear() {
    _autoSaveTimer?.cancel();
    setState(() {
      _realtimeLogs.clear();
      if (_useStandbyMode) {
        _isStandbyActive = true;
      }
    });
    _resetStandbyTimer();
  }

  /// ---------------------------------------------------------------------------
  /// [시뮬레이터] RFID 태그 감지 상황을 재현합니다.
  /// ---------------------------------------------------------------------------
  void _simulateNewDetection() {
    if (_isStandbyActive) {
      _realtimeLogs.clear();
      _isStandbyActive = false;
    }
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
    setState(() {
      _realtimeLogs.insert(0, newLog);
    });
    _startAutoSaveTimer();
  }

  /// 물품만 감지되었을 때 수동으로 사원증 태그를 시뮬레이션합니다.
  void _simulatePersonTag() {
    if (_realtimeLogs.isNotEmpty && _realtimeLogs.first.content == '미인식 작업자') {
      final oldLog = _realtimeLogs.first;
      setState(() {
        _realtimeLogs[0] = DetectionModel(
            id: oldLog.id,
            type: oldLog.type,
            content: '홍길동 책임',
            imageUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?q=80&w=200',
            spot: oldLog.spot,
            status: '출고(작업)',
            isEntry: oldLog.isEntry,
            items: oldLog.items,
            timestamp: oldLog.timestamp
        );
      });
      _startAutoSaveTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          child: (_useStandbyMode && _isStandbyActive)
              ? _buildStandbyScreen(key: const ValueKey('standby_screen'), isDark: isDark)
              : _buildLogScreen(key: const ValueKey('log_screen'), isDark: isDark, theme: theme),
        ),
      ),
    );
  }

  Widget _buildModeSwitcher({required bool isDark, bool forceWhiteText = false}) {
    final Color activeBgColor = AppTheme.primary;
    final Color activeTextColor = Colors.white;
    final Color inactiveBgColor = forceWhiteText ? Colors.black.withValues(alpha: 0.4) : (isDark ? Colors.white12 : Colors.black12);
    final Color inactiveTextColor = forceWhiteText ? Colors.white70 : AppTheme.labelColor(isDark);

    return Container(
      decoration: BoxDecoration(color: inactiveBgColor, borderRadius: BorderRadius.circular(30)),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeBtn(GateScanMode.personnelOnly, "인원 전용", Icons.badge_outlined, activeBgColor, activeTextColor, inactiveTextColor),
          _buildModeBtn(GateScanMode.itemWorkerMatch, "물품·작업자 매칭", Icons.link_rounded, activeBgColor, activeTextColor, inactiveTextColor),
        ],
      ),
    );
  }

  Widget _buildModeBtn(GateScanMode mode, String label, IconData icon, Color activeBg, Color activeText, Color inactiveText) {
    bool isSelected = _currentScanMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentScanMode = mode;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(30)
        ),
        child: Row(
            children: [
              Icon(icon, size: 16, color: isSelected ? activeText : inactiveText),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightMenu, color: isSelected ? activeText : inactiveText))
            ]
        ),
      ),
    );
  }

  Widget _buildTestButton() {
    return ElevatedButton.icon(
      onPressed: _simulateNewDetection,
      icon: const Icon(Icons.sensors, color: Colors.white, size: 18),
      label: const Text("감지 시뮬레이터", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightOthers, color: Colors.white)),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade500, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0))),
    );
  }

  Widget _buildStandbyScreen({required Key key, required bool isDark}) {
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
          Positioned(
              top: 32,
              left: 32,
              child: Text(
                  _currentTime,
                  style: const TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: AppTheme.weightMenu,
                      letterSpacing: 2.0,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 8.0, offset: Offset(2, 2))]
                  )
              )
          ),
          Positioned(
              top: 32,
              right: 32,
              child: Row(
                  children: [
                    _buildTestButton(),
                    const SizedBox(width: 30),
                    _buildModeSwitcher(isDark: isDark, forceWhiteText: true),
                    const SizedBox(width: 30),
                    _buildRequireWorkerToggle(isDark: isDark, forceWhiteText: true),
                    const SizedBox(width: 30),
                    _buildStandbyToggle(isDark: isDark, forceWhiteText: true),
                    const SizedBox(width: 20),
                    IconButton(
                        onPressed: widget.onDismiss,
                        tooltip: "키오스크 모드 종료",
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 40, shadows: [Shadow(color: Colors.black87, blurRadius: 8.0, offset: Offset(2, 2))])
                    )
                  ]
              )
          ),
          Positioned(
              bottom: 30,
              left: 40,
              right: 40,
              child: _MarqueeWidget(text: _noticeText, backgroundColor: Colors.transparent, textColor: Colors.white, forceDarkShadow: true)
          ),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [서브 화면 2] 실시간 입출고 리스트 화면
  /// ---------------------------------------------------------------------------
  Widget _buildLogScreen({required Key key, required bool isDark, required ThemeData theme}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.all(32.0),
      child: Column(
        children: [
          _buildHeader(isDark: isDark),
          const SizedBox(height: 24),
          _buildSummaryBar(isDark: isDark),
          const SizedBox(height: 24),

          // [UI 개선사항 적용] 리스트뷰 부모 컨테이너(Container)에 하단 여백(margin: 20px) 추가
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 20.0), // <- 대표님 지시사항 적용
              child: _realtimeLogs.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sensor_door_rounded, size: 80, color: AppTheme.labelColor(isDark).withValues(alpha: 0.3)),
                    const SizedBox(height: 24),
                    Text(
                        "게이트 감지 대기 중입니다...",
                        style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 24, fontWeight: AppTheme.weightMenu, color: AppTheme.labelColor(isDark))
                    ),
                  ],
                ),
              )
                  : ListView.separated(
                itemCount: _realtimeLogs.length,
                separatorBuilder: (context, index) {
                  return const SizedBox(height: 24);
                },
                itemBuilder: (context, index) {
                  final DetectionModel log = _realtimeLogs[index];
                  final bool isWarning = log.content == '미인식 작업자' && _requireWorkerMatch;
                  return _LogCardWidget(
                      key: ValueKey('log_card_${log.timestamp.toIso8601String()}_$index'),
                      log: log,
                      isDark: isDark,
                      theme: theme,
                      isWarning: isWarning
                  );
                },
              ),
            ),
          ),

          if (_realtimeLogs.isNotEmpty) ...[
            _buildAutoSaveActionPanel(isDark: isDark, theme: theme),
          ]
        ],
      ),
    );
  }

  Widget _buildSummaryBar({required bool isDark}) {
    List<Widget> items = [];
    final Widget divider = Container(width: 1, height: 40, color: isDark ? Colors.white24 : Colors.black12);

    if (_currentScanMode == GateScanMode.personnelOnly) {
      items = [
        Expanded(child: _buildSummaryItem(icon: Icons.history_rounded, label: "전일잔류", count: _prevDayStay, color: Colors.blueGrey, isDark: isDark)),
        divider,
        Expanded(child: _buildSummaryItem(icon: Icons.login_rounded, label: "당일입장", count: _todayEntry, color: AppTheme.success, isDark: isDark)),
        divider,
        Expanded(child: _buildSummaryItem(icon: Icons.logout_rounded, label: "당일퇴장", count: _todayExit, color: Colors.orange.shade700, isDark: isDark)),
        divider,
        Expanded(child: _buildSummaryItem(icon: Icons.people_alt_rounded, label: "현재잔류", count: _currentStay, color: AppTheme.primary, isDark: isDark, isHighlight: true)),
      ];
    } else {
      items = [
        Expanded(child: _buildSummaryItem(icon: Icons.inventory_rounded, label: "전일재고", count: _prevDayStock, color: Colors.blueGrey, isDark: isDark)),
        divider,
        Expanded(child: _buildSummaryItem(icon: Icons.archive_rounded, label: "당일입고", count: _todayIn, color: AppTheme.success, isDark: isDark)),
        divider,
        Expanded(child: _buildSummaryItem(icon: Icons.unarchive_rounded, label: "당일출고", count: _todayOut, color: Colors.orange.shade700, isDark: isDark)),
        divider,
        Expanded(child: _buildSummaryItem(icon: Icons.inventory_2_rounded, label: "현재재고", count: _currentStock, color: AppTheme.primary, isDark: isDark, isHighlight: true)),
      ];
    }
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : AppTheme.silver.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? Colors.white12 : Colors.black12)),
        child: Row(children: items)
    );
  }

  Widget _buildSummaryItem({required IconData icon, required String label, required int count, required Color color, required bool isDark, bool isHighlight = false}) {
    return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: isHighlight ? 0.25 : 0.15), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 12),
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal, color: isHighlight ? color : AppTheme.labelColor(isDark))),
                Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(count.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) { return '${m[1]},'; }), style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 24, fontWeight: AppTheme.weightMenu, color: isHighlight ? color : AppTheme.dataColor(isDark))),
                      const SizedBox(width: 4),
                      Text(label.contains("재고") || label.contains("입고") || label.contains("출고") ? "건" : "명", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal, color: isHighlight ? color : AppTheme.labelColor(isDark))),
                    ]
                )
              ]
          )
        ]
    );
  }

  Widget _buildAutoSaveActionPanel({required bool isDark, required ThemeData theme}) {
    final bool canSave = _canSave;
    final Color panelBg = canSave ? (isDark ? const Color(0xFF1E293B) : Colors.white) : AppTheme.danger.withValues(alpha: 0.08);
    final Color borderColor = canSave ? (isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1)) : AppTheme.danger.withValues(alpha: 0.3);
    final Color textColor = canSave ? AppTheme.dataColor(isDark) : AppTheme.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
      decoration: BoxDecoration(color: panelBg, borderRadius: BorderRadius.circular(16.0), border: Border.all(color: borderColor, width: canSave ? 1.5 : 2.0), boxShadow: [BoxShadow(color: canSave ? Colors.black.withValues(alpha: isDark ? 0.2 : 0.08) : AppTheme.danger.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 4))]),
      child: Row(
        children: [
          SizedBox(
              width: 54,
              height: 54,
              child: canSave
                  ? Stack(fit: StackFit.expand, children: [CircularProgressIndicator(value: (_autoSaveCountdown / _autoSaveDurationSeconds), backgroundColor: AppTheme.silver.withValues(alpha: 0.2), color: AppTheme.primary, strokeWidth: 7), Center(child: Text("$_autoSaveCountdown", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 20, fontWeight: FontWeight.w900, color: textColor)))])
                  : const Center(child: Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 40))
          ),
          const SizedBox(width: 24),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(canSave ? "$_autoSaveCountdown초 후 내역이 시스템에 자동 저장됩니다." : "보안 경고: 인식된 작업자가 없습니다!", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 24, fontWeight: AppTheme.weightMenu, color: textColor)),
                    const SizedBox(height: 4),
                    Text(canSave ? "물품 수량 및 인식 오류 시 '전체 취소' 후 다시 태그해 주세요." : "물품 유출이 의심됩니다. 즉시 사원증을 태그하여 신원을 확인해 주세요.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 17, fontWeight: AppTheme.weightOthers, color: canSave ? AppTheme.labelColor(isDark) : AppTheme.danger.withValues(alpha: 0.8)))
                  ]
              )
          ),
          Row(
              children: [
                if (!canSave) ...[
                  ElevatedButton.icon(
                      onPressed: _simulatePersonTag,
                      icon: const Icon(Icons.badge, size: 20),
                      label: const Text("사원증 태그 (테스트)"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), textStyle: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.bold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))
                  ),
                  const SizedBox(width: 12)
                ],
                OutlinedButton.icon(
                    onPressed: _executeCancelAndClear,
                    icon: const Icon(Icons.refresh_rounded, size: 24),
                    label: const Text("전체 취소"),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger, side: const BorderSide(color: AppTheme.danger, width: 2), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18), textStyle: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 18, fontWeight: AppTheme.weightMenu), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                    onPressed: canSave ? _executeSaveAndClear : null,
                    icon: const Icon(Icons.save_rounded, size: 24, color: Colors.white),
                    label: Text(canSave ? "즉시 확정" : "저장 불가"),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, disabledBackgroundColor: Colors.grey.shade400, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18), textStyle: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 18, fontWeight: AppTheme.weightMenu), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))
                )
              ]
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({required bool isDark}) {
    final Color titleColor = AppTheme.dataColor(isDark);
    final Color subColor = AppTheme.labelColor(isDark);
    return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
              children: [
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.1) : AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.sensor_door_outlined, color: isDark ? Colors.white : AppTheme.primary, size: 36)),
                const SizedBox(width: 20),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("RFID GATE MONITOR", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: subColor, fontSize: 16, fontWeight: AppTheme.weightMenu, letterSpacing: 2.0)), Text("실시간 게이트 모니터링", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: titleColor, fontSize: 32, fontWeight: FontWeight.w900))])
              ]
          ),
          Row(
              children: [
                _buildTestButton(),
                const SizedBox(width: 30),
                _buildModeSwitcher(isDark: isDark),
                const SizedBox(width: 30),
                _buildRequireWorkerToggle(isDark: isDark),
                const SizedBox(width: 30),
                _buildStandbyToggle(isDark: isDark),
                const SizedBox(width: 40),
                Text(_currentTime, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: titleColor, fontSize: 28, fontWeight: AppTheme.weightMenu, letterSpacing: 1.2)),
                const SizedBox(width: 40),
                IconButton(onPressed: widget.onDismiss, tooltip: "키오스크 모드 종료", icon: Icon(Icons.close_rounded, color: subColor, size: 40))
              ]
          ),
        ]
    );
  }

  Widget _buildRequireWorkerToggle({required bool isDark, bool forceWhiteText = false}) {
    final Color textColor = forceWhiteText ? (_requireWorkerMatch ? Colors.white : Colors.white70) : (_requireWorkerMatch ? AppTheme.dataColor(isDark) : AppTheme.labelColor(isDark));
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("인원 필수 감지", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: textColor, fontSize: 16, fontWeight: AppTheme.weightMenu, shadows: forceWhiteText ? const [Shadow(color: Colors.black87, blurRadius: 8.0, offset: Offset(1, 1))] : null)),
          const SizedBox(width: 8),
          Switch(
              value: _requireWorkerMatch,
              activeTrackColor: AppTheme.danger.withValues(alpha: 0.5),
              activeThumbColor: AppTheme.danger,
              onChanged: (v) {
                setState(() {
                  _requireWorkerMatch = v;
                  if (_canSave) {
                    if (_realtimeLogs.isNotEmpty) {
                      _startAutoSaveTimer();
                    }
                  } else {
                    _autoSaveTimer?.cancel();
                  }
                });
              }
          )
        ]
    );
  }

  Widget _buildStandbyToggle({required bool isDark, bool forceWhiteText = false}) {
    final Color textColor = forceWhiteText ? (_useStandbyMode ? Colors.white : Colors.white70) : (_useStandbyMode ? AppTheme.dataColor(isDark) : AppTheme.labelColor(isDark));
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("대기화면 모드", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: textColor, fontSize: 16, fontWeight: AppTheme.weightMenu, shadows: forceWhiteText ? const [Shadow(color: Colors.black87, blurRadius: 8.0, offset: Offset(1, 1))] : null)),
          const SizedBox(width: 8),
          Switch(
              value: _useStandbyMode,
              activeTrackColor: AppTheme.primary.withValues(alpha: 0.5),
              activeThumbColor: AppTheme.primary,
              onChanged: (v) {
                setState(() {
                  _useStandbyMode = v;
                  if (v) {
                    _resetStandbyTimer();
                  } else {
                    _standbyTimer?.cancel();
                    _isStandbyActive = false;
                  }
                });
              }
          )
        ]
    );
  }
}

class _LogCardWidget extends StatefulWidget {
  final DetectionModel log; final bool isDark; final ThemeData theme; final bool isWarning;
  const _LogCardWidget({super.key, required this.log, required this.isDark, required this.theme, this.isWarning = false});
  @override State<_LogCardWidget> createState() => _LogCardWidgetState();
}

class _LogCardWidgetState extends State<_LogCardWidget> {
  final ScrollController _sc = ScrollController();
  @override void dispose() { _sc.dispose(); super.dispose(); }
  Widget _buildImage(String? url, {required double size, bool isCircle = false}) {
    return Container(width: size, height: size, decoration: BoxDecoration(color: AppTheme.silver.withValues(alpha: 0.1), shape: isCircle ? BoxShape.circle : BoxShape.rectangle, borderRadius: isCircle ? null : BorderRadius.circular(10), border: Border.all(color: AppTheme.silver.withValues(alpha: 0.3), width: 1)), clipBehavior: Clip.hardEdge, child: url != null && url.isNotEmpty ? Image.network(url, fit: BoxFit.cover, errorBuilder: (c, e, s) { return Icon(isCircle ? Icons.person : Icons.inventory_2, color: AppTheme.silver, size: size * 0.6); }) : Icon(isCircle ? Icons.person_off : Icons.inventory_2, color: AppTheme.silver, size: size * 0.6));
  }
  @override Widget build(BuildContext context) {
    final bool isPerson = widget.log.type == 'person';
    final bool isMatched = widget.log.type == 'matched';
    final Color statusColor = widget.isWarning ? AppTheme.danger : (isPerson ? (widget.log.isEntry ? AppTheme.success : Colors.orange.shade700) : AppTheme.primary);
    final Color cardBg = widget.isWarning ? AppTheme.danger.withValues(alpha: 0.03) : (widget.theme.cardTheme.color ?? Colors.white);
    final Color cardBorder = widget.isWarning ? AppTheme.danger.withValues(alpha: 0.5) : (widget.isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1));
    return Container(
        decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(AppTheme.cardRadius), border: Border.all(color: (isMatched || isPerson) ? statusColor.withValues(alpha: 0.5) : cardBorder, width: (isMatched || isPerson) ? 3.0 : 1.5), boxShadow: (isMatched || isPerson) ? [BoxShadow(color: statusColor.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 2)] : null),
        padding: const EdgeInsets.all(32.0),
        child: isMatched
            ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                  children: [
                    _buildImage(widget.log.imageUrl, size: 64, isCircle: true),
                    const SizedBox(width: 20),
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: Row(
                            children: [
                              if (widget.isWarning) ...[const Icon(Icons.warning_rounded, color: AppTheme.danger, size: 20), const SizedBox(width: 8)],
                              Text(widget.isWarning ? "작업자 미인식 상태" : "작업 담당자: ${widget.log.content}", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: widget.isWarning ? AppTheme.danger : AppTheme.dataColor(widget.isDark), fontSize: 26, fontWeight: AppTheme.weightMenu))
                            ]
                        )
                    ),
                    const SizedBox(width: 20),
                    Icon(Icons.location_on_outlined, color: AppTheme.labelColor(widget.isDark), size: 22),
                    const SizedBox(width: 8),
                    Text(widget.log.spot, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: AppTheme.labelColor(widget.isDark), fontSize: 20, fontWeight: AppTheme.weightOthers)),
                    const Spacer(),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(30), border: Border.all(color: statusColor, width: 2.5)), child: Text(widget.log.status, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: statusColor, fontSize: 20, fontWeight: AppTheme.weightMenu)))
                  ]
              ),
              const SizedBox(height: 24),
              Divider(color: cardBorder, thickness: 2),
              const SizedBox(height: 24),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("📦 현재 감지된 물품 리스트", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, fontSize: 22, fontWeight: AppTheme.weightMenu)),
                          const SizedBox(height: 4),
                          Text(widget.isWarning ? "경고: 사원증 인식 없이 물품만 반출을 시도하고 있습니다." : "실제 소지하신 물품 개수와 아래 수량을 대조해 주세요.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: widget.isWarning ? AppTheme.danger : AppTheme.labelColor(widget.isDark), fontSize: 17, fontWeight: AppTheme.weightOthers))
                        ]
                    ),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text("Total", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: AppTheme.labelColor(widget.isDark), fontSize: 26, fontWeight: AppTheme.weightMenu)),
                          const SizedBox(width: 12),
                          Text("${widget.log.items.length}", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: statusColor, fontSize: 90, fontWeight: AppTheme.weightMenu, height: 1.0)),
                          const SizedBox(width: 8),
                          Text("Items", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: AppTheme.dataColor(widget.isDark), fontSize: 26, fontWeight: AppTheme.weightMenu))
                        ]
                    )
                  ]
              ),
              const SizedBox(height: 24),
              if (widget.log.items.isNotEmpty)
                Container(
                    height: 380, width: double.infinity,
                    decoration: BoxDecoration(color: widget.isDark ? Colors.black.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(15), border: Border.all(color: cardBorder.withValues(alpha: 0.5))),
                    child: Scrollbar(
                        controller: _sc,
                        thumbVisibility: false,
                        thickness: 10.0,
                        radius: const Radius.circular(10),
                        child: ListView.builder(
                            controller: _sc,
                            padding: const EdgeInsets.all(24),
                            shrinkWrap: true,
                            itemCount: widget.log.items.length,
                            itemBuilder: (context, idx) {
                              final item = widget.log.items[idx];
                              return Padding(
                                  padding: const EdgeInsets.only(bottom: 20.0),
                                  child: Row(
                                      children: [
                                        _buildImage(item['image'], size: 70),
                                        const SizedBox(width: 24),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(item['name'] ?? '알 수 없는 물품', style: TextStyle(fontFamily: AppTheme.fontPretendard, color: AppTheme.dataColor(widget.isDark), fontSize: 28, fontWeight: AppTheme.weightMenu)),
                                                  const SizedBox(height: 4),
                                                  Text("정상 감지 (Sequence No. ${idx + 1})", style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: AppTheme.success, fontSize: 16, fontWeight: AppTheme.weightOthers))
                                                ]
                                            )
                                        ),
                                        Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 36)
                                      ]
                                  )
                              );
                            }
                        )
                    )
                )
            ]
        )
            : Row(
            children: [
              _buildImage(widget.log.imageUrl, size: 80, isCircle: true),
              const SizedBox(width: 32),
              Expanded(flex: 5, child: Text(widget.log.content, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: widget.isWarning ? AppTheme.danger : AppTheme.dataColor(widget.isDark), fontSize: 34, fontWeight: AppTheme.weightMenu))),
              Expanded(flex: 5, child: Row(children: [Icon(Icons.location_on_outlined, color: AppTheme.labelColor(widget.isDark), size: 28), const SizedBox(width: 12), Expanded(child: Text(widget.log.spot, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: AppTheme.labelColor(widget.isDark), fontSize: 24, fontWeight: AppTheme.weightOthers), overflow: TextOverflow.ellipsis))])),
              Expanded(flex: 3, child: Center(child: Text(widget.log.formattedTime, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: AppTheme.labelColor(widget.isDark), fontSize: 26, fontWeight: AppTheme.weightMenu)))),
              SizedBox(width: 180, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(30), border: Border.all(color: statusColor, width: 2.5)), child: Text(widget.log.status, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: statusColor, fontSize: 22, fontWeight: AppTheme.weightMenu)))))
            ]
        )
    );
  }
}

class _MarqueeWidget extends StatefulWidget {
  final String text; final Color backgroundColor; final Color textColor; final bool forceDarkShadow;
  const _MarqueeWidget({required this.text, required this.backgroundColor, required this.textColor, this.forceDarkShadow = false});
  @override State<_MarqueeWidget> createState() => _MarqueeWidgetState();
}

class _MarqueeWidgetState extends State<_MarqueeWidget> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 25))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color shadowColor = widget.forceDarkShadow ? Colors.black87 : (isDark ? Colors.black87 : Colors.white70);
    return Container(
        color: widget.backgroundColor,
        padding: const EdgeInsets.symmetric(vertical: 20.0),
        child: ClipRect(
            child: LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedBuilder(
                      animation: _c,
                      builder: (context, child) {
                        final double offset = constraints.maxWidth - (_c.value * (constraints.maxWidth + 2000));
                        return Transform.translate(offset: Offset(offset, 0), child: child);
                      },
                      child: Text(widget.text, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: widget.textColor, fontSize: 26, fontWeight: AppTheme.weightMenu, letterSpacing: 1.5, shadows: [Shadow(color: shadowColor, blurRadius: 10.0, offset: const Offset(2, 2))]), maxLines: 1, softWrap: false)
                  );
                }
            )
        )
    );
  }
}