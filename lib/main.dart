import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

// 페이지 위젯
import 'pages/main_page.dart';

// 프로바이더 클래스
import 'providers/person_provider.dart';
import 'providers/product_provider.dart';
import 'providers/device_provider.dart';
import 'providers/theme_provider.dart';

// 테마 설정
import 'theme/app_theme.dart';

void main() async {
  // 플러터 프레임워크 초기화 보장
  WidgetsFlutterBinding.ensureInitialized();

  // 데스크톱(Windows) 환경을 위한 키오스크 모드 및 윈도우 설정
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1440, 760),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      fullScreen: true,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      // 실행 시 즉시 전체화면으로 전환하여 키오스크 느낌 부여
      await windowManager.setFullScreen(true);
    });
  }

  runApp(
    // 앱 전역에서 사용할 상태 관리자들을 멀티 프로바이더로 등록
    MultiProvider(
      providers: [
        // 테마 제어 프로바이더 (최상단 배치)
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        // 업무 로직 프로바이더들
        ChangeNotifierProvider(create: (_) => PersonProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ThemeProvider의 변화를 실시간으로 감시합니다.
    // themeProvider.toggleTheme() 호출 시 이 build 함수가 다시 실행되어 테마가 전환됩니다.
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RFID FA Solution',

      // AppTheme에 정립된 미니멀 디자인 테마 연결
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,

      // ThemeProvider의 상태에 따라 현재 테마 모드 결정
      themeMode: themeProvider.themeMode,

      // 메인 대시보드 페이지로 시작
      home: const MainPage(),
    );
  }
}