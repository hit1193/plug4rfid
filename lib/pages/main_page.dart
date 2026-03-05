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

/// RFID 솔루션의 메인 레이아웃을 담당하는 페이지입니다.
/// 디자인 철학: 미니멀리즘, 키오스크 스타일, 톤온톤 배색
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _isKioskMode = false;
  bool _isSidebarExtended = true; // 사이드바 확장/축소 상태 관리
  int _selectedIndex = 0;
  final String _pbBaseUrl = "http://127.0.0.1:8090";

  // 메뉴 데이터 정의
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

  /// 데스크톱 환경을 위한 전체 화면 및 스타일 초기화
  Future<void> _initFullScreenConfiguration() async {
    if (Platform.isWindows) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setFullScreen(true);
      await windowManager.focus();
    }
  }

  @override
  Widget build(BuildContext context) {
    // [핵심] ThemeProvider를 감시(watch)하여 테마 변경 시 배경색을 즉각 반영함
    final themeProvider = context.watch<ThemeProvider>();
    final theme = themeProvider.themeData;

    // 키오스크 모드 UI 전환
    if (_isKioskMode) {
      return Scaffold(
        body: KioskView(onDismiss: () => setState(() => _isKioskMode = false)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth <= 650;

        return Scaffold(
          // [톤온톤 배색] 테마에서 정의한 scaffoldBackgroundColor를 전역 배경색으로 사용
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Row(
            children: [
              // 1. 좌측 사이드바 영역
              if (!isMobile) ...[
                _buildSidebar(_isSidebarExtended, theme, themeProvider),
              ],

              // 2. 우측 콘텐츠 영역 (페이지 전환)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor, // 배경색 동기화
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

  /// 사이드바 빌더: 로고, 업무 메뉴, 감성 테마 선택기 포함
  Widget _buildSidebar(bool extended, ThemeData theme, ThemeProvider themeProvider) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: extended ? 280 : 90,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface, // 사이드바 표면은 Surface 색상 사용
      ),
      child: Column(
        children: [
          _buildSidebarHeader(extended, theme),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                // 일반 업무 메뉴 리스트
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

                // [테마 스위처] 사이드바 확장 시에만 표시되는 감성 테마 선택기
                if (extended) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(
                      "감성 테마 선택",
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  _buildThemeSelector(themeProvider, theme),
                  const SizedBox(height: 20),
                  Divider(color: theme.dividerTheme.color),
                  const SizedBox(height: 20),
                ],

                // 시스템 기능 메뉴
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

  /// 5종 감성 테마를 선택할 수 있는 원형 버튼 그룹
  Widget _buildThemeSelector(ThemeProvider provider, ThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: AppThemeType.values.map((type) {
        final bool isSelected = provider.currentThemeType == type;
        final bool isPureWhite = type == AppThemeType.pureWhite;

        // 테마별 씨드 컬러 매핑 (Selector UI용)
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

  /// 사이드바 헤더: 로고 및 확장 제어 버튼 (오버플로 방지 처리)
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
                    fontSize: 24,
                    letterSpacing: -1.0,
                    color: theme.colorScheme.primary
                ),
                overflow: TextOverflow.ellipsis,
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

  /// 공통 메뉴 아이템 빌더 (오버플로 17px 에러 방지를 위한 Flexible 적용)
  Widget _buildMenuItem({
    required String title,
    required dynamic icon,
    required bool extended,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData theme,
    Color? color,
  }) {
    final Color activeColor = AppTheme.primary;
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
                // [에러 해결] 텍스트가 공간을 초과해도 오버플로가 발생하지 않도록 조치
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
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

  /// 현재 선택된 인덱스에 따른 본문 페이지 렌더링
  Widget _buildBody(bool isMobile) {
    switch (_selectedIndex) {
      case 0: return DeviceMapPage(baseUrl: _pbBaseUrl);
      case 1: return PersonPage(searchQuery: "", filter: '전체', isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 2: return DevicePage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 3: return ProductPage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      default: return const Center(child: Text("기능 개발 중입니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)));
    }
  }
}