import 'package:pocketbase/pocketbase.dart';

/// FA/RFID 시스템 환경에 최적화된 물품(제품/자재/장비) 정보 모델입니다.
/// C++Builder의 레코드(Record) 구조체 역할을 하며,
/// 포켓베이스 통신 및 엑셀(외부 데이터) 임포트 기능을 모두 지원합니다.
class ProductModel {
  // ---------------------------------------------------------------------------
  // 1. 시스템 기본 필드 (모든 컬렉션 공통)
  // ---------------------------------------------------------------------------
  final String id;
  final String collectionId;

  // ---------------------------------------------------------------------------
  // 2. 기본 항목 (필수 데이터)
  // ---------------------------------------------------------------------------
  final String name;         // 품명
  final String tagId;        // RFID 태그 UID (원본 입력 데이터)
  final String tagEpc;       // RFID 태그 EPC (실제 발급/인식된 Hex 데이터)
  final int quantity;        // 현재 수량 (재고)
  final int safetyStock;     // 안전 재고 (이 수량 미만이면 부족 알림)

  // ---------------------------------------------------------------------------
  // 3. 확장 항목 (FA/물류/창고 도메인 특화)
  // ---------------------------------------------------------------------------
  final String? location;    // 보관 위치
  final String? spec;        // 규격 및 사양
  final String? category;    // 분류
  final String status;       // 현재 상태 (예: 보유중, 수리중, 폐기 등)
  final String? remarks;     // 비고
  final String? unit;        // 단위 (예: ea, kg, box)
  final String? serialNumber;// S/N (시리얼 번호)
  final String? manufacturer;// 제조사/공급사

  // ---------------------------------------------------------------------------
  // 4. 시스템 제어 및 메타데이터
  // ---------------------------------------------------------------------------
  final bool isApproved;     // 출입 또는 사용 승인 여부
  final DateTime? lastSeen;  // RFID 리더기에 마지막으로 인식된 시간

  /// [핵심] 동적 속성 및 사용자 정의 데이터가 저장되는 필드
  final Map<String, dynamic> metadata;

  /// [매핑 정보] 엑셀 등 외부 데이터 임포트 시 실제로 어떤 키가 매칭되었는지 저장
  final Map<String, String> originKeyMap;

  final String? image;       // 제품 이미지 파일명
  final DateTime created;    // 등록 일시 (UserModel과 일관성을 위해 DateTime 사용)
  final DateTime updated;    // 마지막 수정 일시

  /// 생성자 (Constructor)
  ProductModel({
    this.id = '',
    this.collectionId = 'products',
    required this.name,
    required this.tagId,
    this.tagEpc = '',
    this.quantity = 0,
    this.safetyStock = 5,
    this.location,
    this.spec,
    this.category,
    this.status = '보유중',
    this.remarks,
    this.unit = 'ea',
    this.serialNumber,
    this.manufacturer,
    this.isApproved = true,
    this.lastSeen,
    this.metadata = const {},
    this.originKeyMap = const {},
    this.image,
    required this.created,
    required this.updated,
  });

  // ---------------------------------------------------------------------------
  // [Getters] 읽기 전용 편의 속성들
  // ---------------------------------------------------------------------------

  /// 물품의 과거 이력(히스토리)을 메타데이터에서 추출하여 반환합니다.
  List<Map<String, dynamic>> get history {
    if (metadata.containsKey('history') && metadata['history'] is List) {
      return List<Map<String, dynamic>>.from(metadata['history']);
    }
    return [];
  }

  /// 현재 재고가 안전 재고보다 적은지(재고 부족 상태인지) 확인합니다.
  bool get isShortage {
    return quantity < safetyStock;
  }

  // ---------------------------------------------------------------------------
  // [Alias Definition] 외부 데이터 매핑용 사전
  // ---------------------------------------------------------------------------
  static const Map<String, List<String>> _aliasDefinition = {
    'name': ['품명', '제품명', '자산명', 'Item Name'],
    'tag_id': ['태그ID', 'RFID', 'UID', 'Barcode'],
    'tag_epc': ['태그EPC', 'EPC', 'Tag EPC'],
    'location': ['위치', '보관위치', '창고', 'Shelf'],
    'spec': ['규격', '모델명', '사양', 'Spec'],
    'manufacturer': ['제조사', '메이커', '공급사', 'Brand', 'Maker'],
    'serial_number': ['S/N', '시리얼', '제조번호'],
    'unit': ['단위', 'Unit'],
    'quantity': ['수량', '재고', 'Qty'],
    'safety_stock': ['안전재고', '기준재고', 'Min Stock'],
    'is_approved': ['승인여부', '승인상태', 'Approval'],
  };

