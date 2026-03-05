import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 앱 전체의 5종 감성 테마 상태를 관리하고 실시간으로 알림을 보냅니다.
class ThemeProvider with ChangeNotifier {
  // [시작 테마] 사용자님의 요청대로 초기 상태를 순백색(pureWhite)으로 설정합니다.
  AppThemeType _currentThemeType = AppThemeType.pureWhite;

  AppThemeType get currentThemeType => _currentThemeType;

  /// [핵심] MaterialApp의 theme 속성에 직접 전달할 실시간 ThemeData 객체입니다.
  /// 이 한 줄이 있어야 배경색과 버튼 스타일이 실제로 변합니다.
  ThemeData get themeData {
    return AppTheme.getTheme(_currentThemeType);
  }

  /// 사용자가 UI(사이드바)에서 테마 버튼을 클릭했을 때 호출됩니다.
  void setTheme(AppThemeType type) {
    if (_currentThemeType != type) {
      _currentThemeType = type;

      // 알림을 보내 main.dart의 MaterialApp이 리빌드되도록 유도합니다.
      notifyListeners();
    }
  }

  /// 다크모드 여부 확인
  bool get isDarkMode => _currentThemeType == AppThemeType.midnight;
}