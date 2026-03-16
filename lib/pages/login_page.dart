import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 웹(Web) 환경 판별을 위해 추가
import 'package:flutter/services.dart';   // 모바일 환경에서의 앱 종료 처리를 위해 추가
import 'dart:io';                         // 데스크탑 환경에서의 강제 종료(exit)를 위해 추가
import 'package:provider/provider.dart';  // 상태 관리 연결을 위해 추가
import 'package:shared_preferences/shared_preferences.dart'; // 전역 설정값 관리를 위해 추가

import '../providers/auth_provider.dart'; // 분리된 데이터 모듈(Provider) 임포트
import '../theme/app_theme.dart';
// import 'main_dashboard_page.dart'; // 추후 접속할 메인 페이지 임포트 (경로에 맞게 수정)

/// ---------------------------------------------------------------------------
/// [통합 로그인 페이지 (LoginPage)]
/// 오프라인 모드 여부를 스스로 감지하여 UI를 동적으로 변경하는 스마트 로그인 창입니다.
/// 데이터베이스 통신 로직은 AuthProvider로 완전히 위임하여 아키텍처를 깔끔하게 분리했습니다.
/// ---------------------------------------------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() {
    return _LoginPageState();
  }
}

class _LoginPageState extends State<LoginPage> {
  // 입력 필드 컨트롤러
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true; // 비밀번호 숨김 여부 (눈 모양 아이콘 토글용)

  // ---------------------------------------------------------------------------
  // [아키텍처 대응 변수] 환경설정에서 저장한 오프라인 모드 상태를 보관합니다.
  // ---------------------------------------------------------------------------
  bool _isInitLoaded = false;   // 설정 로드 완료 여부
  bool _isOfflineMode = false;  // 오프라인 모드 켜짐 여부
  String _savedOfflineCode = "";// 환경설정에서 저장한 로컬 회사코드

  @override
  void initState() {
    super.initState();
    // 화면이 켜지자마자 가장 먼저 환경설정값을 읽어옵니다.
    _loadAuthSettings();
  }

  @override
  void dispose() {
    // 메모리 누수를 방지하기 위해 컨트롤러 자원을 해제합니다.
    _companyController.dispose();
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// ---------------------------------------------------------------------------
  /// [설정값 로드] 환경설정(SettingsPage)에서 기록한 모드와 코드를 가져옵니다.
  /// ---------------------------------------------------------------------------
  Future<void> _loadAuthSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    if (mounted) {
      setState(() {
        _isOfflineMode = prefs.getBool('pref_offline_mode') ?? false;
        _savedOfflineCode = prefs.getString('pref_offline_company_code') ?? '';
        _isInitLoaded = true; // 로딩이 완료되면 화면을 렌더링합니다.
      });
    }
  }

