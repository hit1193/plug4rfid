import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 앱 전체의 감성 테마(Industrial, Forest, Solar, Midnight) 상태를 관리하는 프로바이더입니다.
/// 사용자의 선택에 따라 실시간으로 ThemeData를 변경하고 앱 전체에 전파합니다.
class ThemeProvider with ChangeNotifier {
  // 기본 테마를 전문적인 Industrial Blue 스타일로 초기화합니다.
  AppThemeType _currentThemeType = AppThemeType.industrial;

  // 현재 선택된 테마의 타입을 반환하는 게터입니다. (에러 해결 포인트)
  AppThemeType get currentThemeType {
    return _currentThemeType;
  }

  /// 현재 테마 타입에 매칭되는 실제 ThemeData 객체를 반환합니다.
  /// MaterialApp의 theme 속성에서 이 값을 참조하여 전체 UI 스타일을 결정합니다.
  ThemeData get themeData {
    return AppTheme.getTheme(_currentThemeType);
  }

  /// 새로운 테마를 설정하고 구독 중인 모든 위젯에게 변경 알림을 보냅니다. (에러 해결 포인트)
  void setTheme(AppThemeType type) {
    // 현재 테마와 다를 경우에만 변경 및 알림을 수행합니다.
    if (_currentThemeType != type) {
      _currentThemeType = type;

      // notifyListeners() 호출이 앱 전체의 리렌더링을 유도합니다.
      notifyListeners();
    }
  }

  /// 현재 다크모드 환경(Midnight 테마)인지 여부를 확인하는 게터입니다.
  bool get isDarkMode {
    return _currentThemeType == AppThemeType.midnight;
  }

  /// 플러터 표준 ThemeMode와 호환되도록 값을 반환합니다.
  ThemeMode get themeMode {
    return isDarkMode ? ThemeMode.dark : ThemeMode.light;
  }

  /// 기존 로직과의 호환성을 위해 제공하는 토글 함수입니다.
  /// (필요에 따라 Industrial <-> Midnight 전환용으로 활용 가능)
  void toggleTheme() {
    if (_currentThemeType == AppThemeType.midnight) {
      setTheme(AppThemeType.industrial);
    } else {
      setTheme(AppThemeType.midnight);
    }
  }
}