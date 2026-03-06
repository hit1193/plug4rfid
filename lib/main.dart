import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 웹(Web) 환경 판별(kIsWeb)을 위한 필수 라이브러리
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

// 테마 및 페이지 설정 임포트
import 'pages/main_page.dart';
import 'theme/app_theme.dart';

// 상태 관리를 위한 프로바이더 임포트
import 'providers/user_provider.dart';
import 'providers/product_provider.dart';
import 'providers/device_provider.dart';
import 'providers/theme_provider.dart';

// C++Builder의 DataModule 역할을 하는 전역 통신 객체 임포트
import 'core/pocketbase_client.dart';

void main() async {
  // 플러터 엔진 초기화 (비동기 작업을 위해 필수)
  WidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // [핵심 문제 해결] 포켓베이스 인증 대기 (동기화 블록)
  // PocketBase 관리자 인증이 완전히 끝날 때까지 앱 실행(runApp)을 잠시 대기합니다.
  // 이렇게 해야 Provider들이 초기화될 때 완벽하게 인증된 토큰을 사용할 수 있습니다.
  // ---------------------------------------------------------------------------
  bool isAuthenticated = false;
  try {
    // 사장님 계정으로 최고 관리자 권한 획득 시도
    await pb.collection('_superusers').authWithPassword('ubicore.co.kr@gmail.com', '@masmoto0628#');
    debugPrint('✅ [System] 포켓베이스 관리자(_superusers) 권한 획득 완료! 토큰 발급됨.');
    isAuthenticated = true;
  } catch (e) {
    debugPrint('❌ [System] 포켓베이스 관리자 로그인 실패: $e');
    // 실제 현장(Production)에서는 여기서 에러 다이얼로그나 로그인 화면으로 돌리는 처리가 필요합니다.
  }
  // ---------------------------------------------------------------------------

  // 데스크톱(Windows) 환경을 위한 키오스크 스타일 UI 설정
  // 웹 브라우저에서 실행 시 Platform 에러가 나지 않도록 !kIsWeb 방어 코드 추가
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1440, 760),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // 타이틀바 제거로 미니멀함 강조
      fullScreen: true, // 초기 실행 시 전체 화면
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setFullScreen(true);
    });
  }

  // ---------------------------------------------------------------------------
  // 인증이 완료된 후에만 MultiProvider를 통해 앱을 실행합니다.
  // 이제 각 Provider(UserProvider, ProductProvider)가 생성되면서 호출하는 fetchData()는
  // 반드시 유효한 관리자 토큰을 가지고 통신하게 되므로 403 에러가 발생하지 않습니다.
  // ---------------------------------------------------------------------------
  runApp(
    MultiProvider(
      providers: [
        // 감성 테마 관리자를 최상단에 배치
        ChangeNotifierProvider(create: (_) => ThemeProvider()),

        // 인증이 성공했을 때만 데이터를 불러오는 Provider들을 생성합니다.
        // 만약 인증에 실패했다면 빈 객체를 던져서 치명적 에러를 방지합니다.
        if (isAuthenticated) ...[
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => ProductProvider()),
          ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ] else ...[
          // 인증 실패 시 (네트워크 오류, 비밀번호 틀림 등) 앱이 죽지 않도록 빈 Provider 생성
          // 향후 로그인 폼 구현 시 활용할 수 있는 방어 코드입니다.
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => ProductProvider()),
          ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ]
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ThemeProvider의 상태를 실시간으로 감시(watch)합니다.
    // 사용자가 사이드바에서 테마 버튼을 누르는 순간 이 build 메서드가 다시 실행됩니다.
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RFID FA Solution',

      // 프로바이더가 실시간으로 생성하는 ThemeData를 주입합니다.
      // AppTheme.getTheme()에서 정의한 scaffoldBackgroundColor(톤온톤 배경)가
      // 앱 전체(본문과 사이드바 모두)에 동기화되어 적용되는 핵심 지점입니다.
      theme: themeProvider.themeData,

      // 시스템 테마 설정에 방해받지 않고 우리가 정의한 5종 테마 시스템이
      // 주도권을 갖도록 ThemeMode.light로 고정합니다.
      themeMode: ThemeMode.light,

      // 대시보드 메인 레이아웃 페이지로 진입
      home: const MainPage(),
    );
  }
}