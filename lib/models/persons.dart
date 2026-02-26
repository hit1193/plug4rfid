import 'package:pocketbase/pocketbase.dart';

/// FA/RFID 솔루션에 최적화된 사용자(임직원/작업자) 모델
/// PocketBase의 'persons' 컬렉션 규격에 맞추어 설계되었습니다.
class Person {
  final String id;
  final String collectionId;
  final String code;         // 사번 또는 관리 코드 (Unique Index)
  final String tagId;        // RFID 태그 UID (Unique Index: tag_id)
  final String name;         // 성명
  final String? image;       // 파일명 (PocketBase 저장 파일명)

  // 확장 필드: 소속 및 거래처 정보
  final String department;   // 소속 부서 (예: 생산1팀, 품질관리부)
  final String? companyId;   // 거래처/협력사 ID (Relation)
  final String? companyName; // 거래처명 (Expand를 통해 가져온 데이터 표시용)

  // 시스템 관리 필드
  final String? authId;      // PocketBase 'users' 컬렉션과의 연결 ID (Relation: auth_id)
  final String role;         // 권한 (Admin, Operator, Viewer 등)
  final bool isActive;       // 재직 여부 또는 태그 활성화 상태 (is_active)
  final String remarks;      // 비고/메모 필드

  final Map<String, dynamic> metadata; // 기타 확장 정보 (JSON)
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
    this.authId,
    this.role = 'Operator',
    this.isActive = true,
    this.remarks = '',
    this.metadata = const {},
    required this.created,
    required this.updated,
  });

  /// PocketBase의 RecordModel을 Person 객체로 변환하는 팩토리 생성자
  factory Person.fromRecord(RecordModel record) {
    // expand 데이터를 통해 거래처명을 가져올 수 있습니다.
    final expandedCompany = record.expand['company_id']?.first;

    return Person(
      id: record.id,
      collectionId: record.collectionId,
      code: record.getStringValue('code'),
      tagId: record.getStringValue('tag_id'), // [수정] tag_id -> tagId (기존 변수명 준수)
      name: record.getStringValue('name'),
      image: record.getStringValue('image'),
      department: record.getStringValue('department', 'Unknown'),
      companyId: record.getStringValue('company_id'),
      companyName: expandedCompany?.getStringValue('name'),
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

  /// PocketBase 서버로 전송할 데이터를 생성하는 메서드
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'tag_id': tagId,
      'name': name,
      if (image != null) 'image': image,
      'department': department,
      'company_id': companyId,
      'auth_id': authId,
      'role': role,
      'is_active': isActive,
      'remarks': remarks,
      'metadata': metadata,
    };
  }

  /// 일부 데이터만 수정된 새로운 객체를 생성하는 메서드 (C++ 복사 생성자 역할)
  Person copyWith({
    String? code,
    String? tagId,
    String? name,
    String? image,
    String? department,
    String? companyId,
    String? companyName,
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
      authId: authId ?? this.authId,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      remarks: remarks ?? this.remarks,
      metadata: metadata ?? this.metadata,
      created: created,
      updated: updated,
    );
  }

  /// 이미지 파일의 전체 URL을 생성하는 헬퍼 함수
  String? getImageUrl(String baseUrl, {String thumb = ''}) {
    if (image == null || image!.isEmpty) return null;

    final cid = collectionId.isEmpty ? 'persons' : collectionId;
    String url = "$baseUrl/api/files/$cid/$id/$image";
    if (thumb.isNotEmpty) {
      url += "?thumb=$thumb";
    }
    return url;
  }
}