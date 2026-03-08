import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart'; // 시스템 트레이 패키지 임포트
import 'package:provider/provider.dart';
import 'dart:io';

// 전역 상태 및 통신 모듈 임포트
import '../core/pocketbase_client.dart';
import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';

// 각 기능별 하위 페이지 위젯 임포트
import 'user_page.dart';
import 'product_page.dart';
import 'device_page.dart';
import 'device_map_page.dart';
import 'kiosk_view.dart';

/// ---------------------------------------------------------------------------
/// [RFID 솔루션 통합 메인 레이아웃 페이지 (MainPage)]
/// 좌측 사이드바(메뉴/로고/설정)와 우측 본문(컨텐츠) 영역을 동적으로 관리합니다.
/// 미니멀리즘 디자인 철학에 맞추어 사이드바를 간결하고 직관적으로 구성했습니다.
/// ---------------------------------------------------------------------------
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() {
    return _MainPageState();
  }
}

// WindowListener를 믹스인(with)하여 윈도우 창의 상태 변화(최소화, 복원 등)를 감지합니다.
class _MainPageState extends State<MainPage> with WindowListener {
  // --- 메인 상태 제어 변수 ---
  bool _isKioskMode = false;         // 전체화면 키오스크 모드 활성화 여부
  bool _isSidebarExtended = true;    // 좌측 사이드바의 펼침/접힘 상태
  int _selectedIndex = 0;            // 현재 선택된 메뉴의 인덱스 번호
  final String _pbBaseUrl = "http://127.0.0.1:8090"; // PocketBase 서버 주소

  // 시스템 트레이 제어용 객체 선언
  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();

  // -------------------------------------------------------------------------
  // [메뉴 순서 변경 적용]
  // '관제 상황판 -> 장치 관리 -> 인원 관리 -> 물품 관리' 순서로
  // 사이드바에 표시될 메뉴 아이템 목록이 배치되어 있습니다.
  // -------------------------------------------------------------------------
  final List<Map<String, dynamic>> _menuItems = [
    {'title': '종합 관제 상황판', 'icon': FontAwesomeIcons.chartPie},        // 인덱스 0
    {'title': '장치 관리', 'icon': FontAwesomeIcons.microchip},            // 인덱스 1
    {'title': '인원 관리', 'icon': FontAwesomeIcons.users},                // 인덱스 2
    {'title': '물품 관리', 'icon': FontAwesomeIcons.boxesStacked},         // 인덱스 3
    {'title': '출입 기록', 'icon': FontAwesomeIcons.clockRotateLeft},      // 인덱스 4
    {'title': '환경 설정', 'icon': FontAwesomeIcons.gears},                // 인덱스 5
  ];

  @override
  void initState() {
    super.initState();
    // 플러터 윈도우 매니저에 현재 위젯을 리스너로 등록하여 창 이벤트를 수신합니다.
    windowManager.addListener(this);
    // 비동기 함수로 시스템 트레이를 초기화합니다.
    _initSystemTray();
  }

  @override
  void dispose() {
    // 메모리 누수를 방지하기 위해 위젯 종료 시 리스너를 반드시 해제합니다.
    windowManager.removeListener(this);
    super.dispose();
  }

  /// ---------------------------------------------------------------------------
  /// [시스템 트레이 (System Tray) 초기화 함수]
  /// 윈도우 우측 하단 시계 옆에 숨겨지는 트레이 아이콘과 메뉴를 구성합니다.
  /// ---------------------------------------------------------------------------
  Future<void> _initSystemTray() async {
    if (!kIsWeb && Platform.isWindows) {
      // 1. 트레이 아이콘 설정
      // [주의] 윈도우 환경에서는 반드시 .ico 확장자 파일이 필요합니다.
      // 실제 프로젝트의 assets 폴더에 app_icon.ico 파일을 생성/추가해 주셔야 합니다.
      await _systemTray.initSystemTray(
        title: "RFID 통합 관제",
        iconPath: 'assets/app_icon.ico',
      );

      // 2. 트레이 아이콘 우클릭 시 나타날 컨텍스트 메뉴(Pop-up Menu) 구성
      final Menu menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(
            label: '화면 다시 열기 (Restore)',
            // [오류 해결] MenuItem 클래스를 찾지 못하는 문제를 해결하기 위해 타입을 dynamic으로 지정합니다.
            onClicked: (dynamic menuItem) async {
              // 앱 창을 화면에 다시 띄우고 강제로 전체화면을 덮어씌웁니다.
              await _appWindow.show();
              await windowManager.setFullScreen(true);
            }
        ),
        MenuSeparator(), // 메뉴 구분선
        MenuItemLabel(
            label: '프로그램 완전 종료',
            // [오류 해결] MenuItem 클래스를 찾지 못하는 문제를 해결하기 위해 타입을 dynamic으로 지정합니다.
            onClicked: (dynamic menuItem) async {
              await windowManager.close();
            }
        ),
      ]);

