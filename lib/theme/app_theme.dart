import 'package:flutter/material.dart';

class AppTheme {
  // 고유 브랜드 및 상태 색상
  static const Color primary = Color(0xFF6366F1);
  static const Color success = Color(0xFF36B37E);
  static const Color warning = Color(0xFFFFAB00);
  static const Color danger = Color(0xFFFF5630);

  // [수정] 미확인 상태의 외곽선을 더욱 또렷하게 만들기 위해 더 깊은 다크 그레이로 변경
  static const Color inactive = Color(0xFF475569);

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

  // [유지] 아이템 값 스타일
  static TextStyle itemValueStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 17,
      color: dataColor(isDark),
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    );
  }

  // [유지] 레이블 스타일
  static TextStyle itemLabelStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 14,
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

  // [수정] 리스트 아이템 데코레이션: 입장/퇴장 이외의 상태(미확인 등)일 때 외곽선을 더 진하게 표현
  static BoxDecoration listItemDecoration(BuildContext context, {
    required bool isSelected,
    required Color statusColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // [변경] 입장/퇴장 색상이 아닌 경우(그레이 계열) 투명도를 제거하여 더 진한 외곽선 제공
    // 선택되지 않았을 때, statusColor가 success나 warning이 아니면 더 또렷한 불투명도를 적용합니다.
    Color finalBorderColor;
    if (isSelected) {
      finalBorderColor = theme.colorScheme.primary;
    } else {
      final bool isStandardStatus = statusColor == success || statusColor == warning;
      // 입장/퇴장이 아닌 경우(미확인 등) alpha를 1.0(불투명)으로 설정하여 진하게 표시
      finalBorderColor = isStandardStatus
          ? statusColor.withValues(alpha: isDark ? 0.8 : 0.75)
          : statusColor.withValues(alpha: 1.0);
    }

    return BoxDecoration(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.05)
          : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(
        color: finalBorderColor,
        width: isSelected ? 2.5 : 1.8,
      ),
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
          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primary, width: 2.5),
      ),
    );
  }

  // [수정] 공통 버튼 헬퍼: 그림자를 완벽히 제거 (elevation: 0)
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
        elevation: 0, // 그림자 제거
        shadowColor: Colors.transparent, // 그림자 색상 투명화
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

  // --- 버튼 테마 정의 (글로벌 적용용) ---

  // [수정] 글로벌 ElevatedButton 테마에서도 그림자를 완전히 제거
  static ElevatedButtonThemeData get elevatedButtonTheme => ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontFamily: fontPretendard, fontWeight: FontWeight.w700, fontSize: 15),
      elevation: 0, // 그림자 제거
      shadowColor: Colors.transparent, // 그림자 색상 투명화
    ),
  );

  static TextButtonThemeData get textButtonTheme => TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: primary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontFamily: fontPretendard, fontWeight: FontWeight.w700, fontSize: 15),
    ),
  );

  // [유지] 라이트 테마 정의
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: fontPretendard,
    scaffoldBackgroundColor: Colors.white,
    colorScheme: ColorScheme.fromSeed(seedColor: primary, primary: primary, surface: Colors.white),
    elevatedButtonTheme: elevatedButtonTheme,
    textButtonTheme: textButtonTheme,
    dividerTheme: const DividerThemeData(color: Color(0xFFF1F3F5), thickness: 1),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
        side: BorderSide(color: Color(0xFFDEE2E6), width: 1.5),
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
    elevatedButtonTheme: elevatedButtonTheme,
    textButtonTheme: textButtonTheme,
    dividerTheme: const DividerThemeData(color: Color(0xFF333846), thickness: 1),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Color(0xFF1E212A),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
        side: BorderSide(color: Color(0xFF454C5E), width: 1.5),
      ),
    ),
  );
}