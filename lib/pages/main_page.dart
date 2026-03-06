import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 웹(Web) 환경 판별(kIsWeb)을 위한 필수 라이브러리
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';

// 하위 페이지 위젯 임포트
// [확인 필수!] 이 파일들이 동일한 pages 폴더 내에 존재해야 합니다.
import 'user_page.dart';       // user_page.dart 파일 안에 'class UserPage'가 반드시 있어야 합니다!
import 'product_page.dart';
import 'device_page.dart';
import 'device_map_page.dart';
import 'kiosk_view.dart';

/// ---------------------------------------------------------------------------
/// [RFID 솔루션 통합 메인 레이아웃 페이지]
/// C++Builder의 MDI Parent Form 역할을 수행하며, 좌측 사이드바(메뉴)와
/// 우측 본문(하위 페이지) 영역을 동적으로 렌더링하는 핵심 클래스입니다.
/// ---------------------------------------------------------------------------
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // --- 메인 폼 상태 제어 변수 ---
  bool _isKioskMode = false;       // 키오스크(전체화면 고정) 모드 진입 플래그
  bool _isSidebarExtended = true;  // 좌측 사이드바 펼침/접힘 상태
  int _selectedIndex = 0;          // 현재 선택된 메뉴 인덱스 (Tab Index 역할)
  final String _pbBaseUrl = "http://127.0.0.1:8090"; // 포켓베이스 서버 주소

  // 사이드바 구성을 위한 메뉴 아이템 리스트 (동적 생성용)
  final List<Map<String, dynamic>> _menuItems = [
    {'title': '종합 관제 상황판', 'icon': FontAwesomeIcons.chartPie},
    {'title': '인원 관리', 'icon': FontAwesomeIcons.users},
    {'title': '장치 관리', 'icon': FontAwesomeIcons.microchip},
    {'title': '물품 관리', 'icon': FontAwesomeIcons.boxesStacked},
    {'title': '출입 기록', 'icon': FontAwesomeIcons.clockRotateLeft},
    {'title': '환경 설정', 'icon': FontAwesomeIcons.gears},
  ];

  @override
  void initState() {
    super.initState();
    _initFullScreenConfiguration();
  }

  /// [윈도우 창 제어 초기화]
  /// PC 버전으로 실행 시 타이틀바를 숨기고 전체 화면으로 포커싱합니다.
  Future<void> _initFullScreenConfiguration() async {
    if (!kIsWeb && Platform.isWindows) {
      try {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
        await windowManager.setFullScreen(true);
        await windowManager.focus();
      } catch (e) {
        debugPrint("윈도우 매니저 초기화 중 오류 발생: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 전역 테마 상태를 감시하여 실시간으로 디자인을 동기화합니다.
    final themeProvider = context.watch<ThemeProvider>();
    final theme = themeProvider.themeData;

    // 키오스크 모드일 경우 기존 UI를 완전히 덮어버리는 독립 뷰 표출
    if (_isKioskMode) {
      return Scaffold(
          body: KioskView(
              onDismiss: () => setState(() => _isKioskMode = false)
          )
      );
    }

    // 화면 해상도 변화에 따라 반응형으로 레이아웃을 재구성합니다.
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth <= 650;

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Row(
            children: [
              // 1. 좌측 사이드바 영역 (모바일 환경에서는 감춤)
              if (!isMobile) ...[
                _buildSidebar(_isSidebarExtended, theme, themeProvider),
              ],

              // 2. 우측 메인 본문 영역 (선택된 메뉴에 따른 하위 위젯 렌더링)
              Expanded(
                child: Container(
                  color: theme.scaffoldBackgroundColor,
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: theme.dividerTheme.color ?? Colors.black12,
                                width: 1.0,
                              ),
                            ),
                          ),
                          child: _buildBody(isMobile),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// ---------------------------------------------------------------------------
  /// [좌측 사이드바 패널 빌더]
  /// TSplitView와 동일한 역할을 하며, 애니메이션을 통해 부드럽게 접히고 펼쳐집니다.
  /// ---------------------------------------------------------------------------
  Widget _buildSidebar(bool extended, ThemeData theme, ThemeProvider themeProvider) {
    final bool isDarkMode = theme.brightness == Brightness.dark;

    // 다크모드일 때는 본문보다 아주 살짝만 더 어두운 색상으로 설정하여 깊이감 부여
    final Color deeperSidebarColor = isDarkMode
        ? const Color(0xFF151D2E)
        : Color.alphaBlend(theme.colorScheme.primary.withValues(alpha: 0.06), theme.scaffoldBackgroundColor);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: extended ? 280 : 90,
      curve: Curves.easeInOut,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: deeperSidebarColor,
      ),
      child: Column(
        children: [
          // 앱 로고 및 사이드바 토글 버튼
          _buildSidebarHeader(extended, theme),
          const SizedBox(height: 10),

          // 메뉴 항목 리스트
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                ...List.generate(_menuItems.length, (index) {
                  return _buildMenuItem(
                    title: _menuItems[index]['title'],
                    icon: _menuItems[index]['icon'],
                    extended: extended,
                    isSelected: _selectedIndex == index,
                    theme: theme,
                    onTap: () => setState(() => _selectedIndex = index),
                  );
                }),
                const SizedBox(height: 20),
                Divider(color: theme.dividerTheme.color),
                const SizedBox(height: 20),

                // 테마 변경 영역 (사이드바가 확장되어 있을 때만 표출)
                if (extended) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(
                      "감성 테마 선택",
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: isDarkMode ? Colors.white70 : Colors.black45,
                      ),
                    ),
                  ),
                  _buildThemeSelector(themeProvider, theme),
                  const SizedBox(height: 20),
                  Divider(color: theme.dividerTheme.color),
                  const SizedBox(height: 20),
                ],

                // 특수 모드 진입 및 시스템 제어 버튼 영역
                _buildMenuItem(
                  title: "키오스크 모드",
                  icon: FontAwesomeIcons.lockOpen,
                  extended: extended,
                  isSelected: false,
                  theme: theme,
                  onTap: () => setState(() => _isKioskMode = true),
                ),

                // 데스크탑(Windows) 환경일 때만 시스템 종료 버튼 표출 (웹 빌드 오류 방지)
                if (!kIsWeb && Platform.isWindows) ...[
                  const SizedBox(height: 4),
                  _buildMenuItem(
                    title: "시스템 종료",
                    icon: Icons.power_settings_new_rounded,
                    extended: extended,
                    isSelected: false,
                    color: AppTheme.danger,
                    theme: theme,
                    onTap: () async => await windowManager.close(),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 사이드바 최상단 앱 타이틀 및 메뉴 열기/닫기 토글 버튼 영역
  Widget _buildSidebarHeader(bool extended, ThemeData theme) {
    final bool isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.fromLTRB(14, extended ? 50 : 25, 14, 25),
      child: Row(
        mainAxisAlignment: extended ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
        children: [
          if (extended)
            Flexible(
              child: Text(
                "PLUG4",
                style: TextStyle(
                  fontFamily: AppTheme.fontPretendard,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  letterSpacing: -1.2,
                  color: isDarkMode ? Colors.white : theme.colorScheme.primary,
                ),
                overflow: TextOverflow.clip,
                softWrap: false,
                maxLines: 1,
              ),
            ),
          IconButton(
            onPressed: () => setState(() => _isSidebarExtended = !_isSidebarExtended),
            icon: Icon(
                extended ? Icons.menu_open_rounded : Icons.menu_rounded,
                color: isDarkMode ? Colors.white70 : theme.colorScheme.primary.withValues(alpha: 0.7),
                size: 28
            ),
          ),
        ],
      ),
    );
  }

  /// 사이드바 개별 메뉴 버튼 생성 위젯
  Widget _buildMenuItem({
    required String title,
    required dynamic icon,
    required bool extended,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData theme,
    Color? color,
  }) {
    final bool isDarkMode = theme.brightness == Brightness.dark;
    final Color activeColor = theme.colorScheme.primary;
    final Color inactiveColor = color ?? (isDarkMode ? Colors.white70 : Colors.black54);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 56,
          padding: EdgeInsets.symmetric(horizontal: extended ? 18 : 0),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : (isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                child: Center(
                  child: icon is IconData
                      ? Icon(icon, size: 20, color: isSelected ? Colors.white : inactiveColor)
                      : FaIcon(icon as IconData, size: 18, color: isSelected ? Colors.white : inactiveColor),
                ),
              ),
              if (extended) ...[
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      color: isSelected ? Colors.white : inactiveColor,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    maxLines: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 사용자가 원하는 색상 테마(Theme)를 실시간으로 선택할 수 있는 팔레트 영역입니다.
  Widget _buildThemeSelector(ThemeProvider provider, ThemeData theme) {
    final bool isDarkMode = theme.brightness == Brightness.dark;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: AppThemeType.values.map((type) {
        final bool isSelected = provider.currentThemeType == type;
        final bool isPureWhite = type == AppThemeType.pureWhite;

        Color seedColor;
        switch (type) {
          case AppThemeType.pureWhite:
            seedColor = const Color(0xFF94A3B8);
            break;
          case AppThemeType.industrial:
            seedColor = AppTheme.primary;
            break;
          case AppThemeType.forest:
            seedColor = const Color(0xFF10B981);
            break;
          case AppThemeType.solar:
            seedColor = const Color(0xFFF59E0B);
            break;
          case AppThemeType.midnight:
          // [수정됨] 직관적인 다크모드 인지를 위해 남색(0xFF6366F1)에서 완전한 검은색으로 변경했습니다.
            seedColor = Colors.black;
            break;
        }

        return GestureDetector(
          onTap: () => provider.setTheme(type),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isPureWhite ? Colors.white : seedColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? (isDarkMode ? Colors.white : theme.colorScheme.primary)
                    : (isPureWhite ? Colors.black12 : Colors.transparent),
                width: isSelected ? 4 : 1,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(color: seedColor.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))
              ],
            ),
            child: isSelected
                ? Icon(Icons.check, color: isPureWhite ? Colors.black : Colors.white, size: 18)
                : null,
          ),
        );
      }).toList(),
    );
  }

  /// [메인 프레임 뷰 라우팅]
  /// 선택된 메뉴 인덱스(_selectedIndex)에 따라 우측 메인 영역에 각 기능 페이지를 띄웁니다.
  Widget _buildBody(bool isMobile) {
    switch (_selectedIndex) {
      case 0: return DeviceMapPage(baseUrl: _pbBaseUrl);
      case 1: return UserPage(searchQuery: "", filter: '전체', isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 2: return DevicePage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 3: return ProductPage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      default: return const Center(
          child: Text("기능 개발 중입니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))
      );
    }
  }
}