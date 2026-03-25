import 'dart:typed_data';
// 🔥 오직 네이티브 플랫폼에서만 이 패키지를 불러옵니다! 웹에서는 이 파일이 완전히 무시됩니다.
import 'package:flutter_libserialport/flutter_libserialport.dart';

// ============================================================================
// [PC/모바일 전용 시리얼 포트 실제 구현체]
// 윈도우 및 안드로이드 등 네이티브 환경에서만 컴파일되는 영역입니다.
// 대표님께서 작성하신 핵심 제어 로직(DTR/RTS High)이 여기에 들어갑니다.
// ============================================================================
class AppSerialPort {
  final SerialPort _port;

  // 생성자: 넘어온 이름(COM 포트명 등)으로 실제 장치를 엽니다.
  AppSerialPort(String name) : _port = SerialPort(name);

  // 시스템에 연결된 실제 COM 포트 목록을 긁어옵니다.
  static List<String> get availablePorts {
    try {
      return SerialPort.availablePorts;
    } catch (e) {
      return [];
    }
  }

  String get name {
    return _port.name ?? "";
  }

  String? get description {
    return _port.description;
  }

  // 장치 이름을 기반으로 블루투스 여부를 판별합니다.
  bool get isBluetooth {
    try {
      return _port.transport == SerialPortTransport.bluetooth;
    } catch (_) {
      return false;
    }
  }

  bool get isOpen {
    return _port.isOpen;
  }

  int get bytesAvailable {
    return _port.bytesAvailable;
  }

  bool openReadWrite() {
    return _port.openReadWrite();
  }

  // 통신 포트 환경설정 세팅
  void configure({required int baudRate}) {
    final config = _port.config;
    config.baudRate = baudRate;

    // 🔥 [결정적 픽스] 이 부분이 추가되어야 하드웨어가 깨어납니다!
    // C++Builder의 TComPort처럼 포트 개방 시 제어 핀을 강제로 High(1)로 켭니다.
    config.bits = 8;
    config.stopBits = 1;
    config.setFlowControl(SerialPortFlowControl.none);
    config.dtr = 1; // DTR (Data Terminal Ready) 핀 High -> 장비 메인 전원 활성화
    config.rts = 1; // RTS (Request to Send) 핀 High -> 송수신 채널 활성화

    _port.config = config;
  }

  Uint8List read(int bytes) {
    return _port.read(bytes);
  }

  void write(Uint8List data) {
    _port.write(data);
  }

  void close() {
    _port.close();
  }

  void dispose() {
    _port.dispose();
  }
}