  // ---------------------------------------------------------------------------
  // [Factory] 데이터 변환 메서드
  // ---------------------------------------------------------------------------

  /// 1. 포켓베이스 전용 파서 (PocketBase 통신용)
  /// 데이터베이스에서 가져온 RecordModel을 플러터 객체로 변환합니다.
  factory ProductModel.fromRecord(RecordModel record) {
    // DB의 is_approved 필드를 우선적으로 읽고, 없으면 metadata 참조
    final bool approvedValue = record.getBoolValue(
      'is_approved',
      record.data['metadata']?['last_approval_status'] ?? true,
    );

    // last_seen 시간 파싱
    DateTime? parsedLastSeen;
    final lastSeenStr = record.getStringValue('last_seen');
    if (lastSeenStr.isNotEmpty) {
      parsedLastSeen = DateTime.tryParse(lastSeenStr);
    }

    return ProductModel(
      id: record.id,
      collectionId: record.collectionId,
      name: record.getStringValue('name'),
      tagId: record.getStringValue('tag_id'),
      tagEpc: record.getStringValue('tag_epc'),
      quantity: record.getIntValue('quantity', 0),
      safetyStock: record.getIntValue('safety_stock', 5),
      location: record.getStringValue('location'),
      spec: record.getStringValue('spec'),
      category: record.getStringValue('category'),
      status: record.getStringValue('status', '보유중'),
      remarks: record.getStringValue('remarks'),
      unit: record.getStringValue('unit', 'ea'),
      serialNumber: record.getStringValue('serial_number'),
      manufacturer: record.getStringValue('manufacturer'),
      isApproved: approvedValue,
      lastSeen: parsedLastSeen,
      image: record.getStringValue('image'),

      metadata: record.data['metadata'] is Map<String, dynamic>
          ? record.data['metadata'] as Map<String, dynamic>
          : {},
      originKeyMap: record.data['origin_key_map'] is Map<String, dynamic>
          ? Map<String, String>.from(record.data['origin_key_map'])
          : {},

      created: DateTime.parse(record.created),
      updated: DateTime.parse(record.updated),
    );
  }

