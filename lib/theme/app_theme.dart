import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF0052CC);
  static const Color success = Color(0xFF36B37E);
  static const Color warning = Color(0xFFFFAB00);
  static const Color danger = Color(0xFFFF5630);
  static const Color surface = Colors.white;

  static const String fontPretendard = 'Pretendard';

  static const double cardRadius = 10.0;
  static const double dialogRadius = 12.0;
  static const double outlineWidth = 1.8;

  static const Color inputFillColor = Colors.white;
  static const Color inputFocusColor = Colors.white;
  static const Color inputBorderColor = Color(0xFFADB5BD);

  static const TextStyle inputLabelStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: Colors.black87,
  );

  static const TextStyle inputHintStyle = TextStyle(
    fontSize: 14,
    color: Colors.black38,
  );

  /// [보정] 힌트 텍스트 가려짐 방지를 위한 패딩 및 베젤 조정
  static InputDecoration inputDecoration({
    required String label,
    String? hint,
    IconData? prefixIcon,
    bool hasFocus = false,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: inputLabelStyle.copyWith(
        color: hasFocus ? primary : Colors.black54,
      ),
      hintText: hint,
      hintStyle: inputHintStyle,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20) : null,
      filled: true,
      fillColor: inputFillColor,
      // [수정] 수직 패딩을 16으로 조정하여 텍스트가 잘리지 않게 함
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      // 라벨이 위로 올라갔을 때 힌트와 겹치지 않게 처리
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: inputBorderColor, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primary, width: 2.5),
      ),
      // 에러 시에도 레이아웃 유지
      alignLabelWithHint: true,
    );
  }

  static Widget actionButton({
    required String label,
    required VoidCallback onPressed,
    Color? color,
    Color? textColor,
    IconData? icon,
    bool isFullWidth = false,
  }) {
    final button = ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? primary,
        foregroundColor: textColor ?? Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: color == Colors.transparent
              ? const BorderSide(color: Colors.black12, width: 1.5)
              : BorderSide.none,
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 8),
          ],
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }

  static Widget dialogTitle(String title, IconData icon, {Color? color}) {
    return Row(
      children: [
        Icon(icon, color: color ?? primary, size: 24),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ],
    );
  }

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: fontPretendard,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      surface: surface,
    ),
    scaffoldBackgroundColor: surface,
    dialogTheme: const DialogThemeData(
      elevation: 0,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(dialogRadius)),
        side: BorderSide(color: Colors.black12, width: 1.2),
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
        side: BorderSide(color: Colors.black12, width: 1.2),
      ),
    ),
  );
}