      // 구성한 메뉴를 시스템 트레이에 연결합니다.
      await _systemTray.setContextMenu(menu);

      // 3. 트레이 아이콘 마우스 클릭 이벤트 감지 루틴
      _systemTray.registerSystemTrayEventHandler((String eventName) async {
        if (eventName == kSystemTrayEventClick) {
          // 좌클릭 시: 창을 다시 보여주고 전체화면 복구
          await _appWindow.show();
          await windowManager.setFullScreen(true);
        } else if (eventName == kSystemTrayEventRightClick) {
          // 우클릭 시: 컨텍스트 메뉴 띄우기
          await _systemTray.popUpContextMenu();
        }
      });
    }
  }

  /// ---------------------------------------------------------------------------
  /// [윈도우 창 이벤트 감지 - OnRestore]
  /// 혹시라도 다른 경로를 통해 창이 다시 띄워졌을 때 전체화면을 보장하는 방어 코드입니다.
  /// ---------------------------------------------------------------------------
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
    // 앱 전체의 테마 상태를 가져옵니다.
    // 여기서 디자인을 통제하므로 하위 위젯들은 기본적으로 이 테마를 따르게 됩니다.
    final ThemeProvider themeProvider = context.watch<ThemeProvider>();
    final ThemeData theme = themeProvider.themeData;

    // 1. 키오스크 모드가 켜진 경우, 상단바/사이드바 없이 전체화면으로 덮어버립니다.
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

    // 2. 일반 모드인 경우, 화면 크기에 따라 반응형(Responsive) 레이아웃을 제공합니다.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 화면 너비가 650픽셀 이하일 경우 모바일 환경으로 간주합니다.
        bool isMobile = constraints.maxWidth <= 650;

        return Scaffold(
          // 테마에 정의된 기본 배경색을 적용합니다 (순정 위젯 활용)
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Row(
            children: [
              // 모바일 크기가 아닐 때만 좌측 사이드바를 표시합니다.
              if (!isMobile) ...[
                _buildSidebar(_isSidebarExtended, theme, themeProvider),
              ],
              // 우측 실제 데이터가 표시되는 메인 본문 영역입니다. (Expanded로 남은 공간 모두 차지)
              Expanded(
                child: Container(
                  color: theme.scaffoldBackgroundColor,
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              // 사이드바와 본문 사이를 구분하는 얇은 세로선입니다.
                              left: BorderSide(
                                color: theme.dividerTheme.color ?? Colors.black12,
                                width: 1.0,
                              ),
                            ),
                          ),
                          // 선택된 메뉴 인덱스에 따라 우측 화면을 동적으로 바꿔줍니다.
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
  /// [좌측 사이드바 위젯 생성기]
  /// 로고, 메뉴 리스트, 로그아웃, 종료 버튼 등을 포함하는 네비게이션 영역입니다.
  /// ---------------------------------------------------------------------------
  Widget _buildSidebar(bool extended, ThemeData theme, ThemeProvider themeProvider) {
    final bool isDarkMode = theme.brightness == Brightness.dark;

    // 사이드바 배경색을 메인 테마 색상과 은은하게 섞어 고급스러움을 더합니다.
    final Color deeperSidebarColor = isDarkMode
        ? const Color(0xFF151D2E)
        : Color.alphaBlend(theme.colorScheme.primary.withValues(alpha: 0.06), theme.scaffoldBackgroundColor);

    return AnimatedContainer(
      // 사이드바가 접히고 펴질 때 부드러운 애니메이션 효과를 줍니다.
      duration: const Duration(milliseconds: 250),
      width: extended ? 280 : 90,
      curve: Curves.easeInOut,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: deeperSidebarColor,
      ),
      child: Column(
        children: [
          // [로고 및 접기 버튼 헤더]
          _buildSidebarHeader(extended, theme),

          // 로고와 메뉴 사이의 간격을 줄여 메뉴들이 위로 끌어올려지도록 했습니다.
          const SizedBox(height: 10),

          // 메뉴 리스트 영역 (ListView를 사용하여 메뉴가 많아져도 스크롤이 가능합니다)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                // 1. 주요 메뉴 목록을 반복문으로 생성합니다.
                ...List.generate(_menuItems.length, (int index) {
                  return _buildMenuItem(
                    title: _menuItems[index]['title'],
                    icon: _menuItems[index]['icon'],
                    extended: extended,
                    isSelected: _selectedIndex == index,
                    theme: theme,
                    // 메뉴 클릭 시 인덱스를 변경하여 우측 본문 화면을 전환합니다.
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                  );
                }),

                // 구분선을 그어 주요 기능과 시스템 기능(키오스크, 로그아웃 등)을 나눕니다.
                const SizedBox(height: 20),
                Divider(color: theme.dividerTheme.color),
                const SizedBox(height: 20),

                // 2. 부가 기능 메뉴 (키오스크 모드, 로그아웃, 시스템 제어)
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
                    // PocketBase 인증 정보를 초기화하여 로그인 화면으로 돌아가게 합니다.
                    pb.authStore.clear();
                  },
                ),

                // 윈도우 데스크탑 환경일 경우에만 시스템 제어 버튼들을 노출합니다.
                if (!kIsWeb && Platform.isWindows) ...[
                  const SizedBox(height: 4),
                  // 시스템 트레이로 완전히 숨깁니다.
                  _buildMenuItem(
                    title: "트레이로 숨기기",
                    icon: Icons.visibility_off,
                    extended: extended,
                    isSelected: false,
                    color: Colors.blueGrey,
                    theme: theme,
                    onTap: () async {
                      // 윈도우 매니저의 hide() 함수를 호출하여 화면 및 작업표시줄에서 앱을 완벽히 지웁니다.
                      // (트레이 아이콘은 _initSystemTray()를 통해 우측 하단에 남아있게 됩니다)
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
                    // 윈도우 매니저를 통해 앱을 완전히 종료합니다.
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

  /// ---------------------------------------------------------------------------
  /// [사이드바 상단 헤더 (로고 및 메뉴 접기 버튼)]
  /// ---------------------------------------------------------------------------
  Widget _buildSidebarHeader(bool extended, ThemeData theme) {
    final bool isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      // 상단 여백(top)을 24로 줄여서 전체적으로 위로 끌어올렸습니다.
      padding: EdgeInsets.fromLTRB(14, extended ? 24 : 20, 14, 10),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 1. 로고 이미지 영역
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              constraints: BoxConstraints(
                maxHeight: extended ? 80 : 40,
                maxWidth: extended ? 180 : 50,
              ),
              child: Image.asset(
                'assets/images/PLUG4ASSET.png',
                fit: BoxFit.contain,
                // 이미지를 찾지 못할 경우의 안전장치 (텍스트로 대체 표시)
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

          // 2. 메뉴 토글 아이콘 (접기/펴기 버튼)
          Positioned(
            top: extended ? -16 : -10,
            right: extended ? -12 : null,
            left: extended ? null : -12,
            child: Material(
              color: Colors.transparent, // 배경 투명 처리로 깔끔하게 배치
              child: IconButton(
                // 버튼을 누르면 사이드바 확장 상태 변수를 토글합니다.
                onPressed: () {
                  setState(() {
                    _isSidebarExtended = !_isSidebarExtended;
                  });
                },
                tooltip: extended ? "사이드바 접기" : "사이드바 펴기",
                icon: Icon(
                  extended ? Icons.menu_open_rounded : Icons.menu_rounded,
                  color: isDarkMode ? Colors.white70 : theme.colorScheme.primary.withValues(alpha: 0.8),
                  size: 28, // 로고 크기에 맞춰 아이콘 크기도 약간 작고 정갈하게 변경
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

  /// ---------------------------------------------------------------------------
  /// [사이드바 개별 메뉴 버튼 위젯]
  /// 미니멀리즘 디자인을 해치지 않도록 깔끔한 테두리와 호버(Hover) 효과를 제공합니다.
  /// ---------------------------------------------------------------------------
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

    // 선택된 상태일 때는 테마의 메인 색상(Primary)을 사용합니다.
    final Color activeColor = theme.colorScheme.primary;
    // 선택되지 않았을 때는 연한 회색(또는 전달받은 커스텀 색상)을 사용합니다.
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
            // 선택된 항목만 배경색을 채웁니다.
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            // 미니멀리즘 스타일의 얇고 세련된 테두리를 그립니다.
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
                  // 아이콘 표시 영역 (기본 Icon 또는 FontAwesome 아이콘을 모두 지원하도록 처리)
                  SizedBox(
                    width: 24,
                    child: Center(
                      child: icon is IconData
                          ? Icon(icon, size: 20, color: isSelected ? Colors.white : inactiveColor)
                          : FaIcon(icon as IconData, size: 18, color: isSelected ? Colors.white : inactiveColor),
                    ),
                  ),
                  // 사이드바가 확장된 상태일 때만 메뉴 텍스트를 표시합니다.
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
  /// [우측 컨텐츠 라우팅 엔진]
  /// 왼쪽 사이드바에서 선택된 인덱스(_selectedIndex)에 따라 우측 화면을 교체합니다.
  /// ---------------------------------------------------------------------------
  Widget _buildBody(bool isMobile) {
    switch (_selectedIndex) {
      case 0:
      // [종합 관제 상황판] 대시보드 화면
        return DeviceMapPage(baseUrl: _pbBaseUrl);
      case 1:
      // [장치 관리] 화면
        return DevicePage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 2:
      // [인원 관리] 화면
        return UserPage(searchQuery: "", filter: '전체', isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 3:
      // [물품 관리] 화면
        return ProductPage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 5:
      // [환경 설정] 화면 (추후 개발될 테마 선택 기능 등을 이곳에 배치하시면 됩니다)
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
      // 아직 연결되지 않은 메뉴를 눌렀을 때의 기본 화면입니다.
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