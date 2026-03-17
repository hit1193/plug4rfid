import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

// 데스크탑 환경에서 창 이동과 모니터 정보를 가져오기 위한 패키지
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
// 상태 관리 및 테마 즉각 반영을 위한 패키지 임포트
import 'package:provider/provider.dart';
// 로컬 PC의 폴더(디렉토리)를 열고 선택하기 위한 파일 픽커 패키지
import 'package:file_picker/file_picker.dart';

import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';

/// ---------------------------------------------------------------------------
/// [환경설정 페이지]
/// 데이터베이스(PocketBase) 서버 IP, ERP 연동 주소, 자동 동기화 주기 등
/// 앱 구동에 필요한 핵심 로컬 설정값들을 관리하는 화면입니다.
/// 키오스크 환경(장갑을 낀 상태 등)을 고려하여 큼직하고 직관적인 UI로 구성되었습니다.
/// ---------------------------------------------------------------------------
class SettingsPage extends StatefulWidget {
  final bool isMobile;

  const SettingsPage({
    super.key,
    required this.isMobile,
  });

  @override
  State<SettingsPage> createState() {
    return _SettingsPageState();
  }
}

class _SettingsPageState extends State<SettingsPage> {
  // ---------------------------------------------------------------------------
  // [상태 관리 변수]
  // ---------------------------------------------------------------------------
  bool _isLoading = true;

  // [1] 데이터베이스 및 서버 설정 (하이브리드 아키텍처 대응)
  bool _isOfflineMode = false; // 오프라인(로컬 망) 단독 동작 여부
  final TextEditingController _offlineCompanyCodeController = TextEditingController(); // 로컬 전용 회사코드
  final TextEditingController _dbUrlController = TextEditingController();

  // [2] ERP 연동 설정 (송수신 분리 적용)
  final TextEditingController _erpReceiveUrlController = TextEditingController();
  final TextEditingController _erpSendUrlController = TextEditingController();

  bool _autoSyncEnabled = false;
  int _syncIntervalMin = 10;

  // [3] 디스플레이 및 화면 동작 설정
  bool _isKioskModeDefault = false;

  // 테마 목록: 앱 전체 색상을 즉각적으로 변경할 수 있는 옵션들
  final List<Map<String, dynamic>> _themeOptions = [
    {'type': AppThemeType.pureWhite, 'color': Colors.white, 'label': '화이트'},
    {'type': AppThemeType.industrial, 'color': AppTheme.colorIndustrial, 'label': '블루'},
    {'type': AppThemeType.forest, 'color': AppTheme.colorForest, 'label': '그린'},
    {'type': AppThemeType.solar, 'color': AppTheme.colorSolar, 'label': '오렌지'},
    {'type': AppThemeType.midnight, 'color': const Color(0xFF1E293B), 'label': '다크'},
  ];
  int _selectedThemeIndex = 0;

  // 다중 모니터 정보 저장용 변수
  List<Display> _displays = [];
  String? _selectedDisplayId;

  // [4] 배경 이미지 폴더 설정
  final TextEditingController _bgImagePathController = TextEditingController();

  // [5] RFID 발급 옵션 설정
  String _tagBitOption = '96bit';

  // 🔥 [6] AI (Gemini) API Key 입력용 컨트롤러 추가
  final TextEditingController _geminiApiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  /// 메모리 누수를 방지하기 위해 화면이 닫힐 때 컨트롤러 자원을 해제합니다.
  @override
  void dispose() {
    _offlineCompanyCodeController.dispose();
    _dbUrlController.dispose();
    _erpReceiveUrlController.dispose();
    _erpSendUrlController.dispose();
    _bgImagePathController.dispose();
    _geminiApiKeyController.dispose(); // 🔥 해제 추가
    super.dispose();
  }

  /// 초기화 함수: 모니터 정보를 먼저 가져오고, 저장된 설정값들을 불러옵니다.
  Future<void> _initSettings() async {
    await _fetchDisplays();
    await _loadSettings();
  }

