import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // debugPrint용
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart'; // 기존에 정의하신 AppTheme 및 AppThemeType 임포트

/// ---------------------------------------------------------------------------
/// [테마 상태 관리 프로바이더 (ThemeProvider)]
/// 앱 전체의 5종 감성 테마 상태를 관리하는 핵심 프로바이더입니다.
/// MaterialApp에 실시간으로 ThemeData를 주입하여 배경색 변화를 제어하며,
/// 앱 실행 시 SharedPreferences를 통해 마지막으로 설정한 테마를 자동으로 복구합니다.
/// ---------------------------------------------------------------------------
class ThemeProvider with ChangeNotifier {
  // [설정] 디자인 철학에 따라 초기 테마를 '순백색(pureWhite)'으로 고정합니다.
  AppThemeType _currentThemeType = AppThemeType.pureWhite;

  AppThemeType get currentThemeType => _currentThemeType;

  // ---------------------------------------------------------------------------
  // 생성자 (Constructor)
  // Provider가 메모리에 등록되는 순간(앱 최초 실행 시),
  // 즉시 로컬 저장소에 저장된 테마 값을 읽어오는 함수를 실행합니다.
  // 이 로직 덕분에 앱을 껐다 켜도 테마가 초기화되지 않고 그대로 유지됩니다.
  // ---------------------------------------------------------------------------
  ThemeProvider() {
    _loadSavedTheme();
  }

  // ---------------------------------------------------------------------------
  // [테마 불러오기 함수]
  // 비동기(async) 방식으로 기기 로컬 저장소를 열어 'pref_theme_index'를 확인합니다.
  // ---------------------------------------------------------------------------
  Future<void> _loadSavedTheme() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // 환경설정에서 저장한 테마 인덱스를 가져옵니다. 값이 없으면 기본값 0(화이트)을 사용합니다.
      final int savedIndex = prefs.getInt('pref_theme_index') ?? 0;

      // 가져온 숫자(인덱스)를 실제 테마 열거형(Enum)으로 변환하여 적용합니다.
      _applyThemeByIndex(savedIndex);

      debugPrint('✅ 테마 설정 로드 완료 - 적용된 테마 인덱스: $savedIndex');
    } catch (e) {
      debugPrint('❌ 저장된 테마를 불러오는 중 오류 발생: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // [숫자 인덱스 -> 테마 타입 변환기]
  // 환경설정에서 사용하는 인덱스(0~4)를 실제 테마 열거형(Enum)으로 맵핑합니다.
  // ---------------------------------------------------------------------------
  void _applyThemeByIndex(int index) {
    switch (index) {
      case 0:
        _currentThemeType = AppThemeType.pureWhite;
        break;
      case 1:
        _currentThemeType = AppThemeType.industrial;
        break;
      case 2:
        _currentThemeType = AppThemeType.forest;
        break;
      case 3:
        _currentThemeType = AppThemeType.solar;
        break;
      case 4:
        _currentThemeType = AppThemeType.midnight; // 다크 모드
        break;
      default:
      // 혹시라도 범위를 벗어난 이상한 값이 들어오면 안전하게 기본값으로 처리합니다.
        _currentThemeType = AppThemeType.pureWhite;
    }

    // 로컬에서 불러온 테마로 상태를 갱신했으니 화면을 다시 그리도록 알립니다.
    notifyListeners();
  }

  /// ---------------------------------------------------------------------------
  /// [핵심] MaterialApp의 theme 속성에 직접 주입할 실시간 테마 객체입니다.
  /// 이 getter를 통해 AppTheme에서 정의한 톤온톤 배경색이 앱 전역에 적용됩니다.
  /// ---------------------------------------------------------------------------
  ThemeData get themeData {
    return AppTheme.getTheme(_currentThemeType);
  }

  /// ---------------------------------------------------------------------------
  /// 사용자가 UI(사이드바, 환경설정 등)에서 테마를 선택했을 때 호출됩니다.
  /// 화면을 즉시 갱신하고, 다음 번 앱 실행을 위해 로컬 저장소에도 영구 저장합니다.
  /// ---------------------------------------------------------------------------
  void setTheme(AppThemeType type) async {
    if (_currentThemeType != type) {
      _currentThemeType = type;

      // 알림을 보내 main.dart의 MaterialApp이 리빌드되도록 유도합니다.
      notifyListeners();

      // [추가된 안정성 로직]
      // 토글 버튼이나 단축키 등으로 테마가 바뀌었을 때도 누락 없이 로컬에 저장합니다.
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        int indexToSave = 0;

        switch (type) {
          case AppThemeType.pureWhite:
            indexToSave = 0;
            break;
          case AppThemeType.industrial:
            indexToSave = 1;
            break;
          case AppThemeType.forest:
            indexToSave = 2;
            break;
          case AppThemeType.solar:
            indexToSave = 3;
            break;
          case AppThemeType.midnight:
            indexToSave = 4;
            break;
        }

        await prefs.setInt('pref_theme_index', indexToSave);
        debugPrint('✅ 테마 인덱스 [$indexToSave] 로컬 저장 완료');
      } catch (e) {
        debugPrint('❌ 테마 인덱스 로컬 저장 중 오류 발생: $e');
      }
    }
  }

  /// Midnight 테마일 때만 다크모드 환경으로 간주합니다.
  bool get isDarkMode => _currentThemeType == AppThemeType.midnight;

  /// 기존 라이트/다크 토글 로직과의 호환성 유지
  void toggleTheme() {
    setTheme(isDarkMode ? AppThemeType.pureWhite : AppThemeType.midnight);
  }
}