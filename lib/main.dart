import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

// 테마 및 페이지 설정 임포트
import 'pages/main_page.dart';
import 'theme/app_theme.dart';

// 상태 관리를 위한 프로바이더 임포트
import 'providers/person_provider.dart';
import 'providers/product_provider.dart';
import 'providers/device_provider.dart';
import 'providers/theme_provider.dart';

void main() async {
  // 플러터 엔진 초기화
  WidgetsFlutterBinding.ensureInitialized();

  // 데스크톱(Windows) 환경을 위한 키오스크 스타일 UI 설정
  if (Platform.isWindows) {
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

  runApp(
    MultiProvider(
      providers: [
        // [핵심] 감성 테마 관리자를 최상단에 배치
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
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
    // [중요] ThemeProvider의 상태를 실시간으로 감시(watch)합니다.
    // 사용자가 사이드바에서 테마 버튼을 누르는 순간 이 build 메서드가 다시 실행됩니다.
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RFID FA Solution',

      // [해결 포인트] 프로바이더가 실시간으로 생성하는 ThemeData를 주입합니다.
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