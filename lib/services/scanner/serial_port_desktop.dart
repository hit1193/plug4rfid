// serial_port_desktop.dart
import 'package:libserialport/libserialport.dart'; // 데스크탑에서만 임포트합니다.
import 'serial_port_stub.dart';

class RfidScannerServiceDesktop implements RfidScannerService {
  SerialPort? _serialPort;

  @override
  Future<void> connect(String portName) async {
    // 윈도우용 실제 시리얼 포트 연결 로직을 작성합니다.
    _serialPort = SerialPort(portName);
    _serialPort!.openReadWrite();
  }

  @override
  Future<String> readData() async {
    // 실제 장비에서 데이터를 읽어오는 로직입니다.
    return "RFID_DATA_12345";
  }
}

// 데스크탑 환경일 경우 이 클래스를 반환합니다.
RfidScannerService getScannerService() {
  return RfidScannerServiceDesktop();
}