  /// 2. 범용 JSON 파서 (엑셀 임포트, 외부 API, 로컬 캐시용)
  /// 강력한 Alias 매핑 로직이 적용되어 있습니다.
  factory ProductModel.fromJson(Map<String, dynamic> json) {
    // metadata가 없을 때 전체 json을 대입하지 않도록 방어 (시스템 필드 혼입 방지)
    final Map<String, dynamic> meta = (json['metadata'] is Map)
        ? Map<String, dynamic>.from(json['metadata'])
        : {};

    final Map<String, String> usedKeys = {};

    // JSON 키와 Alias를 비교하여 실제 값을 찾아내는 내부 함수
    String? findValue(String systemKey) {
      if (json.containsKey(systemKey) && json[systemKey] != null) {
        usedKeys[systemKey] = systemKey;
        return json[systemKey].toString();
      }
      final aliases = _aliasDefinition[systemKey] ?? [];
      for (var alias in aliases) {
        if (meta.containsKey(alias)) {
          usedKeys[systemKey] = alias;
          return meta[alias]?.toString();
        }
      }
      return null;
    }

    final dynamic approvedJson = json['is_approved'];
    final bool approvedValue = approvedJson is bool
        ? approvedJson
        : (meta['last_approval_status'] ?? true);

    return ProductModel(
      id: json['id']?.toString() ?? '',
      collectionId: json['collectionId']?.toString() ?? 'products',
      name: findValue('name') ?? '',
      tagId: findValue('tag_id') ?? '',
      tagEpc: findValue('tag_epc') ?? '',
      quantity: int.tryParse(findValue('quantity') ?? '') ?? (json['quantity'] as int? ?? 0),
      safetyStock: int.tryParse(findValue('safety_stock') ?? '') ?? (json['safety_stock'] as int? ?? 5),
      location: findValue('location'),
      spec: findValue('spec'),
      category: findValue('category'),
      status: findValue('status') ?? '보유중',
      remarks: findValue('remarks'),
      unit: findValue('unit') ?? 'ea',
      serialNumber: findValue('serial_number'),
      manufacturer: findValue('manufacturer'),
      isApproved: approvedValue,
      lastSeen: json['last_seen'] != null ? DateTime.tryParse(json['last_seen'].toString()) : null,
      metadata: meta,
      originKeyMap: usedKeys,
      image: json['image']?.toString(),

      // 날짜 데이터 파싱 방어 코드
      created: json['created'] != null
          ? DateTime.tryParse(json['created'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updated: json['updated'] != null
          ? DateTime.tryParse(json['updated'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// 3. toJson 직렬화 (포켓베이스 업로드 및 로컬 저장용)
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> syncedMeta = Map<String, dynamic>.from(metadata);
    // UI 호환용 상태 백업
    syncedMeta['last_approval_status'] = isApproved;

    return {
      'id': id,
      'collectionId': collectionId,
      'name': name,
      'tag_id': tagId,
      'tag_epc': tagEpc,
      'quantity': quantity,
      'safety_stock': safetyStock,
      'location': location,
      'spec': spec,
      'category': category,
      'status': status,
      'remarks': remarks,
      'unit': unit,
      'serial_number': serialNumber,
      'manufacturer': manufacturer,
      'is_approved': isApproved,
      'last_seen': lastSeen?.toIso8601String(),
      'metadata': syncedMeta,
      'origin_key_map': originKeyMap,
      if (image != null) 'image': image,
      'created': created.toIso8601String(),
      'updated': updated.toIso8601String(),
    };
  }

  // ---------------------------------------------------------------------------
  // [State Management] 플러터 상태 관리용 복제 메서드
  // ---------------------------------------------------------------------------

  /// 기존 객체의 속성은 유지한 채 필요한 필드만 변경하여 새로운 객체를 반환합니다.
  ProductModel copyWith({
    String? name,
    String? tagId,
    String? tagEpc,
    int? quantity,
    int? safetyStock,
    String? location,
    String? spec,
    String? category,
    String? status,
    String? remarks,
    String? unit,
    String? serialNumber,
    String? manufacturer,
    bool? isApproved,
    DateTime? lastSeen,
    Map<String, dynamic>? metadata,
    Map<String, String>? originKeyMap,
    String? image,
  }) {
    return ProductModel(
      id: id,
      collectionId: collectionId,
      name: name ?? this.name,
      tagId: tagId ?? this.tagId,
      tagEpc: tagEpc ?? this.tagEpc,
      quantity: quantity ?? this.quantity,
      safetyStock: safetyStock ?? this.safetyStock,
      location: location ?? this.location,
      spec: spec ?? this.spec,
      category: category ?? this.category,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      unit: unit ?? this.unit,
      serialNumber: serialNumber ?? this.serialNumber,
      manufacturer: manufacturer ?? this.manufacturer,
      isApproved: isApproved ?? this.isApproved,
      lastSeen: lastSeen ?? this.lastSeen,
      metadata: metadata ?? this.metadata,
      originKeyMap: originKeyMap ?? this.originKeyMap,
      image: image ?? this.image,
      created: created,
      updated: updated,
    );
  }

  // ---------------------------------------------------------------------------
  // [Utils] 유틸리티 메서드
  // ---------------------------------------------------------------------------

  /// 물품의 이미지 URL을 생성하여 반환합니다.
  String getImageUrl(String baseUrl, {String thumb = ''}) {
    if (image == null || image!.isEmpty || id.isEmpty) {
      return '';
    }

    final cid = collectionId.isEmpty ? 'products' : collectionId;
    String url = "$baseUrl/api/files/$cid/$id/$image";

    if (thumb.isNotEmpty) {
      url += "?thumb=$thumb";
    }
    return url;
  }
}