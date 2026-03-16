import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'dart:io';

import '../core/pocketbase_client.dart';
import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart'; // 로그인된 사용자 정보를 가져오기 위해 AuthProvider 임포트!

// 연결할 각 하위 페이지들을 임포트합니다.
import 'user_page.dart';
import 'product_page.dart';
import 'device_page.dart';
import 'device_map_page.dart';
import 'kiosk_view.dart';
import 'detection_history_page.dart';
import 'notice_page.dart';
import 'settings_page.dart';

/// ---------------------------------------------------------------------------
/// [RFID 솔루션 통합 메인 레이아웃 페이지 (MainPage)]
/// 좌측 사이드바와 우측 본문 영역을 동적으로 관리하며 메뉴 네비게이션을 담당합니다.
/// C++Builder의 MDI Main Form과 같은 역할을 수행합니다.
/// ---------------------------------------------------------------------------
class MainPage extends StatefulWidget {
  // main.dart로부터 전달받는 키오스크 모드 시작 설정값 변수입니다.
  final bool initialKioskMode;

  const MainPage({
    super.key,
    this.initialKioskMode = false, // 값이 전달되지 않았을 경우를 대비한 안전한 기본값
  });

  @override
  State<MainPage> createState() {
    return _MainPageState();
  }
}

class _MainPageState extends State<MainPage> with WindowListener {
  late bool _isKioskMode;

  bool _isSidebarExtended = true;
  int _selectedIndex = 0;
  final String _pbBaseUrl = "http://127.0.0.1:8090";

  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();

  // 사이드바 및 글로벌 바에 표시될 메뉴 리스트입니다.
  final List<Map<String, dynamic>> _menuItems = [
    {'title': '종합 관제 상황판', 'icon': FontAwesomeIcons.chartPie},        // Index 0
    {'title': '장치 관리', 'icon': FontAwesomeIcons.microchip},            // Index 1
    {'title': '인원 관리', 'icon': FontAwesomeIcons.users},                // Index 2
    {'title': '물품 관리', 'icon': FontAwesomeIcons.boxesStacked},         // Index 3
    {'title': '출입 기록', 'icon': FontAwesomeIcons.clockRotateLeft},      // Index 4
    {'title': '공지사항', 'icon': FontAwesomeIcons.bullhorn},              // Index 5
    {'title': '환경 설정', 'icon': FontAwesomeIcons.gears},                // Index 6
  ];

