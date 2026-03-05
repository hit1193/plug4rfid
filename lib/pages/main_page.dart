import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'dart:io';

// 각 페이지 위젯
import 'kiosk_view.dart';
import 'person_page.dart';
import 'device_page.dart';
import 'product_page.dart';
import 'device_map_page.dart';

// 테마 및 프로바이더
import '../theme/app_theme.dart';
import '../providers/person_provider.dart';
import '../providers/product_provider.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _isKioskMode = false;
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

  // 윈도우 환경에서 안드로이드 태블릿처럼 전체화면 및 캡션바 제거 설정
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

    // 키오스크 모드 전환 시의 화면
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
        bool isDesktop = constraints.maxWidth > 1100;
        bool isMobile = constraints.maxWidth <= 650;

        return Scaffold(
          // 배경색을 순백색으로 통일
          backgroundColor: Colors.white,
          body: Row(
            children: [
              // 좌측 사이드바
              if (!isMobile) ...[
                _buildSidebar(isDesktop, theme),
              ],

              // 메인 컨텐츠 영역
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      left: BorderSide(
                        color: theme.dividerTheme.color ?? Colors.black.withValues(alpha: 0.05),
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

  // 좌측 사이드바 빌더
  Widget _buildSidebar(bool extended, ThemeData theme) {
    double width = extended ? 280 : 90;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      decoration: const BoxDecoration(
        color: Colors.white, // 사이드바 배경색 화이트 통일
      ),
      child: Column(
        children: [
          // 사이드바 로고 영역
          _buildSidebarLogo(extended),

          const SizedBox(height: 10),

          // 통합 리스트뷰 (메뉴 + 시스템 액션)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                // 1. 일반 업무 메뉴들
                ...List.generate(_menuItems.length, (index) {
                  return _buildMenuItem(
                    index: index,
                    title: _menuItems[index]['title'],
                    icon: _menuItems[index]['icon'],
                    extended: extended,
                    isSelected: _selectedIndex == index,
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

                // 2. 시스템 액션 메뉴 (메뉴와 동일한 스타일로 배치)
                _buildMenuItem(
                  title: "키오스크 모드",
                  icon: FontAwesomeIcons.lockOpen,
                  extended: extended,
                  isSelected: false,
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

  // 사이드바 로고 영역
  Widget _buildSidebarLogo(bool extended) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: extended ? 50 : 25, horizontal: 10),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: extended ? 180 : 50,
          height: extended ? 180 : 50,
          child: Image.asset(
            'assets/images/PLUG4ASSET.png',
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => Icon(
              Icons.api_rounded,
              size: extended ? 60 : 30,
              color: AppTheme.primary.withValues(alpha: 0.1),
            ),
          ),
        ),
      ),
    );
  }

  // 공통 메뉴 아이템 빌더 (업무 메뉴 및 시스템 메뉴 공용)
  Widget _buildMenuItem({
    int? index,
    required String title,
    required dynamic icon,
    required bool extended,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
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
            color: isSelected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: isSelected ? AppTheme.primary : (color?.withValues(alpha: 0.2) ?? Colors.black.withValues(alpha: 0.05)),
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
                    color: isSelected ? Colors.white : (color ?? Colors.black45),
                  )
                      : FaIcon(
                    icon as IconData,
                    size: 18,
                    color: isSelected ? Colors.white : (color ?? Colors.black45),
                  ),
                ),
              ),
              if (extended) ...[
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : (color ?? Colors.black87),
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

  // 메인 바디 영역 전환 로직
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
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.construction_rounded, size: 64, color: AppTheme.primary.withValues(alpha: 0.1)),
              const SizedBox(height: 16),
              const Text(
                "기능 개발 중입니다.",
                style: TextStyle(color: Colors.black26, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
        );
    }
  }
}

// 창 이동 처리를 위한 영역 위젯
class DragToMoveArea extends StatelessWidget {
  final Widget child;
  const DragToMoveArea({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return child;
  }
}