  /// ---------------------------------------------------------------------------
  /// [모니터 정보 조회] 시스템에 연결된 모든 디스플레이(모니터)를 열거합니다.
  /// ---------------------------------------------------------------------------
  Future<void> _fetchDisplays() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        final List<Display> displays = await screenRetriever.getAllDisplays();
        if (mounted) {
          setState(() {
            _displays = displays;
          });
        }
      } catch (e) {
        debugPrint("모니터 정보를 불러오는 중 오류 발생: $e");
      }
    }
  }

  /// ---------------------------------------------------------------------------
  /// [데이터 로드] 기기에 저장된 설정값 불러오기
  /// ---------------------------------------------------------------------------
  Future<void> _loadSettings() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      if (mounted) {
        setState(() {
          // 하이브리드 인증 설정을 불러옵니다.
          _isOfflineMode = prefs.getBool('pref_offline_mode') ?? false;
          _offlineCompanyCodeController.text = prefs.getString('pref_offline_company_code') ?? '';
          _dbUrlController.text = prefs.getString('pref_db_url') ?? 'http://127.0.0.1:8090';

          // 송수신 URL을 각각 불러옵니다. 기존에 저장된 값이 없다면 안전한 기본값을 제공합니다.
          _erpReceiveUrlController.text = prefs.getString('pref_erp_receive_url') ?? 'https://api.erp-system.com/v1/read';
          _erpSendUrlController.text = prefs.getString('pref_erp_send_url') ?? 'https://api.erp-system.com/v1/write';

          _autoSyncEnabled = prefs.getBool('pref_auto_sync') ?? false;
          _syncIntervalMin = prefs.getInt('pref_sync_interval') ?? 10;
          _isKioskModeDefault = prefs.getBool('pref_kiosk_default') ?? false;

          _selectedThemeIndex = prefs.getInt('pref_theme_index') ?? 0;
          _selectedDisplayId = prefs.getString('pref_display_id');

          _bgImagePathController.text = prefs.getString('pref_bg_image_path') ?? '';
          _tagBitOption = prefs.getString('pref_tag_bit_option') ?? '96bit';

          // 🔥 저장된 API 키 불러오기
          _geminiApiKeyController.text = prefs.getString('pref_gemini_api_key') ?? '';

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('설정 로드 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// ---------------------------------------------------------------------------
  /// [데이터 저장] 입력한 설정값을 기기에 영구 저장하기 및 모니터 이동 적용
  /// ---------------------------------------------------------------------------
  Future<void> _saveSettings() async {
    // 1. 필수값 검증 로직 (DB 주소는 무조건 있어야 함)
    if (_dbUrlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('데이터베이스 서버 주소는 필수입니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    // 2. 오프라인 모드일 경우 '회사코드' 필수 입력 검증 (데이터 태깅용)
    if (_isOfflineMode && _offlineCompanyCodeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('오프라인 모드 활성화 시, 향후 온라인 통합을 위해 로컬 회사코드는 필수입니다!', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // 서버 및 오프라인 아키텍처 저장
      await prefs.setBool('pref_offline_mode', _isOfflineMode);
      await prefs.setString('pref_offline_company_code', _offlineCompanyCodeController.text.trim());
      await prefs.setString('pref_db_url', _dbUrlController.text.trim());

      // 분리된 송수신 URL을 각각 저장합니다.
      await prefs.setString('pref_erp_receive_url', _erpReceiveUrlController.text.trim());
      await prefs.setString('pref_erp_send_url', _erpSendUrlController.text.trim());

      await prefs.setBool('pref_auto_sync', _autoSyncEnabled);
      await prefs.setInt('pref_sync_interval', _syncIntervalMin);
      await prefs.setBool('pref_kiosk_default', _isKioskModeDefault);
      await prefs.setInt('pref_theme_index', _selectedThemeIndex);

      await prefs.setString('pref_bg_image_path', _bgImagePathController.text.trim());
      await prefs.setString('pref_tag_bit_option', _tagBitOption);

      // 🔥 AI (Gemini) API Key 저장
      await prefs.setString('pref_gemini_api_key', _geminiApiKeyController.text.trim());

      if (_selectedDisplayId != null) {
        await prefs.setString('pref_display_id', _selectedDisplayId!);
      }

      // [모니터 즉각 이동] 선택된 모니터가 있다면 해당 모니터의 좌측 상단으로 앱 창을 이동시킵니다.
      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        if (_selectedDisplayId != null && _displays.isNotEmpty) {
          try {
            final Display targetDisplay = _displays.firstWhere((d) => d.id.toString() == _selectedDisplayId);
            final Offset targetPosition = targetDisplay.visiblePosition ?? const Offset(0, 0);
            await windowManager.setPosition(targetPosition);
          } catch (e) {
            debugPrint("모니터 이동 실패 (해당 모니터를 찾을 수 없음): $e");
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ 환경설정이 성공적으로 저장되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
          elevation: 0,
        ));
      }
    } catch (e) {
      debugPrint('설정 저장 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ 저장 실패: $e', style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
          backgroundColor: AppTheme.danger,
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 데이터베이스 서버와의 연결 상태를 점검하는 테스트 함수입니다.
  Future<void> _testDbConnection() async {
    final String targetUrl = _dbUrlController.text.trim();
    if (targetUrl.isEmpty) {
      return;
    }

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("서버 응답을 확인하는 중...", style: TextStyle(fontFamily: AppTheme.fontPretendard)),
              ],
            ),
          );
        }
    );

    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) {
      return;
    }

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✅ [$targetUrl] 접속 테스트 성공!', style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// ---------------------------------------------------------------------------
  /// [화면 렌더링] 메인 UI 구축
  /// ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    // 동적 테마 연동: 사용자가 선택한 테마의 주요 색상을 가져옵니다.
    final Color dynamicPrimary = theme.colorScheme.primary;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator(color: dynamicPrimary)),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopHeader(theme, isDark, dynamicPrimary),
          Divider(height: 1, color: theme.dividerTheme.color),

          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: widget.isMobile ? 16.0 : 32.0,
                top: widget.isMobile ? 16.0 : 32.0,
                right: widget.isMobile ? 16.0 : 32.0,
                bottom: (widget.isMobile ? 16.0 : 32.0) + 20.0, // 하단 여백 추가
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900), // 가독성을 위해 최대 너비를 제한합니다.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ----------------------------------------------------------------
                      // 섹션 1: 메인 서버 연결 설정 (오프라인 모드 포함)
                      // ----------------------------------------------------------------
                      _buildSectionCard(
                        title: "1. 메인 데이터베이스 및 동작 모드",
                        icon: Icons.dns_rounded,
                        theme: theme,
                        primaryColor: dynamicPrimary,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "앱이 데이터를 보관할 서버 환경과 동작 모드를 설정합니다.\n인터넷이 차단된 로컬 폐쇄망에서는 오프라인 모드를 활성화하십시오.",
                              style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5),
                            ),
                            const SizedBox(height: 20),

                            Container(
                              decoration: AppTheme.listItemDecoration(context, isSelected: _isOfflineMode, statusColor: dynamicPrimary),
                              child: SwitchListTile(
                                title: const Text("오프라인 (로컬 폐쇄망) 단독 구동", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
                                subtitle: const Text("마스터 클라우드 인증을 거치지 않고, 로컬 PocketBase DB에 직접 접속합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
                                value: _isOfflineMode,
                                activeThumbColor: dynamicPrimary,
                                activeTrackColor: dynamicPrimary.withValues(alpha: 0.4),
                                onChanged: (bool value) {
                                  setState(() {
                                    _isOfflineMode = value;
                                  });
                                },
                              ),
                            ),

                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              child: _isOfflineMode
                                  ? Padding(
                                padding: const EdgeInsets.only(top: 16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextField(
                                      controller: _offlineCompanyCodeController,
                                      style: AppTheme.itemValueStyle(context).copyWith(fontSize: 18),
                                      decoration: AppTheme.inputDecoration(
                                          label: "로컬 전용 회사코드 (필수)",
                                          context: context,
                                          prefixIcon: Icons.badge_rounded
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 4.0),
                                      child: Text(
                                        "💡 향후 온라인(구독형) 서비스로 데이터를 원활하게 이관(마이그레이션)하기 위해,\n오프라인 모드에서도 이 앱이 생성하는 모든 데이터에 해당 코드가 꼬리표처럼 기록됩니다.",
                                        style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 12, color: Colors.blueGrey, height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                                  : const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 24),

                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _dbUrlController,
                                    style: AppTheme.itemValueStyle(context).copyWith(fontSize: 18),
                                    decoration: AppTheme.inputDecoration(label: "서버 주소 (예: http://192.168.0.10:8090)", context: context, prefixIcon: Icons.link),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                SizedBox(
                                  height: 60,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.wifi_tethering),
                                    label: const Text("연결 테스트", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: dynamicPrimary,
                                      side: BorderSide(color: dynamicPrimary),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: _testDbConnection,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ----------------------------------------------------------------
                      // 섹션 2: ERP 연동 설정 (수신/송신 URL 분리)
                      // ----------------------------------------------------------------
                      _buildSectionCard(
                        title: "2. 외부 ERP 시스템 통신 설정",
                        icon: Icons.sync_alt_rounded,
                        theme: theme,
                        primaryColor: dynamicPrimary,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "거래처 또는 사내 ERP 시스템과 데이터를 주고받을 수신/송신 API 주소와 백그라운드 동기화 정책을 설정합니다.",
                              style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5),
                            ),
                            const SizedBox(height: 20),
                            // 수신 전용 URL 입력 필드
                            TextField(
                              controller: _erpReceiveUrlController,
                              style: AppTheme.itemValueStyle(context).copyWith(fontSize: 18),
                              decoration: AppTheme.inputDecoration(label: "수신용 API 주소 (데이터 조회용)", context: context, prefixIcon: Icons.download_rounded),
                            ),
                            const SizedBox(height: 16),
                            // 송신 전용 URL 입력 필드
                            TextField(
                              controller: _erpSendUrlController,
                              style: AppTheme.itemValueStyle(context).copyWith(fontSize: 18),
                              decoration: AppTheme.inputDecoration(label: "송신용 API 주소 (데이터 등록/수정용)", context: context, prefixIcon: Icons.upload_rounded),
                            ),
                            const SizedBox(height: 24),

                            Container(
                              decoration: AppTheme.listItemDecoration(context, isSelected: _autoSyncEnabled, statusColor: dynamicPrimary),
                              child: SwitchListTile(
                                title: const Text("백그라운드 자동 동기화 활성화", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
                                subtitle: const Text("앱을 켜두면 보이지 않는 곳에서 주기적으로 ERP 데이터를 수신하여 로컬에 업데이트합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
                                value: _autoSyncEnabled,
                                activeThumbColor: dynamicPrimary,
                                activeTrackColor: dynamicPrimary.withValues(alpha: 0.4),
                                onChanged: (bool value) {
                                  setState(() {
                                    _autoSyncEnabled = value;
                                  });
                                },
                              ),
                            ),

                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              child: _autoSyncEnabled
                                  ? Padding(
                                padding: const EdgeInsets.only(top: 20.0, left: 8, right: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("동기화 주기: $_syncIntervalMin 분마다 갱신", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: AppTheme.dataColor(isDark))),
                                    Slider(
                                      value: _syncIntervalMin.toDouble(),
                                      min: 1,
                                      max: 60,
                                      divisions: 59,
                                      activeColor: dynamicPrimary,
                                      label: '$_syncIntervalMin 분',
                                      onChanged: (double value) {
                                        setState(() {
                                          _syncIntervalMin = value.toInt();
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ----------------------------------------------------------------
                      // 섹션 3: 디스플레이 및 화면 동작 설정 (테마 및 모니터 선택 포함)
                      // ----------------------------------------------------------------
                      _buildSectionCard(
                        title: "3. 화면 표시 및 동작 설정",
                        icon: Icons.desktop_windows_rounded,
                        theme: theme,
                        primaryColor: dynamicPrimary,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("시스템 전체 테마 색상 변경", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 8),
                            const Text("앱 전체의 배경과 버튼, 데이터 포인트 색상을 즉시 변경합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
                            const SizedBox(height: 16),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: List.generate(_themeOptions.length, (index) {
                                  final option = _themeOptions[index];
                                  final Color color = option['color'];
                                  final String label = option['label'];
                                  final AppThemeType type = option['type'];
                                  final bool isSelected = _selectedThemeIndex == index;

                                  return GestureDetector(
                                    onTap: () async {
                                      setState(() {
                                        _selectedThemeIndex = index;
                                      });

                                      final SharedPreferences prefs = await SharedPreferences.getInstance();
                                      await prefs.setInt('pref_theme_index', index);

                                      if (mounted) {
                                        try {
                                          final themeProvider = context.read<ThemeProvider>();
                                          (themeProvider as dynamic).setTheme(type);
                                        } catch (e) {
                                          debugPrint("ThemeProvider 상태 갱신 오류: $e");
                                        }
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 20),
                                      child: Column(
                                        children: [
                                          Container(
                                            width: 56,
                                            height: 56,
                                            decoration: BoxDecoration(
                                                color: color,
                                                shape: BoxShape.circle,
                                                border: isSelected
                                                    ? Border.all(color: isDark ? Colors.white : Colors.black87, width: 3)
                                                    : Border.all(color: theme.dividerTheme.color ?? Colors.grey.withValues(alpha: 0.3), width: 1.5),
                                                boxShadow: [
                                                  if (isSelected)
                                                    BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2)
                                                ]
                                            ),
                                            child: isSelected
                                                ? Icon(Icons.check_rounded, color: color == Colors.white ? Colors.black87 : Colors.white, size: 28)
                                                : null,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                              label,
                                              style: TextStyle(
                                                  fontFamily: AppTheme.fontPretendard,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                  color: isSelected ? dynamicPrimary : Colors.grey
                                              )
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Divider(color: theme.dividerTheme.color?.withValues(alpha: 0.5)),
                            const SizedBox(height: 24),

                            if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ...[
                              const Text("기본 표시 모니터 설정", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 8),
                              const Text("다중 모니터 환경인 경우, 앱이 구동될 모니터를 지정할 수 있습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedDisplayId,
                                decoration: AppTheme.inputDecoration(label: "출력 대상 모니터", context: context),
                                items: [
                                  const DropdownMenuItem(
                                      value: null,
                                      child: Row(
                                        children: [
                                          Icon(Icons.desktop_windows_outlined, size: 20, color: Colors.grey),
                                          SizedBox(width: 8),
                                          Text("시스템 기본 모니터 사용 (OS 위임)", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w600)),
                                        ],
                                      )
                                  ),
                                  ..._displays.asMap().entries.map((entry) {
                                    final int index = entry.key + 1;
                                    final Display display = entry.value;
                                    final String name = display.name ?? '알 수 없는 디스플레이';
                                    final int width = display.size.width.toInt();
                                    final int height = display.size.height.toInt();

                                    return DropdownMenuItem(
                                      value: display.id.toString(),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.monitor, size: 20, color: Colors.blueGrey),
                                          const SizedBox(width: 8),
                                          Text("모니터 $index : $name ($width x $height)", style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                                onChanged: (String? val) {
                                  setState(() {
                                    _selectedDisplayId = val;
                                  });
                                },
                              ),
                              const SizedBox(height: 32),
                              Divider(color: theme.dividerTheme.color?.withValues(alpha: 0.5)),
                              const SizedBox(height: 24),
                            ],

                            Container(
                              decoration: AppTheme.listItemDecoration(context, isSelected: false, statusColor: Colors.grey),
                              child: SwitchListTile(
                                title: const Text("기본 화면을 키오스크(포스터) 모드로 시작", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
                                subtitle: const Text("앱이 실행될 때 관리자 목록이 아닌 꽉 찬 포스터 화면으로 자동 시작합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
                                value: _isKioskModeDefault,
                                activeThumbColor: Colors.blueGrey,
                                activeTrackColor: Colors.blueGrey.withValues(alpha: 0.4),
                                onChanged: (bool value) {
                                  setState(() {
                                    _isKioskModeDefault = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ----------------------------------------------------------------
                      // 섹션 4: 키오스크 배경 이미지 폴더 설정
                      // ----------------------------------------------------------------
                      _buildSectionCard(
                        title: "4. 키오스크 배경 이미지 롤링 설정",
                        icon: Icons.wallpaper_rounded,
                        theme: theme,
                        primaryColor: dynamicPrimary,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "키오스크 대기 화면에서 슬라이드쇼로 표시될 이미지가 담긴 로컬 폴더를 지정합니다.\n폴더를 지정하면 해당 폴더 내의 이미지들이 일정 시간마다 교체되며 화면에 그려집니다.",
                              style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _bgImagePathController,
                                    readOnly: true,
                                    style: AppTheme.itemValueStyle(context).copyWith(fontSize: 16),
                                    decoration: AppTheme.inputDecoration(label: "선택된 폴더 경로 (비어있으면 기본 테마 적용)", context: context, prefixIcon: Icons.folder_open),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                SizedBox(
                                  height: 60,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.search),
                                    label: const Text("폴더 찾아보기", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: dynamicPrimary,
                                      side: BorderSide(color: dynamicPrimary),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () async {
                                      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                                      if (selectedDirectory != null && mounted) {
                                        setState(() {
                                          _bgImagePathController.text = selectedDirectory;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ----------------------------------------------------------------
                      // 섹션 5: RFID 태그 발급(인코딩) 옵션 설정
                      // ----------------------------------------------------------------
                      _buildSectionCard(
                        title: "5. RFID 태그 발급(인코딩) 옵션",
                        icon: Icons.nfc_rounded,
                        theme: theme,
                        primaryColor: dynamicPrimary,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "현장에서 신규 자산 및 인원 등록 시 프린터/리더기로 발급되는 EPC 데이터 규격을 설정합니다.",
                              style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<String>(
                                showSelectedIcon: true,
                                style: SegmentedButton.styleFrom(
                                  selectedBackgroundColor: dynamicPrimary,
                                  selectedForegroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  textStyle: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800),
                                ),
                                segments: const [
                                  ButtonSegment(value: '96bit', label: Text('96-bit (표준 EPC Gen2)')),
                                  ButtonSegment(value: '128bit', label: Text('128-bit (확장 메모리)')),
                                ],
                                selected: {_tagBitOption},
                                onSelectionChanged: (Set<String> newSelection) {
                                  setState(() {
                                    _tagBitOption = newSelection.first;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 🔥 ----------------------------------------------------------------
                      // 섹션 6: AI 스마트 검색 (Gemini API) 설정
                      // ----------------------------------------------------------------
                      _buildSectionCard(
                        title: "6. AI 스마트 검색 (Gemini API) 설정",
                        icon: Icons.auto_awesome_rounded,
                        theme: theme,
                        primaryColor: Colors.deepPurpleAccent, // AI 기능 특화 컬러 적용
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "물품 및 인원 관리 화면에서 자연어로 검색할 수 있도록 구글 Gemini API 키를 등록합니다.\n각 거래처(클라이언트)별로 발급받은 고유 키를 직접 입력하여 과금을 분리하고 보안을 유지합니다.",
                              style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _geminiApiKeyController,
                              obscureText: true, // 보안을 위해 키를 마스킹 처리합니다.
                              style: AppTheme.itemValueStyle(context).copyWith(fontSize: 18),
                              decoration: AppTheme.inputDecoration(
                                  label: "Google Gemini API Key (AIzaSy...)",
                                  context: context,
                                  prefixIcon: Icons.vpn_key_rounded
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4.0),
                              child: Text(
                                "💡 무료 API 키 발급처: https://aistudio.google.com/app/apikey",
                                style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.blueGrey, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [UI 조각] 상단 타이틀 영역
  Widget _buildTopHeader(ThemeData theme, bool isDark, Color dynamicPrimary) {
    return Container(
      padding: EdgeInsets.all(widget.isMobile ? 16.0 : 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.save_rounded, size: 20),
            label: const Text("저장 및 적용", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: dynamicPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _saveSettings,
          ),
        ],
      ),
    );
  }

  /// [UI 조각] 설정을 묶어주는 미니멀 카드 섹션
  Widget _buildSectionCard({required String title, required IconData icon, required Widget child, required ThemeData theme, required Color primaryColor}) {
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey.withValues(alpha: 0.3)),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: primaryColor, size: 24),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.dataColor(isDark)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: theme.dividerTheme.color),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}