// serial_port_stub.dart
class RfidScannerService {
  // 시리얼 포트 연결 함수 뼈대
  Future<void> connect(String portName) async {
    throw UnimplementedError('이 플랫폼에서는 지원하지 않습니다.');
  }

  // 스캔 데이터 읽기 함수 뼈대
  Future<String> readData() async {
    throw UnimplementedError('이 플랫폼에서는 지원하지 않습니다.');
  }
}

// 이 함수가 핵심입니다. 환경에 따라 데스크탑용 파일이나 웹용 파일을 반환하게 됩니다.
RfidScannerService getScannerService() => throw UnsupportedError('지원하지 않는 플랫폼입니다.');