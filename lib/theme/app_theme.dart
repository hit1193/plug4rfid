import 'package:flutter/material.dart';

/// 앱 전체에서 사용할 디자인 시스템 상수 및 테마 정의
/// Material 3의 특성인 입체감(Elevation/Tint)을 FA 환경에 맞게 원천 차단합니다.
class AppTheme {
  // 폰트 및 기본 색상 정의
  static const String fontPretendard = 'Pretendard';
  static const Color primary = Color(0xFF6366F1);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFF94A3B8);
  static const Color headerBg = Color(0xFFF1F5F9);
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);

  static const Color dividerColor = Color(0xFFE9ECEF);

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
  static const double cardRadius = 16.0;

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

      // 구분선 테마
      dividerTheme: const DividerThemeData(
        color: dividerColor,
        thickness: 1.0,
        space: 1.0,
      ),

      // SegmentedButton 테마 (Pill 스타일)
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          side: const BorderSide(color: primary, width: outlineWidth),
          backgroundColor: Colors.white,
          selectedBackgroundColor: primary,
          selectedForegroundColor: Colors.white,
          foregroundColor: Colors.black54,
        ),
      ),

      // 입력창 테마
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
      ),

      // [핵심 수정] 모든 상태에서 입체감 효과(Shadow/Tint)를 제거하여 완벽한 Flat 스타일 구현
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,                   // 고정 그림자 제거
          shadowColor: Colors.transparent, // 그림자 색상 제거 (잔상 방지)
          surfaceTintColor: Colors.transparent, // Material 3 특유의 푸르스름한 색조 제거
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // 텍스트 버튼 (취소용)
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colors.black54,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}