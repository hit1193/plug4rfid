import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class AppSerialPort {
  final SerialPort _port;

  AppSerialPort(String name) : _port = SerialPort(name);

  // 실제 PC에 꽂힌 COM 포트를 긁어옵니다.
  static List<String> get availablePorts {
    try {
      return SerialPort.availablePorts;
    } catch (e) {
      return [];
    }
  }

  String get name => _port.name ?? "";
  String? get description => _port.description;

  bool get isBluetooth {
    try {
      return _port.transport == SerialPortTransport.bluetooth;
    } catch (_) {
      return false;
    }
  }

  bool get isOpen => _port.isOpen;
  int get bytesAvailable => _port.bytesAvailable;

  bool openReadWrite() => _port.openReadWrite();

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

  Uint8List read(int bytes) => _port.read(bytes);
  void write(Uint8List data) => _port.write(data);
  void close() => _port.close();
  void dispose() => _port.dispose();
}