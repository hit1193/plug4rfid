import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'dart:io';

// 테마 및 프로바이더 임포트
import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';

// 하위 페이지 위젯 임포트
import 'person_page.dart';
import 'product_page.dart';
import 'device_page.dart';
import 'device_map_page.dart';
import 'kiosk_view.dart';

/// RFID FA 솔루션의 메인 레이아웃 페이지입니다.
/// [디자인 업데이트] 사이드바에 깊이감을 주기 위해 본문보다 약간 더 진한 톤온톤 배색을 적용했습니다.
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

    if (_isKioskMode) {
      return Scaffold(
        body: KioskView(onDismiss: () => setState(() => _isKioskMode = false)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth <= 650;

        return Scaffold(
          // 전체 베이스 배경색
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Row(
            children: [
              // 1. 좌측 사이드바 (본문보다 약간 더 진한 톤 적용)
              if (!isMobile) ...[
                _buildSidebar(_isSidebarExtended, theme, themeProvider),
              ],

              // 2. 우측 콘텐츠 영역 (테마 고유의 연한 배경색 유지)
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
                                // 사이드바가 더 진해졌으므로 경계선은 더 은은하게 처리
                                color: theme.dividerTheme.color ?? Colors.black.withValues(alpha: 0.05),
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

  /// [핵심 수정] 사이드바의 배경색을 본문(scaffoldBackgroundColor)보다 약간 더 진하게(Deeper Tone) 설정합니다.
  Widget _buildSidebar(bool extended, ThemeData theme, ThemeProvider themeProvider) {
    final bool isPureWhite = themeProvider.currentThemeType == AppThemeType.pureWhite;
    final bool isDark = theme.brightness == Brightness.dark;

    // 사이드바 전용 색상 계산: 본문 배경색에 Primary 컬러를 5% 섞어 명도를 미세하게 낮춤
    final Color deeperSidebarColor = isPureWhite
        ? const Color(0xFFF8FAFC) // 순백색 테마일 때 사이드바는 아주 연한 회색톤
        : Color.alphaBlend(
        theme.colorScheme.primary.withValues(alpha: 0.06),
        theme.scaffoldBackgroundColor
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: extended ? 280 : 90,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        // 다크모드일 때는 표면색을 유지하고, 라이트 테마들에서는 본문보다 진한 색상 적용
        color: isDark ? theme.colorScheme.surface : deeperSidebarColor,
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
                Divider(color: theme.dividerTheme.color?.withValues(alpha: 0.5), thickness: 1),
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
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  _buildThemeSelector(themeProvider, theme),
                  const SizedBox(height: 20),
                  Divider(color: theme.dividerTheme.color?.withValues(alpha: 0.5), thickness: 1),
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
                    color: theme.colorScheme.primary
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          IconButton(
            onPressed: () => setState(() => _isSidebarExtended = !_isSidebarExtended),
            icon: Icon(
                extended ? Icons.menu_open_rounded : Icons.menu_rounded,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
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
    final Color activeColor = theme.colorScheme.primary;
    final Color inactiveColor = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 56,
          padding: EdgeInsets.symmetric(horizontal: extended ? 18 : 0),
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : (color?.withValues(alpha: 0.2) ?? theme.dividerTheme.color?.withValues(alpha: 0.5) ?? Colors.black.withValues(alpha: 0.05)),
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
                    overflow: TextOverflow.ellipsis,
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
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: AppThemeType.values.map((type) {
        final bool isSelected = provider.currentThemeType == type;
        final bool isPureWhite = type == AppThemeType.pureWhite;

        Color seedColor;
        switch (type) {
          case AppThemeType.pureWhite: seedColor = const Color(0xFF475569); break;
          case AppThemeType.industrial: seedColor = AppTheme.primary; break;
          case AppThemeType.forest: seedColor = const Color(0xFF10B981); break;
          case AppThemeType.solar: seedColor = const Color(0xFFF59E0B); break;
          case AppThemeType.midnight: seedColor = const Color(0xFF334155); break;
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
                color: isSelected ? theme.colorScheme.primary : (isPureWhite ? Colors.black.withValues(alpha: 0.1) : Colors.transparent),
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