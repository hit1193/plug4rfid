import 'package:pocketbase/pocketbase.dart';

/// [모델] 장치 정보 클래스
/// RFID 리더, 프린터, 바코드 스캐너 등 하드웨어 장치의 정보를 담습니다.
class Device {
  final String id;
  final String name;
  final String model;
  final String ipAddress;
  final String status;     // 'Online', 'Offline'
  final String commMethod; // 'TCP/IP', 'COM', 'Bluetooth'
  final String type;       // 'RFID', 'Printer', 'Barcode-Scanner', 'Other' [추가]

  Device({
    required this.id,
    required this.name,
    required this.model,
    required this.ipAddress,
    required this.status,
    required this.commMethod,
    required this.type,
  });

  /// PocketBase 레코드를 Device 객체로 변환하는 팩토리 생성자
  factory Device.fromRecord(RecordModel record) {
    return Device(
      id: record.id,
      name: record.getStringValue('name'),
      model: record.getStringValue('model'),
      ipAddress: record.getStringValue('ip_address'),
      status: record.getStringValue('status'),
      commMethod: record.getStringValue('comm_method'),
      type: record.getStringValue('type'), // [추가] DB 필드명: type
    );
  }
}