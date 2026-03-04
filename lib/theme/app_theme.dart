import 'package:flutter/material.dart';

/// 앱 전체의 디자인 시스템을 관장하는 클래스
class AppTheme {
  // 핵심 포인트 컬러 (Vibrant Indigo FA 테마)
  static const Color primary = Color(0xFF6366F1);
  static const Color success = Color(0xFF36B37E);
  static const Color warning = Color(0xFFFFAB00);
  static const Color danger = Color(0xFFFF5630);

  // 전역 폰트 설정 (Pretendard)
  static const String fontPretendard = 'Pretendard';

  // --- [중앙 제어 색상 설정] ---

  // 실제 데이터 값 컬러 (Charcoal Gray)
  static Color dataColor(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.85)
      : const Color(0xFF454545);

  // 레이블 항목명 컬러 (Silver)
  static Color labelColor(bool isDark) => isDark
      ? const Color(0xFFC0C0C0).withValues(alpha: 0.7)
      : const Color(0xFFC0C0C0);

  static const double cardRadius = 12.0;

  // --- [중앙 제어 스타일 메서드] ---

  // 데이터 값 폰트 스타일링 (Pretendard + w900)
  static TextStyle itemValueStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 15,
      color: dataColor(isDark),
      fontWeight: FontWeight.w900,
    );
  }

  // 레이블 항목명 폰트 스타일링 (Pretendard + Silver)
  static TextStyle itemLabelStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 12,
      color: labelColor(isDark),
      fontWeight: FontWeight.bold,
    );
  }

  // 다이얼로그 타이틀 빌더
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

  // 리스트 아이템 카드 데코레이션
  static BoxDecoration listItemDecoration(BuildContext context, {
    required bool isSelected,
    required Color statusColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return BoxDecoration(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.02)
          : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(
        color: isSelected ? theme.colorScheme.primary : (isDark ? const Color(0xFF333846) : const Color(0xFFE9ECEF)),
        width: isSelected ? 2.5 : 1.5,
      ),
    );
  }

  // 통합 입력창 스타일 (InputDecoration)
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

  // 공통 액션 버튼
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

  // [수정] CardTheme를 CardThemeData로 변경하여 타입 에러 해결
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: fontPretendard,
    scaffoldBackgroundColor: Colors.white,
    colorScheme: ColorScheme.fromSeed(seedColor: primary, primary: primary, surface: Colors.white),
    dividerTheme: const DividerThemeData(color: Color(0xFFF1F3F5), thickness: 1),
    cardTheme: const CardThemeData( // 명확하게 CardThemeData 사용
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
    cardTheme: const CardThemeData( // 명확하게 CardThemeData 사용
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