import 'package:flutter/material.dart';
import 'pages/main_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RFID FA Solution',
      // 앱 전체 테마 설정
      theme: ThemeData(
        useMaterial3: true,
        // 1. 폰트 패밀리 설정 (pubspec.yaml에 등록된 이름과 일치해야 함)
        fontFamily: 'Pretendard',

        // 2. 기본 텍스트 테마 정의
        textTheme: const TextTheme(
          bodyLarge: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w700, // Bold
            color: Color(0xFF333333),    // 블랙보다 약간 연한 색
          ),
          bodyMedium: TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.w600, // Semi-bold
            color: Color(0xFF444444),
          ),
        ),

        // 3. 앱바 등 기본 색상 제어
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF333333),
          elevation: 0,
        ),
      ),
      home: const MainPage(),
    );
  }
}