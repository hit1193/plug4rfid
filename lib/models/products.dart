import 'package:pocketbase/pocketbase.dart';

/// FA/RFID 시스템 환경에 최적화된 물품 정보 모델
class ProductModel {
  final String id;           // PocketBase 고유 ID (Record ID)
  final String collectionId; // 컬렉션 ID (이미지 URL 생성용)

  // [핵심 필드] - 엑셀 업로드 시 필수 매칭 권장
  final String name;         // 품명
  final String tagId;        // RFID 태그 ID (EPC)
  final int quantity;        // 현재 수량

  // [선택 필드] - 엑셀 컬럼과 1:1 매칭되는 확장 정보
  final String? location;    // 보관 위치 (예: 창고A-1)
  final String? spec;        // 규격/모델명 (예: 50mm, 전압 등)
  final String? category;    // 분류 (예: 원부자재, 반제품, 완제품)

  // [시스템 및 상태 필드]
  final String status;       // 상태 (Select 타입 연동: 정상, 부족, 검수필요, 수리중, 폐기)
  final DateTime? lastSeen;  // 최종 RFID 스캔 일시
  final Map<String, dynamic> metadata; // 기타 비정형 데이터 (JSON 타입)
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
    this.lastSeen,
    this.metadata = const {},
    this.image,
    DateTime? created,
  }) : created = created ?? DateTime.now();

  /// PocketBase JSON 데이터를 Dart 객체로 변환 (TQuery.FieldByName)
  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] ?? '',
      collectionId: json['collectionId'] ?? json['collectionName'] ?? 'products',
      name: json['name'] ?? '',
      tagId: json['tag_id'] ?? '',
      // 수량 데이터 타입 안전성 확보
      quantity: (json['quantity'] is num) ? (json['quantity'] as num).toInt() : 0,
      location: json['location'],
      spec: json['spec'],
      category: json['category'],
      status: json['status'] ?? '정상',
      // 날짜 데이터 파싱
      lastSeen: json['last_seen'] != null ? DateTime.parse(json['last_seen']) : null,
      // 가변 데이터 Map 변환
      metadata: json['metadata'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['metadata'])
          : {},
      image: json['image'],
      created: json['created'] != null
          ? DateTime.parse(json['created'])
          : DateTime.now(),
    );
  }

  /// 서버 저장을 위한 JSON 변환 (TUpdateSQL 역할)
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'tag_id': tagId,
      'quantity': quantity,
      'location': location,
      'spec': spec,
      'category': category,
      'status': status,
      'last_seen': lastSeen?.toIso8601String(),
      'metadata': metadata,
      // image 필드는 파일 업로드 시 별도 멀티파트 처리가 필요하므로 보통 제외
    };
  }

  /// PocketBase 파일 접근 URL 생성 헬퍼
  String? getImageUrl(String baseUrl, {String thumb = ''}) {
    if (image == null || image!.isEmpty || id.isEmpty) return null;
    final cid = collectionId.isEmpty ? 'products' : collectionId;
    String url = '$baseUrl/api/files/$cid/$id/$image';
    if (thumb.isNotEmpty) url += '?thumb=$thumb';
    return url;
  }

  /// 부분 수정을 위한 복사 메서드 (상태 관리 및 Partial Update 시 필수)
  ProductModel copyWith({
    String? name,
    String? tagId,
    int? quantity,
    String? location,
    String? spec,
    String? category,
    String? status,
    DateTime? lastSeen,
    Map<String, dynamic>? metadata,
    String? image,
  }) {
    return ProductModel(
      id: id,
      collectionId: collectionId,
      name: name ?? this.name,
      tagId: tagId ?? this.tagId,
      quantity: quantity ?? this.quantity,
      location: location ?? this.location,
      spec: spec ?? this.spec,
      category: category ?? this.category,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      metadata: metadata ?? this.metadata,
      image: image ?? this.image,
      created: created,
    );
  }
}