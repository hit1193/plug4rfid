import 'package:flutter/material.dart';

/// 앱 전체의 테마 상태를 결정하고 전파하는 클래스 (TStyleManager 역할)
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  // 테마 토글 함수
  void toggleTheme() {
    _themeMode = (_themeMode == ThemeMode.light) ? ThemeMode.dark : ThemeMode.light;
    notifyListeners(); // 이 호출이 C++의 SendMessage(WM_PAINT)처럼 전체 리렌더링을 유발함
  }

  // 특정 모드 강제 지정
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}