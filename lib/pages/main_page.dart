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

// 테마 설정
import '../theme/app_theme.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  bool _isKioskMode = false;
  int _selectedIndex = 0;
  final String _pbBaseUrl = "http://127.0.0.1:8090";

  // 메뉴 정의 데이터 (아이콘 고정 폭 정렬을 위해 텍스트 분리)
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
      // 1. 캡션바 스타일 숨김 강제 (2중 잠금)
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );

      // 2. 전체화면 모드 실행 (작업표시줄 위로 앱을 올림)
      await windowManager.setFullScreen(true);

      // 3. 창 크기 조절 금지 및 포커스 확보
      await windowManager.setResizable(false);
      await windowManager.focus();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. 키오스크 모드 (전체화면 오버레이)
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

    // 2. 관리자 대시보드 모드 (캡션바 없는 순수 0px 시작 레이아웃)
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth > 1100;
        bool isMobile = constraints.maxWidth <= 650;

        return Scaffold(
          backgroundColor: Colors.white,
          body: Row(
            children: [
              // 좌측 사이드바 (시스템 종료/최소화 버튼 포함)
              if (!isMobile) ...[
                _buildSidebar(isDesktop),
              ],
              // 메인 컨텐츠 영역
              Expanded(
                child: Container(
                  margin: EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    // 사이드바와 본문 사이를 구분하는 가느다란 라인
                    border: Border(
                      left: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
                    ),
                  ),
                  // [수정] 캡션바 영역 없이 즉시 본문 페이지 렌더링
                  child: _buildBody(isMobile),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 좌측 사이드바 (최상단 0px부터 시작하도록 로고 삭제)
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
          // 상단 여백 (캡션바가 없으므로 최소한의 시각적 숨통 확보)
          const SizedBox(height: 24),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _menuItems.length,
              itemBuilder: (context, index) {
                return _buildMenuItem(index, extended);
              },
            ),
          ),

          // 하단 시스템 제어 영역 (최소화, 종료 등)
          _buildSidebarSystemActions(extended),
        ],
      ),
    );
  }

  // 사이드바 하단 제어 버튼 셋
  Widget _buildSidebarSystemActions(bool extended) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.03))),
      ),
      child: Column(
        children: [
          // 창 최소화 버튼
          if (Platform.isWindows) ...[
            _buildSidebarActionButton(
              icon: Icons.minimize,
              label: "최소화",
              extended: extended,
              onTap: () async {
                await windowManager.minimize();
              },
            ),
            const SizedBox(height: 8),
          ],

          // 키오스크 모드 전환
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

          // 프로그램 종료 버튼
          if (Platform.isWindows) ...[
            _buildSidebarActionButton(
              icon: Icons.power_settings_new,
              label: "프로그램 종료",
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

  // 사이드바 액션 버튼 빌더
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

  // 메뉴 개별 항목 빌더
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
            // 선택 시 엘리베이션(그림자) 효과 제거
            boxShadow: null,
          ),
          child: Row(
            mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              // [수정] 고정 폭 아이콘 영역을 통해 우측 텍스트 정렬선 일치
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
                      fontSize: 15, // [수정] 메뉴 글자 크기 상향
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

// 윈도우 드래그 클래스 (전체화면 고정형 모드에서는 기능을 무력화함)
class DragToMoveArea extends StatelessWidget {
  final Widget child;
  const DragToMoveArea({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return child;
  }
}