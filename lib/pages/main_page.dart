import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:window_manager/window_manager.dart';
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
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // --- 메인 상태 제어 변수 ---
  bool _isKioskMode = false;         // 전체화면 키오스크 모드 활성화 여부
  bool _isSidebarExtended = true;    // 좌측 사이드바의 펼침/접힘 상태
  int _selectedIndex = 0;            // 현재 선택된 메뉴의 인덱스 번호
  final String _pbBaseUrl = "http://127.0.0.1:8090"; // PocketBase 서버 주소

  // 사이드바에 표시될 메뉴 아이템 목록 (향후 DB에서 불러오도록 확장 가능합니다)
  final List<Map<String, dynamic>> _menuItems = [
    {'title': '종합 관제 상황판', 'icon': FontAwesomeIcons.chartPie},
    {'title': '인원 관리', 'icon': FontAwesomeIcons.users},
    {'title': '장치 관리', 'icon': FontAwesomeIcons.microchip},
    {'title': '물품 관리', 'icon': FontAwesomeIcons.boxesStacked},
    {'title': '출입 기록', 'icon': FontAwesomeIcons.clockRotateLeft},
    {'title': '환경 설정', 'icon': FontAwesomeIcons.gears},
  ];

  @override
  Widget build(BuildContext context) {
    // 앱 전체의 테마 상태를 가져옵니다.
    // 여기서 디자인을 통제하므로 하위 위젯들은 기본적으로 이 테마를 따르게 됩니다.
    final themeProvider = context.watch<ThemeProvider>();
    final theme = themeProvider.themeData;

    // 1. 키오스크 모드가 켜진 경우, 상단바/사이드바 없이 전체화면으로 덮어버립니다.
    if (_isKioskMode) {
      return Scaffold(
          body: KioskView(
              onDismiss: () => setState(() => _isKioskMode = false)
          )
      );
    }

    // 2. 일반 모드인 경우, 화면 크기에 따라 반응형(Responsive) 레이아웃을 제공합니다.
    return LayoutBuilder(
      builder: (context, constraints) {
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
          // [로고 및 접기 버튼 헤더] - 로고 크기를 줄이고 위로 바짝 올렸습니다.
          _buildSidebarHeader(extended, theme),

          // 로고와 메뉴 사이의 간격을 줄여 메뉴들이 위로 끌어올려지도록 했습니다.
          const SizedBox(height: 10),

          // 메뉴 리스트 영역 (ListView를 사용하여 메뉴가 많아져도 스크롤이 가능합니다)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                // 1. 주요 메뉴 목록을 반복문으로 생성합니다.
                ...List.generate(_menuItems.length, (index) {
                  return _buildMenuItem(
                    title: _menuItems[index]['title'],
                    icon: _menuItems[index]['icon'],
                    extended: extended,
                    isSelected: _selectedIndex == index,
                    theme: theme,
                    // 메뉴 클릭 시 인덱스를 변경하여 우측 본문 화면을 전환합니다.
                    onTap: () => setState(() => _selectedIndex = index),
                  );
                }),

                // 구분선을 그어 주요 기능과 시스템 기능(키오스크, 로그아웃 등)을 나눕니다.
                const SizedBox(height: 20),
                Divider(color: theme.dividerTheme.color),
                const SizedBox(height: 20),

                // 테마 선택 기능은 삭제하고, 추후 '환경 설정' 메뉴에서 개발하시도록 비워두었습니다.

                // 2. 부가 기능 메뉴 (키오스크 모드, 로그아웃, 시스템 종료)
                _buildMenuItem(
                  title: "키오스크 모드",
                  icon: FontAwesomeIcons.lockOpen,
                  extended: extended,
                  isSelected: false,
                  theme: theme,
                  onTap: () => setState(() => _isKioskMode = true),
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

                // 윈도우 데스크탑 환경일 경우에만 '종료하기' 버튼을 노출합니다.
                if (!kIsWeb && Platform.isWindows) ...[
                  const SizedBox(height: 4),
                  _buildMenuItem(
                    title: "종료하기",
                    icon: Icons.power_settings_new_rounded,
                    extended: extended,
                    isSelected: false,
                    color: AppTheme.danger,
                    theme: theme,
                    // 윈도우 매니저를 통해 앱을 완전히 종료합니다.
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

  /// ---------------------------------------------------------------------------
  /// [사이드바 상단 헤더 (로고 및 메뉴 접기 버튼)]
  /// 사장님의 요청에 따라 로고 크기를 줄이고, 위쪽 공백을 대폭 축소하였습니다.
  /// 이로 인해 하단의 메뉴 항목들이 자연스럽게 위쪽으로 끌어올려집니다.
  /// ---------------------------------------------------------------------------
  Widget _buildSidebarHeader(bool extended, ThemeData theme) {
    final bool isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      // [수정] 상단 여백(top)을 기존 60에서 24로 줄여서 전체적으로 위로 끌어올렸습니다.
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
                // [수정] maxHeight를 80으로 대폭 줄여서 미니멀하고 깔끔하게 변경했습니다.
                maxHeight: extended ? 80 : 40,
                maxWidth: extended ? 180 : 50,
              ),
              child: Image.asset(
                'assets/images/PLUG4ASSET.png',
                fit: BoxFit.contain,
                // 이미지를 찾지 못할 경우의 안전장치 (텍스트로 대체 표시)
                errorBuilder: (context, error, stackTrace) {
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
            // [수정] 로고 크기와 여백이 줄어든 것에 맞추어 토글 버튼의 좌표도 자연스럽게 조정했습니다.
            top: extended ? -16 : -10,
            right: extended ? -12 : null,
            left: extended ? null : -12,
            child: Material(
              color: Colors.transparent, // 배경 투명 처리로 깔끔하게 배치
              child: IconButton(
                // 버튼을 누르면 사이드바 확장 상태 변수를 토글합니다.
                onPressed: () => setState(() => _isSidebarExtended = !_isSidebarExtended),
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
      // [인원 관리] 화면
        return UserPage(searchQuery: "", filter: '전체', isMobile: isMobile, baseUrl: _pbBaseUrl);
      case 2:
      // [장치 관리] 화면
        return DevicePage(searchQuery: "", isMobile: isMobile, baseUrl: _pbBaseUrl);
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