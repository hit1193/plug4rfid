// serial_port_web.dart
import 'serial_port_stub.dart';

class RfidScannerServiceWeb implements RfidScannerService {
  @override
  Future<void> connect(String portName) async {
    // 웹에서는 시리얼 통신이 안 되므로 콘솔에 로그만 찍고 넘어갑니다.
    print('웹 환경에서는 시리얼 포트에 접근할 수 없습니다. (가상 연결 성공)');
  }

  @override
  Future<String> readData() async {
    // 웹 환경 테스트를 위해 가상의 더미 데이터를 반환합니다.
    return "WEB_DUMMY_RFID_99999";
  }
}

// 웹 환경일 경우 이 가짜 클래스를 반환합니다.
RfidScannerService getScannerService() {
  return RfidScannerServiceWeb();
}