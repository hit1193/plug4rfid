import 'package:flutter/material.dart';

/// 앱에서 제공하는 5종 감성 테마 열거형입니다.
enum AppThemeType {
  pureWhite,  // 순백색/미니멀 (기본 시작 테마)
  industrial, // 전문가용/신뢰 (Blue 기반)
  forest,     // 자연/안정 (Green 기반)
  solar,      // 활기/에너지 (Amber 기반)
  midnight    // 집중/심야 (Navy 다크모드)
}

class AppTheme {
  // 전역 폰트 및 디자인 토큰 정의
  static const String fontPretendard = 'Pretendard';
  static const double cardRadius = 12.0;

  // 각 테마별 핵심 브랜드 컬러 (Seed Colors)
  static const Color primary = Color(0xFF6366F1);
  static const Color colorPureWhite = Color(0xFF475569);
  static const Color colorIndustrial = primary;
  static const Color colorForest = Color(0xFF10B981);
  static const Color colorSolar = Color(0xFFF59E0B);
  static const Color colorMidnight = Color(0xFF334155);

  // 공정 및 업무 상태 알림용 공통 컬러
  static const Color success = Color(0xFF36B37E);
  static const Color warning = Color(0xFFFFAB00);
  static const Color danger = Color(0xFFFF5630);
  static const Color inactive = Color(0xFF475569);

  /// 테마 타입에 따라 배경색(ToT)이 적용된 ThemeData를 생성합니다.
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

  /// 공통 테마 빌더: 지시하신 입력 필드 스타일(또렷한 Outline, 연한 Hint/Label)을 전역 적용합니다.
  static ThemeData _buildTheme(Color seedColor, Brightness brightness, Color scaffoldBg) {
    final bool isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontPretendard,
      scaffoldBackgroundColor: scaffoldBg,

      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
        primary: seedColor,
        surface: isDark ? const Color(0xFF1E293B) : Colors.white,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
            width: 1.5,
          ),
        ),
      ),

      // [수정] 전역 입력창 디자인: Outline은 또렷하게(alpha 0.5), Hint/Label은 연하게(alpha 0.3)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF262A35) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        // HintText 연하게
        hintStyle: TextStyle(
          color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2),
          fontSize: 14,
        ),
        // LabelText 연하게
        labelStyle: TextStyle(
          color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.4),
          fontWeight: FontWeight.w600,
        ),
        // 평상시 외곽선: 또렷하게 (기존 0.12 -> 0.5로 강화)
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        // 포커스 시 외곽선: 테마 메인 컬러 적용
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: seedColor, width: 2.5),
        ),
      ),

      // 버튼 디자인: 그림자 제거(Elevation 0) 및 굵은 텍스트 유지
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontFamily: fontPretendard, fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: seedColor,
          side: BorderSide(color: seedColor, width: 1.5),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontFamily: fontPretendard, fontWeight: FontWeight.w700),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: seedColor,
          elevation: 0,
          textStyle: const TextStyle(fontFamily: fontPretendard, fontWeight: FontWeight.w700),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        thickness: 1,
      ),
    );
  }

  // --- 기존 헬퍼 메서드 유지 ---

  static Color dataColor(bool isDark) => isDark ? const Color(0xFFE9ECEF) : const Color(0xFF2D2E33);
  static Color labelColor(bool isDark) => isDark ? const Color(0xFF718096) : const Color(0xFFA0AEC0);

  static TextStyle itemValueStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(fontFamily: fontPretendard, fontSize: 17, color: dataColor(isDark), fontWeight: FontWeight.w700);
  }

  static TextStyle itemLabelStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(fontFamily: fontPretendard, fontSize: 14, color: labelColor(isDark), fontWeight: FontWeight.w600);
  }

  static Widget dialogTitle(String text, IconData icon, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color ?? primary, size: 26),
        const SizedBox(width: 12),
        Flexible(child: Text(text, style: const TextStyle(fontFamily: fontPretendard, fontWeight: FontWeight.w800, fontSize: 20))),
      ],
    );
  }

  static BoxDecoration listItemDecoration(BuildContext context, {required bool isSelected, required Color statusColor}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    Color finalBorderColor;
    if (isSelected) {
      finalBorderColor = theme.colorScheme.primary;
    } else {
      final bool isStandardStatus = statusColor == success || statusColor == warning;
      finalBorderColor = isStandardStatus ? statusColor.withValues(alpha: isDark ? 0.8 : 0.75) : statusColor.withValues(alpha: 1.0);
    }
    return BoxDecoration(
      color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.05) : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(color: finalBorderColor, width: isSelected ? 2.5 : 1.8),
    );
  }

  /// [수정] 개별 페이지 호출용 입력 필드 스타일: Outline 또렷하게, Hint/Label 연하게 강제 적용
  static InputDecoration inputDecoration({
    required String label,
    required BuildContext context,
    String? hint,
    IconData? prefixIcon,
    bool hasFocus = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color currentPrimary = theme.colorScheme.primary;

    return InputDecoration(
      labelText: label,
      // Label 연하게 (기존보다 더 연한 alpha 0.4 적용)
      labelStyle: TextStyle(
        fontFamily: fontPretendard,
        fontWeight: FontWeight.w600,
        color: hasFocus ? currentPrimary : (isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.4)),
      ),
      hintText: hint,
      // Hint 연하게 (alpha 0.2 적용)
      hintStyle: TextStyle(
        color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2),
        fontSize: 14,
      ),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20, color: hasFocus ? currentPrimary : (isDark ? Colors.white24 : Colors.black26)) : null,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        // Outline 또렷하게 (alpha 0.45로 강화)
        borderSide: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: currentPrimary, width: 2.5),
      ),
    );
  }

  /// 공통 액션 버튼 헬퍼: 그림자 제거 및 굵은 글씨 유지
  static Widget actionButton({
    required String label,
    required VoidCallback onPressed,
    Color? color,
    Color? textColor,
    IconData? icon,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Text(label, style: const TextStyle(fontFamily: fontPretendard, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}