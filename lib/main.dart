import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'dart:async';

// 테마 및 페이지 설정 임포트
import 'pages/login_page.dart';
import 'pages/main_page.dart';
import 'theme/app_theme.dart';

// 상태 관리를 위한 프로바이더 임포트
import 'providers/user_provider.dart';
import 'providers/product_provider.dart';
import 'providers/device_provider.dart';
import 'providers/theme_provider.dart';

// 전역 포켓베이스 클라이언트 임포트
import 'core/pocketbase_client.dart';

/// ---------------------------------------------------------------------------
/// [애플리케이션 메인 진입점]
/// C++Builder의 WinMain 함수와 같은 역할을 수행하며, 초기 윈도우 환경을 설정합니다.
/// ---------------------------------------------------------------------------
void main() async {
  // 플러터 엔진 비동기 초기화 보장
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isWindows) {
    // 윈도우 매니저 서비스 초기화
    await windowManager.ensureInitialized();

    // 윈도우 옵션 설정
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1440, 760),
      minimumSize: Size(800, 600),
      center: true,
      skipTaskbar: false,
      // 타이틀바 스타일을 숨김으로 설정하여 기본 캡션바 제거 시도
      titleBarStyle: TitleBarStyle.hidden,
    );

    // 윈도우가 준비되면 실행될 콜백 설정
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // [강력한 패치] 윈도우 프레임을 물리적으로 제거하여 캡션바가 나타날 틈을 주지 않습니다.
      await windowManager.setAsFrameless();
      // 외곽선 그림자까지 제거하여 완벽한 미니멀 디자인 구현
      await windowManager.setHasShadow(false);

      await windowManager.show();
      await windowManager.focus();

      // [해결] 작업표시줄까지 완벽하게 덮는 전체화면 모드 진입
      // 이 명령이 실행되면 윈도우 OS가 이 앱을 '최상위 키오스크'로 인식하게 됩니다.
      await windowManager.setFullScreen(true);
    });
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RFID FA Solution',
      theme: themeProvider.themeData,
      themeMode: ThemeMode.light,
      home: const AuthGate(),
    );
  }
}

/// [인증 라우터 게이트]
/// 로그인 상태에 따라 로그인 폼 혹은 메인 폼으로 자동으로 분기합니다.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isAuthenticated = pb.authStore.isValid;
  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();
    // 포켓베이스 인증 상태 변화를 실시간으로 감시
    _authSubscription = pb.authStore.onChange.listen((event) {
      if (mounted) {
        setState(() {
          _isAuthenticated = pb.authStore.isValid;
        });
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticated) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => ProductProvider()),
          ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ],
        child: const MainPage(),
      );
    }
    return const LoginPage();
  }
}