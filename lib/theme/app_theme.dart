import 'package:flutter/material.dart';

/// 앱에서 제공하는 5종 감성 테마 열거형입니다.
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

  // [디자인 정책] 폰트 두께 정의
  static const FontWeight weightMenu = FontWeight.w800;     // 메뉴 및 타이틀 (Pretendard Bold)
  static const FontWeight weightOthers = FontWeight.w600;   // 일반 본문 및 데이터 (Pretendard SemiBold)

  // 색상 정의
  static const Color silver = Color(0xFFC0C0C0);
  static const Color primary = Color(0xFF6366F1);
  static const Color colorPureWhite = Color(0xFF475569);
  static const Color colorIndustrial = primary;
  static const Color colorForest = Color(0xFF10B981);
  static const Color colorSolar = Color(0xFFF59E0B);
  static const Color colorMidnight = Color(0xFF6366F1);

  // 상태 컬러
  static const Color success = Color(0xFF36B37E);
  static const Color warning = Color(0xFFFFAB00);
  static const Color danger = Color(0xFFFF5630);

  /// 테마 타입에 따라 동적으로 적용된 ThemeData를 생성합니다.
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

  static ThemeData _buildTheme(Color seedColor, Brightness brightness, Color scaffoldBg) {
    final bool isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontPretendard,
      scaffoldBackgroundColor: scaffoldBg,

      // [수정] 전역 텍스트 테마: 본문은 SemiBold(w600)로 통일하여 또렷함 유지
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontWeight: weightOthers, letterSpacing: -0.4),
        bodyMedium: TextStyle(fontWeight: weightOthers, letterSpacing: -0.3),
        titleLarge: TextStyle(fontWeight: weightMenu, letterSpacing: -0.8), // 메뉴/타이틀은 Bold
      ),

      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
        primary: seedColor,
        surface: isDark ? const Color(0xFF1E293B) : Colors.white,
      ),

      // [수정] 입력창 테마: 실버 색상 가이드 및 SemiBold 적용
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        hintStyle: const TextStyle(color: silver, fontWeight: weightOthers, fontSize: 14),
        labelStyle: const TextStyle(fontFamily: fontPretendard, color: silver, fontWeight: weightOthers),
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

      // [수정] 버튼 테마: 메뉴 성격의 요소이므로 Bold(w800) 적용
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontFamily: fontPretendard, fontWeight: weightMenu, fontSize: 16),
        ),
      ),

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

  // --- 정적 헬퍼 메서드 (통일된 폰트 정책 반영) ---

  static Color dataColor(bool isDark) => isDark ? Colors.white : const Color(0xFF0F172A);
  static Color labelColor(bool isDark) => isDark ? silver.withValues(alpha: 0.8) : silver;

  /// 데이터 값 스타일: SemiBold(w600)로 통일
  static TextStyle itemValueStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 17,
      color: dataColor(isDark),
      fontWeight: weightOthers, // SemiBold 적용
      letterSpacing: -0.4,
    );
  }

  /// 항목 설명 라벨 스타일: 실버 색상 및 SemiBold(w600) 적용
  static TextStyle itemLabelStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 13,
      color: labelColor(isDark),
      fontWeight: weightOthers, // SemiBold 적용
      letterSpacing: -0.2,
    );
  }

  /// 섹션 타이틀 위젯: 메뉴 성격이므로 Bold(w800) 적용
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
              fontWeight: weightMenu, // Bold 적용
              fontSize: 22,
              letterSpacing: -0.8,
            ),
          ),
        ),
      ],
    );
  }

  static BoxDecoration listItemDecoration(BuildContext context, {required bool isSelected, required Color statusColor}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    Color finalBorderColor = isSelected ? theme.colorScheme.primary : statusColor;

    return BoxDecoration(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.1)
          : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(color: finalBorderColor, width: isSelected ? 2.5 : 2.0),
    );
  }

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
      labelStyle: TextStyle(fontFamily: fontPretendard, fontSize: 14, fontWeight: weightOthers, color: hasFocus ? theme.colorScheme.primary : silver),
      hintText: hint,
      hintStyle: const TextStyle(color: silver, fontWeight: weightOthers, fontSize: 14),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 22, color: hasFocus ? theme.colorScheme.primary : silver) : null,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.2), width: 2.0),
      ),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: theme.colorScheme.primary, width: 2.5)),
    );
  }

  static Widget actionButton({required String label, required VoidCallback onPressed, Color? color, Color? textColor, IconData? icon}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? primary,
        foregroundColor: textColor ?? Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Text(label, style: const TextStyle(fontFamily: fontPretendard, fontWeight: weightMenu)), // Bold 적용
        ],
      ),
    );
  }
}