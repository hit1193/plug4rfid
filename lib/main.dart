import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

import 'pages/main_page.dart';
import 'providers/person_provider.dart';
import 'providers/product_provider.dart';
import 'providers/device_provider.dart';
import 'providers/theme_provider.dart'; // [추가] 테마 프로바이더 임포트
import 'theme/app_theme.dart'; // [추가] 테마 설정 임포트

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1440, 760),
      minimumSize: Size(400, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      fullScreen: true,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setFullScreen(true);
    });
  }

  runApp(
    // [핵심] ThemeProvider를 추가하여 앱 전체에서 테마 상태를 공유합니다.
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()), // 테마 제어 추가
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
    // [핵심] ThemeProvider의 상태를 감시(Watch)하여 변경 시 앱 전체를 리렌더링합니다.
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RFID FA Solution',

      // 우리가 정립한 AppTheme의 라이트/다크 설정을 연결합니다.
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,

      // 현재 선택된 테마 모드 (System, Light, Dark)를 결정합니다.
      themeMode: themeProvider.themeMode,

      home: const MainPage(),
    );
  }
}