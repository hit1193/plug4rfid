import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';

// 하위 페이지 위젯
import 'person_page.dart';
import 'product_page.dart';
import 'device_page.dart';
import 'device_map_page.dart';
import 'kiosk_view.dart';

/// RFID 솔루션의 메인 레이아웃을 담당하는 페이지입니다.
/// 디자인 철학: 미니멀리즘, 키오스크 스타일, 톤온톤 배색
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _isKioskMode = false;
  bool _isSidebarExtended = true;
  int _selectedIndex = 0;
  final String _pbBaseUrl = "http://127.0.0.1:8090";

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

  Future<void> _initFullScreenConfiguration() async {
    if (Platform.isWindows) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      await windowManager.setFullScreen(true);
      await windowManager.focus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = themeProvider.themeData;
    final isDark = theme.brightness == Brightness.dark;

    if (_isKioskMode) {
      return Scaffold(body: KioskView(onDismiss: () => setState(() => _isKioskMode = false)));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth <= 650;

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Row(
            children: [
              if (!isMobile) ...[
                _buildSidebar(_isSidebarExtended, theme, themeProvider),
              ],
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

  Widget _buildSidebar(bool extended, ThemeData theme, ThemeProvider themeProvider) {
    final bool isDark = theme.brightness == Brightness.dark;

    // 다크모드일 때는 본문보다 아주 살짝만 더 어두운 색상으로 깊이감 부여
    final Color deeperSidebarColor = isDark
        ? const Color(0xFF151D2E)
        : Color.alphaBlend(theme.colorScheme.primary.withValues(alpha: 0.06), theme.scaffoldBackgroundColor);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: extended ? 280 : 90,
      curve: Curves.easeInOut,
      // [에러 해결 1] 컨테이너 크기가 변할 때 내부 자식 요소가 선을 넘어가면 깔끔하게 잘라줍니다(오버플로 방지).
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: deeperSidebarColor,
      ),
      child: Column(
        children: [
          _buildSidebarHeader(extended, theme),
          const SizedBox(height: 10),
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

                if (extended) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(
                      "감성 테마 선택",
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white70 : Colors.black45,
                      ),
                    ),
                  ),
                  _buildThemeSelector(themeProvider, theme),
                  const SizedBox(height: 20),
                  Divider(color: theme.dividerTheme.color),
                  const SizedBox(height: 20),
                ],

                _buildMenuItem(
                  title: "키오스크 모드",
                  icon: FontAwesomeIcons.lockOpen,
                  extended: extended,
                  isSelected: false,
                  theme: theme,
                  onTap: () => setState(() => _isKioskMode = true),
                ),
                if (Platform.isWindows) ...[
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

  Widget _buildSidebarHeader(bool extended, ThemeData theme) {
    final bool isDark = theme.brightness == Brightness.dark;
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
                  color: isDark ? Colors.white : theme.colorScheme.primary,
                ),
                // [에러 해결 2] 애니메이션 도중 17px 에러를 막기 위해 ellipsis(...) 대신 공간이 없으면 그냥 자르는(clip) 방식을 사용합니다.
                overflow: TextOverflow.clip,
                softWrap: false, // 줄바꿈을 원천 차단하여 레이아웃 계산 오류를 없앱니다.
                maxLines: 1,
              ),
            ),
          IconButton(
            onPressed: () => setState(() => _isSidebarExtended = !_isSidebarExtended),
            icon: Icon(
                extended ? Icons.menu_open_rounded : Icons.menu_rounded,
                color: isDark ? Colors.white70 : theme.colorScheme.primary.withValues(alpha: 0.7),
                size: 28
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required String title,
    required dynamic icon,
    required bool extended,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData theme,
    Color? color,
  }) {
    final bool isDark = theme.brightness == Brightness.dark;
    final Color activeColor = theme.colorScheme.primary;
    final Color inactiveColor = color ?? (isDark ? Colors.white70 : Colors.black54);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 56,
          padding: EdgeInsets.symmetric(horizontal: extended ? 18 : 0),
          // [에러 해결 3] 개별 메뉴 아이템도 크기가 줄어들 때 글씨가 튀어나오지 않게 경계를 확실히 잘라줍니다.
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
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
                    // [에러 해결 4] ellipsis 가 강제하는 17픽셀 최소 공간 제약을 해제합니다.
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

  Widget _buildThemeSelector(ThemeProvider provider, ThemeData theme) {
    final bool isDark = theme.brightness == Brightness.dark;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: AppThemeType.values.map((type) {
        final bool isSelected = provider.currentThemeType == type;
        final bool isPureWhite = type == AppThemeType.pureWhite;

        Color seedColor;
        switch (type) {
          case AppThemeType.pureWhite: seedColor = const Color(0xFF94A3B8); break;
          case AppThemeType.industrial: seedColor = AppTheme.primary; break;
          case AppThemeType.forest: seedColor = const Color(0xFF10B981); break;
          case AppThemeType.solar: seedColor = const Color(0xFFF59E0B); break;
          case AppThemeType.midnight: seedColor = const Color(0xFF6366F1); break;
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
                    ? (isDark ? Colors.white : theme.colorScheme.primary)
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

  Widget _buildBody(bool isMobile) {
    switch (_selectedIndex) {
      case 0: return DeviceMapPage(baseUrl: _pbBaseUrl);
      case 1: return PersonPage(searchQuery: "", filter: '전체', isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 2: return DevicePage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 3: return ProductPage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      default: return const Center(child: Text("기능 개발 중입니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)));
    }
  }
}