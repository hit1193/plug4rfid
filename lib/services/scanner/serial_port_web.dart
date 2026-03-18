import 'dart:typed_data';

class AppSerialPort {
  AppSerialPort(String name);

  // 웹에서는 하드웨어 접근이 안 되므로 가짜 리스트를 줍니다.
  static List<String> get availablePorts => ['COM_WEB_가상포트'];

  String get name => "Web_Virtual_Port";
  String? get description => "웹 브라우저 가상 포트";

  bool get isBluetooth => false;
  bool get isOpen => false;
  int get bytesAvailable => 0;

  bool openReadWrite() => false;
  void configure({required int baudRate}) {}
  Uint8List read(int bytes) => Uint8List(0);
  void write(Uint8List data) {}
  void close() {}
  void dispose() {}
}