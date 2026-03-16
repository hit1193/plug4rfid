import 'package:pocketbase/pocketbase.dart';

/// [Model] 장치 정보 클래스 (순수 데이터 구조체)
/// C++Builder의 struct 혹은 단순 class와 같습니다.
/// 모든 필드는 final로 선언하여 데이터의 불변성(Immutability)을 보장합니다.
class DeviceModel {
  final String id;
  final String collectionId;
  final String name;          // 장치 표시명
  final String model;         // 제조사 및 모델명
  final String commMethod;    // 통신 방식 (TCP/IP 등)
  final String ipAddress;     // IP 주소
  final int port;             // 통신 포트
  final String status;        // 현재 상태 (Online, Offline, Error)
  final bool isActive;        // 장치 활성화 여부

  // 앱(프로그램) 구동 시 백그라운드에서 자동으로 연결을 시도할지 여부
  final bool isAutoConnect;

  final String clientId;      // Host Serial ID
  final String? image;        // 장치 사진 파일명
  final double posX;          // 도면 내 X 좌표 (0.0~1.0)
  final double posY;          // 도면 내 Y 좌표 (0.0~1.0)
  final Map<String, dynamic> settings;
  final DateTime created;
  final DateTime updated;

  DeviceModel({
    required this.id,
    this.collectionId = 'devices',
    required this.name,
    required this.model,
    required this.commMethod,
    required this.clientId,
    this.ipAddress = '',
    this.port = 8080,
    this.status = 'Offline',
    this.isActive = true,
    this.isAutoConnect = false, // 기본값은 '수동 연결(false)'로 둡니다.
    this.image,
    this.posX = 0.0,
    this.posY = 0.0,
    this.settings = const {},
    required this.created,
    required this.updated,
  });

  /// -------------------------------------------------------------------------
  /// [copyWith 메서드]
  /// 객체의 일부 속성만 변경하여 새로운 객체를 생성할 때 사용합니다.
  /// 파라미터와 이름이 겹치는 변수에만 this.를 사용하여 Dart의 권장 사항을 준수합니다.
  /// -------------------------------------------------------------------------
  DeviceModel copyWith({
    String? status,
    double? posX,
    double? posY,
    bool? isActive,
    DateTime? updated,
    Map<String, dynamic>? settings,
  }) {
    return DeviceModel(
      id: id,
      collectionId: collectionId,
      name: name,
      model: model,
      commMethod: commMethod,
      clientId: clientId,
      ipAddress: ipAddress,
      port: port,
      status: status ?? this.status, // 이름이 겹치므로 this. 사용
      isActive: isActive ?? this.isActive, // 이름이 겹치므로 this. 사용
      isAutoConnect: isAutoConnect,
      image: image,
      posX: posX ?? this.posX, // 이름이 겹치므로 this. 사용
      posY: posY ?? this.posY, // 이름이 겹치므로 this. 사용
      settings: settings ?? this.settings, // 이름이 겹치므로 this. 사용
      created: created,
      updated: updated ?? this.updated, // 이름이 겹치므로 this. 사용
    );
  }

  /// DB 레코드로부터 객체 생성 (Field Mapping)
  factory DeviceModel.fromRecord(RecordModel record) {
    return DeviceModel(
      id: record.id,
      collectionId: record.collectionId,
      name: record.getStringValue('name'),
      model: record.getStringValue('model'),
      commMethod: record.getStringValue('comm_method', 'TCP/IP'),
      clientId: record.getStringValue('client_id'),
      ipAddress: record.getStringValue('ip_address'),
      port: record.getIntValue('port', 8080),
      status: record.getStringValue('status', 'Offline'),
      isActive: record.getBoolValue('is_active', true),
      isAutoConnect: record.getBoolValue('is_auto_connect', false),
      image: record.getStringValue('image'),
      posX: record.getDoubleValue('pos_x', 0.0),
      posY: record.getDoubleValue('pos_y', 0.0),
      settings: record.data['settings'] is Map<String, dynamic> ? record.data['settings'] : {},
      created: DateTime.parse(record.created),
      updated: DateTime.parse(record.updated),
    );
  }

  /// 이미지 URL 생성 도우미
  String? getImageUrl(String baseUrl, {String thumb = ''}) {
    if (image == null || image!.isEmpty) {
      return null;
    }
    return "$baseUrl/api/files/$collectionId/$id/$image${thumb.isNotEmpty ? '?thumb=$thumb' : ''}";
  }
}