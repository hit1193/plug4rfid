import 'package:flutter/material.dart';

/// 앱에서 제공하는 5종 감성 테마 열거형입니다.
/// 각 테마는 브랜드 컬러와 그에 맞춘 톤온톤(ToT) 배경색을 가집니다.
enum AppThemeType {
  pureWhite,  // 순백색 미니멀
  industrial, // 전문가용 Blue 기반
  forest,     // 자연/안정 Green 기반
  solar,      // 활기/에너지 Amber 기반
  midnight    // 집중/심야 Navy 기반 (다크모드)
}

class AppTheme {
  // 전역 디자인 토큰 및 폰트 설정
  static const String fontPretendard = 'Pretendard';
  static const double cardRadius = 12.0;

  // [수정] 지시하신 실버 색상 정의 및 브랜드 컬러
  static const Color silver = Color(0xFFC0C0C0);
  static const Color primary = Color(0xFF6366F1);
  static const Color colorPureWhite = Color(0xFF475569);
  static const Color colorIndustrial = primary;
  static const Color colorForest = Color(0xFF10B981);
  static const Color colorSolar = Color(0xFFF59E0B);
  static const Color colorMidnight = Color(0xFF6366F1);

  // FA 현장 상태별 공통 컬러
  static const Color success = Color(0xFF36B37E);
  static const Color warning = Color(0xFFFFAB00);
  static const Color danger = Color(0xFFFF5630);
  static const Color inactive = Color(0xFF475569);

  /// 테마 타입에 따라 동적으로 적용된 ThemeData를 생성하여 반환합니다.
  static ThemeData getTheme(AppThemeType type) {
    switch (type) {
      case AppThemeType.pureWhite:
        return _buildTheme(colorPureWhite, Brightness.light, Colors.white);
      case AppThemeType.industrial:
        return _buildTheme(colorIndustrial, Brightness.light, const Color(0xFFF5F7FF));
      case AppThemeType.forest:
        return _buildTheme(colorForest, Brightness.light, const Color(0xFFF0FDF4));
      case AppThemeType.solar:
        return _buildTheme(colorSolar, Brightness.light, const Color(0xFFFFFBF0));
      case AppThemeType.midnight:
        return _buildTheme(colorMidnight, Brightness.dark, const Color(0xFF0F172A));
    }
  }

  /// 공통 테마 빌더: 미니멀리즘 및 키오스크 스타일 전역 설정
  static ThemeData _buildTheme(Color seedColor, Brightness brightness, Color scaffoldBg) {
    final bool isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontPretendard,
      scaffoldBackgroundColor: scaffoldBg,

      // 전역 텍스트 테마: Semi Bold(w600)를 표준으로 채택하여 또렷함 유지
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.4),
        bodyMedium: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.3),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.6),
      ),

      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
        primary: seedColor,
        surface: isDark ? const Color(0xFF1E293B) : Colors.white,
      ),

      // [디자인] 입력창 테마: labelText, hintText에 Silver 색상 및 Semi Bold 적용
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        // HintText: 실버 색상 적용
        hintStyle: const TextStyle(
          color: silver,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        // LabelText: 실버 색상 및 Semi Bold(w600)로 또렷하게
        labelStyle: const TextStyle(
          fontFamily: fontPretendard,
          color: silver,
          fontWeight: FontWeight.w600,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.2),
            width: 2.0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: seedColor, width: 2.5),
        ),
      ),

      // [디자인] 버튼 테마: 그림자 제거(Elevation 0) 및 Semi Bold 적용
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontFamily: fontPretendard,
            fontWeight: FontWeight.w600,
            fontSize: 16,
            letterSpacing: -0.2,
          ),
        ),
      ),

      // [디자인] 카드 테마: 또렷한 외곽선 처리
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1),
            width: 2.0,
          ),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1),
        thickness: 1.5,
      ),
    );
  }

  // --- 위젯 가독성 및 하위 페이지 호환성을 위한 정적 헬퍼 메서드 ---

  static Color dataColor(bool isDark) => isDark ? Colors.white : const Color(0xFF0F172A);

  /// 레이블 전용 컬러: 다크모드 대응을 포함한 실버 톤 유지
  static Color labelColor(bool isDark) => isDark ? silver.withValues(alpha: 0.8) : silver;

  /// 리스트뷰 및 상세 정보의 값(Value) 스타일: Semi Bold로 또렷하게 표현
  static TextStyle itemValueStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 17,
      color: dataColor(isDark),
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
    );
  }

  /// [수정] 리스트뷰의 항목 설명 라벨(Label) 스타일:
  /// 지시하신 대로 Silver 색상을 적용하고 Semi Bold(w600)로 또렷하게 처리
  static TextStyle itemLabelStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 13,
      color: labelColor(isDark), // Silver 색상 적용
      fontWeight: FontWeight.w600, // Semi Bold로 또렷하게
      letterSpacing: -0.2,
    );
  }

  /// 섹션 타이틀 위젯
  static Widget dialogTitle(String text, IconData icon, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color ?? primary, size: 28),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: fontPretendard,
              fontWeight: FontWeight.w700,
              fontSize: 22,
              letterSpacing: -0.8,
            ),
          ),
        ),
      ],
    );
  }

  /// 리스트 아이템 데코레이션: 또렷한 외곽선과 톤온톤 배경 조합
  static BoxDecoration listItemDecoration(BuildContext context, {required bool isSelected, required Color statusColor}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    Color finalBorderColor = isSelected ? theme.colorScheme.primary : statusColor;

    return BoxDecoration(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.1)
          : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(
        color: finalBorderColor,
        width: isSelected ? 2.5 : 2.0,
      ),
    );
  }

  /// 입력 필드 데코레이션: Silver 가이드 텍스트와 또렷한 테두리 강제 적용
  static InputDecoration inputDecoration({
    required String label,
    required BuildContext context,
    String? hint,
    IconData? prefixIcon,
    bool hasFocus = false,
  }) {
    final theme = Theme.of(context);

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontFamily: fontPretendard,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: hasFocus ? theme.colorScheme.primary : silver, // Silver 색상 적용
      ),
      hintText: hint,
      hintStyle: const TextStyle(
        color: silver, // Silver 색상 적용
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 22, color: hasFocus ? theme.colorScheme.primary : silver)
          : null,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: theme.brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.2),
          width: 2.0,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2.5),
      ),
    );
  }

  /// 공통 액션 버튼 헬퍼: 그림자 없는 미니멀 스타일 및 Semi Bold 적용
  static Widget actionButton({
    required String label,
    required VoidCallback onPressed,
    Color? color,
    Color? textColor,
    IconData? icon,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? primary,
        foregroundColor: textColor ?? Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Text(
              label,
              style: const TextStyle(
                fontFamily: fontPretendard,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              )
          ),
        ],
      ),
    );
  }
}