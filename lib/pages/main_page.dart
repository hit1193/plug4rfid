import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'dart:io';

// 하위 페이지 위젯 임포트
import 'kiosk_view.dart';
import 'person_page.dart';
import 'device_page.dart';
import 'product_page.dart';
import 'device_map_page.dart';

// 테마 및 프로바이더 임포트
import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';
import '../providers/person_provider.dart';
import '../providers/product_provider.dart';

/// 앱의 메인 레이아웃을 담당하는 페이지입니다.
/// 좌측 사이드바와 우측 콘텐츠 영역으로 구성되며, 실시간 테마 변경에 반응합니다.
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _isKioskMode = false;
  bool _isSidebarExtended = true; // 사이드바 확장/축소 상태
  int _selectedIndex = 0;
  final String _pbBaseUrl = "http://127.0.0.1:8090";

  // 메뉴 정의 데이터
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

  /// 키오스크 느낌을 주기 위한 전체화면 및 윈도우 스타일 설정
  Future<void> _initFullScreenConfiguration() async {
    if (Platform.isWindows) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      await windowManager.setFullScreen(true);
      await windowManager.focus();
    }
  }

  @override
  Widget build(BuildContext context) {
    // [중요] ThemeProvider를 감시(watch)하여 테마 변경 시 배경색을 즉각 반영합니다.
    final themeProvider = context.watch<ThemeProvider>();
    final theme = themeProvider.themeData;

    // 키오스크 모드 전환 시 UI
    if (_isKioskMode) {
      return Scaffold(
        body: KioskView(onDismiss: () => setState(() => _isKioskMode = false)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth <= 650;

        return Scaffold(
          // [톤온톤 배색 핵심] 테마에서 정의한 연한 배경색(scaffoldBackgroundColor)을 직접 할당합니다.
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Row(
            children: [
              // 1. 좌측 사이드바 영역
              if (!isMobile) ...[
                _buildSidebar(_isSidebarExtended, theme, themeProvider),
              ],

              // 2. 우측 콘텐츠 영역
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor, // 콘텐츠 영역 배경색 동기화
                    border: Border(
                      left: BorderSide(
                        color: theme.dividerTheme.color ?? Colors.black12,
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

  /// 사이드바 빌더: 로고, 메뉴, 테마 스위처를 포함합니다.
  Widget _buildSidebar(bool extended, ThemeData theme, ThemeProvider themeProvider) {
    double width = extended ? 280 : 90;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: width,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface, // 사이드바 표면은 흰색(또는 다크 그레이)으로 유지
      ),
      child: Column(
        children: [
          _buildSidebarHeader(extended, theme),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                // 업무 메뉴 리스트
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
                Divider(color: theme.dividerTheme.color, height: 1),
                const SizedBox(height: 20),

                // [테마 스위처 섹션] 확장 상태일 때만 표시
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

                // 하단 시스템 메뉴
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

  /// 5종 테마를 선택할 수 있는 원형 버튼 그룹
  Widget _buildThemeSelector(ThemeProvider provider, ThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: AppThemeType.values.map((type) {
        final bool isSelected = provider.currentThemeType == type;
        final Color seedColor = _getSeedColor(type);
        final bool isPureWhite = type == AppThemeType.pureWhite;

        return GestureDetector(
          onTap: () => provider.setTheme(type),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isPureWhite ? Colors.white : seedColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? theme.colorScheme.primary : (isPureWhite ? Colors.black12 : Colors.transparent),
                width: isSelected ? 3 : 1,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(color: seedColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))
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

  /// 테마 타입에 따른 강조 색상 반환 (Selector UI용)
  Color _getSeedColor(AppThemeType type) {
    switch (type) {
      case AppThemeType.industrial: return AppTheme.primary; // Industrial Blue
      case AppThemeType.forest: return const Color(0xFF10B981);
      case AppThemeType.solar: return const Color(0xFFF59E0B);
      case AppThemeType.midnight: return const Color(0xFF334155);
      case AppThemeType.pureWhite: return const Color(0xFF475569);
    }
  }

  /// 사이드바 헤더: 로고 및 확장/축소 제어 버튼
  Widget _buildSidebarHeader(bool extended, ThemeData theme) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, extended ? 50 : 25, 14, 25),
      child: Row(
        mainAxisAlignment: extended ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
        children: [
          if (extended)
            Text(
              "PLUG4",
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  letterSpacing: -1.0,
                  color: theme.colorScheme.primary
              ),
            ),
          IconButton(
            onPressed: () => setState(() => _isSidebarExtended = !_isSidebarExtended),
            icon: Icon(
                extended ? Icons.menu_open_rounded : Icons.menu_rounded,
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
                size: 26
            ),
          ),
        ],
      ),
    );
  }

  /// 공통 메뉴 아이템 위젯
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
                            color: isSelected ? Colors.white : inactiveColor,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 16,
                            letterSpacing: -0.5
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1
                    )
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 현재 인덱스에 맞는 본문 페이지 반환
  Widget _buildBody(bool isMobile) {
    switch (_selectedIndex) {
      case 0: return DeviceMapPage(baseUrl: _pbBaseUrl);
      case 1: return PersonPage(searchQuery: "", filter: '전체', isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 2: return DevicePage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 3: return ProductPage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      default: return const Center(child: Text("기능 개발 중입니다."));
    }
  }
}