  /// ---------------------------------------------------------------------------
  /// [스마트 로그인 처리 로직]
  /// UI 검증 및 회사 코드 처리를 담당하고, 실제 인증은 AuthProvider에 위임합니다.
  /// ---------------------------------------------------------------------------
  Future<void> _handleLogin() async {
    // 1. 오프라인 모드면 세팅된 코드를 쓰고, 온라인이면 입력받은 코드를 씁니다.
    final String company = _isOfflineMode ? _savedOfflineCode : _companyController.text.trim();
    final String id = _idController.text.trim();
    final String password = _passwordController.text.trim();

    // 2. 빈 값 검증 로직 (사전 차단)
    if (id.isEmpty || password.isEmpty) {
      _showErrorDialog("입력 오류", "아이디와 비밀번호를 모두 입력해 주세요.");
      return;
    }

    if (!_isOfflineMode && company.isEmpty) {
      _showErrorDialog("입력 오류", "회사명(코드)을 입력해 주세요.");
      return;
    }

    if (_isOfflineMode && company.isEmpty) {
      _showErrorDialog("설정 오류", "환경설정에서 '로컬 전용 회사코드'가 지정되지 않았습니다.\n우측 상단의 톱니바퀴를 눌러 설정해 주세요.");
      return;
    }

    // 키보드를 내립니다.
    FocusScope.of(context).unfocus();

    // 3. Provider를 통한 인증 요청 (데이터베이스 로직 분리)
    final AuthProvider auth = context.read<AuthProvider>();
    final String errorMsg = await auth.login(id, password);

    if (!mounted) return;

    if (errorMsg.isEmpty) {
      // [데이터 태깅 준비] 최종 확정된 회사코드를 '현재 접속 중인 코드'로 전역 저장소에 기록합니다.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_company_code', company);

      // 로그인 성공 시 메인 화면으로 완벽하게 전환합니다. (스택 지우기)
      /* // 주석 해제하여 라우팅 연결
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const MainDashboardPage()),
        (Route<dynamic> route) => false,
      );
      */

      // 테스트용 성공 팝업 (라우팅 연결 후 삭제하세요)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 시스템 접속 성공!'), backgroundColor: AppTheme.success),
      );

    } else {
      // Provider가 넘겨준 구체적인 에러 메시지를 다이얼로그로 띄웁니다.
      _showErrorDialog("로그인 실패", errorMsg);
    }
  }

  /// ---------------------------------------------------------------------------
  /// [취소 처리 로직 (프로그램 강제 종료)]
  /// 실행 환경(웹, 데스크톱, 모바일)에 맞춰 적절한 종료 처리를 수행합니다.
  /// ---------------------------------------------------------------------------
  void _handleCancel() {
    if (kIsWeb) {
      _showErrorDialog("알림", "웹 브라우저에서는 탭을 직접 닫아주세요.");
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      exit(0); // 데스크탑 환경 완벽 종료
    } else {
      SystemNavigator.pop(); // 안드로이드/iOS 환경 앱 백그라운드 전환 및 종료
    }
  }

  /// ---------------------------------------------------------------------------
  /// [공통 에러 다이얼로그 (메시지 박스)]
  /// ---------------------------------------------------------------------------
  void _showErrorDialog(String title, String message) {
    showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: AppTheme.dialogTitle(title, Icons.warning_amber_rounded, color: AppTheme.danger),
            content: Text(message, style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
            actions: [
              AppTheme.actionButton(
                  label: "확인",
                  onPressed: () {
                    Navigator.pop(ctx);
                  }
              )
            ],
          );
        }
    );
  }

  @override
  Widget build(BuildContext context) {
    // AuthProvider의 로딩 상태를 구독하여 UI를 동적으로 변경합니다.
    final AuthProvider auth = context.watch<AuthProvider>();
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    // 설정값이 아직 안 불러와졌다면 빈 화면(또는 스피너)을 보여주어 UI 깜빡임을 방지합니다.
    if (!_isInitLoaded) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // 메인 로그인 폼 영역 (반응형 대응: 중앙 정렬 및 최대 너비 고정)
          Center(
            child: SingleChildScrollView(
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                    color: theme.cardTheme.color,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      )
                    ]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. [회사 로고 이미지 영역]
                    _buildLogoSpace(theme, isDark),
                    const SizedBox(height: 40),

                    // -----------------------------------------------------------
                    // 2. [스마트 UI 분기 - 회사 코드]
                    // 오프라인 모드가 아닐 때(온라인 SaaS 모드)만 회사코드 입력칸을 노출합니다.
                    // -----------------------------------------------------------
                    if (!_isOfflineMode) ...[
                      _buildLoginField(
                          controller: _companyController,
                          label: "회사명 또는 코드",
                          icon: Icons.business,
                          theme: theme
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 3. [아이디 및 비밀번호 입력 영역]
                    _buildLoginField(
                        controller: _idController,
                        label: "아이디 (이메일 또는 사번)",
                        icon: Icons.person_outline,
                        theme: theme
                    ),
                    const SizedBox(height: 16),
                    _buildLoginField(
                        controller: _passwordController,
                        label: "비밀번호",
                        icon: Icons.lock_outline,
                        isPassword: true,
                        theme: theme
                    ),
                    const SizedBox(height: 40),

                    // 4. [액션 버튼 영역 (종료 / 시스템 접속)]
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark ? Colors.white70 : Colors.grey.shade700,
                                side: BorderSide(
                                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                                    width: 2
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: auth.isLoading ? null : _handleCancel,
                              child: const Text(
                                "종료",
                                style: TextStyle(
                                    fontFamily: AppTheme.fontPretendard,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: auth.isLoading ? null : _handleLogin,
                              child: auth.isLoading
                                  ? const SizedBox(
                                  width: 24, height: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                              )
                                  : const Text(
                                "시스템 접속",
                                style: TextStyle(
                                    fontFamily: AppTheme.fontPretendard,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // 5. [오프라인 모드 안내 문구]
                    if (_isOfflineMode) ...[
                      const SizedBox(height: 24),
                      Text(
                        "현재 오프라인(Local) 모드로 구동 중입니다.\n데이터는 [$_savedOfflineCode] 코드로 안전하게 기록됩니다.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppTheme.fontPretendard,
                          fontSize: 12,
                          color: Colors.blueGrey.withValues(alpha: 0.8),
                          height: 1.4,
                        ),
                      )
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [회사 로고 렌더링 위젯]
  /// 미니멀리즘 디자인 철학을 반영하여 깔끔하게 에러 처리를 지원합니다.
  /// ---------------------------------------------------------------------------
  Widget _buildLogoSpace(ThemeData theme, bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 240,
      child: Image.asset(
        'assets/images/PLUG4ASSET.png',
        fit: BoxFit.contain,
        errorBuilder: (BuildContext context, Object exception, StackTrace? stackTrace) {
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                width: 1.5,
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image_rounded, size: 48, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(
                  "로고 이미지를 찾을 수 없습니다",
                  style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "경로(assets/images/PLUG4ASSET.png) 확인 요망",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    fontSize: 12,
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [로그인 폼 입력 필드 전용 위젯 (TEdit 대체)]
  /// 반복되는 텍스트 필드 코드를 모듈화하여 가독성과 유지보수성을 높였습니다.
  /// ---------------------------------------------------------------------------
  Widget _buildLoginField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    required ThemeData theme
  }) {
    final bool isDark = theme.brightness == Brightness.dark;

    return TextField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      style: TextStyle(
          fontFamily: AppTheme.fontPretendard,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppTheme.dataColor(isDark)
      ),
      decoration: AppTheme.inputDecoration(label: label, context: context).copyWith(
        prefixIcon: Icon(icon, color: Colors.grey.shade400),
        // 비밀번호 입력란일 경우 우측에 눈 모양 토글 버튼 생성
        suffixIcon: isPassword
            ? IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey.shade400,
          ),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        )
            : null,
      ),
      onSubmitted: (_) {
        // Provider의 isLoading 변수를 참조합니다.
        final bool isLoading = context.read<AuthProvider>().isLoading;
        if (!isLoading) {
          _handleLogin();
        }
      },
    );
  }
}