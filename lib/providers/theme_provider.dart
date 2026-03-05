import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 앱 전체의 5종 감성 테마 상태를 관리하는 프로바이더입니다.
/// MaterialApp에 실시간으로 ThemeData를 주입하여 배경색 변화를 제어합니다.
class ThemeProvider with ChangeNotifier {
  // [설정] 디자인 철학에 따라 초기 테마를 '순백색(pureWhite)'으로 고정합니다.
  AppThemeType _currentThemeType = AppThemeType.pureWhite;

  AppThemeType get currentThemeType => _currentThemeType;

  /// [핵심] MaterialApp의 theme 속성에 직접 주입할 실시간 테마 객체입니다.
  /// 이 getter를 통해 AppTheme에서 정의한 톤온톤 배경색이 앱 전역에 적용됩니다.
  ThemeData get themeData {
    return AppTheme.getTheme(_currentThemeType);
  }

  /// 사용자가 UI(사이드바)에서 테마를 선택했을 때 호출됩니다.
  void setTheme(AppThemeType type) {
    if (_currentThemeType != type) {
      _currentThemeType = type;

      // 알림을 보내 main.dart의 MaterialApp이 리빌드되도록 유도합니다.
      notifyListeners();
    }
  }

  /// Midnight 테마일 때만 다크모드 환경으로 간주합니다.
  bool get isDarkMode => _currentThemeType == AppThemeType.midnight;

  /// 기존 라이트/다크 토글 로직과의 호환성 유지
  void toggleTheme() {
    setTheme(isDarkMode ? AppThemeType.pureWhite : AppThemeType.midnight);
  }
}