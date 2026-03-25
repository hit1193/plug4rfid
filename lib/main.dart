import 'package:flutter/material.dart';
// 🔥 [에러 수정 완료] kIsWeb 상수를 사용하기 위해 foundation.dart를 다시 추가합니다.
// (이전 경고는 ai_search_helper.dart 쪽이었습니다!)
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart'; // [신규 추가] 로컬 설정값 로드용
import 'dart:async';
// 🚫 [주의] dart:io는 웹 컴파일 에러의 주범이므로 삭제했습니다!

// [수정] API 통신 서비스 임포트 경로 명확화
// 에러 방지를 위해 'lib/services/' 폴더를 생성하고 그 안에 api_service.dart 파일을 넣어주세요.
import 'services/api_service.dart';

// 테마 및 페이지 설정 임포트
import 'pages/login_page.dart';
import 'pages/main_page.dart';
import 'theme/app_theme.dart';

// 상태 관리를 위한 프로바이더 임포트
import 'providers/user_provider.dart';
import 'providers/product_provider.dart';
import 'providers/device_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart'; // 🔥 [추가] 로그인 에러 해결을 위해 AuthProvider를 임포트합니다.

// 전역 포켓베이스 클라이언트 임포트
import 'core/pocketbase_client.dart';

/// ---------------------------------------------------------------------------
/// [전역 API 서비스 인스턴스 생성]
/// 앱 전역에서 사용할 수 있도록 선언하며, main() 함수에서 로컬 설정값으로 초기화됩니다.
/// ---------------------------------------------------------------------------
final RfidApiService globalApiService = RfidApiService(
  receiveBaseUrl: '',
  sendBaseUrl: '',
);

/// ---------------------------------------------------------------------------
/// [애플리케이션 메인 진입점]
/// 플러터 데스크탑 환경에서 작업표시줄을 완벽히 덮는
/// 키오스크 스타일의 안정적인 전체화면(Full-Screen)을 구현합니다.
/// ---------------------------------------------------------------------------
void main() async {
  // 플러터 프레임워크가 렌더링 엔진과 완전히 연결되도록 보장합니다. (비동기 초기화 시 필수)
  WidgetsFlutterBinding.ensureInitialized();

  // [핵심 추가 1] 환경설정(SettingsPage)에서 저장한 API 주소 및 회사코드를 불러옵니다.
  await globalApiService.loadSettingsFromLocal();

  // [핵심 추가 2] 키오스크 모드로 시작할지 여부를 로컬 저장소에서 읽어옵니다.
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final bool isKioskDefault = prefs.getBool('pref_kiosk_default') ?? false;

  // 🔥 [웹 호환성 조치] Platform.isWindows 대신 defaultTargetPlatform을 사용합니다.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    // 1. 윈도우 매니저 서비스를 초기화합니다.
    await windowManager.ensureInitialized();

    // 🔥 [우하단 치우침 완벽 해결 1]
    // center: true 옵션을 제거했습니다!
    // 전체화면 상태와 중앙 정렬(center) 로직이 충돌하면,
    // 윈도우 OS가 전체화면의 '좌측 상단 꼭지점'을 모니터의 '정중앙'에 맞춰버려서 우하단으로 처박히는 현상이 발생합니다.
    WindowOptions windowOptions = const WindowOptions(
      // 전체화면이 풀렸을 때(예: 다이얼로그 팝업 등)를 대비한 기본 해상도
      size: Size(1440, 760),
      titleBarStyle: TitleBarStyle.hidden, // 기본 타이틀바(최소화/최대화/닫기)를 숨깁니다.
    );

    // 3. 윈도우 창이 화면에 렌더링될 준비가 완료되었을 때 실행되는 안정적인 콜백입니다.
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 🔥 [우하단 치우침 완벽 해결 2]
      // Future.delayed 같은 인위적인 딜레이 꼼수를 완전히 제거했습니다.
      // 창이 사용자 눈에 보이지 않는 백그라운드 상태에서 전체화면을 먼저 꽉 채우고,
      // 그 다음 화면에 나타나게(show) 하면 마우스를 따라가거나 화면 밖으로 밀리는 현상 없이 단번에 자연스럽게 활성화됩니다.
      await windowManager.setFullScreen(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // 기존에는 ThemeProvider 단일 항목만 주입했지만, MultiProvider를 사용하여
  // 앱 전체에서 사용할 ThemeProvider와 AuthProvider를 동시에 메모리에 올립니다.
  // 이 부분이 수정되어야 로그인 페이지에서 프로바이더 참조 오류가 사라집니다.
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()), // 기존 테마 관리 모듈
        ChangeNotifierProvider(create: (_) => AuthProvider()),  // 새로 추가된 인증(로그인) 관리 모듈
      ],
      // 읽어온 키오스크 설정값을 최상위 위젯으로 넘겨줍니다.
      child: MyApp(initialKioskMode: isKioskDefault),
    ),
  );
}

