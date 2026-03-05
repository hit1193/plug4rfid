import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import 'kiosk_view.dart';
import 'person_page.dart';
import 'device_page.dart';
import 'product_page.dart';
import 'device_map_page.dart';

import '../theme/app_theme.dart';
import '../providers/person_provider.dart';
import '../providers/product_provider.dart';
import '../providers/theme_provider.dart';

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
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setFullScreen(true);
      await windowManager.setResizable(false);
      await windowManager.focus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();

    if (_isKioskMode) {
      return Scaffold(
        body: KioskView(
          onDismiss: () {
            setState(() {
              _isKioskMode = false;
            });
          },
        ),
      );
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
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    border: Border(
                      left: BorderSide(
                        color: theme.dividerTheme.color ?? theme.colorScheme.outlineVariant,
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: _buildBody(isMobile),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar(bool extended, ThemeData theme, ThemeProvider themeProvider) {
    double width = extended ? 280 : 90;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: width,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
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
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                  );
                }),
                const SizedBox(height: 20),
                Divider(color: theme.dividerTheme.color, height: 1),
                const SizedBox(height: 20),

                // [추가] 테마 스위처 섹션
                if (extended) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(
                      "감성 테마 선택",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  _buildThemeSelector(themeProvider, theme),
                  const SizedBox(height: 20),
                  Divider(color: theme.dividerTheme.color, height: 1),
                  const SizedBox(height: 20),
                ],

                _buildMenuItem(
                  title: "키오스크 모드",
                  icon: FontAwesomeIcons.lockOpen,
                  extended: extended,
                  isSelected: false,
                  theme: theme,
                  onTap: () {
                    setState(() {
                      _isKioskMode = true;
                    });
                  },
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
                    onTap: () async {
                      await windowManager.close();
                    },
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

  // [추가] 테마를 선택할 수 있는 가로형 버튼 그룹
  Widget _buildThemeSelector(ThemeProvider provider, ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AppThemeType.values.map((type) {
        final bool isSelected = provider.currentThemeType == type;
        final Color seedColor = _getSeedColor(type);

        return GestureDetector(
          onTap: () => provider.setTheme(type),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: seedColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? theme.colorScheme.onSurface : Colors.transparent,
                width: 3,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: seedColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
              ],
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
        );
      }).toList(),
    );
  }

  Color _getSeedColor(AppThemeType type) {
    switch (type) {
      case AppThemeType.industrial: return AppTheme.colorIndustrial;
      case AppThemeType.forest: return AppTheme.colorForest;
      case AppThemeType.solar: return AppTheme.colorSolar;
      case AppThemeType.midnight: return AppTheme.colorMidnight;
    }
  }

  Widget _buildSidebarHeader(bool extended, ThemeData theme) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, extended ? 50 : 25, 14, 25),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: extended ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
            children: [
              if (extended)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 140,
                  child: Image.asset(
                    'assets/images/PLUG4ASSET.png',
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) => Text(
                      "PLUG4",
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _isSidebarExtended = !_isSidebarExtended;
                  });
                },
                icon: Icon(
                  extended ? Icons.menu_open_rounded : Icons.menu_rounded,
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                  size: 26,
                ),
              ),
            ],
          ),
          if (!extended) ...[
            const SizedBox(height: 20),
            Icon(
              Icons.api_rounded,
              size: 32,
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
          ],
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
                  : (color?.withValues(alpha: 0.3) ?? theme.dividerTheme.color ?? Colors.black12),
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
                      ? Icon(
                    icon,
                    size: 20,
                    color: isSelected ? Colors.white : inactiveColor,
                  )
                      : FaIcon(
                    icon as IconData,
                    size: 18,
                    color: isSelected ? Colors.white : inactiveColor,
                  ),
                ),
              ),
              if (extended) ...[
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : inactiveColor,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 16,
                      letterSpacing: -0.5,
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

  Widget _buildBody(bool isMobile) {
    switch (_selectedIndex) {
      case 0:
        return DeviceMapPage(baseUrl: _pbBaseUrl);
      case 1:
        return PersonPage(searchQuery: "", filter: '전체', isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 2:
        return DevicePage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 3:
        return ProductPage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      default:
        return const Center(
          child: Text("기능 개발 중입니다."),
        );
    }
  }
}

class DragToMoveArea extends StatelessWidget {
  final Widget child;
  const DragToMoveArea({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return child;
  }
}