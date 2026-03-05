import 'package:flutter/material.dart';

/// 앱에서 제공하는 감성 테마의 종류를 정의하는 열거형입니다.
enum AppThemeType {
  industrial, // 전문적/신뢰 (Blue - 기본)
  forest,     // 자연/안정 (Green - 봄/가을)
  solar,      // 활기/에너지 (Amber - 여름)
  midnight    // 집중/심야 (Navy - 겨울/다크)
}

class AppTheme {
  // 폰트 및 기본 디자인 토큰 설정
  static const String fontPretendard = 'Pretendard';
  static const double cardRadius = 12.0;

  // [유지] 기존 코드에서 'AppTheme.primary'로 참조하는 기본 브랜드 컬러
  static const Color primary = Color(0xFF6366F1);

  // 각 테마별 핵심 씨앗 색상 (Seed Colors)
  static const Color colorIndustrial = primary;         // Indigo Blue
  static const Color colorForest = Color(0xFF10B981);     // Emerald Green
  static const Color colorSolar = Color(0xFFF59E0B);      // Amber Orange
  static const Color colorMidnight = Color(0xFF334155);   // Slate Navy

  // FA 현장 상태별 공통 색상 정의
  static const Color success = Color(0xFF36B37E);
  static const Color warning = Color(0xFFFFAB00);
  static const Color danger = Color(0xFFFF5630);
  static const Color inactive = Color(0xFF475569);

  // [복구] main.dart에서 발생하는 'Member not found' 에러 해결을 위한 정적 게터
  // 기존 lightTheme 호출 시 가장 표준인 Industrial 테마를 반환합니다.
  static ThemeData get lightTheme {
    return getTheme(AppThemeType.industrial);
  }

  // [복구] main.dart에서 발생하는 'Member not found' 에러 해결을 위한 정적 게터
  // 기존 darkTheme 호출 시 Midnight 테마를 반환합니다.
  static ThemeData get darkTheme {
    return getTheme(AppThemeType.midnight);
  }

  // [유지] 기존 페이지에서 텍스트 색상 결정 시 참조하는 정적 메서드
  static Color dataColor(bool isDark) {
    if (isDark) {
      return const Color(0xFFE9ECEF); // 다크모드: 밝은 그레이
    } else {
      return const Color(0xFF2D2E33); // 라이트모드: 깊은 다크 그레이
    }
  }

  // [유지] 기존 페이지에서 레이블 색상 결정 시 참조하는 정적 메서드
  static Color labelColor(bool isDark) {
    if (isDark) {
      return const Color(0xFF718096); // 다크모드: 중간 그레이
    } else {
      return const Color(0xFFA0AEC0); // 라이트모드: 연한 실버 그레이
    }
  }

  /// 선택된 테마 타입에 맞는 전체 ThemeData를 생성하여 반환합니다.
  static ThemeData getTheme(AppThemeType type) {
    switch (type) {
      case AppThemeType.industrial:
        return _buildTheme(colorIndustrial, Brightness.light, const Color(0xFFF1F5F9));
      case AppThemeType.forest:
        return _buildTheme(colorForest, Brightness.light, const Color(0xFFF0FDF4));
      case AppThemeType.solar:
        return _buildTheme(colorSolar, Brightness.light, const Color(0xFFFFFBEB));
      case AppThemeType.midnight:
        return _buildTheme(colorMidnight, Brightness.dark, const Color(0xFF0F172A));
    }
  }

  /// Material 3 기반의 테마 빌드 로직 (내부 전용)
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

      // 카드 디자인 통일
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1.5,
          ),
        ),
      ),

      // 구분선 스타일
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        thickness: 1,
      ),

      // 버튼 디자인 통일
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
              fontFamily: fontPretendard,
              fontWeight: FontWeight.w700,
              fontSize: 15
          ),
        ),
      ),
    );
  }

  // --- UI 컴포넌트용 정적 도우미 메서드 ---

  static TextStyle itemValueStyle(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 17,
      color: dataColor(isDark),
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    );
  }

  static TextStyle itemLabelStyle(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 14,
      color: labelColor(isDark),
      fontWeight: FontWeight.w600,
    );
  }

  static Widget dialogTitle(String text, IconData icon, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color ?? primary, size: 26),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(
              fontFamily: fontPretendard,
              fontWeight: FontWeight.w800,
              fontSize: 20
          ),
        ),
      ],
    );
  }

  static BoxDecoration listItemDecoration(BuildContext context, {
    required bool isSelected,
    required Color statusColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color finalBorderColor;
    if (isSelected) {
      finalBorderColor = theme.colorScheme.primary;
    } else {
      final bool isStandardStatus = (statusColor == success || statusColor == warning);
      finalBorderColor = isStandardStatus
          ? statusColor.withValues(alpha: isDark ? 0.8 : 0.75)
          : statusColor;
    }

    return BoxDecoration(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.05)
          : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(
          color: finalBorderColor,
          width: isSelected ? 2.5 : 1.8
      ),
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
    final isDark = theme.brightness == Brightness.dark;

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontFamily: fontPretendard,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: hasFocus
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      hintText: hint,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 20, color: hasFocus ? theme.colorScheme.primary : null)
          : null,
      filled: true,
      fillColor: isDark ? const Color(0xFF262A35) : const Color(0xFFF8F9FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.dividerTheme.color!, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2.5),
      ),
    );
  }

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
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Text(label),
        ],
      ),
    );
  }
}