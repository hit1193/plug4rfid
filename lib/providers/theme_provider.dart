import 'package:flutter/material.dart';

/// App-wide theme state manager (TStyleManager role)
class ThemeProvider extends ChangeNotifier {
  // Set the initial state to dark mode as requested
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// Toggles between light and dark theme modes
  void toggleTheme() {
    _themeMode = (_themeMode == ThemeMode.light) ? ThemeMode.dark : ThemeMode.light;

    // This call triggers a re-build of all listening widgets (like MaterialApp in main.dart)
    notifyListeners();
  }

  /// Force a specific theme mode
  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }
  }
}