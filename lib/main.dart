import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

import 'pages/main_page.dart';
import 'providers/person_provider.dart';
import 'providers/device_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();

    // 1920x1080 (125%) 환경 최적화 설정
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1440, 760),
      // [수정] 최소 폭을 400으로 낮추어 모바일 모드(650px 이하) 전환 테스트가 가능하게 합니다.
      minimumSize: Size(400, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PersonProvider()),
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RFID FA Solution',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Pretendard',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
          surface: const Color(0xFFF1F5F9),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18.0, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
          bodyMedium: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
        ),
      ),
      home: const MainPage(),
    );
  }
}