  @override
  void initState() {
    super.initState();

    _isKioskMode = widget.initialKioskMode;

    windowManager.addListener(this);
    _initWindowPosition();
    _initSystemTray();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// ---------------------------------------------------------------------------
  /// [창 초기 위치/크기 보정 함수]
  /// ---------------------------------------------------------------------------
  Future<void> _initWindowPosition() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        bool isFull = await windowManager.isFullScreen();
        if (!isFull) {
          await windowManager.setFullScreen(true);
        }
      } catch (e) {
        debugPrint("창 초기화 중 오류 발생: $e");
      }
    }
  }

  /// 시스템 트레이(작업 표시줄 아이콘) 초기화 함수
  Future<void> _initSystemTray() async {
    if (!kIsWeb && Platform.isWindows) {
      await _systemTray.initSystemTray(
        title: "RFID 통합 관제",
        iconPath: 'assets/app_icon.ico',
      );

      final Menu menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(
            label: '화면 다시 열기 (Restore)',
            onClicked: (dynamic menuItem) async {
              await _appWindow.show();
              await windowManager.setFullScreen(true);
            }
        ),
        MenuSeparator(),
        MenuItemLabel(
            label: '프로그램 완전 종료',
            onClicked: (dynamic menuItem) async {
              await windowManager.close();
            }
        ),
      ]);

      await _systemTray.setContextMenu(menu);

      _systemTray.registerSystemTrayEventHandler((String eventName) async {
        if (eventName == kSystemTrayEventClick) {
          await _appWindow.show();
          await windowManager.setFullScreen(true);
        } else if (eventName == kSystemTrayEventRightClick) {
          await _systemTray.popUpContextMenu();
        }
      });
    }
  }

  @override
  void onWindowRestore() async {
    if (!kIsWeb && Platform.isWindows) {
      bool isFull = await windowManager.isFullScreen();
      if (!isFull) {
        await windowManager.setFullScreen(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeProvider themeProvider = context.watch<ThemeProvider>();
    final ThemeData theme = themeProvider.themeData;
    final AuthProvider authProvider = context.watch<AuthProvider>();

    if (_isKioskMode) {
      return Scaffold(
          body: KioskView(
              onDismiss: () {
                setState(() {
                  _isKioskMode = false;
                });
              }
          )
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
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
                      // 글로벌 Top Bar 렌더링
                      _buildGlobalTopBar(theme, authProvider, isMobile),

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

  /// ---------------------------------------------------------------------------
  /// [UI 조각] 글로벌 Top Bar (메뉴 타이틀 + 아이콘 & 사용자 프로필 칩)
  /// ---------------------------------------------------------------------------
  Widget _buildGlobalTopBar(ThemeData theme, AuthProvider auth, bool isMobile) {
    final String currentTitle = _menuItems[_selectedIndex]['title'];
    final dynamic currentIcon = _menuItems[_selectedIndex]['icon'];
    final bool isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      height: 70, // 탑 바의 높이 고정
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerTheme.color ?? Colors.black12, width: 1.0),
          left: BorderSide(color: theme.dividerTheme.color ?? Colors.black12, width: 1.0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 타이틀 옆에 현재 메뉴의 아이콘을 멋지게 배치합니다.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: FaIcon(
              currentIcon as IconData,
              size: 22,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          // 현재 진입해 있는 메뉴의 타이틀을 큼직하게 보여줍니다.
          Text(
            currentTitle,
            style: TextStyle(
              fontFamily: AppTheme.fontPretendard,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: isDarkMode ? Colors.white : Colors.black87,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(), // 남은 공간을 밀어내어 프로필 칩을 우측 끝으로 보냅니다.

          _buildLoginUserInfo(auth, theme),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [UI 조각] 로그인된 사용자 정보를 뱃지 형태로 깔끔하게 표시합니다.
  /// ---------------------------------------------------------------------------
  Widget _buildLoginUserInfo(AuthProvider auth, ThemeData theme) {
    final String userName = auth.currentUser;
    final String role = auth.role; // 🔥 DB 정규 필드인 role을 활용합니다.

    // 관리자(Admin/Manager)일 경우 강조 색상을 다르게 줍니다.
    final bool isManagerLevel = auth.isAdmin || role.contains('관리자') || role.toLowerCase().contains('admin');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isManagerLevel ? Colors.indigo.withValues(alpha: 0.1) : theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isManagerLevel ? Colors.indigo.withValues(alpha: 0.3) : theme.colorScheme.primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isManagerLevel ? Icons.admin_panel_settings : Icons.person,
            color: isManagerLevel ? Colors.indigo : theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            '$userName 님 접속중',
            style: TextStyle(
              fontFamily: AppTheme.fontPretendard,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isManagerLevel ? Colors.indigo : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isManagerLevel ? Colors.indigo : theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              role, // 🔥 role 필드의 데이터를 그대로 칩 안에 텍스트로 보여줍니다!
              style: const TextStyle(
                fontFamily: AppTheme.fontPretendard,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 좌측 사이드바 위젯 생성
  Widget _buildSidebar(bool extended, ThemeData theme, ThemeProvider themeProvider) {
    final bool isDarkMode = theme.brightness == Brightness.dark;
    final Color deeperSidebarColor = isDarkMode
        ? const Color(0xFF151D2E)
        : Color.alphaBlend(theme.colorScheme.primary.withValues(alpha: 0.06), theme.scaffoldBackgroundColor);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: extended ? 280 : 90,
      curve: Curves.easeInOut,
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
                ...List.generate(_menuItems.length, (int index) {
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
                Divider(color: theme.dividerTheme.color),
                const SizedBox(height: 20),

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
                const SizedBox(height: 4),
                _buildMenuItem(
                  title: "로그아웃",
                  icon: Icons.logout_rounded,
                  extended: extended,
                  isSelected: false,
                  color: Colors.blueGrey,
                  theme: theme,
                  onTap: () {
                    pb.authStore.clear();
                  },
                ),
                if (!kIsWeb && Platform.isWindows) ...[
                  const SizedBox(height: 4),
                  _buildMenuItem(
                    title: "트레이로 숨기기",
                    icon: Icons.visibility_off,
                    extended: extended,
                    isSelected: false,
                    color: Colors.blueGrey,
                    theme: theme,
                    onTap: () async {
                      await windowManager.hide();
                    },
                  ),
                  const SizedBox(height: 4),
                  _buildMenuItem(
                    title: "종료하기",
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

  /// 사이드바 상단 로고 영역 생성
  Widget _buildSidebarHeader(bool extended, ThemeData theme) {
    final bool isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.fromLTRB(14, extended ? 24 : 20, 14, 10),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              constraints: BoxConstraints(
                maxHeight: extended ? 80 : 40,
                maxWidth: extended ? 180 : 50,
              ),
              padding: EdgeInsets.zero,
              child: Image.asset(
                'assets/images/PLUG4ASSET.png',
                fit: BoxFit.cover,
                errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                  return Text(
                    "PLUG4",
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      fontWeight: FontWeight.w900,
                      fontSize: extended ? 24 : 16,
                      color: isDarkMode ? Colors.white : theme.colorScheme.primary,
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: extended ? -16 : -10,
            right: extended ? -12 : null,
            left: extended ? null : -12,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                onPressed: () {
                  setState(() {
                    _isSidebarExtended = !_isSidebarExtended;
                  });
                },
                tooltip: extended ? "사이드바 접기" : "사이드바 펴기",
                icon: Icon(
                  extended ? Icons.menu_open_rounded : Icons.menu_rounded,
                  color: isDarkMode ? Colors.white70 : theme.colorScheme.primary.withValues(alpha: 0.8),
                  size: 28,
                ),
                padding: const EdgeInsets.all(10),
                constraints: const BoxConstraints(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 개별 메뉴 항목 버튼 생성 (아이콘 + 텍스트)
  Widget _buildMenuItem({
    required String title,
    required dynamic icon,
    required bool extended,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData theme,
    Color? color,
  }) {
    final bool isDarkMode = theme.brightness == Brightness.dark;
    final Color activeColor = theme.colorScheme.primary;
    final Color inactiveColor = color ?? (isDarkMode ? Colors.white70 : Colors.black54);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 56,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : (isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
              width: 1.5,
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Container(
              width: extended ? 252 : 62,
              padding: EdgeInsets.symmetric(horizontal: extended ? 18 : 0),
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
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontFamily: AppTheme.fontPretendard,
                          color: isSelected ? Colors.white : inactiveColor,
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                          fontSize: 16,
                        ),
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
        ),
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [라우팅 핵심 로직] 선택된 메뉴(Index)에 따라 우측 본문 화면을 동적으로 반환합니다.
  /// ---------------------------------------------------------------------------
  Widget _buildBody(bool isMobile) {
    switch (_selectedIndex) {
      case 0:
        return DeviceMapPage(baseUrl: _pbBaseUrl);
      case 1:
        return DevicePage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 2:
        return UserPage(searchQuery: "", filter: '전체', isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 3:
        return ProductPage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 4:
        return DetectionHistoryPage(isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 5:
        return NoticePage(isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 6:
        return SettingsPage(isMobile: isMobile);
      default:
        return const Center(
            child: Text(
                "선택한 기능은 현재 준비 중입니다.",
                style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    fontWeight: FontWeight.bold
                )
            )
        );
    }
  }
}