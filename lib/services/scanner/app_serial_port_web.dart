import 'dart:typed_data';

// ============================================================================
// [웹 전용 시리얼 포트 껍데기(Stub)]
// 크롬 컴파일 시 dart:ffi 패키지 호출로 인한 컴파일 에러를 방지하기 위해,
// PC용(app_serial_port_pc.dart)과 완벽하게 동일한 구조(인터페이스)만 맞춰둔 가상 클래스입니다.
// ============================================================================
class AppSerialPort {
  AppSerialPort(String name);

  // 웹에서는 하드웨어 접근이 원천 차단되므로 임의의 가상 포트를 반환합니다.
  static List<String> get availablePorts {
    return ['COM_WEB_가상포트'];
  }

  String get name {
    return "Web_Virtual_Port";
  }

  String? get description {
    return "웹 브라우저 가상 포트";
  }

  bool get isBluetooth {
    return false;
  }

  bool get isOpen {
    return false;
  }

  int get bytesAvailable {
    return 0;
  }

  bool openReadWrite() {
    return false;
  }

  // 형태만 맞춰두고 실제 기능은 없습니다.
  void configure({required int baudRate}) {
    // 아무 동작 안 함
  }

  Uint8List read(int bytes) {
    return Uint8List(0); // 빈 데이터 반환
  }

  void write(Uint8List data) {
    // 아무 동작 안 함
  }

  void close() {
    // 아무 동작 안 함
  }

  void dispose() {
    // 아무 동작 안 함
  }
}