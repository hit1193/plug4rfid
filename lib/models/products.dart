import 'package:intl/intl.dart';

/// FA/RFID 시스템 환경에 최적화된 물품 정보 모델
class ProductModel {
  final String id;
  final String collectionId;

  // [기본 항목]
  final String name;
  final String tagId;
  final int quantity;
  final int safetyStock;

  // [확장 항목]
  final String? location;
  final String? spec;
  final String? category;
  final String status;
  final String? remarks;
  final String? unit;
  final String? serialNumber;
  final String? manufacturer;

  // [시스템 필드]
  final DateTime? lastSeen;

  /// [핵심] 변경 이력 및 사용자 정의 데이터가 저장되는 필드
  /// 이력은 metadata['history'] 에 List 형태로 저장됩니다.
  final Map<String, dynamic> metadata;

  final String? image;
  final String? created;
  final String? updated;

  // [매핑 정보] 엑셀 임포트 시 실제로 어떤 키가 사용되었는지 저장
  final Map<String, String> originKeyMap;

  ProductModel({
    this.id = '',
    this.collectionId = 'products',
    required this.name,
    required this.tagId,
    this.quantity = 0,
    this.safetyStock = 5,
    this.location,
    this.spec,
    this.category,
    this.status = '정상',
    this.remarks,
    this.unit = 'ea',
    this.serialNumber,
    this.manufacturer,
    this.lastSeen,
    this.metadata = const {},
    this.image,
    this.created,
    this.updated,
    this.originKeyMap = const {},
  });

  /// [보탬] 변경 이력만 따로 뽑아주는 Getter (UI에서 리스트로 뿌릴 때 사용)
  List<Map<String, dynamic>> get history {
    if (metadata.containsKey('history') && metadata['history'] is List) {
      return List<Map<String, dynamic>>.from(metadata['history']);
    }
    return [];
  }

  /// 시스템이 기본적으로 알고 있는 별칭들
  static const Map<String, List<String>> _aliasDefinition = {
    'name': ['품명', '제품명', '자산명', 'Item Name'],
    'tag_id': ['태그ID', 'RFID', 'EPC', 'Barcode'],
    'location': ['위치', '보관위치', '창고', 'Shelf'],
    'spec': ['규격', '모델명', '사양', 'Spec'],
    'manufacturer': ['제조사', '메이커', '공급사', 'Brand', 'Maker'],
    'serial_number': ['S/N', '시리얼', '제조번호'],
    'unit': ['단위', 'Unit'],
    'quantity': ['수량', '재고', 'Qty'],
    'safety_stock': ['안전재고', '기준재고', 'Min Stock'],
  };

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> meta = Map<String, dynamic>.from(json['metadata'] ?? json);
    final Map<String, String> usedKeys = {};

    String? findValue(String systemKey) {
      final aliases = _aliasDefinition[systemKey] ?? [];
      if (json.containsKey(systemKey)) {
        usedKeys[systemKey] = systemKey;
        return json[systemKey]?.toString();
      }
      for (var alias in aliases) {
        if (meta.containsKey(alias)) {
          usedKeys[systemKey] = alias;
          return meta[alias]?.toString();
        }
      }
      return null;
    }

    return ProductModel(
      id: json['id'] ?? '',
      collectionId: json['collectionId'] ?? 'products',
      name: findValue('name') ?? '',
      tagId: findValue('tag_id') ?? '',
      quantity: int.tryParse(findValue('quantity') ?? '') ?? (json['quantity'] ?? 0),
      safetyStock: int.tryParse(findValue('safety_stock') ?? '') ?? (json['safety_stock'] ?? 5),
      location: findValue('location'),
      spec: findValue('spec'),
      category: findValue('category'),
      status: findValue('status') ?? '정상',
      remarks: findValue('remarks'),
      unit: findValue('unit') ?? 'ea',
      serialNumber: findValue('serial_number'),
      manufacturer: findValue('manufacturer'),
      lastSeen: json['last_seen'] != null ? DateTime.tryParse(json['last_seen']) : null,
      metadata: meta,
      originKeyMap: usedKeys,
      image: json['image'],
      created: json['created'],
      updated: json['updated'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> syncedMeta = Map<String, dynamic>.from(metadata);

    void sync(String systemKey, dynamic value) {
      final originKey = originKeyMap[systemKey] ?? systemKey;
      syncedMeta[originKey] = value;
    }

    sync('name', name);
    if (location != null) sync('location', location);
    if (spec != null) sync('spec', spec);
    if (category != null) sync('category', category);
    if (status != '정상') sync('status', status);
    if (remarks != null) sync('remarks', remarks);
    if (manufacturer != null) sync('manufacturer', manufacturer);
    if (serialNumber != null) sync('serial_number', serialNumber);
    if (unit != null) sync('unit', unit);

    return {
      'name': name,
      'tag_id': tagId,
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
      'last_seen': lastSeen?.toIso8601String(),
      'metadata': syncedMeta,
      'origin_key_map': originKeyMap,
    };
  }

  String getValue(String key) {
    switch (key) {
      case '품명': return name;
      case 'TAG ID': return tagId;
      case '수량': return "$quantity $unit";
      case '상태': return status;
      case '위치': return location ?? "-";
      case '규격': return spec ?? "-";
      case '제조사': return manufacturer ?? "-";
      case 'S/N': return serialNumber ?? "-";
      case '비고': return remarks ?? "-";
      default:
        if (metadata.containsKey(key)) return metadata[key].toString();
        return "-";
    }
  }

  String? getImageUrl(String baseUrl, {String thumb = ''}) {
    if (image == null || image!.isEmpty || id.isEmpty) return null;
    return '$baseUrl/api/files/$collectionId/$id/$image${thumb.isNotEmpty ? '?thumb=$thumb' : ''}';
  }

  bool get isShortage => quantity < safetyStock;
}