import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

// [수정] 데이터 모델과 통신 프로바이더(DataModule)를 명시적으로 임포트합니다.
import '../models/devices.dart';
import '../providers/device_provider.dart';

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
  bool _isKioskMode = true;
  int _selectedIndex = 0;
  final String _pbBaseUrl = "http://127.0.0.1:8090";

  @override
  Widget build(BuildContext context) {
    // 키오스크 모드 (VCL의 FullScreen 모달 폼과 유사)
    if (_isKioskMode) {
      return Scaffold(
        body: KioskView(
          onDismiss: () => setState(() => _isKioskMode = false),
        ),
      );
    }

    // [핵심] DeviceProvider를 여기서 주입 (Global DataModule)
    // 이 위치에 있어야 '장치관리'에서 '상황판'으로 넘어가도 TCP 세션이 유지됩니다.
    return ChangeNotifierProvider(
      create: (_) => DeviceProvider(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 1000;
          bool isMobile = constraints.maxWidth <= 650;

          return Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            body: Row(
              children: [
                // 왼쪽 네비게이션 레일 (C++Builder의 사이드 메뉴 바)
                if (!isMobile) _buildNavRail(isDesktop),

                Expanded(
                  child: Column(
                    children: [
                      // 상단 드래그 영역 및 헤더
                      if (!isMobile) DragToMoveArea(child: _buildHeader()),

                      // 메인 콘텐츠 영역 (TPageControl의 ActivePage 전환과 동일)
                      Expanded(
                        child: _buildBody(isMobile),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// [UI] 사이드 네비게이션 바
  Widget _buildNavRail(bool extended) {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      extended: extended,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      backgroundColor: Colors.white,
      unselectedIconTheme: const IconThemeData(color: Colors.blueGrey, size: 20),
      selectedIconTheme: const IconThemeData(color: Colors.indigo, size: 22),
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
        child: IconButton(
          icon: const Icon(Icons.lock_outline, color: Colors.blueGrey),
          onPressed: () => setState(() => _isKioskMode = true),
        ),
      ),
    );
  }

  /// [UI] 상단 헤더 영역
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'RFID Smart Solution',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
          ),
          if (Platform.isWindows)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
              onPressed: () => windowManager.close(),
            ),
        ],
      ),
    );
  }

  /// [Logic] 페이지 전환 본체 (ActivePageIndex 분기 로직)
  Widget _buildBody(bool isMobile) {
    switch (_selectedIndex) {
      case 0:
        return DeviceMapPage(baseUrl: _pbBaseUrl);
      case 1:
        return PersonPage(
          searchQuery: "",
          filter: '전체',
          isMobile: isMobile,
          baseUrl: _pbBaseUrl,
        );
      case 2:
        return DevicePage(
          searchQuery: "",
          isMobile: isMobile,
          baseUrl: _pbBaseUrl,
        );
      case 3:
        return ProductPage(
          searchQuery: "",
          isMobile: isMobile,
          baseUrl: _pbBaseUrl,
        );
      default:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const FaIcon(FontAwesomeIcons.hammer, size: 40, color: Colors.grey),
              const SizedBox(height: 16),
              Text("$_selectedIndex번 페이지 준비 중"),
            ],
          ),
        );
    }
  }
}