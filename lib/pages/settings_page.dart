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

  // [1] 데이터베이스 및 서버 설정
  bool _isOfflineMode = false;
  final TextEditingController _offlineCompanyCodeController = TextEditingController();
  final TextEditingController _dbUrlController = TextEditingController();

  // [2] ERP 연동 설정
  final TextEditingController _erpReceiveUrlController = TextEditingController();
  final TextEditingController _erpSendUrlController = TextEditingController();
  bool _autoSyncEnabled = false;
  int _syncIntervalMin = 10;

  // [3] 디스플레이 및 화면 동작 설정
  bool _isKioskModeDefault = false;
  final List<Map<String, dynamic>> _themeOptions = [
    {'type': AppThemeType.pureWhite, 'color': Colors.white, 'label': '화이트'},
    {'type': AppThemeType.industrial, 'color': AppTheme.colorIndustrial, 'label': '블루'},
    {'type': AppThemeType.forest, 'color': AppTheme.colorForest, 'label': '그린'},
    {'type': AppThemeType.solar, 'color': AppTheme.colorSolar, 'label': '오렌지'},
    {'type': AppThemeType.midnight, 'color': const Color(0xFF1E293B), 'label': '다크'},
  ];
  int _selectedThemeIndex = 0;
  List<Display> _displays = [];
  String? _selectedDisplayId;

  // [4] 배경 이미지 폴더 설정
  final TextEditingController _bgImagePathController = TextEditingController();

  // [5] RFID 발급 옵션 설정
  String _tagBitOption = '96bit';

  // [6] AI (Gemini) API Key 입력용
  final TextEditingController _geminiApiKeyController = TextEditingController();

  // [7] 키보드 에뮬레이션 (Wedge) 설정
  bool _keyboardWedgeEnabled = false;

  // [8] 카카오톡 알림톡 설정 변수
  bool _kakaoEnabled = false;
  final TextEditingController _kakaoApiKeyController = TextEditingController();
  final TextEditingController _kakaoSenderIdController = TextEditingController();

  // [9] 이메일 발송 (SMTP) 설정 변수
  bool _emailEnabled = false;
  final TextEditingController _smtpHostController = TextEditingController();
  final TextEditingController _smtpPortController = TextEditingController();
  final TextEditingController _smtpUserController = TextEditingController();
  final TextEditingController _smtpPasswordController = TextEditingController();

  // [10] 사용자 정의 웹훅 (Webhook) 설정 변수
  bool _webhookEnabled = false;
  final TextEditingController _webhookUrlController = TextEditingController();

  // 🔥 [11] TCP/IP Socket 연동 변수 추가
  bool _tcpEnabled = false;
  final TextEditingController _tcpHostController = TextEditingController();
  final TextEditingController _tcpPortController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  /// 메모리 누수를 방지하기 위해 화면이 닫힐 때 모든 컨트롤러 자원을 확실히 해제합니다.
  @override
  void dispose() {
    _offlineCompanyCodeController.dispose();
    _dbUrlController.dispose();
    _erpReceiveUrlController.dispose();
    _erpSendUrlController.dispose();
    _bgImagePathController.dispose();
    _geminiApiKeyController.dispose();
    _kakaoApiKeyController.dispose();
    _kakaoSenderIdController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    _smtpUserController.dispose();
    _smtpPasswordController.dispose();
    _webhookUrlController.dispose();
    _tcpHostController.dispose(); // 🔥 해제 추가
    _tcpPortController.dispose(); // 🔥 해제 추가
    super.dispose();
  }

  Future<void> _initSettings() async {
    await _fetchDisplays();
    await _loadSettings();
  }

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

  Future<void> _loadSettings() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      if (mounted) {
        setState(() {
          // 기존 1 ~ 10번 설정들 로드
          _isOfflineMode = prefs.getBool('pref_offline_mode') ?? false;
          _offlineCompanyCodeController.text = prefs.getString('pref_offline_company_code') ?? '';
          _dbUrlController.text = prefs.getString('pref_db_url') ?? 'http://127.0.0.1:8090';
          _erpReceiveUrlController.text = prefs.getString('pref_erp_receive_url') ?? 'https://api.erp-system.com/v1/read';
          _erpSendUrlController.text = prefs.getString('pref_erp_send_url') ?? 'https://api.erp-system.com/v1/write';
          _autoSyncEnabled = prefs.getBool('pref_auto_sync') ?? false;
          _syncIntervalMin = prefs.getInt('pref_sync_interval') ?? 10;
          _isKioskModeDefault = prefs.getBool('pref_kiosk_default') ?? false;
          _selectedThemeIndex = prefs.getInt('pref_theme_index') ?? 0;
          _selectedDisplayId = prefs.getString('pref_display_id');
          _bgImagePathController.text = prefs.getString('pref_bg_image_path') ?? '';
          _tagBitOption = prefs.getString('pref_tag_bit_option') ?? '96bit';
          _geminiApiKeyController.text = prefs.getString('pref_gemini_api_key') ?? '';
          _keyboardWedgeEnabled = prefs.getBool('pref_keyboard_wedge') ?? false;

          _kakaoEnabled = prefs.getBool('pref_kakao_enabled') ?? false;
          _kakaoApiKeyController.text = prefs.getString('pref_kakao_api_key') ?? '';
          _kakaoSenderIdController.text = prefs.getString('pref_kakao_sender_id') ?? '';

          _emailEnabled = prefs.getBool('pref_email_enabled') ?? false;
          _smtpHostController.text = prefs.getString('pref_smtp_host') ?? '';
          _smtpPortController.text = prefs.getString('pref_smtp_port') ?? '587';
          _smtpUserController.text = prefs.getString('pref_smtp_user') ?? '';
          _smtpPasswordController.text = prefs.getString('pref_smtp_password') ?? '';

          _webhookEnabled = prefs.getBool('pref_webhook_enabled') ?? false;
          _webhookUrlController.text = prefs.getString('pref_webhook_url') ?? '';

          // 🔥 TCP/IP 설정 로드
          _tcpEnabled = prefs.getBool('pref_tcp_enabled') ?? false;
          _tcpHostController.text = prefs.getString('pref_tcp_host') ?? '';
          _tcpPortController.text = prefs.getString('pref_tcp_port') ?? '';

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('설정 로드 실패: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (_dbUrlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('데이터베이스 서버 주소는 필수입니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)), backgroundColor: AppTheme.danger));
      return;
    }

    if (_isOfflineMode && _offlineCompanyCodeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('오프라인 모드 활성화 시 로컬 회사코드는 필수입니다!', style: TextStyle(fontFamily: AppTheme.fontPretendard)), backgroundColor: AppTheme.danger));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // 기존 1 ~ 10번 설정 저장
      await prefs.setBool('pref_offline_mode', _isOfflineMode);
      await prefs.setString('pref_offline_company_code', _offlineCompanyCodeController.text.trim());
      await prefs.setString('pref_db_url', _dbUrlController.text.trim());
      await prefs.setString('pref_erp_receive_url', _erpReceiveUrlController.text.trim());
      await prefs.setString('pref_erp_send_url', _erpSendUrlController.text.trim());
      await prefs.setBool('pref_auto_sync', _autoSyncEnabled);
      await prefs.setInt('pref_sync_interval', _syncIntervalMin);
      await prefs.setBool('pref_kiosk_default', _isKioskModeDefault);
      await prefs.setInt('pref_theme_index', _selectedThemeIndex);
      await prefs.setString('pref_bg_image_path', _bgImagePathController.text.trim());
      await prefs.setString('pref_tag_bit_option', _tagBitOption);
      await prefs.setString('pref_gemini_api_key', _geminiApiKeyController.text.trim());
      await prefs.setBool('pref_keyboard_wedge', _keyboardWedgeEnabled);
      if (_selectedDisplayId != null) await prefs.setString('pref_display_id', _selectedDisplayId!);

      await prefs.setBool('pref_kakao_enabled', _kakaoEnabled);
      await prefs.setString('pref_kakao_api_key', _kakaoApiKeyController.text.trim());
      await prefs.setString('pref_kakao_sender_id', _kakaoSenderIdController.text.trim());

      await prefs.setBool('pref_email_enabled', _emailEnabled);
      await prefs.setString('pref_smtp_host', _smtpHostController.text.trim());
      await prefs.setString('pref_smtp_port', _smtpPortController.text.trim());
      await prefs.setString('pref_smtp_user', _smtpUserController.text.trim());
      await prefs.setString('pref_smtp_password', _smtpPasswordController.text.trim());

      await prefs.setBool('pref_webhook_enabled', _webhookEnabled);
      await prefs.setString('pref_webhook_url', _webhookUrlController.text.trim());

      // 🔥 TCP/IP 설정 저장
      await prefs.setBool('pref_tcp_enabled', _tcpEnabled);
      await prefs.setString('pref_tcp_host', _tcpHostController.text.trim());
      await prefs.setString('pref_tcp_port', _tcpPortController.text.trim());

      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        if (_selectedDisplayId != null && _displays.isNotEmpty) {
          try {
            final Display targetDisplay = _displays.firstWhere((d) => d.id.toString() == _selectedDisplayId);
            await windowManager.setPosition(targetDisplay.visiblePosition ?? const Offset(0, 0));
          } catch (e) {
            debugPrint("모니터 이동 실패: $e");
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 환경설정이 성공적으로 저장되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
      }
    } catch (e) {
      debugPrint('설정 저장 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 저장 실패: $e', style: const TextStyle(fontFamily: AppTheme.fontPretendard)), backgroundColor: AppTheme.danger));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _testDbConnection() async {
    final String targetUrl = _dbUrlController.text.trim();
    if (targetUrl.isEmpty) return;

    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text("서버 응답 확인 중...", style: TextStyle(fontFamily: AppTheme.fontPretendard))])));
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ [$targetUrl] 접속 테스트 성공!', style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)), backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color dynamicPrimary = theme.colorScheme.primary;

    if (_isLoading) {
      return Scaffold(backgroundColor: theme.scaffoldBackgroundColor, body: Center(child: CircularProgressIndicator(color: dynamicPrimary)));
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
                bottom: (widget.isMobile ? 16.0 : 32.0) + 20.0,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- 기존 섹션 1 ~ 10 ---
                      _buildSection1(theme, dynamicPrimary),
                      const SizedBox(height: 24),
                      _buildSection2(theme, dynamicPrimary, isDark),
                      const SizedBox(height: 24),
                      _buildSection3(theme, dynamicPrimary, isDark),
                      const SizedBox(height: 24),
                      _buildSection4(theme, dynamicPrimary),
                      const SizedBox(height: 24),
                      _buildSection5(theme, dynamicPrimary),
                      const SizedBox(height: 24),
                      _buildSection6(theme),
                      const SizedBox(height: 24),
                      _buildSection7(theme),
                      const SizedBox(height: 24),
                      _buildSection8(theme),
                      const SizedBox(height: 24),
                      _buildSection9(theme),
                      const SizedBox(height: 24),
                      _buildSection10(theme),
                      const SizedBox(height: 24),

                      // 🔥 ----------------------------------------------------------------
                      // 신규 섹션 11: TCP/IP Socket 연동 설정
                      // ----------------------------------------------------------------
                      _buildSectionCard(
                        title: "11. TCP/IP Socket 전송 설정",
                        icon: Icons.electrical_services_rounded,
                        theme: theme,
                        primaryColor: Colors.redAccent,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "거래처의 PLC 장비, MES/POP 시스템 포트로 직접 Raw 데이터를 전송(Push)할 때 사용합니다.\nREST API를 지원하지 않는 레거시 장비 및 산업용 PC 연동에 필수적인 기능입니다.",
                              style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              decoration: AppTheme.listItemDecoration(context, isSelected: _tcpEnabled, statusColor: Colors.redAccent),
                              child: SwitchListTile(
                                title: const Text("TCP/IP 소켓 데이터 전송 활성화", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
                                subtitle: const Text("이벤트 발생 시 지정된 IP 주소와 포트로 문자열 패킷을 밀어넣습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
                                value: _tcpEnabled,
                                activeThumbColor: Colors.redAccent,
                                activeTrackColor: Colors.redAccent.withValues(alpha: 0.4),
                                onChanged: (bool value) => setState(() => _tcpEnabled = value),
                              ),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              child: _tcpEnabled
                                  ? Padding(
                                padding: const EdgeInsets.only(top: 16.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: _tcpHostController,
                                        style: AppTheme.itemValueStyle(context).copyWith(fontSize: 16),
                                        decoration: AppTheme.inputDecoration(
                                            label: "수신측 IP 주소 (예: 192.168.0.50)",
                                            context: context,
                                            prefixIcon: Icons.computer_rounded
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 1,
                                      child: TextField(
                                        controller: _tcpPortController,
                                        keyboardType: TextInputType.number,
                                        style: AppTheme.itemValueStyle(context).copyWith(fontSize: 16),
                                        decoration: AppTheme.inputDecoration(
                                            label: "포트 (예: 5000)",
                                            context: context,
                                            prefixIcon: Icons.settings_ethernet_rounded
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                                  : const SizedBox.shrink(),
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

  // =========================================================================
  // 이하 기존 섹션 UI 모듈화 분리 (위젯 트리가 길어지는 것을 방지)
  // =========================================================================

  Widget _buildSection1(ThemeData theme, Color dynamicPrimary) {
    return _buildSectionCard(
      title: "1. 메인 데이터베이스 및 동작 모드",
      icon: Icons.dns_rounded,
      theme: theme,
      primaryColor: dynamicPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("앱이 데이터를 보관할 서버 환경과 동작 모드를 설정합니다.\n인터넷이 차단된 로컬 폐쇄망에서는 오프라인 모드를 활성화하십시오.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5)),
          const SizedBox(height: 20),
          Container(
            decoration: AppTheme.listItemDecoration(context, isSelected: _isOfflineMode, statusColor: dynamicPrimary),
            child: SwitchListTile(
              title: const Text("오프라인 (로컬 폐쇄망) 단독 구동", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: const Text("마스터 클라우드 인증을 거치지 않고, 로컬 PocketBase DB에 직접 접속합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
              value: _isOfflineMode,
              activeThumbColor: dynamicPrimary,
              activeTrackColor: dynamicPrimary.withValues(alpha: 0.4),
              onChanged: (bool value) => setState(() => _isOfflineMode = value),
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
                    decoration: AppTheme.inputDecoration(label: "로컬 전용 회사코드 (필수)", context: context, prefixIcon: Icons.badge_rounded),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text("💡 향후 온라인(구독형) 서비스로 데이터를 원활하게 이관(마이그레이션)하기 위해,\n오프라인 모드에서도 이 앱이 생성하는 모든 데이터에 해당 코드가 꼬리표처럼 기록됩니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 12, color: Colors.blueGrey, height: 1.4)),
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
                  style: OutlinedButton.styleFrom(foregroundColor: dynamicPrimary, side: BorderSide(color: dynamicPrimary), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: _testDbConnection,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection2(ThemeData theme, Color dynamicPrimary, bool isDark) {
    return _buildSectionCard(
      title: "2. 외부 ERP 시스템 통신 설정",
      icon: Icons.sync_alt_rounded,
      theme: theme,
      primaryColor: dynamicPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("거래처 또는 사내 ERP 시스템과 데이터를 주고받을 수신/송신 API 주소와 백그라운드 동기화 정책을 설정합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5)),
          const SizedBox(height: 20),
          TextField(controller: _erpReceiveUrlController, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 18), decoration: AppTheme.inputDecoration(label: "수신용 API 주소 (데이터 조회용)", context: context, prefixIcon: Icons.download_rounded)),
          const SizedBox(height: 16),
          TextField(controller: _erpSendUrlController, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 18), decoration: AppTheme.inputDecoration(label: "송신용 API 주소 (데이터 등록/수정용)", context: context, prefixIcon: Icons.upload_rounded)),
          const SizedBox(height: 24),
          Container(
            decoration: AppTheme.listItemDecoration(context, isSelected: _autoSyncEnabled, statusColor: dynamicPrimary),
            child: SwitchListTile(
              title: const Text("백그라운드 자동 동기화 활성화", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: const Text("앱을 켜두면 보이지 않는 곳에서 주기적으로 ERP 데이터를 수신하여 로컬에 업데이트합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
              value: _autoSyncEnabled,
              activeThumbColor: dynamicPrimary,
              activeTrackColor: dynamicPrimary.withValues(alpha: 0.4),
              onChanged: (bool value) => setState(() => _autoSyncEnabled = value),
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
                  Slider(value: _syncIntervalMin.toDouble(), min: 1, max: 60, divisions: 59, activeColor: dynamicPrimary, label: '$_syncIntervalMin 분', onChanged: (double value) => setState(() => _syncIntervalMin = value.toInt())),
                ],
              ),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildSection3(ThemeData theme, Color dynamicPrimary, bool isDark) {
    return _buildSectionCard(
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
                    setState(() => _selectedThemeIndex = index);
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
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle,
                              border: isSelected ? Border.all(color: isDark ? Colors.white : Colors.black87, width: 3) : Border.all(color: theme.dividerTheme.color ?? Colors.grey.withValues(alpha: 0.3), width: 1.5),
                              boxShadow: [if (isSelected) BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2)]
                          ),
                          child: isSelected ? Icon(Icons.check_rounded, color: color == Colors.white ? Colors.black87 : Colors.white, size: 28) : null,
                        ),
                        const SizedBox(height: 8),
                        Text(label, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, color: isSelected ? dynamicPrimary : Colors.grey)),
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
                const DropdownMenuItem(value: null, child: Row(children: [Icon(Icons.desktop_windows_outlined, size: 20, color: Colors.grey), SizedBox(width: 8), Text("시스템 기본 모니터 사용 (OS 위임)", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w600))])),
                ..._displays.asMap().entries.map((entry) {
                  final int index = entry.key + 1;
                  final Display display = entry.value;
                  return DropdownMenuItem(value: display.id.toString(), child: Row(children: [const Icon(Icons.monitor, size: 20, color: Colors.blueGrey), const SizedBox(width: 8), Text("모니터 $index : ${display.name ?? '알 수 없는 디스플레이'} (${display.size.width.toInt()} x ${display.size.height.toInt()})", style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w600))]));
                }),
              ],
              onChanged: (String? val) => setState(() => _selectedDisplayId = val),
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
              onChanged: (bool value) => setState(() => _isKioskModeDefault = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection4(ThemeData theme, Color dynamicPrimary) {
    return _buildSectionCard(
      title: "4. 키오스크 배경 이미지 롤링 설정",
      icon: Icons.wallpaper_rounded,
      theme: theme,
      primaryColor: dynamicPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("키오스크 대기 화면에서 슬라이드쇼로 표시될 이미지가 담긴 로컬 폴더를 지정합니다.\n폴더를 지정하면 해당 폴더 내의 이미지들이 일정 시간마다 교체되며 화면에 그려집니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5)),
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
                  style: OutlinedButton.styleFrom(foregroundColor: dynamicPrimary, side: BorderSide(color: dynamicPrimary), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: () async {
                    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                    if (selectedDirectory != null && mounted) setState(() => _bgImagePathController.text = selectedDirectory);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection5(ThemeData theme, Color dynamicPrimary) {
    return _buildSectionCard(
      title: "5. RFID 태그 발급(인코딩) 옵션",
      icon: Icons.nfc_rounded,
      theme: theme,
      primaryColor: dynamicPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("현장에서 신규 자산 및 인원 등록 시 프린터/리더기로 발급되는 EPC 데이터 규격을 설정합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: true,
              style: SegmentedButton.styleFrom(selectedBackgroundColor: dynamicPrimary, selectedForegroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 20), textStyle: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800)),
              segments: const [ButtonSegment(value: '96bit', label: Text('96-bit (표준 EPC Gen2)')), ButtonSegment(value: '128bit', label: Text('128-bit (확장 메모리)'))],
              selected: {_tagBitOption},
              onSelectionChanged: (Set<String> newSelection) => setState(() => _tagBitOption = newSelection.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection6(ThemeData theme) {
    return _buildSectionCard(
      title: "6. AI 스마트 검색 (Gemini API) 설정",
      icon: Icons.auto_awesome_rounded,
      theme: theme,
      primaryColor: Colors.deepPurpleAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("물품 및 인원 관리 화면에서 자연어로 검색할 수 있도록 구글 Gemini API 키를 등록합니다.\n각 거래처(클라이언트)별로 발급받은 고유 키를 직접 입력하여 과금을 분리하고 보안을 유지합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5)),
          const SizedBox(height: 20),
          TextField(controller: _geminiApiKeyController, obscureText: true, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 18), decoration: AppTheme.inputDecoration(label: "Google Gemini API Key (AIzaSy...)", context: context, prefixIcon: Icons.vpn_key_rounded)),
          const SizedBox(height: 12),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4.0), child: Text("💡 무료 API 키 발급처: https://aistudio.google.com/app/apikey", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.blueGrey, height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildSection7(ThemeData theme) {
    return _buildSectionCard(
      title: "7. 키보드 이벤트 발생 (Wedge Mode)",
      icon: Icons.keyboard_alt_rounded,
      theme: theme,
      primaryColor: Colors.orangeAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("RFID 태그가 감지되면 해당 데이터를 시스템의 실제 키보드 입력으로 변환합니다.\n윈도우용 외부 ERP나 엑셀, 메모장 등에 직접 데이터를 입력하고 싶을 때 유용합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5)),
          const SizedBox(height: 20),
          Container(
            decoration: AppTheme.listItemDecoration(context, isSelected: _keyboardWedgeEnabled, statusColor: Colors.orangeAccent),
            child: SwitchListTile(
              title: const Text("실시간 키보드 입력 발생 활성화", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: const Text("감지된 태그 ID를 타이핑한 후 자동으로 'Enter'를 입력합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
              value: _keyboardWedgeEnabled,
              activeThumbColor: Colors.orangeAccent,
              activeTrackColor: Colors.orangeAccent.withValues(alpha: 0.4),
              onChanged: (bool value) => setState(() => _keyboardWedgeEnabled = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection8(ThemeData theme) {
    return _buildSectionCard(
      title: "8. 카카오톡 알림톡 설정",
      icon: Icons.chat_bubble_rounded,
      theme: theme,
      primaryColor: const Color(0xFFFEE500),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("비인가 자산 반출, 위험 구역 진입 등의 이벤트 발생 시 등록된 번호로 카카오톡 알림을 전송합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5)),
          const SizedBox(height: 20),
          Container(
            decoration: AppTheme.listItemDecoration(context, isSelected: _kakaoEnabled, statusColor: const Color(0xFFFEE500)),
            child: SwitchListTile(
              title: const Text("카카오톡 알림 발송 활성화", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: const Text("이벤트 발생 시 즉각적으로 담당자에게 메시지를 전송합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
              value: _kakaoEnabled,
              activeThumbColor: const Color(0xFF3C1E1E),
              activeTrackColor: const Color(0xFFFEE500).withValues(alpha: 0.8),
              onChanged: (bool value) => setState(() => _kakaoEnabled = value),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: _kakaoEnabled
                ? Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Column(
                children: [
                  TextField(controller: _kakaoApiKeyController, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 16), decoration: AppTheme.inputDecoration(label: "알림톡 발송 API Key", context: context, prefixIcon: Icons.key_rounded)),
                  const SizedBox(height: 12),
                  TextField(controller: _kakaoSenderIdController, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 16), decoration: AppTheme.inputDecoration(label: "발신자 번호 (Sender ID)", context: context, prefixIcon: Icons.phone_android_rounded)),
                ],
              ),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildSection9(ThemeData theme) {
    return _buildSectionCard(
      title: "9. 이메일 (SMTP) 자동 발송 설정",
      icon: Icons.email_rounded,
      theme: theme,
      primaryColor: Colors.blueAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("일일 재고 현황 보고서, 불량 발생 로그 등을 지정된 담당자의 이메일로 자동 발송합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5)),
          const SizedBox(height: 20),
          Container(
            decoration: AppTheme.listItemDecoration(context, isSelected: _emailEnabled, statusColor: Colors.blueAccent),
            child: SwitchListTile(
              title: const Text("이메일 자동 발송 활성화", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: const Text("리포트 및 중요 알림을 메일로 발송합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
              value: _emailEnabled,
              activeThumbColor: Colors.blueAccent,
              activeTrackColor: Colors.blueAccent.withValues(alpha: 0.4),
              onChanged: (bool value) => setState(() => _emailEnabled = value),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: _emailEnabled
                ? Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(flex: 2, child: TextField(controller: _smtpHostController, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 16), decoration: AppTheme.inputDecoration(label: "SMTP 서버 주소 (예: smtp.naver.com)", context: context, prefixIcon: Icons.dns_rounded))),
                      const SizedBox(width: 12),
                      Expanded(flex: 1, child: TextField(controller: _smtpPortController, keyboardType: TextInputType.number, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 16), decoration: AppTheme.inputDecoration(label: "포트 (예: 587)", context: context, prefixIcon: Icons.settings_ethernet_rounded))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _smtpUserController, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 16), decoration: AppTheme.inputDecoration(label: "계정 (이메일 주소)", context: context, prefixIcon: Icons.person_rounded)),
                  const SizedBox(height: 12),
                  TextField(controller: _smtpPasswordController, obscureText: true, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 16), decoration: AppTheme.inputDecoration(label: "비밀번호 (또는 앱 비밀번호)", context: context, prefixIcon: Icons.password_rounded)),
                ],
              ),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildSection10(ThemeData theme) {
    return _buildSectionCard(
      title: "10. 사용자 정의 웹훅 (Webhook) 전송 설정",
      icon: Icons.webhook_rounded,
      theme: theme,
      primaryColor: Colors.teal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("거래처에서 미리 구축해둔 외부 시스템(예: myservice.php, Node.js 등)으로 감지 데이터를 즉시 POST 전송합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, height: 1.5)),
          const SizedBox(height: 20),
          Container(
            decoration: AppTheme.listItemDecoration(context, isSelected: _webhookEnabled, statusColor: Colors.teal),
            child: SwitchListTile(
              title: const Text("외부 웹훅 전송 활성화", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: const Text("이벤트 발생 시 지정된 URL로 JSON 데이터를 전송합니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.grey)),
              value: _webhookEnabled,
              activeThumbColor: Colors.teal,
              activeTrackColor: Colors.teal.withValues(alpha: 0.4),
              onChanged: (bool value) => setState(() => _webhookEnabled = value),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: _webhookEnabled
                ? Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: TextField(
                controller: _webhookUrlController,
                style: AppTheme.itemValueStyle(context).copyWith(fontSize: 16),
                decoration: AppTheme.inputDecoration(label: "웹훅 수신 API 주소 (예: https://client.com/myservice.php)", context: context, prefixIcon: Icons.link_rounded),
              ),
            )
                : const SizedBox.shrink(),
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
            style: ElevatedButton.styleFrom(backgroundColor: dynamicPrimary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
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
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: primaryColor, size: 24), const SizedBox(width: 10), Text(title, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.dataColor(isDark)))]),
          const SizedBox(height: 16),
          Divider(color: theme.dividerTheme.color),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}