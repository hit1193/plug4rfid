import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:async';

// 상위 시스템에서 정의한 중앙 집중형 테마를 임포트합니다.
import '../theme/app_theme.dart';

/// RFID 게이트의 운영 모드를 정의하는 열거형입니다.
enum GateScanMode {
  personnelOnly, // 인원 출입 전용 모드
  itemWorkerMatch // 물품 + 작업자 매칭 모드
}

/// ---------------------------------------------------------------------------
/// [실시간 입/출고 감시 키오스크 화면]
/// 평소에는 미니멀한 대기화면(Standby)을 띄워두고,
/// RFID 감지가 발생하면 즉각적으로 입/출고 리스트 화면으로 전환됩니다.
///
/// [최종 업데이트 사항]
/// 1. 이미지 여백 제거: 이미지 프레임 내부의 여백(Padding)을 모두 없애서 꽉 찬 느낌을 주었습니다.
/// 2. 수량 폰트 최적화: 너무 두꺼웠던 수량 폰트를 w800(weightMenu)으로 유지합니다.
/// 3. 최상단 삽입(Push-down) 방식: 새로운 감지 내역이 최상단에 꽂히며 기존 내역을 밀어냅니다.
/// 4. 독립 스크롤러: 개별 로그 카드가 독립적인 ScrollController를 가져 충돌을 방지합니다.
/// ---------------------------------------------------------------------------
class KioskView extends StatefulWidget {
  /// 키오스크 모드를 종료하고 메인 화면으로 돌아가기 위한 콜백 함수입니다.
  final VoidCallback onDismiss;

  /// 생성자입니다. 위젯 트리의 성능 최적화를 위해 const 키워드를 사용합니다.
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
  // 초기 샘플 시연을 위해 리스트 화면이 활성화된 상태로 시작합니다.
  bool _isStandbyActive = false;

  final int _standbyTimeoutSeconds = 10;
  final int _autoSaveDurationSeconds = 10;
  int _autoSaveCountdown = 0;

  GateScanMode _currentScanMode = GateScanMode.itemWorkerMatch;

  // -------------------------------------------------------------------------
  // [슬라이드쇼 이미지 데이터]
  // -------------------------------------------------------------------------
  final List<String> _backgroundImages = [
    "https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?q=80&w=2000&auto=format&fit=crop",
    "https://images.unsplash.com/photo-1504328345606-18bbc8c9d7d1?q=80&w=2000&auto=format&fit=crop",
    "https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d?q=80&w=2000&auto=format&fit=crop",
  ];
  int _currentImageIndex = 0;

  final String _noticeText =
      "[사내 공지] 2026년 상반기 정기 재물조사가 다음 주 월요일부터 시작됩니다. 각 부서 자산관리자는 RFID 태그 부착 상태를 점검해 주시기 바랍니다.   *** [안전 수칙] 물류 창고 진입 시 반드시 안전모를 착용해 주십시오.";

  // -------------------------------------------------------------------------
  // [실시간 로그 데이터 - 시연용 샘플]
  // -------------------------------------------------------------------------
  final List<Map<String, dynamic>> _realtimeLogs = [
    {
      'type': 'matched',
      'content': '홍길동 책임',
      'imageUrl': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?q=80&w=200',
      'spot': 'B구역 1번 자재고 게이트',
      'status': '출고(대여)',
      'time': '13:15:22',
      'isEntry': false,
      'items': [
        {'name': '전동 드릴 (DEWALT-88)', 'image': 'https://images.unsplash.com/photo-1504148455328-c39c5ef21d29?q=80&w=200'},
        {'name': '산업용 태블릿 (G-Tab v4)', 'image': 'https://images.unsplash.com/photo-1544244015-0df4b3ffc6b0?q=80&w=200'},
        {'name': '검교정 키트 (SK-202)', 'image': 'https://images.unsplash.com/photo-1530124566582-a618bc2615ad?q=80&w=200'},
        {'name': '절연 장갑 L-size', 'image': 'https://images.unsplash.com/photo-1599408162162-6b0af444014e?q=80&w=200'},
        {'name': '휴대용 손전등 (Led-Pro)', 'image': 'https://images.unsplash.com/photo-1554734867-bf3c00a49371?q=80&w=200'},
      ]
    },
  ];

