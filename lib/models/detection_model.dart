import 'dart:convert';

/// ---------------------------------------------------------------------------
/// [DetectionModel] 실시간 감지 및 출입 이력 데이터 모델
/// PocketBase의 'detections' 컬렉션과 1:1로 대응됩니다.
///
/// [업데이트 내역]
/// - 날짜 파싱 오류(Invalid date format) 방지를 위한 강력한 문자열 보정 로직 추가
/// ---------------------------------------------------------------------------
class DetectionModel {
  final String id;          // PocketBase 고유 레코드 ID
  final String type;        // 'person' (인원 전용) 또는 'matched' (물품 매칭)
  final String content;     // 작업자 성함 혹은 내용
  final String imageUrl;    // 담당자 프로필 이미지 주소
  final String spot;        // 감지 위치 (리더명)
  final String status;      // 상태 문자열 (예: 출고(대여))
  final bool isEntry;       // 입고 여부 (Flag)
  final List<Map<String, String>> items; // 매칭된 물품 리스트 (이름, 이미지)
  final DateTime timestamp; // 감지 및 저장 시각

  /// 기본 생성자
  DetectionModel({
    this.id = '',
    required this.type,
    required this.content,
    required this.imageUrl,
    required this.spot,
    required this.status,
    required this.isEntry,
    required this.items,
    required this.timestamp,
  });

  /// ---------------------------------------------------------------------------
  /// [Factory] PocketBase(JSON) 데이터를 객체로 변환합니다. (역직렬화)
  /// ---------------------------------------------------------------------------
  factory DetectionModel.fromJson(Map<String, dynamic> json) {
    // 1. items_json 파싱 로직 (리스트 안전 처리)
    var itemsList = <Map<String, String>>[];
    if (json['items_json'] != null) {
      if (json['items_json'] is String) {
        // DB에서 문자열로 넘어온 경우
        var decoded = jsonDecode(json['items_json']) as List;
        itemsList = decoded.map((item) => Map<String, String>.from(item)).toList();
      } else {
        // 이미 List 객체인 경우
        var list = json['items_json'] as List;
        itemsList = list.map((item) => Map<String, String>.from(item)).toList();
      }
    }

    // 2. [오류 해결] 날짜 형식 안전 파싱 로직
    // PocketBase는 간혹 "2026-03-08 17:38:18.902Z" 처럼 중간에 'T' 대신 공백을 씁니다.
    // Dart의 DateTime.parse는 이를 거부할 수 있으므로, 공백을 'T'로 강제 치환해 줍니다.
    DateTime parsedTime;
    if (json['timestamp'] != null) {
      String dateStr = json['timestamp'].toString();
      // 공백이 있다면 표준 ISO 8601의 'T'로 변경해 줍니다.
      dateStr = dateStr.replaceAll(' ', 'T');
      try {
        parsedTime = DateTime.parse(dateStr);
      } catch (e) {
        // 최악의 경우 파싱에 실패하면 현재 시간을 기본값으로 넣습니다. (앱이 뻗지 않도록 방어)
        parsedTime = DateTime.now();
      }
    } else {
      parsedTime = DateTime.now();
    }

    return DetectionModel(
      id: json['id'] ?? '',
      type: json['type'] ?? 'person',
      content: json['content'] ?? '',
      imageUrl: json['image_url'] ?? '',
      spot: json['spot'] ?? '',
      status: json['status'] ?? '',
      isEntry: json['is_entry'] ?? true,
      items: itemsList,
      timestamp: parsedTime,
    );
  }

  /// ---------------------------------------------------------------------------
  /// [Method] 객체 데이터를 JSON 형태로 변환하여 서버에 저장할 때 사용합니다. (직렬화)
  /// ---------------------------------------------------------------------------
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'content': content,
      'image_url': imageUrl,
      'spot': spot,
      'status': status,
      'is_entry': isEntry,
      'items_json': items,
      // 서버 저장 시에는 UTC 기준 표준 포맷으로 맞춰서 보냅니다.
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }

  /// ---------------------------------------------------------------------------
  /// [Helper] UI 표현을 위한 시간 포맷팅 (예: 13:45:22)
  /// ---------------------------------------------------------------------------
  String get formattedTime {
    return "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
  }
}