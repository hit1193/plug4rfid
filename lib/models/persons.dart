import 'package:pocketbase/pocketbase.dart';

/// FA/RFID 솔루션에 최적화된 사용자(임직원/작업자) 모델
class Person {
  final String id;
  final String collectionId;
  final String code;         // 사번
  final String tagId;        // RFID 태그 UID
  final String name;         // 성명
  final String? image;       // 이미지 파일명

  final String department;   // 소속 부서
  final String? companyId;   // 거래처 ID
  final String? companyName; // 거래처명

  // [확인] 출입 승인 필드 - PocketBase 최상위 필드와 연동
  final bool isApproved;

  final String? authId;
  final String role;
  final bool isActive;
  final String remarks;

  final Map<String, dynamic> metadata;
  final DateTime created;
  final DateTime updated;

  Person({
    required this.id,
    this.collectionId = 'persons',
    required this.code,
    required this.tagId,
    required this.name,
    this.image,
    required this.department,
    this.companyId,
    this.companyName,
    this.isApproved = true, // 기본값 승인
    this.authId,
    this.role = 'Operator',
    this.isActive = true,
    this.remarks = '',
    this.metadata = const {},
    required this.created,
    required this.updated,
  });

  factory Person.fromRecord(RecordModel record) {
    final expandedCompany = record.expand['company_id']?.first;

    // DB의 is_approved 필드를 우선 읽고, 없으면 metadata의 과거 기록 참조
    final bool approvedValue = record.getBoolValue('is_approved',
        record.data['metadata']?['last_approval_status'] ?? true);

    return Person(
      id: record.id,
      collectionId: record.collectionId,
      code: record.getStringValue('code'),
      tagId: record.getStringValue('tag_id'),
      name: record.getStringValue('name'),
      image: record.getStringValue('image'),
      department: record.getStringValue('department', 'Unknown'),
      companyId: record.getStringValue('company_id'),
      companyName: expandedCompany?.getStringValue('name'),
      isApproved: approvedValue,
      authId: record.getStringValue('auth_id'),
      role: record.getStringValue('role', 'Operator'),
      isActive: record.getBoolValue('is_active', true),
      remarks: record.getStringValue('remarks'),
      metadata: record.data['metadata'] is Map<String, dynamic>
          ? record.data['metadata'] as Map<String, dynamic>
          : {},
      created: DateTime.parse(record.created),
      updated: DateTime.parse(record.updated),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'tag_id': tagId,
      'name': name,
      if (image != null) 'image': image,
      'department': department,
      'company_id': companyId,
      'is_approved': isApproved, // 서버 최상위 필드 저장
      'auth_id': authId,
      'role': role,
      'is_active': isActive,
      'remarks': remarks,
      'metadata': {
        ...metadata,
        'last_approval_status': isApproved, // UI 호환용 백업
      },
    };
  }

  Person copyWith({
    String? code,
    String? tagId,
    String? name,
    String? image,
    String? department,
    String? companyId,
    String? companyName,
    bool? isApproved,
    String? authId,
    String? role,
    bool? isActive,
    String? remarks,
    Map<String, dynamic>? metadata,
  }) {
    return Person(
      id: id,
      collectionId: collectionId,
      code: code ?? this.code,
      tagId: tagId ?? this.tagId,
      name: name ?? this.name,
      image: image ?? this.image,
      department: department ?? this.department,
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      isApproved: isApproved ?? this.isApproved,
      authId: authId ?? this.authId,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      remarks: remarks ?? this.remarks,
      metadata: metadata ?? this.metadata,
      created: created,
      updated: updated,
    );
  }

  String? getImageUrl(String baseUrl, {String thumb = ''}) {
    if (image == null || image!.isEmpty) return null;
    final cid = collectionId.isEmpty ? 'persons' : collectionId;
    String url = "$baseUrl/api/files/$cid/$id/$image";
    if (thumb.isNotEmpty) url += "?thumb=$thumb";
    return url;
  }
}