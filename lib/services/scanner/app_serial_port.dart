// ---------------------------------------------------------------------------
// 파일명: lib/services/scanner/app_serial_port_native.dart
// 역할: 윈도우/안드로이드에서 실제 COM 포트를 긁어오는 진짜 구현체입니다.
// ---------------------------------------------------------------------------
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
    _port.config = config;
  }

  Uint8List read(int bytes) => _port.read(bytes);
  void write(Uint8List data) => _port.write(data);
  void close() => _port.close();
  void dispose() => _port.dispose();
}