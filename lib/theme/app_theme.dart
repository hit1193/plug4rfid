import 'package:flutter/material.dart';

/// 앱에서 제공하는 5종 감성 테마 열거형입니다.
/// 각 테마는 브랜드 컬러와 그에 어울리는 매우 연한 배경색(ToT)을 가집니다.
enum AppThemeType {
  pureWhite,  // [기본 시작] 완전한 순백색 미니멀 테마
  industrial, // 전문가용/신뢰 (Blue 기반 톤온톤)
  forest,     // 자연/안정 (Green 기반 톤온톤)
  solar,      // 활기/에너지 (Amber 기반 톤온톤)
  midnight    // 집중/심야 (Navy 기반 다크모드)
}

class AppTheme {
  // 전역 디자인 토큰 및 폰트 설정
  static const String fontPretendard = 'Pretendard';
  static const double cardRadius = 12.0;

  // 각 테마별 핵심 브랜드 컬러 (Seed Colors)
  static const Color primary = Color(0xFF6366F1);
  static const Color colorPureWhite = Color(0xFF475569); // 중립 슬레이트 그레이
  static const Color colorIndustrial = primary;
  static const Color colorForest = Color(0xFF10B981);
  static const Color colorSolar = Color(0xFFF59E0B);
  static const Color colorMidnight = Color(0xFF334155);

  // 공정 상태 알림용 공통 컬러
  static const Color success = Color(0xFF36B37E);
  static const Color warning = Color(0xFFFFAB00);
  static const Color danger = Color(0xFFFF5630);
  static const Color inactive = Color(0xFF475569);

  /// [핵심] 테마 타입에 따라 배경색(ToT)이 동적으로 적용된 ThemeData를 생성합니다.
  /// 이 메서드가 반환하는 ThemeData의 scaffoldBackgroundColor가 실시간 배경색의 원천입니다.
  static ThemeData getTheme(AppThemeType type) {
    switch (type) {
      case AppThemeType.pureWhite:
      // 순백색: 완전한 화이트 배경 (#FFFFFF)
        return _buildTheme(colorPureWhite, Brightness.light, Colors.white);
      case AppThemeType.industrial:
      // 블루 톤온톤: 매우 연한 라벤더 블루 배경
        return _buildTheme(colorIndustrial, Brightness.light, const Color(0xFFF5F7FF));
      case AppThemeType.forest:
      // 그린 톤온톤: 매우 연한 민트 그린 배경
        return _buildTheme(colorForest, Brightness.light, const Color(0xFFF0FDF4));
      case AppThemeType.solar:
      // 앰버 톤온톤: 매우 연한 샴페인 골드 배경
        return _buildTheme(colorSolar, Brightness.light, const Color(0xFFFFFBF0));
      case AppThemeType.midnight:
      // 다크모드: 깊이감 있는 다크 네이비 배경
        return _buildTheme(colorMidnight, Brightness.dark, const Color(0xFF0F172A));
    }
  }

  /// 공통 테마 빌더: 가독성 높은 블록 스타일로 작성되었습니다.
  /// 디자인 철학인 미니멀리즘과 키오스크 스타일을 전역 설정으로 강제합니다.
  static ThemeData _buildTheme(Color seedColor, Brightness brightness, Color scaffoldBg) {
    final bool isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontPretendard,
      scaffoldBackgroundColor: scaffoldBg, // [해결] 톤온톤 배경색 적용

      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
        primary: seedColor,
        // 카드나 다이얼로그 표면색은 배경 위에서 선명하게 보이도록 화이트(또는 다크 그레이) 유지
        surface: isDark ? const Color(0xFF1E293B) : Colors.white,
      ),

      // [디자인] 입력창: 외곽선은 또렷하게, 가이드 텍스트(Hint/Label)는 연하게
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF262A35) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        // HintText: 매우 연하게 처리 (0.12)
        hintStyle: TextStyle(
          color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.12),
          fontSize: 14,
        ),
        // LabelText: 연하게 처리 (0.25)
        labelStyle: TextStyle(
          fontFamily: fontPretendard,
          color: isDark ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.25),
          fontWeight: FontWeight.w600,
        ),
        // 평상시 외곽선: 또렷하게 강조 (0.45)
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        // 포커스 시 외곽선: 테마 메인 컬러
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: seedColor, width: 2.5),
        ),
      ),

      // [디자인] 버튼: 그림자 완전 제거(elevation 0) 및 굵은 프리텐다드 서체 적용
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          elevation: 0, // 그림자 제거
          shadowColor: Colors.transparent, // 그림자 완전 투명화
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontFamily: fontPretendard,
            fontWeight: FontWeight.w700, // 글자 굵게 적용
            fontSize: 15,
            letterSpacing: -0.2,
          ),
        ),
      ),

      // [디자인] 카드: 그림자 제거 및 미니멀한 외곽선 테두리
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

      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        thickness: 1,
      ),
    );
  }

  // --- 기존 코드 및 하위 페이지 가독성을 위한 정적 헬퍼 메서드 ---

  static Color dataColor(bool isDark) => isDark ? const Color(0xFFE9ECEF) : const Color(0xFF2D2E33);
  static Color labelColor(bool isDark) => isDark ? const Color(0xFF718096) : const Color(0xFFA0AEC0);

  /// 아이템 값 스타일: 전역 폰트 및 굵기 적용
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

  /// 레이블 스타일: 은은한 폰트 두께
  static TextStyle itemLabelStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontFamily: fontPretendard,
      fontSize: 14,
      color: labelColor(isDark),
      fontWeight: FontWeight.w600,
    );
  }

  /// 섹션 타이틀 위젯
  static Widget dialogTitle(String text, IconData icon, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color ?? primary, size: 26),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: fontPretendard,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }

  /// 리스트 아이템 데코레이션: 톤온톤 배경 위에서 또렷한 외곽선 제공
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
      final bool isStandardStatus = statusColor == success || statusColor == warning;
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

  /// [수정] 수동 호출용 입력창 데코레이션: 또렷한 외곽선, 연한 Hint/Label 강제 반영
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
      // LabelText: 연하게 조정 (0.25)
      labelStyle: TextStyle(
        fontFamily: fontPretendard,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: hasFocus ? theme.colorScheme.primary : (isDark ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.25)),
      ),
      hintText: hint,
      // HintText: 매우 연하게 조정 (0.12)
      hintStyle: TextStyle(
        color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.12),
        fontSize: 14,
      ),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 20, color: hasFocus ? theme.colorScheme.primary : (isDark ? Colors.white24 : Colors.black26))
          : null,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        // 평상시 외곽선: 또렷하게 (0.45)
        borderSide: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2.5),
      ),
    );
  }

  /// [수정] 공통 버튼 헬퍼: 그림자 제거(elevation 0) 및 굵은 폰트 강제 적용
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
        shadowColor: Colors.transparent, // 그림자 투명화
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
                fontWeight: FontWeight.w700, // 굵게 강제 적용
                fontSize: 15,
              )
          ),
        ],
      ),
    );
  }
}