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

  // [핵심] 안드로이드 태블릿처럼 캡션바와 작업표시줄을 완벽히 덮어버리는 설정
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
          backgroundColor: Colors.white,
          body: Row(
            children: [
              // 좌측 사이드바 (로고 포함)
              if (!isMobile) ...[
                _buildSidebar(isDesktop),
              ],
              // 메인 컨텐츠 영역
              Expanded(
                child: Container(
                  margin: EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      left: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
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

  // 좌측 사이드바
  Widget _buildSidebar(bool extended) {
    double width = extended ? 260 : 85;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBFC),
      ),
      child: Column(
        children: [
          // 사이드바 최상단 로고 이미지
          _buildSidebarLogo(extended),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _menuItems.length,
              itemBuilder: (context, index) {
                return _buildMenuItem(index, extended);
              },
            ),
          ),

          // 하단 시스템 제어 (키오스크 모드 전환 및 종료)
          _buildSidebarSystemActions(extended),
        ],
      ),
    );
  }

  Widget _buildSidebarLogo(bool extended) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: extended ? 40 : 20, horizontal: 10),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: extended ? 160 : 45,
          height: extended ? 160 : 45,
          child: Image.asset(
            'assets/images/PLUG4ASSET.png',
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => Icon(
              Icons.api_rounded,
              size: extended ? 60 : 30,
              color: AppTheme.primary.withValues(alpha: 0.2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarSystemActions(bool extended) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.03))),
      ),
      child: Column(
        children: [
          // [수정] 창 최소화 버튼 제거됨
          _buildSidebarActionButton(
            icon: Icons.lock_open,
            label: "KIOSK MODE",
            extended: extended,
            onTap: () {
              setState(() {
                _isKioskMode = true;
              });
            },
          ),
          const SizedBox(height: 8),
          if (Platform.isWindows) ...[
            _buildSidebarActionButton(
              icon: Icons.power_settings_new,
              label: "시스템 종료",
              color: AppTheme.danger,
              extended: extended,
              onTap: () async {
                await windowManager.close();
              },
            ),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildSidebarActionButton({
    required IconData icon,
    required String label,
    required bool extended,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 48,
        padding: EdgeInsets.symmetric(horizontal: extended ? 16 : 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
        ),
        child: Row(
          mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color ?? Colors.black45),
            if (extended) ...[
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color ?? Colors.black54,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(int index, bool extended) {
    bool isSelected = _selectedIndex == index;
    var item = _menuItems[index];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 52,
          padding: EdgeInsets.symmetric(horizontal: extended ? 16 : 0),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                child: Center(
                  child: FaIcon(
                    item['icon'],
                    size: 18,
                    color: isSelected ? Colors.white : Colors.black45,
                  ),
                ),
              ),
              if (extended) ...[
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    item['title'],
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 15,
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
          child: Text("기능 개발 중입니다.", style: TextStyle(color: Colors.black26, fontWeight: FontWeight.bold)),
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