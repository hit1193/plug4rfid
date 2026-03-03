import 'package:flutter/material.dart';

/// 앱 전체에서 사용할 디자인 시스템 상수 및 테마 정의
/// C++Builder의 전역 스타일 시트나 공통 헤더와 같은 역할을 합니다.
class AppTheme {
  // 폰트 및 기본 색상 정의
  static const String fontPretendard = 'Pretendard';
  static const Color primary = Color(0xFF6366F1);
  static const Color surface = Colors.white; // 상세 리스트 배경색 일원화
  static const Color border = Color(0xFF94A3B8);
  static const Color headerBg = Color(0xFFF1F5F9);
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);

  // --- UX 세부 설정 상수 ---
  static const TextStyle inputHintStyle = TextStyle(
    color: Colors.black12,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle inputLabelStyle = TextStyle(
    color: Colors.black38,
    fontSize: 13,
    fontWeight: FontWeight.bold,
  );

  static const Color inputFillColor = Color(0xFFF8F9FA);
  static const Color inputFocusColor = Colors.white;
  static const Color inputBorderColor = Colors.black26;
  static const double buttonElevation = 0.0;
  static const double outlineWidth = 2.0;

  static TextStyle get headerStyle => const TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w900,
    fontFamily: fontPretendard,
    color: Colors.black,
  );

  /// MaterialApp의 theme 속성에 할당할 수 있는 ThemeData 객체
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
        fillColor: inputFillColor,
        labelStyle: inputLabelStyle,
        hintStyle: inputHintStyle,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: inputBorderColor, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primary, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger, width: 1.0),
        ),
      ),

      // 버튼 테마 설정 (Flat 스타일 구현을 위해 WidgetStateProperty 사용)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(primary),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          // [수정] 모든 상태에서 그림자를 제거하여 완벽한 Flat 스타일 구현
          elevation: WidgetStateProperty.all(0),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return Colors.white10;
            if (states.contains(WidgetState.hovered)) return Colors.white.withValues(alpha: 0.05);
            return null;
          }),
          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colors.black54,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}