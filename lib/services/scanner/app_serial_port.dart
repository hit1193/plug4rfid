import 'dart:typed_data';

// -----------------------------------------------------------------------------
// [공통 인터페이스 껍데기 (Stub)]
// C/C++의 헤더 파일(.h)과 같은 역할을 합니다.
// 플러터 컴파일러가 타입과 메서드 이름만을 미리 참조할 수 있게 해주는 명세서이며,
// 실제 동작은 이 파일이 아니라 분기된 하위 파일(desktop 또는 web)에서 수행됩니다.
// -----------------------------------------------------------------------------
class AppSerialPort {
  // PC에 연결된 COM 포트 목록을 가져오는 정적(Static) 메서드
  static List<String> get availablePorts => throw UnsupportedError('Stub');

  // 포트의 기본 정보 속성들
  String get name => throw UnsupportedError('Stub');
  String? get description => throw UnsupportedError('Stub');
  bool get isBluetooth => throw UnsupportedError('Stub');
  bool get isOpen => throw UnsupportedError('Stub');
  int get bytesAvailable => throw UnsupportedError('Stub');

  // 생성자
  AppSerialPort(String name);

  // 하드웨어 포트 제어 메서드들
  bool openReadWrite() => throw UnsupportedError('Stub');
  void configure({required int baudRate}) => throw UnsupportedError('Stub');
  Uint8List read(int bytes) => throw UnsupportedError('Stub');
  void write(Uint8List data) => throw UnsupportedError('Stub');
  void close() => throw UnsupportedError('Stub');
  void dispose() => throw UnsupportedError('Stub');
}