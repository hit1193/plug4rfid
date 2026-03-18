// serial_port_stub.dart

// ---------------------------------------------------------------------------
// [공통 인터페이스 껍데기 (Stub)]
// 역할: C/C++의 헤더 파일(.h)과 같이 클래스와 함수의 원형(뼈대)만 정의합니다.
// ---------------------------------------------------------------------------
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
// (실제 구현체 파일에서 이 함수를 오버라이딩(재정의)하여 사용하게 됩니다.)
RfidScannerService getScannerService() => throw UnsupportedError('지원하지 않는 플랫폼입니다.');