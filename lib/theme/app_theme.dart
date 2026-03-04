import 'package:flutter/material.dart';

class AppTheme {
  // 고유 브랜드 색상
  static const Color primary = Color(0xFF6366F1);
  static const Color success = Color(0xFF36B37E);
  static const Color warning = Color(0xFFFFAB00);
  static const Color danger = Color(0xFFFF5630);

  // 폰트 설정
  static const String fontPretendard = 'Pretendard';

  // [유지] 또렷한 가독성을 위해 불투명도를 제거하고 솔리드 다크 그레이 적용
  static Color dataColor(bool isDark) => isDark
      ? const Color(0xFFE9ECEF) // 다크모드: 밝은 그레이 (Solid)
      : const Color(0xFF2D2E33); // 라이트모드: 깊은 다크 그레이 (Charcoal)

  // [유지] 레이블 색상
  static Color labelColor(bool isDark) => isDark
      ? const Color(0xFF718096) // 다크모드: 조금 더 가라앉은 그레이
      : const Color(0xFFA0AEC0); // 라이트모드: 연한 실버 그레이

  static const double cardRadius = 12.0;

  // [수정] 아이템 값 스타일: fontSize를 15에서 17로 키워 데이터 식별력 강화
  static TextStyle itemValueStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 17, // 기존 15에서 상향 조정
      color: dataColor(isDark),
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4, // 글자가 커짐에 따라 자간을 미세하게 더 좁혀 응집력 유지
    );
  }

  // [수정] 레이블 스타일: fontSize를 12에서 14로 키워 정보 구조를 더 명확히 함
  static TextStyle itemLabelStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 14, // 기존 12에서 상향 조정
      color: labelColor(isDark),
      fontWeight: FontWeight.w600,
    );
  }

  // [유지] 다이얼로그 타이틀
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
            fontSize: 20,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  // [유지] 리스트 아이템 데코레이션
  static BoxDecoration listItemDecoration(BuildContext context, {
    required bool isSelected,
    required Color statusColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color borderColor = isSelected
        ? theme.colorScheme.primary
        : statusColor.withValues(alpha: isDark ? 0.4 : 0.3);

    return BoxDecoration(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.02)
          : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(
        color: borderColor,
        width: isSelected ? 2.5 : 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 10,
          offset: const Offset(0, 4),
        )
      ],
    );
  }

  // [유지] 입력창 데코레이션
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
        fontWeight: FontWeight.w600,
        color: hasFocus
            ? primary
            : (isDark ? Colors.white38 : Colors.black38),
      ),
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? Colors.white12 : Colors.black12,
        fontSize: 14,
      ),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 20, color: hasFocus ? primary : (isDark ? Colors.white24 : Colors.black26))
          : null,
      filled: true,
      fillColor: isDark ? const Color(0xFF262A35) : const Color(0xFFF8F9FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF4A5568) : const Color(0xFF94A3B8),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primary, width: 2.5),
      ),
    );
  }

  // [유지] 공통 버튼
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
                fontWeight: FontWeight.w700,
                fontSize: 15,
              )
          ),
        ],
      ),
    );
  }

  // [유지] 라이트 테마 정의
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

  // [유지] 다크 테마 정의
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