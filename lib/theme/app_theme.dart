import 'package:flutter/material.dart';

class AppTheme {
  // [포인트 컬러] 시니어 개발자님이 정립하신 Vibrant Indigo
  static const Color primary = Color(0xFF6366F1);
  static const Color success = Color(0xFF36B37E);
  static const Color warning = Color(0xFFFFAB00);
  static const Color danger = Color(0xFFFF5630);

  static const String fontPretendard = 'Pretendard';

  // [중앙 관리 색상]
  // 1. 실제 데이터 값: 세련된 다크그레이 (#454545)
  static Color dataColor(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.85)
      : const Color(0xFF454545);

  // 2. 레이블(항목명): 요청하신 Silver (#C0C0C0)
  static Color labelColor(bool isDark) => isDark
      ? const Color(0xFFC0C0C0).withValues(alpha: 0.7)
      : const Color(0xFFC0C0C0);

  // 3. 힌트 및 가이드: 시인성을 위해 아주 연하게 보정
  static Color hintColor(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.black.withValues(alpha: 0.07);

  // 4. 외곽선: 폼의 윤곽을 잡기 위한 농도
  static Color borderColor(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.25)
      : Colors.black.withValues(alpha: 0.22);

  static const double cardRadius = 12.0;

  // --- [신규] 리스트뷰 전용 통합 텍스트 스타일 ---

  // 데이터 값 스타일 (Dark Gray, w900 - Black급 굵기)
  static TextStyle itemValueStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: 15,
      color: dataColor(isDark),
      fontWeight: FontWeight.w900,
    );
  }

  // 레이블 스타일 (Silver, bold)
  static TextStyle itemLabelStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: 12,
      color: labelColor(isDark),
      fontWeight: FontWeight.bold,
    );
  }

  // 리스트 카드 데코레이션 (배경 및 테두리 통합)
  static BoxDecoration listItemDecoration(BuildContext context, {
    required bool isSelected,
    required Color statusColor,
  }) {
    final theme = Theme.of(context);
    return BoxDecoration(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.02)
          : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(
        color: isSelected ? theme.colorScheme.primary : statusColor,
        width: isSelected ? 2.5 : 1.5,
      ),
    );
  }

  // --- 공용 UI 컴포넌트 빌더 ---

  static Widget dialogTitle(String text, IconData icon, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color ?? primary, size: 26),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: -0.5),
        ),
      ],
    );
  }

  static InputDecoration inputDecoration({
    required String label,
    required BuildContext context,
    String? hint,
    IconData? prefixIcon,
    bool hasFocus = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = primary;

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: hasFocus ? activeColor : labelColor(isDark),
      ),
      hintText: hint,
      hintStyle: TextStyle(color: hintColor(isDark), fontWeight: FontWeight.normal),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20, color: hasFocus ? activeColor : labelColor(isDark)) : null,
      filled: true,
      fillColor: isDark ? const Color(0xFF262A35) : const Color(0xFFF8F9FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor(isDark), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: activeColor, width: 2.5),
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
        backgroundColor: color ?? primary,
        foregroundColor: textColor ?? Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }

  // --- 테마 데이터 정의 (CardThemeData 타입 에러 해결) ---

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: fontPretendard,
    scaffoldBackgroundColor: Colors.white,
    colorScheme: ColorScheme.fromSeed(seedColor: primary, primary: primary, surface: Colors.white),
    dividerTheme: const DividerThemeData(color: Color(0xFFE9ECEF), thickness: 1),
    // [해결] CardThemeData를 명시적으로 사용하여 타입 불일치 방지
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: const BorderSide(color: Color(0xFFE9ECEF), width: 1.5),
      ),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: fontPretendard,
    scaffoldBackgroundColor: const Color(0xFF12141C),
    colorScheme: const ColorScheme.dark(primary: primary, surface: Color(0xFF1E212A), onSurface: Colors.white),
    dividerTheme: const DividerThemeData(color: Color(0xFF333846), thickness: 1),
    // [해결] CardThemeData를 명시적으로 사용하여 타입 불일치 방지
    cardTheme: CardThemeData(
      elevation: 0,
      color: const Color(0xFF1E212A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: const BorderSide(color: Color(0xFF333846), width: 1.5),
      ),
    ),
  );
}