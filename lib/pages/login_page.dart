import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 웹(Web) 환경 판별을 위해 추가
import 'package:flutter/services.dart';   // 모바일 환경에서의 앱 종료 처리를 위해 추가
import 'dart:io';                         // 데스크탑 환경에서의 강제 종료(exit)를 위해 추가
import 'package:pocketbase/pocketbase.dart';

import '../core/pocketbase_client.dart';
import '../theme/app_theme.dart';

/// ---------------------------------------------------------------------------
/// [통합 로그인 페이지 (LoginPage)]
/// C++Builder의 LoginForm 역할을 수행합니다.
/// 회사코드, 아이디, 비밀번호를 입력받아 PocketBase 서버에 인증을 요청합니다.
/// 미니멀리즘 디자인 철학을 반영하여 깔끔한 카드 형태로 제작되었습니다.
/// ---------------------------------------------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // 입력 필드 컨트롤러
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;      // 로그인 처리 중 상태 플래그
  bool _obscurePassword = true; // 비밀번호 숨김 여부

  @override
  void dispose() {
    _companyController.dispose();
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// ---------------------------------------------------------------------------
  /// [스마트 로그인 처리 로직]
  /// 입력된 ID/PW를 가지고 일반 사용자(users) 권한인지,
  /// 최고 관리자(_superusers) 권한인지 자동으로 판별하여 로그인을 시도합니다.
  /// ---------------------------------------------------------------------------
  Future<void> _handleLogin() async {
    final String company = _companyController.text.trim();
    final String id = _idController.text.trim();
    final String password = _passwordController.text.trim();

    if (company.isEmpty || id.isEmpty || password.isEmpty) {
      _showErrorDialog("입력 오류", "회사명(코드), 아이디, 비밀번호를 모두 입력해 주세요.");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. 먼저 일반 작업자(users 컬렉션)로 로그인을 시도합니다.
      // (현장 작업자용 스마트폰/태블릿 배포 시 주로 사용됨)
      await pb.collection('users').authWithPassword(id, password);

      // 로그인이 성공하면 pb.authStore.isValid 가 true로 변경되며,
      // main.dart의 AuthGate가 이를 감지하여 자동으로 MainPage로 화면을 전환합니다!

    } catch (e) {
      try {
        // 2. 일반 사용자 로그인이 실패했을 경우,
        // 사장님이나 시스템 관리자의 계정(_superusers 컬렉션)인지 2차로 확인합니다.
        await pb.collection('_superusers').authWithPassword(id, password);

      } catch (e2) {
        // 3. 양쪽 모두 인증에 실패한 경우 에러 메시지를 띄웁니다.
        if (mounted) {
          _showErrorDialog("인증 실패", "아이디 또는 비밀번호가 일치하지 않거나 권한이 없습니다.\n다시 확인해 주세요.");
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// ---------------------------------------------------------------------------
  /// [취소 처리 로직 (프로그램 강제 종료)]
  /// C++Builder의 Application->Terminate() 와 완벽하게 동일한 역할을 수행합니다.
  /// 플랫폼(Windows, Web, Mobile)에 맞추어 안전하게 시스템을 종료합니다.
  /// ---------------------------------------------------------------------------
  void _handleCancel() {
    if (kIsWeb) {
      // 웹 브라우저 환경에서는 스크립트로 창을 강제로 닫을 수 없으므로 경고창만 표출합니다.
      _showErrorDialog("알림", "웹 브라우저에서는 탭을 직접 닫아주세요.");
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 윈도우 키오스크/PC 환경: 프로세스를 즉시 강제 종료합니다.
      exit(0);
    } else {
      // 안드로이드/iOS 환경: 시스템에 앱 종료를 요청합니다.
      SystemNavigator.pop();
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: AppTheme.dialogTitle(title, Icons.warning_amber_rounded, color: AppTheme.danger),
          content: Text(message, style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
          actions: [
            AppTheme.actionButton(
                label: "확인",
                onPressed: () => Navigator.pop(ctx)
            )
          ],
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 420, // 키오스크/PC 화면에서도 너무 퍼지지 않도록 폭 고정
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
                // -----------------------------------------------------------
                // [회사 로고 이미지 영역]
                // -----------------------------------------------------------
                _buildLogoSpace(theme, isDark),
                const SizedBox(height: 40),

                // -----------------------------------------------------------
                // [입력 폼 영역]
                // -----------------------------------------------------------
                _buildLoginField(
                    controller: _companyController,
                    label: "회사명 또는 코드",
                    icon: Icons.business,
                    theme: theme
                ),
                const SizedBox(height: 16),
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

                // -----------------------------------------------------------
                // [버튼 영역] 취소(프로그램 종료) 및 로그인 버튼을 가로로 나란히 배치
                // -----------------------------------------------------------
                Row(
                  children: [
                    // 취소(종료) 버튼 (아웃라인 스타일로 메인 버튼과 시각적 차이를 둠)
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
                          onPressed: _isLoading ? null : _handleCancel,
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

                    // 로그인 버튼 (프라이머리 컬러 사용)
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
                          onPressed: _isLoading ? null : _handleLogin,
                          child: _isLoading
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [회사 로고 렌더링 위젯]
  /// 사장님께서 준비하신 실제 파일(PLUG4ASSET.png)을 스크린 상단에 표출합니다.
  /// ---------------------------------------------------------------------------
  Widget _buildLogoSpace(ThemeData theme, bool isDark) {
    return SizedBox(
      width: double.infinity, // 가로 공간을 꽉 채웁니다
      // [수정됨] 기존 160에서 240으로 높이를 대폭 키워 로고를 훨씬 더 크고 시원하게 표시합니다.
      height: 240,
      child: Image.asset(
        'assets/images/PLUG4ASSET.png', // 사장님께서 yaml에 등록하신 실제 로고 파일 경로 적용 완료!
        fit: BoxFit.contain,            // 비율을 유지하며 영역 안에 깔끔하게 맞춥니다. (가로 세로 찌그러짐 방지)

        // [안전장치] 만약 파일명 오타나 설정 문제로 이미지를 불러오지 못할 경우,
        // 앱이 강제 종료되지 않도록 부드러운 에러 화면을 띄워주는 방어(Guard) 코드입니다.
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
  /// [로그인 폼 입력 필드 (TEdit)]
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
        if (!_isLoading) _handleLogin(); // 엔터 키를 누르면 바로 로그인 시도
      },
    );
  }
}