/// ---------------------------------------------------------------------------
/// [MyApp: 최상위 앱 위젯]
/// 앱의 전반적인 디자인 테마와 라우팅의 기초를 담당합니다.
/// ---------------------------------------------------------------------------
class MyApp extends StatelessWidget {
  // 진입점에서 받아온 키오스크 설정 변수
  final bool initialKioskMode;

  const MyApp({
    super.key,
    required this.initialKioskMode,
  });

  @override
  Widget build(BuildContext context) {
    // ThemeProvider에서 현재 테마 상태를 실시간으로 구독(watch)합니다.
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      // 화면 우측 상단의 'DEBUG' 리본 띠를 숨겨 깔끔하게 만듭니다.
      debugShowCheckedModeBanner: false,
      // 앱의 시스템상 제목을 설정합니다. (작업 관리자 등에 표시됨)
      title: 'RFID FA Solution',
      // 프로바이더에서 전달받은 테마(AppTheme)를 앱 전체에 적용하여 디자인을 중앙 통제합니다.
      theme: themeProvider.themeData,
      // 다크모드/라이트모드 중 기본값을 라이트 모드로 강제 고정합니다.
      themeMode: ThemeMode.light,
      // 앱 실행 시 가장 먼저 보여질 화면을 인증 게이트(AuthGate)로 지정하며 설정값을 넘깁니다.
      home: AuthGate(initialKioskMode: initialKioskMode),
    );
  }
}

/// ---------------------------------------------------------------------------
/// [인증 라우터 게이트 (AuthGate)]
/// 사용자의 로그인 상태를 실시간으로 감지하여,
/// 로그인된 사용자는 메인 화면으로, 미인증 사용자는 로그인 화면으로 분기처리합니다.
/// ---------------------------------------------------------------------------
class AuthGate extends StatefulWidget {
  // 하위 위젯으로 넘겨주기 위한 키오스크 설정 변수
  final bool initialKioskMode;

  const AuthGate({
    super.key,
    required this.initialKioskMode,
  });

  @override
  State<AuthGate> createState() {
    return _AuthGateState();
  }
}

class _AuthGateState extends State<AuthGate> {
  // 포켓베이스(PocketBase)의 인증 스토어를 확인하여 현재 로그인 여부를 저장하는 변수입니다.
  bool _isAuthenticated = pb.authStore.isValid;

  // 로그인 상태 변경 이벤트를 구독하기 위한 스트림 변수입니다.
  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();

    // [안전장치] 첫 화면이 위젯 트리에 완전히 그려진 직후(PostFrame) 실행됩니다.
    // 혹시라도 앱 구동 중 다른 프로그램의 간섭으로 인해 전체화면이 풀렸을 경우를 대비합니다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 🔥 [웹 호환성 조치] Platform.isWindows 대신 defaultTargetPlatform을 사용합니다.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        bool isFull = await windowManager.isFullScreen();
        if (!isFull) {
          // 화면이 그려진 후 다시 한번 강제로 전체화면을 시도합니다.
          await windowManager.setFullScreen(true);
        }
      }
    });

    // 포켓베이스의 로그인 상태가 변할 때(예: 로그인 성공, 로그아웃 등)마다 화면을 즉시 갱신합니다.
    _authSubscription = pb.authStore.onChange.listen((event) {
      if (mounted) {
        setState(() {
          _isAuthenticated = pb.authStore.isValid;
        });
      }
    });
  }

  @override
  void dispose() {
    // 위젯이 메모리에서 해제될 때 메모리 누수를 방지하기 위해 스트림 구독을 취소합니다.
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 인증이 완료된 사용자일 경우, 메인 서비스 로직에 필요한 상태 프로바이더들을 묶어서 제공합니다.
    if (_isAuthenticated) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => ProductProvider()),
          ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ],
        // 모든 프로바이더가 준비된 상태로 메인 페이지를 열면서 키오스크 설정값을 전달합니다.
        child: MainPage(initialKioskMode: widget.initialKioskMode),
      );
    }

    // 인증되지 않은 사용자(또는 첫 접속자)일 경우 로그인 페이지를 보여줍니다.
    return const LoginPage();
  }
}