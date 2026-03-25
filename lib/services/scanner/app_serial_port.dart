// ============================================================================
// [조건부 Export 브릿지]
// C++의 #ifdef 매크로와 완벽히 동일한 역할을 수행하는 라우터 파일입니다.
//
// - 기본적으로는 웹용 가짜 파일(app_serial_port_web.dart)을 내보냅니다.
// - 하지만 현재 컴파일 환경이 dart.library.io (윈도우, 안드로이드 등 네이티브)를
//   지원한다면, 진짜 파일(app_serial_port_pc.dart)로 교체해서 내보냅니다.
//
// 다른 UI 파일들(device_page.dart 등)은 오직 이 파일 하나만 import 하면 됩니다!
// ============================================================================

export 'app_serial_port_web.dart' if (dart.library.io) 'app_serial_port_pc.dart';