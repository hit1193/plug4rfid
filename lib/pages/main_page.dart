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
import '../providers/auth_provider.dart';

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
/// 윈도우즈 PC, 안드로이드 웹/앱 모두에 대응하는 완벽한 반응형 메인 폼입니다.
/// 화면 크기에 따라 좌측 고정 사이드바(PC)와 서랍형 Drawer(모바일)로 자동 전환됩니다.
/// ---------------------------------------------------------------------------
class MainPage extends StatefulWidget {
  final bool initialKioskMode;

  const MainPage({
    super.key,
    this.initialKioskMode = false,
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

  // 모바일 화면에서 햄버거 메뉴를 눌렀을 때 Drawer(서랍)를 열기 위해 Scaffold를 제어하는 키입니다.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // [웹 호환성 완벽 조치] 객체를 미리 생성하지 않고 Nullable(?)로 선언만 해둡니다.
  SystemTray? _systemTray;
  AppWindow? _appWindow;

  // 🔥 [수정] 원본 메뉴 리스트를 따로 보관합니다.
  final List<Map<String, dynamic>> _allMenuItems = [
    {'title': '종합 관제 상황판', 'icon': FontAwesomeIcons.chartPie},        // Index 0
    {'title': '장치 관리', 'icon': FontAwesomeIcons.microchip},            // Index 1
    {'title': '인원 관리', 'icon': FontAwesomeIcons.users},                // Index 2
    {'title': '물품 관리', 'icon': FontAwesomeIcons.boxesStacked},         // Index 3
    {'title': '출입 기록', 'icon': FontAwesomeIcons.clockRotateLeft},      // Index 4
    {'title': '공지사항', 'icon': FontAwesomeIcons.bullhorn},              // Index 5
    {'title': '환경 설정', 'icon': FontAwesomeIcons.gears},                // Index 6
  ];

  // 🔥 [추가] 플랫폼을 스스로 감지하여 웹/모바일 환경에서는 '장치 관리' 메뉴를 아예 노출하지 않게 차단합니다.
  List<Map<String, dynamic>> get _menuItems {
    if (kIsWeb || (!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
      return _allMenuItems.where((item) => item['title'] != '장치 관리').toList();
    }
    return _allMenuItems;
  }

  @override
  void initState() {
    super.initState();
    _isKioskMode = widget.initialKioskMode;

    // 웹이 아닐 때만 윈도우 매니저 리스너를 등록합니다.
    if (!kIsWeb) {
      windowManager.addListener(this);
    }
    _initWindowPosition();
    _initSystemTray();
  }

  @override
  void dispose() {
    // 웹이 아닐 때만 리스너를 해제합니다.
    if (!kIsWeb) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  /// ---------------------------------------------------------------------------
  /// [창 초기 위치/크기 보정 함수] (윈도우/맥/리눅스 전용)
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

  /// ---------------------------------------------------------------------------
  /// [시스템 트레이(작업 표시줄 아이콘) 초기화 함수] (윈도우 전용)
  /// ---------------------------------------------------------------------------
  Future<void> _initSystemTray() async {
    // 윈도우 환경임이 확실할 때만 객체를 실제로 생성(메모리 할당)합니다.
    if (!kIsWeb && Platform.isWindows) {
      _systemTray = SystemTray();
      _appWindow = AppWindow();

      await _systemTray!.initSystemTray(
        title: "RFID 통합 관제",
        iconPath: 'assets/app_icon.ico',
      );

      final Menu menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(
            label: '화면 다시 열기 (Restore)',
            onClicked: (dynamic menuItem) async {
              await _appWindow!.show();
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

      await _systemTray!.setContextMenu(menu);

      _systemTray!.registerSystemTrayEventHandler((String eventName) async {
        if (eventName == kSystemTrayEventClick) {
          await _appWindow!.show();
          await windowManager.setFullScreen(true);
        } else if (eventName == kSystemTrayEventRightClick) {
          await _systemTray!.popUpContextMenu();
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

    // 키오스크 모드일 때는 메뉴 네비게이션 없이 뷰어 화면만 꽉 차게 띄웁니다.
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
        // 화면 너비가 800 이하일 경우 모바일/태블릿(세로) 환경으로 판단합니다.
        bool isMobile = constraints.maxWidth <= 800;

        return Scaffold(
          // Scaffold 키를 등록하여 글로벌 Top Bar에서 Drawer를 열 수 있게 연결합니다.
          key: _scaffoldKey,
          backgroundColor: theme.scaffoldBackgroundColor,

          // [반응형 핵심] 모바일 모드일 때만 Drawer(서랍형 메뉴)를 부착합니다.
          drawer: isMobile ? _buildMobileDrawer(theme) : null,

          body: Row(
            children: [
              // PC 화면(isMobile == false)일 때만 좌측에 고정된 사이드바를 보여줍니다.
              if (!isMobile) ...[
                _buildSidebar(_isSidebarExtended, theme, themeProvider),
              ],
              // 우측 본문 영역 (모바일일 경우 100% 꽉 채웁니다)
              Expanded(
                child: Container(
                  color: theme.scaffoldBackgroundColor,
                  child: Column(
                    children: [
                      // 상단 글로벌 Top Bar 렌더링
                      _buildGlobalTopBar(theme, authProvider, isMobile),

                      // 실제 선택된 메뉴의 컨텐츠가 렌더링되는 영역
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
  /// [UI 조각] 안드로이드 폰/태블릿을 위한 Drawer (서랍형 모바일 메뉴)
  /// ---------------------------------------------------------------------------
  Widget _buildMobileDrawer(ThemeData theme) {
    final bool isDarkMode = theme.brightness == Brightness.dark;
    final Color drawerColor = isDarkMode ? const Color(0xFF151D2E) : Colors.white;

    return Drawer(
      backgroundColor: drawerColor,
      child: Column(
        children: [
          // 모바일 서랍장 상단 로고 및 여백 영역
          Container(
            height: 120,
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
            child: Image.asset(
              'assets/images/PLUG4ASSET.png',
              height: 40,
              errorBuilder: (context, error, stackTrace) {
                return Text(
                  "PLUG4",
                  style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    color: theme.colorScheme.primary,
                  ),
                );
              },
            ),
          ),
          // 모바일 메뉴 리스트
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              children: [
                ...List.generate(_menuItems.length, (int index) {
                  final bool isSelected = _selectedIndex == index;
                  return ListTile(
                    leading: FaIcon(
                      _menuItems[index]['icon'] as IconData,
                      color: isSelected ? theme.colorScheme.primary : (isDarkMode ? Colors.white70 : Colors.black87),
                      size: 20,
                    ),
                    title: Text(
                      _menuItems[index]['title'],
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                        color: isSelected ? theme.colorScheme.primary : (isDarkMode ? Colors.white70 : Colors.black87),
                      ),
                    ),
                    selected: isSelected,
                    selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                      });
                      // 메뉴 클릭 후 서랍을 자동으로 닫아줍니다.
                      Navigator.of(context).pop();
                    },
                  );
                }),
                const Divider(height: 30),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.lockOpen, size: 20),
                  title: const Text('키오스크 모드', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _isKioskMode = true;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, size: 22, color: Colors.blueGrey),
                  title: const Text('로그아웃', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w600)),
                  onTap: () {
                    pb.authStore.clear();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [UI 조각] 글로벌 Top Bar (메뉴 타이틀 + 아이콘 & 사용자 프로필 칩)
  /// 🔥 [수정됨] 화면이 좁을 때 글씨가 삐져나오는(Overflow) 현상을 막기 위해
  /// Expanded와 Flexible 위젯을 적용하여 가로 길이를 안전하게 제어합니다.
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
          // 모바일 모드일 때는 맨 좌측에 햄버거(메뉴) 버튼을 표시합니다.
          if (isMobile) ...[
            IconButton(
              icon: Icon(Icons.menu, color: isDarkMode ? Colors.white : Colors.black87, size: 28),
              onPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
            ),
            const SizedBox(width: 8),
          ],

          // 타이틀 아이콘
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

          // 🔥 [에러 조치 1] 타이틀 텍스트가 화면을 넘어가면 말줄임표(...) 처리되도록 Expanded로 감쌉니다.
          Expanded(
            child: Text(
              currentTitle,
              style: TextStyle(
                fontFamily: AppTheme.fontPretendard,
                fontSize: isMobile ? 18 : 22,
                fontWeight: FontWeight.w900,
                color: isDarkMode ? Colors.white : Colors.black87,
                letterSpacing: -0.5,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),

          const SizedBox(width: 8), // Spacer 대신 최소 여유 공간만 줍니다.

          // 우측 상단 사용자 정보 표시
          _buildLoginUserInfo(auth, theme, isMobile),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [UI 조각] 로그인된 사용자 정보를 뱃지 형태로 표시합니다.
  /// ---------------------------------------------------------------------------
  Widget _buildLoginUserInfo(AuthProvider auth, ThemeData theme, bool isMobile) {
    final String userName = auth.currentUser;
    final String role = auth.role;

    final bool isManagerLevel = auth.isAdmin || role.contains('관리자') || role.toLowerCase().contains('admin');

    return Container(
      // 부모 영역이 줄어들면 같이 유연하게 줄어들도록 ConstrainedBox로 최대/최소 크기 제약을 줍니다.
      constraints: BoxConstraints(maxWidth: isMobile ? 120 : 250),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: 8),
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
          // 모바일 화면에서는 공간 확보를 위해 이름 텍스트를 아예 숨기거나 간소화합니다.
          if (!isMobile) ...[
            const SizedBox(width: 10),
            // 🔥 [에러 조치 2] 사용자 이름이 너무 길어질 때를 대비해 Flexible로 방어합니다.
            Flexible(
              child: Text(
                '$userName 님',
                style: TextStyle(
                  fontFamily: AppTheme.fontPretendard,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isManagerLevel ? Colors.indigo : theme.colorScheme.primary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isManagerLevel ? Colors.indigo : theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              role,
              style: const TextStyle(
                fontFamily: AppTheme.fontPretendard,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [UI 조각] PC 전용 고정형 좌측 사이드바 위젯 생성
  /// ---------------------------------------------------------------------------
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

  /// 사이드바 상단 로고 영역 생성 (PC 전용)
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
    // 🔥 [에러 원천 차단] 메뉴가 동적으로 숨겨질 수 있으므로 인덱스 대신 '타이틀명'으로 화면을 분기합니다.
    final String currentTitle = _menuItems[_selectedIndex]['title'];

    switch (currentTitle) {
      case '종합 관제 상황판':
        return DeviceMapPage(baseUrl: _pbBaseUrl);
      case '장치 관리':
        return DevicePage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      case '인원 관리':
        return UserPage(searchQuery: "", filter: '전체', isMobile: isMobile, baseUrl: _pbBaseUrl);
      case '물품 관리':
        return ProductPage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      case '출입 기록':
        return DetectionHistoryPage(isMobile: isMobile, baseUrl: _pbBaseUrl);
      case '공지사항':
        return NoticePage(isMobile: isMobile, baseUrl: _pbBaseUrl);
      case '환경 설정':
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