  @override
  void initState() {
    super.initState();
    _syncServerTime();

    // 1. 실시간 시계 타이머
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      _updateClock();
    });

    // 2. 초기 리스트가 존재할 경우 자동 저장 타이머 가동
    if (_realtimeLogs.isNotEmpty) {
      _startAutoSaveTimer();
    } else {
      _resetStandbyTimer();
    }

    // 3. 배경 슬라이드쇼 타이머
    _slideshowTimer = Timer.periodic(const Duration(seconds: 8), (Timer timer) {
      if (mounted && _useStandbyMode && _isStandbyActive) {
        setState(() {
          _currentImageIndex = (_currentImageIndex + 1) % _backgroundImages.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _standbyTimer?.cancel();
    _slideshowTimer?.cancel();
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  /// ---------------------------------------------------------------------------
  /// [비즈니스 로직] 서버 시간 동기화
  /// ---------------------------------------------------------------------------
  Future<void> _syncServerTime() async {
    try {
      setState(() {
        _timeOffset = Duration.zero;
      });
    } catch (e) {
      debugPrint("서버 시간 동기화 실패: $e");
    }
  }

  /// ---------------------------------------------------------------------------
  /// [비즈니스 로직] 시계 업데이트 (요일 포함)
  /// ---------------------------------------------------------------------------
  void _updateClock() {
    final DateTime now = DateTime.now().add(_timeOffset);
    final String yyyy = now.year.toString();
    final String mm = now.month.toString().padLeft(2, '0');
    final String dd = now.day.toString().padLeft(2, '0');
    final String hh = now.hour.toString().padLeft(2, '0');
    final String min = now.minute.toString().padLeft(2, '0');
    final String ss = now.second.toString().padLeft(2, '0');

    const List<String> weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final String weekdayStr = weekdays[now.weekday - 1];

    setState(() {
      _currentTime = "$yyyy년 $mm월 $dd일 ($weekdayStr)   $hh : $min : $ss";
    });
  }

  /// ---------------------------------------------------------------------------
  /// [비즈니스 로직] 무방비 상태 타이머 (대기화면 복귀)
  /// ---------------------------------------------------------------------------
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

  /// ---------------------------------------------------------------------------
  /// [비즈니스 로직] 자동 저장 카운트다운 타이머 시작
  /// ---------------------------------------------------------------------------
  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _standbyTimer?.cancel();
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
  /// [비즈니스 로직] 데이터 저장 완료 및 리스트 비우기
  /// ---------------------------------------------------------------------------
  void _executeSaveAndClear() {
    _autoSaveTimer?.cancel();
    debugPrint("======== 서버 자동 저장 실행 ========");
    debugPrint("저장 내역: ${_realtimeLogs.length}건");
    debugPrint("=================================");

    setState(() {
      _realtimeLogs.clear();
      if (_useStandbyMode) _isStandbyActive = true;
    });
    _resetStandbyTimer();
  }

  /// ---------------------------------------------------------------------------
  /// [비즈니스 로직] 감지 내역 취소 및 초기화
  /// ---------------------------------------------------------------------------
  void _executeCancelAndClear() {
    _autoSaveTimer?.cancel();
    setState(() {
      _realtimeLogs.clear();
      if (_useStandbyMode) _isStandbyActive = true;
    });
    _resetStandbyTimer();
  }

  /// ---------------------------------------------------------------------------
  /// [비즈니스 로직] 가상 RFID 감지 시뮬레이션
  /// ---------------------------------------------------------------------------
  void _simulateNewDetection() {
    if (_isStandbyActive) {
      _realtimeLogs.clear();
      _isStandbyActive = false;
    }

    final DateTime now = DateTime.now().add(_timeOffset);
    final String hh = now.hour.toString().padLeft(2, '0');
    final String min = now.minute.toString().padLeft(2, '0');
    final String ss = now.second.toString().padLeft(2, '0');

    Map<String, dynamic> newLog;

    if (_currentScanMode == GateScanMode.personnelOnly) {
      newLog = {
        'type': 'person',
        'content': '박개발 선임',
        'imageUrl': 'https://images.unsplash.com/photo-1599566150163-29194dcaad36?q=80&w=200',
        'spot': 'A구역 연구소 게이트',
        'status': '입고(출근)',
        'time': '$hh:$min:$ss',
        'isEntry': true,
        'items': <Map<String, String>>[]
      };
    } else {
      newLog = {
        'type': 'matched',
        'content': '홍길동 책임',
        'imageUrl': 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?q=80&w=200',
        'spot': 'B구역 2번 공정 게이트',
        'status': '출고(작업)',
        'time': '$hh:$min:$ss',
        'isEntry': false,
        'items': [
          {'name': '측정기 A-type', 'image': 'https://images.unsplash.com/photo-1581092160562-40aa08e78837?q=80&w=200'},
          {'name': '정비 바스켓 (L)', 'image': 'https://images.unsplash.com/photo-1532634896-26909d0d4b89?q=80&w=200'},
          {'name': '개인 공구함', 'image': 'https://images.unsplash.com/photo-1530124566582-a618bc2615ad?q=80&w=200'},
        ]
      };
    }

    setState(() {
      // 새로운 감지 데이터를 리스트 최상단(Index 0)에 삽입합니다.
      _realtimeLogs.insert(0, newLog);
    });

    _startAutoSaveTimer();
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
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          child: (_useStandbyMode && _isStandbyActive)
              ? _buildStandbyScreen(key: const ValueKey('standby_screen'), isDark: isDark)
              : _buildLogScreen(key: const ValueKey('log_screen'), isDark: isDark, theme: theme),
        ),
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [위젯 컴포넌트] 운영 모드 전환 UI
  /// ---------------------------------------------------------------------------
  Widget _buildModeSwitcher({required bool isDark, bool forceWhiteText = false}) {
    final Color activeBgColor = AppTheme.primary;
    final Color activeTextColor = Colors.white;
    final Color inactiveBgColor = forceWhiteText ? Colors.black.withValues(alpha: 0.4) : (isDark ? Colors.white12 : Colors.black12);
    final Color inactiveTextColor = forceWhiteText ? Colors.white70 : AppTheme.labelColor(isDark);

    return Container(
      decoration: BoxDecoration(
        color: inactiveBgColor,
        borderRadius: BorderRadius.circular(30),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _currentScanMode = GateScanMode.personnelOnly),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: _currentScanMode == GateScanMode.personnelOnly ? activeBgColor : Colors.transparent,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  Icon(Icons.badge_outlined, size: 16, color: _currentScanMode == GateScanMode.personnelOnly ? activeTextColor : inactiveTextColor),
                  const SizedBox(width: 8),
                  Text(
                    "인원 전용",
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      fontWeight: AppTheme.weightMenu,
                      color: _currentScanMode == GateScanMode.personnelOnly ? activeTextColor : inactiveTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _currentScanMode = GateScanMode.itemWorkerMatch),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: _currentScanMode == GateScanMode.itemWorkerMatch ? activeBgColor : Colors.transparent,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 18, color: _currentScanMode == GateScanMode.itemWorkerMatch ? activeTextColor : inactiveTextColor),
                  const SizedBox(width: 8),
                  Text(
                    "물품·작업자 매칭",
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      fontWeight: AppTheme.weightMenu,
                      color: _currentScanMode == GateScanMode.itemWorkerMatch ? activeTextColor : inactiveTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [위젯 컴포넌트] 감지 모드 테스트 버튼
  /// ---------------------------------------------------------------------------
  Widget _buildTestButton() {
    return ElevatedButton.icon(
      onPressed: _simulateNewDetection,
      icon: const Icon(Icons.sensors, color: Colors.white, size: 18),
      label: const Text(
        "감지 모드",
        style: TextStyle(
          fontFamily: AppTheme.fontPretendard,
          fontWeight: AppTheme.weightOthers,
          color: Colors.white,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.teal.shade500,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [서브 화면 1] 대기화면 (사진 원본 노출)
  /// ---------------------------------------------------------------------------
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
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const ColoredBox(color: Color(0xFF121826));
                },
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
                shadows: [
                  Shadow(color: Colors.black87, blurRadius: 8.0, offset: Offset(2, 2)),
                ],
              ),
            ),
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
                _buildStandbyToggle(isDark: isDark, forceWhiteText: true),
                const SizedBox(width: 20),
                IconButton(
                  onPressed: widget.onDismiss,
                  tooltip: "키오스크 모드 종료",
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 40,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 8.0, offset: Offset(2, 2))],
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 30,
            left: 40,
            right: 40,
            child: _MarqueeWidget(
              text: _noticeText,
              backgroundColor: Colors.transparent,
              textColor: Colors.white,
              forceDarkShadow: true,
            ),
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
          const SizedBox(height: 32),

          Expanded(
            child: _realtimeLogs.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sensor_door_rounded, size: 80, color: AppTheme.labelColor(isDark).withValues(alpha: 0.3)),
                  const SizedBox(height: 24),
                  Text(
                    "게이트 감지 대기 중입니다...",
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      fontSize: 24,
                      fontWeight: AppTheme.weightMenu,
                      color: AppTheme.labelColor(isDark),
                    ),
                  ),
                ],
              ),
            )
                : ListView.separated(
              itemCount: _realtimeLogs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 24),
              itemBuilder: (context, index) {
                final Map<String, dynamic> log = _realtimeLogs[index];
                return _LogCardWidget(
                  key: ValueKey('log_card_${log['time']}_$index'),
                  log: log,
                  isDark: isDark,
                  theme: theme,
                );
              },
            ),
          ),

          if (_realtimeLogs.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildAutoSaveActionPanel(isDark: isDark, theme: theme),
          ]
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [위젯 컴포넌트] 하단 자동 저장 액션 패널
  /// ---------------------------------------------------------------------------
  Widget _buildAutoSaveActionPanel({required bool isDark, required ThemeData theme}) {
    final Color panelBgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color borderColor = isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1);
    final Color textColor = AppTheme.dataColor(isDark);
    final Color subTextColor = AppTheme.labelColor(isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
      decoration: BoxDecoration(
        color: panelBgColor,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: _autoSaveCountdown / _autoSaveDurationSeconds,
                  backgroundColor: AppTheme.silver.withValues(alpha: 0.2),
                  color: AppTheme.primary,
                  strokeWidth: 7,
                ),
                Center(
                  child: Text(
                    "$_autoSaveCountdown",
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "$_autoSaveCountdown초 후 내역이 시스템에 자동 저장됩니다.",
                  style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    fontSize: 24,
                    fontWeight: AppTheme.weightMenu,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "물품 수량 및 인식 오류 시 '전체 취소' 후 다시 태그해 주세요.",
                  style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    fontSize: 17,
                    fontWeight: AppTheme.weightOthers,
                    color: subTextColor,
                  ),
                ),
              ],
            ),
          ),

          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _executeCancelAndClear,
                icon: const Icon(Icons.refresh_rounded, size: 24),
                label: const Text("전체 취소 및 재인식"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: const BorderSide(color: AppTheme.danger, width: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  textStyle: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 18, fontWeight: AppTheme.weightMenu),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 16),

              ElevatedButton.icon(
                onPressed: _executeSaveAndClear,
                icon: const Icon(Icons.save_rounded, size: 24, color: Colors.white),
                label: const Text("즉시 확정 및 저장"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                  textStyle: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 18, fontWeight: AppTheme.weightMenu),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.sensor_door_outlined, color: isDark ? Colors.white : AppTheme.primary, size: 36),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "RFID GATE MONITOR",
                  style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    color: subColor,
                    fontSize: 16,
                    fontWeight: AppTheme.weightMenu,
                    letterSpacing: 2.0,
                  ),
                ),
                Text(
                  "실시간 게이트 모니터링",
                  style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    color: titleColor,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),

        Row(
          children: [
            _buildTestButton(),
            const SizedBox(width: 30),
            _buildModeSwitcher(isDark: isDark),
            const SizedBox(width: 30),
            _buildStandbyToggle(isDark: isDark),
            const SizedBox(width: 40),
            Text(
              _currentTime,
              style: TextStyle(
                fontFamily: AppTheme.fontPretendard,
                color: titleColor,
                fontSize: 28,
                fontWeight: AppTheme.weightMenu,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 40),
            IconButton(
              onPressed: widget.onDismiss,
              tooltip: "키오스크 모드 종료",
              icon: Icon(Icons.close_rounded, color: subColor, size: 40),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStandbyToggle({required bool isDark, bool forceWhiteText = false}) {
    final Color textColor = forceWhiteText
        ? (_useStandbyMode ? Colors.white : Colors.white70)
        : (_useStandbyMode ? AppTheme.dataColor(isDark) : AppTheme.labelColor(isDark));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "대기화면 모드",
          style: TextStyle(
            fontFamily: AppTheme.fontPretendard,
            color: textColor,
            fontSize: 16,
            fontWeight: AppTheme.weightMenu,
            shadows: forceWhiteText
                ? const [Shadow(color: Colors.black87, blurRadius: 8.0, offset: Offset(1, 1))]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: _useStandbyMode,
          activeTrackColor: AppTheme.primary.withValues(alpha: 0.5),
          activeThumbColor: AppTheme.primary,
          onChanged: (value) {
            setState(() {
              _useStandbyMode = value;
              if (value) {
                _resetStandbyTimer();
              } else {
                _standbyTimer?.cancel();
                _isStandbyActive = false;
              }
            });
          },
        ),
      ],
    );
  }
}

class _LogCardWidget extends StatefulWidget {
  final Map<String, dynamic> log;
  final bool isDark;
  final ThemeData theme;

  const _LogCardWidget({
    super.key,
    required this.log,
    required this.isDark,
    required this.theme,
  });

  @override
  State<_LogCardWidget> createState() => _LogCardWidgetState();
}

class _LogCardWidgetState extends State<_LogCardWidget> {
  final ScrollController _innerScrollController = ScrollController();

  @override
  void dispose() {
    _innerScrollController.dispose();
    super.dispose();
  }

  /// ---------------------------------------------------------------------------
  /// [이미지 위젯 보완] 대표님의 요청에 따라 안쪽 여백(Padding)을 완전히 없앴습니다.
  /// ---------------------------------------------------------------------------
  Widget _buildImage(String? url, {required double size, bool isCircle = false}) {
    return Container(
      width: size,
      height: size,
      // [수정] 대표님의 요청으로 안쪽 여백을 삭제(EdgeInsets.zero)했습니다.
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: AppTheme.silver.withValues(alpha: 0.1),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(10),
        border: Border.all(color: AppTheme.silver.withValues(alpha: 0.3), width: 1),
      ),
      clipBehavior: Clip.hardEdge,
      child: url != null && url.isNotEmpty
          ? Image.network(
        url,
        // [팁] BoxFit.cover를 사용하여 여백 없이 가득 채웁니다.
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(
            isCircle ? Icons.person : Icons.inventory_2,
            color: AppTheme.silver,
            size: size * 0.6
        ),
      )
          : Icon(
          isCircle ? Icons.person : Icons.inventory_2,
          color: AppTheme.silver,
          size: size * 0.6
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMatched = widget.log['type'] == 'matched';
    final bool isEntry = widget.log['isEntry'] == true;
    final Color statusColor = isEntry ? AppTheme.success : AppTheme.primary;

    final Color cardBgColor = widget.theme.cardTheme.color ?? Colors.white;
    final Color cardBorderColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.1);
    final Color mainTextColor = AppTheme.dataColor(widget.isDark);
    final Color subTextColor = AppTheme.labelColor(widget.isDark);

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: isMatched ? statusColor.withValues(alpha: 0.5) : cardBorderColor,
          width: isMatched ? 3.0 : 1.5,
        ),
        boxShadow: isMatched ? [
          BoxShadow(color: statusColor.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 2)
        ] : null,
      ),
      padding: const EdgeInsets.all(32.0),
      child: isMatched
          ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildImage(widget.log['imageUrl'], size: 64, isCircle: true),
              const SizedBox(width: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "작업 담당자: ${widget.log['content']}",
                  style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    color: mainTextColor,
                    fontSize: 26,
                    fontWeight: AppTheme.weightMenu,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Icon(Icons.location_on_outlined, color: subTextColor, size: 22),
              const SizedBox(width: 8),
              Text(
                widget.log['spot'],
                style: TextStyle(
                  fontFamily: AppTheme.fontPretendard,
                  color: subTextColor,
                  fontSize: 20,
                  fontWeight: AppTheme.weightOthers,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: statusColor, width: 2.5),
                ),
                child: Text(
                  widget.log['status'],
                  style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    color: statusColor,
                    fontSize: 20,
                    fontWeight: AppTheme.weightMenu,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          Divider(color: cardBorderColor, thickness: 2),
          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "📦 현재 감지된 물품 리스트",
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      color: Colors.grey,
                      fontSize: 22,
                      fontWeight: AppTheme.weightMenu,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "실제 소지하신 물품 개수와 아래 수량을 대조해 주세요.",
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      color: subTextColor,
                      fontSize: 17,
                      fontWeight: AppTheme.weightOthers,
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    "Total",
                    style: TextStyle(fontFamily: AppTheme.fontPretendard, color: subTextColor, fontSize: 26, fontWeight: AppTheme.weightMenu),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "${(widget.log['items'] as List).length}",
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      color: statusColor,
                      fontSize: 90,
                      fontWeight: AppTheme.weightMenu,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Items",
                    style: TextStyle(fontFamily: AppTheme.fontPretendard, color: mainTextColor, fontSize: 26, fontWeight: AppTheme.weightMenu),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          if (widget.log['items'] != null && (widget.log['items'] as List).isNotEmpty)
            Container(
              height: 380,
              width: double.infinity,
              decoration: BoxDecoration(
                color: widget.isDark ? Colors.black.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: cardBorderColor.withValues(alpha: 0.5)),
              ),
              child: Scrollbar(
                controller: _innerScrollController,
                thumbVisibility: false,
                thickness: 10.0,
                radius: const Radius.circular(10),
                child: ListView.builder(
                  controller: _innerScrollController,
                  padding: const EdgeInsets.all(24),
                  shrinkWrap: true,
                  itemCount: (widget.log['items'] as List).length,
                  itemBuilder: (context, itemIdx) {
                    final item = widget.log['items'][itemIdx];
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
                                Text(
                                  item['name'],
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontPretendard,
                                    color: mainTextColor,
                                    fontSize: 28,
                                    fontWeight: AppTheme.weightMenu,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "정상 감지 (Sequence No. ${itemIdx + 1})",
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontPretendard,
                                    color: AppTheme.success,
                                    fontSize: 16,
                                    fontWeight: AppTheme.weightOthers,
                                  ),
                                )
                              ],
                            ),
                          ),
                          Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 36),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      )
          : Row(
        children: [
          _buildImage(widget.log['imageUrl'], size: 80, isCircle: true),
          const SizedBox(width: 32),

          Expanded(
            flex: 5,
            child: Text(
              widget.log['content'],
              style: TextStyle(
                fontFamily: AppTheme.fontPretendard,
                color: mainTextColor,
                fontSize: 34,
                fontWeight: AppTheme.weightMenu,
              ),
            ),
          ),

          Expanded(
            flex: 5,
            child: Row(
              children: [
                Icon(Icons.location_on_outlined, color: subTextColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.log['spot'],
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      color: subTextColor,
                      fontSize: 24,
                      fontWeight: AppTheme.weightOthers,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            flex: 3,
            child: Center(
              child: Text(
                widget.log['time'],
                style: TextStyle(
                  fontFamily: AppTheme.fontPretendard,
                  color: subTextColor,
                  fontSize: 26,
                  fontWeight: AppTheme.weightMenu,
                ),
              ),
            ),
          ),

          SizedBox(
            width: 180,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: statusColor, width: 2.5),
                ),
                child: Text(
                  widget.log['status'],
                  style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    color: statusColor,
                    fontSize: 22,
                    fontWeight: AppTheme.weightMenu,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarqueeWidget extends StatefulWidget {
  final String text;
  final Color backgroundColor;
  final Color textColor;
  final bool forceDarkShadow;

  const _MarqueeWidget({
    super.key,
    required this.text,
    required this.backgroundColor,
    required this.textColor,
    this.forceDarkShadow = false,
  });

  @override
  State<_MarqueeWidget> createState() => _MarqueeWidgetState();
}

class _MarqueeWidgetState extends State<_MarqueeWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color shadowColor = widget.forceDarkShadow
        ? Colors.black87
        : (isDark ? Colors.black87 : Colors.white70);

    return Container(
      color: widget.backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final double moveOffset = constraints.maxWidth - (_controller.value * (constraints.maxWidth + 2000));
                return Transform.translate(
                  offset: Offset(moveOffset, 0),
                  child: child,
                );
              },
              child: Text(
                widget.text,
                style: TextStyle(
                  fontFamily: AppTheme.fontPretendard,
                  color: widget.textColor,
                  fontSize: 26,
                  fontWeight: AppTheme.weightMenu,
                  letterSpacing: 1.5,
                  shadows: [
                    Shadow(color: shadowColor, blurRadius: 10.0, offset: const Offset(2, 2)),
                  ],
                ),
                maxLines: 1,
                softWrap: false,
              ),
            );
          },
        ),
      ),
    );
  }
}