import 'package:flutter/material.dart';

/// 앱 전체에서 사용할 디자인 시스템 상수 및 테마 정의
/// C++Builder의 전역 스타일 시트나 공통 헤더와 같은 역할을 합니다.
class AppTheme {
  // 폰트 및 기본 색상 정의
  static const String fontPretendard = 'Pretendard';
  static const Color primary = Color(0xFF6366F1);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color border = Color(0xFF94A3B8);
  static const Color headerBg = Color(0xFFF1F5F9);
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);

  // 고정 텍스트 스타일
  static TextStyle get headerStyle => const TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w900,
    fontFamily: fontPretendard,
    color: Colors.black,
  );

  /// MaterialApp의 theme 속성에 할당할 수 있는 ThemeData 객체를 생성합니다.
  /// FA/RFID 현장용 앱의 시인성을 고려하여 깔끔한 스타일을 기본으로 합니다.
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        surface: surface,
        error: danger,
      ),
      fontFamily: fontPretendard,
      scaffoldBackgroundColor: Colors.white,

      // 입력창(TextField) 기본 디자인 설정
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primary, width: 2.0),
        ),
      ),

      // 버튼 기본 디자인 설정
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}