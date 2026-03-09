import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../core/pocketbase_client.dart';
import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';

// 연결할 각 하위 페이지들을 임포트합니다.
import 'user_page.dart';
import 'product_page.dart';
import 'device_page.dart';
import 'device_map_page.dart';
import 'kiosk_view.dart';
// DB에 보관된 출입 기록을 조회하는 페이지를 임포트합니다.
import 'detection_history_page.dart';
// [신규 추가] 새롭게 제작한 공지사항 페이지를 임포트합니다.
import 'notice_page.dart';

/// ---------------------------------------------------------------------------
/// [RFID 솔루션 통합 메인 레이아웃 페이지 (MainPage)]
/// 좌측 사이드바와 우측 본문 영역을 동적으로 관리하며 메뉴 네비게이션을 담당합니다.
///
/// [업데이트 내역]
/// 1. 출입 기록 메뉴(인덱스 4)에 DetectionHistoryPage 라우팅 연결 완료
/// 2. 사이드바 상단 로고 이미지 안쪽 여백 제거 및 BoxFit.cover 적용 유지
/// 3. [신규] 사이드바 메뉴에 '공지사항' 추가 및 라우팅 연결 완료 (인덱스 5)
/// ---------------------------------------------------------------------------
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() {
    return _MainPageState();
  }
}

class _MainPageState extends State<MainPage> with WindowListener {
  bool _isKioskMode = false;
  bool _isSidebarExtended = true;
  int _selectedIndex = 0;
  final String _pbBaseUrl = "http://127.0.0.1:8090";

  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();

  // 사이드바에 표시될 메뉴 리스트입니다.
  // 직관적인 관리를 위해 배열 형태로 메뉴 데이터(제목, 아이콘)를 보관합니다.
  final List<Map<String, dynamic>> _menuItems = [
    {'title': '종합 관제 상황판', 'icon': FontAwesomeIcons.chartPie},        // Index 0
    {'title': '장치 관리', 'icon': FontAwesomeIcons.microchip},            // Index 1
    {'title': '인원 관리', 'icon': FontAwesomeIcons.users},                // Index 2
    {'title': '물품 관리', 'icon': FontAwesomeIcons.boxesStacked},         // Index 3
    {'title': '출입 기록', 'icon': FontAwesomeIcons.clockRotateLeft},      // Index 4
    // [신규 추가] 공지사항 메뉴를 5번에 배치하고 직관적인 확성기 아이콘을 사용합니다.
    {'title': '공지사항', 'icon': FontAwesomeIcons.bullhorn},              // Index 5
    // 환경 설정은 인덱스 6으로 한 칸 밀려납니다.
    {'title': '환경 설정', 'icon': FontAwesomeIcons.gears},                // Index 6
  ];

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initSystemTray();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// 시스템 트레이(작업 표시줄 아이콘) 초기화 함수 (Windows 전용)
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
    // 앱 전체의 테마 상태를 Provider로부터 가져옵니다.
    final ThemeProvider themeProvider = context.watch<ThemeProvider>();
    final ThemeData theme = themeProvider.themeData;

    // 키오스크 모드가 활성화되면 사이드바 등을 모두 가리고 전체 화면으로 KioskView를 띄웁니다.
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
        // 화면 가로폭이 650 픽셀 이하이면 모바일 모드로 간주합니다. (반응형 대응)
        bool isMobile = constraints.maxWidth <= 650;

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Row(
            children: [
              // 모바일 환경이 아닐 때만 좌측 사이드바를 노출합니다.
              if (!isMobile) ...[
                _buildSidebar(_isSidebarExtended, theme, themeProvider),
              ],
              // 우측 본문(Body) 영역
              Expanded(
                child: Container(
                  color: theme.scaffoldBackgroundColor,
                  child: Column(
                    children: [
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
                          // 선택된 메뉴 인덱스에 따라 알맞은 화면을 렌더링합니다.
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

  /// 좌측 사이드바 위젯 생성
  Widget _buildSidebar(bool extended, ThemeData theme, ThemeProvider themeProvider) {
    final bool isDarkMode = theme.brightness == Brightness.dark;
    // 사이드바 배경색을 메인 배경과 약간 다르게 주어 깊이감을 형성합니다.
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
                // _menuItems 배열에 등록된 항목 수만큼 메뉴 버튼을 생성합니다.
                ...List.generate(_menuItems.length, (int index) {
                  return _buildMenuItem(
                    title: _menuItems[index]['title'],
                    icon: _menuItems[index]['icon'],
                    extended: extended,
                    isSelected: _selectedIndex == index,
                    theme: theme,
                    onTap: () {
                      setState(() {
                        // 메뉴를 클릭하면 선택된 인덱스를 업데이트하여 우측 본문 화면을 바꿉니다.
                        _selectedIndex = index;
                      });
                    },
                  );
                }),
                const SizedBox(height: 20),
                Divider(color: theme.dividerTheme.color),
                const SizedBox(height: 20),

                // 시스템 제어 전용 메뉴들 (아래쪽에 고정되는 성격의 메뉴들입니다)
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
                // 웹이 아니고 Windows 환경일 때만 데스크톱 전용 제어 메뉴를 보여줍니다.
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
              // 로고 이미지 안쪽 패딩 없이 꽉 채워 미니멀리즘 디자인을 강조합니다.
              padding: EdgeInsets.zero,
              child: Image.asset(
                'assets/images/PLUG4ASSET.png',
                fit: BoxFit.cover,
                errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                  // 이미지 로드 실패 시 글자로 대체합니다.
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

          // 사이드바 접기/펴기 토글 버튼입니다.
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
                  // 사이드바가 열려있을 때만 글자를 보여줍니다.
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
  /// 이 부분이 앱의 핵심 네비게이션 역할을 합니다.
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

    // [신규 연결] 인덱스 5번 클릭 시 제작 완료된 공지사항 페이지(NoticePage)를 화면에 그립니다.
    // 다른 페이지와 동일하게 isMobile과 baseUrl 파라미터를 넘겨주어 일관성을 유지합니다.
      case 5:
        return NoticePage(isMobile: isMobile, baseUrl: _pbBaseUrl);

    // 기존 인덱스 5번이었던 환경 설정이 6번으로 밀려났습니다.
      case 6:
        return const Center(
            child: Text(
                "환경 설정 기능은 현재 개발 진행 중입니다.\n(이곳에 테마 선택 등의 옵션을 추가할 예정입니다)",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.fontPretendard,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                )
            )
        );
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