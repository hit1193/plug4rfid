import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

// 각 페이지 위젯들 (파일이 존재해야 컴파일됩니다)
import 'kiosk_view.dart';
import 'person_page.dart';
import 'device_page.dart';
import 'product_page.dart';
import 'device_map_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // [중요] 초기값을 false로 설정해야 아이콘이 있는 대시보드가 먼저 뜹니다.
  // 스크린샷의 화면은 이 값이 true일 때 나오는 'KioskView'입니다.
  bool _isKioskMode = false;
  int _selectedIndex = 0;
  final String _pbBaseUrl = "http://127.0.0.1:8090";

  @override
  Widget build(BuildContext context) {
    // 1. 키오스크 모드 (제어 아이콘이 없는 현장 대기 화면)
    if (_isKioskMode) {
      return Scaffold(
        body: KioskView(
          onDismiss: () => setState(() => _isKioskMode = false),
        ),
      );
    }

    // 2. 관리자 모드 (상단에 제어 아이콘이 있는 대시보드)
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth > 1000;
        bool isMobile = constraints.maxWidth <= 650;

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: Row(
            children: [
              if (!isMobile) _buildModernNavRail(isDesktop),
              Expanded(
                child: Column(
                  children: [
                    // 이 영역이 'DragToMoveArea'이며, 우측에 최소/최대/닫기 아이콘이 배치됩니다.
                    DragToMoveArea(child: _buildHeader()),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildBody(isMobile),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModernNavRail(bool extended) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF0F172A)),
      child: NavigationRail(
        selectedIndex: _selectedIndex,
        extended: extended,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: Colors.transparent,
        unselectedIconTheme: const IconThemeData(color: Color(0xFF94A3B8), size: 20),
        selectedIconTheme: const IconThemeData(color: Colors.white, size: 22),
        unselectedLabelTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        selectedLabelTextStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
        indicatorColor: const Color(0xFF334155),
        destinations: const [
          NavigationRailDestination(icon: FaIcon(FontAwesomeIcons.chartPie), label: Text('관제상황판')),
          NavigationRailDestination(icon: FaIcon(FontAwesomeIcons.users), label: Text('인원관리')),
          NavigationRailDestination(icon: FaIcon(FontAwesomeIcons.microchip), label: Text('장치관리')),
          NavigationRailDestination(icon: FaIcon(FontAwesomeIcons.boxesStacked), label: Text('물품관리')),
          NavigationRailDestination(icon: FaIcon(FontAwesomeIcons.clockRotateLeft), label: Text('출입기록')),
          NavigationRailDestination(icon: FaIcon(FontAwesomeIcons.gears), label: Text('설정')),
        ],
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              const Icon(Icons.precision_manufacturing, color: Color(0xFF38BDF8), size: 28),
              const SizedBox(height: 20),
              IconButton(
                icon: const Icon(Icons.lock_outline, color: Color(0xFF94A3B8)),
                onPressed: () => setState(() => _isKioskMode = true),
                tooltip: '키오스크 모드로 전환',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(_getMenuTitle(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(width: 12),
              _buildStatusBadge(),
            ],
          ),
          // 이 부분이 윈도우 우측 상단 버튼들입니다.
          if (Platform.isWindows)
            Row(
              children: [
                _buildWindowBtn(Icons.remove, () => windowManager.minimize()),
                _buildWindowBtn(Icons.crop_square, () async {
                  if (await windowManager.isMaximized()) {
                    windowManager.unmaximize();
                  } else {
                    windowManager.maximize();
                  }
                }),
                _buildWindowBtn(Icons.close, () => windowManager.close(), isClose: true),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(backgroundColor: Colors.green, radius: 4),
          SizedBox(width: 6),
          Text('System Online', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        ],
      ),
    );
  }

  String _getMenuTitle() {
    const titles = ['종합 관제 상황판', '인원 관리', '장치 관리', '물품 관리', '출입 기록', '환경 설정'];
    return titles[_selectedIndex];
  }

  Widget _buildWindowBtn(IconData icon, VoidCallback onPressed, {bool isClose = false}) {
    return SizedBox(
      width: 45,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 16, color: isClose ? Colors.redAccent : const Color(0xFF64748B)),
        onPressed: onPressed,
        hoverColor: isClose ? Colors.red.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        style: IconButton.styleFrom(shape: const RoundedRectangleBorder()),
      ),
    );
  }

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

class DragToMoveArea extends StatelessWidget {
  final Widget child;
  const DragToMoveArea({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) { if (Platform.isWindows) windowManager.startDragging(); },
      child: child,
    );
  }
}