import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

// 테마 및 페이지 임포트
import 'pages/main_page.dart';
import 'theme/app_theme.dart';

// 프로바이더 임포트
import 'providers/person_provider.dart';
import 'providers/product_provider.dart';
import 'providers/device_provider.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 데스크톱 키오스크 설정을 위한 윈도우 매니저 초기화
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1440, 760),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // 타이틀바 제거로 미니멀함 강조
      fullScreen: true,
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
        // 테마 관리자를 최상단에 배치하여 앱 전역의 스타일 변경을 감시
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
    // [중요] ThemeProvider의 상태를 실시간으로 감시(Watch)합니다.
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RFID FA Solution',

      // [수정 핵심] 프로바이더가 실시간으로 제공하는 ThemeData를 직접 주입합니다.
      // 이 연결이 있어야 테마 버튼 클릭 시 배경색이 즉시 변화합니다.
      theme: themeProvider.themeData,

      // 시스템 설정에 구애받지 않고 우리만의 감성 테마 시스템이 작동하도록 설정
      themeMode: ThemeMode.light,

      home: const MainPage(),
    );
  }
}