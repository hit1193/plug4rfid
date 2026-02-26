import 'package:pocketbase/pocketbase.dart';

/// FA/RFID 시스템 환경에 최적화된 물품 정보 모델
class ProductModel {
  final String id;           // PocketBase 고유 ID
  final String collectionId; // 컬렉션 ID (이미지 URL 생성용)

  // [핵심 필드]
  final String name;         // 품명
  final String tagId;        // RFID 태그 ID (EPC)
  final int quantity;        // 현재 수량

  // [확장 필드]
  final String? location;    // 보관 위치
  final String? spec;        // 규격/모델명
  final String? category;    // 분류
  final String status;       // 상태 (정상, 부족, 검수필요 등)
  final String? remarks;     // 비고 (추가된 필드)

  // [시스템 필드]
  final DateTime? lastSeen;  // 최종 RFID 스캔 일시
  final Map<String, dynamic> metadata; // 기타 비정형 데이터
  final String? image;       // 사진 파일명
  final DateTime created;    // 등록일

  ProductModel({
    this.id = '',
    this.collectionId = 'products',
    required this.name,
    required this.tagId,
    this.quantity = 0,
    this.location,
    this.spec,
    this.category,
    this.status = '정상',
    this.remarks,
    this.lastSeen,
    this.metadata = const {},
    this.image,
    DateTime? created,
  }) : created = created ?? DateTime.now();

  /// JSON 데이터를 모델로 변환 (C++의 FieldByName과 유사)
  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] ?? '',
      collectionId: json['collectionId'] ?? 'products',
      name: json['name'] ?? '',
      tagId: json['tag_id'] ?? '',
      quantity: (json['quantity'] is num) ? (json['quantity'] as num).toInt() : 0,
      location: json['location'],
      spec: json['spec'],
      category: json['category'],
      status: json['status'] ?? '정상',
      remarks: json['remarks'], // PocketBase의 remarks 필드 매핑
      lastSeen: json['last_seen'] != null ? DateTime.tryParse(json['last_seen']) : null,
      metadata: json['metadata'] is Map ? Map<String, dynamic>.from(json['metadata']) : {},
      image: json['image'],
      created: json['created'] != null ? DateTime.parse(json['created']) : DateTime.now(),
    );
  }

  /// [핵심] UI에서 컬럼 이름으로 값을 동적으로 가져오기 위한 헬퍼
  String getValue(String key) {
    switch (key) {
      case 'name': return name;
      case 'tag_id': return tagId;
      case 'location': return location ?? "-";
      case 'spec': return spec ?? "-";
      case 'category': return category ?? "-";
      case 'status': return status;
      case 'quantity': return quantity.toString();
      case 'remarks': return remarks ?? "-"; // 명시적 필드 우선 반환
      default:
      // 그 외 필드는 metadata 내부에서 검색
        if (metadata.containsKey(key)) return metadata[key].toString();
        return "-";
    }
  }

  /// 서버 저장을 위한 JSON 변환
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'tag_id': tagId,
      'quantity': quantity,
      'location': location,
      'spec': spec,
      'category': category,
      'status': status,
      'remarks': remarks, // 저장 시에도 포함
      'last_seen': lastSeen?.toIso8601String(),
      'metadata': metadata,
    };
  }

  /// PocketBase 파일 접근 URL 생성 헬퍼
  String? getImageUrl(String baseUrl, {String thumb = ''}) {
    if (image == null || image!.isEmpty || id.isEmpty) return null;
    String url = '$baseUrl/api/files/$collectionId/$id/$image';
    if (thumb.isNotEmpty) url += '?thumb=$thumb';
    return url;
  }
}