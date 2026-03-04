import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF6366F1);
  static const Color success = Color(0xFF36B37E);
  static const Color warning = Color(0xFFFFAB00);
  static const Color danger = Color(0xFFFF5630);

  static const String fontPretendard = 'Pretendard';

  static Color dataColor(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.85)
      : const Color(0xFF454545);

  static Color labelColor(bool isDark) => isDark
      ? const Color(0xFFC0C0C0).withValues(alpha: 0.7)
      : const Color(0xFFC0C0C0);

  static const double cardRadius = 12.0;

  static TextStyle itemValueStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 15,
      color: dataColor(isDark),
      fontWeight: FontWeight.w900,
    );
  }

  static TextStyle itemLabelStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 12,
      color: labelColor(isDark),
      fontWeight: FontWeight.bold,
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
              fontWeight: FontWeight.bold,
              fontSize: 20,
              letterSpacing: -0.5
          ),
        ),
      ],
    );
  }

  // --- [수정] 리스트 아이템 데코레이션: 상태색을 테두리(Outline)에 적용 ---
  static BoxDecoration listItemDecoration(BuildContext context, {
    required bool isSelected,
    required Color statusColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 선택되지 않았을 때 테두리에 상태색을 은은하게 적용 (알파값 조절로 고급스러움 유지)
    final Color borderColor = isSelected
        ? theme.colorScheme.primary
        : statusColor.withValues(alpha: isDark ? 0.6 : 0.5);

    return BoxDecoration(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.02)
          : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(
        color: borderColor,
        width: isSelected ? 2.5 : 1.8, // 상태 구분을 위해 기본 두께를 1.8로 소폭 상향
      ),
      // 키오스크 느낌을 위한 미세한 그림자 효과 추가
      boxShadow: [
        BoxShadow(
          color: statusColor.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        )
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
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontFamily: fontPretendard,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: hasFocus ? primary : (isDark ? Colors.white60 : Colors.black54),
      ),
      hintText: hint,
      hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20, color: hasFocus ? primary : null) : null,
      filled: true,
      fillColor: isDark ? const Color(0xFF262A35) : const Color(0xFFF8F9FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: isDark ? const Color(0xFF333846) : const Color(0xFFADB5BD), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primary, width: 2.5),
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
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Text(
              label,
              style: const TextStyle(
                  fontFamily: fontPretendard,
                  fontWeight: FontWeight.bold,
                  fontSize: 15
              )
          ),
        ],
      ),
    );
  }

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: fontPretendard,
    scaffoldBackgroundColor: Colors.white,
    colorScheme: ColorScheme.fromSeed(seedColor: primary, primary: primary, surface: Colors.white),
    dividerTheme: const DividerThemeData(color: Color(0xFFF1F3F5), thickness: 1),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
        side: BorderSide(color: Color(0xFFE9ECEF), width: 1.5),
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
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Color(0xFF1E212A),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
        side: BorderSide(color: Color(0xFF333846), width: 1.5),
      ),
    ),
  );
}