import 'package:pocketbase/pocketbase.dart';

/// FA/RFID 솔루션에 최적화된 사용자(임직원/작업자) 모델입니다.
/// 기존의 persons 컬렉션 구조를 포켓베이스 기본 인증 컬렉션인 users로 완벽히 이관한 클래스입니다.
/// C++Builder의 레코드(Record)나 데이터 모듈에서 사용하던 구조체 역할을 수행합니다.
class UserModel {
  // ---------------------------------------------------------------------------
  // 1. 포켓베이스 시스템 기본 필드 (users 컬렉션 고유 속성)
  // ---------------------------------------------------------------------------
  final String id;
  final String collectionId;
  final String username;     // 포켓베이스 users 컬렉션 기본 로그인 아이디
  final String email;        // 포켓베이스 users 컬렉션 기본 이메일

  // ---------------------------------------------------------------------------
  // 2. FA / RFID 업무용 커스텀 필드
  // ---------------------------------------------------------------------------
  final String code;         // 사번 (고유 식별자)
  final String tagId;        // RFID 태그 UID
  final String name;         // 성명
  final String? avatar;      // 이미지 파일명 (users 컬렉션은 image 대신 avatar를 사용합니다)

  final String department;   // 소속 부서
  final String? companyId;   // 거래처 ID (Relation)
  final String? companyName; // 거래처명 (Expand를 통해 가져온 값)

  final bool isApproved;     // 출입 또는 시스템 사용 승인 여부
  // 🔥 [수정] 불필요한 grade 필드를 삭제하고, 기본 제공되는 role 필드를 권한(등급)용으로 적극 활용합니다.
  final String role;         // 시스템 권한 및 등급 (예: 최고관리자, 현장관리자, 일반작업자 등)
  final bool isActive;       // 퇴사/정지 여부를 가리는 활성화 상태
  final String remarks;      // 비고란

  // ---------------------------------------------------------------------------
  // 3. 메타데이터 및 타임스탬프
  // ---------------------------------------------------------------------------
  final Map<String, dynamic> metadata; // 기타 확장 정보를 담는 JSON 구조
  final DateTime created;              // 생성 일시
  final DateTime updated;              // 마지막 수정 일시

  /// 생성자 (Constructor)
  /// 클래스 객체를 메모리에 올릴 때 초기값을 세팅합니다.
  UserModel({
    required this.id,
    this.collectionId = 'users', // 기본값을 users로 고정합니다.
    this.username = '',
    this.email = '',
    required this.code,
    required this.tagId,
    required this.name,
    this.avatar,
    required this.department,
    this.companyId,
    this.companyName,
    this.isApproved = true,
    this.role = '일반작업자 (Operator)', // 🔥 기본값을 3단계 중 가장 낮은 등급으로 고정합니다.
    this.isActive = true,
    this.remarks = '',
    this.metadata = const {},
    required this.created,
    required this.updated,
  });

  /// 팩토리 생성자 (fromRecord) - 포켓베이스 전용
  /// 포켓베이스 서버에서 전달받은 데이터(RecordModel)를 플러터 객체(UserModel)로 변환합니다.
  /// Firebird DB에서 Fetch한 Record 데이터셋을 애플리케이션 변수에 매핑하는 과정과 같습니다.
  factory UserModel.fromRecord(RecordModel record) {
    // 릴레이션(Relation)으로 연결된 거래처(company_id) 정보가 있다면 펼쳐서(Expand) 가져옵니다.
    final expandedCompany = record.expand['company_id']?.first;

    // 데이터베이스의 is_approved 필드를 우선적으로 읽고,
    // 값이 없을 경우 metadata에 백업된 과거 기록을 참조하는 안전장치입니다.
    final bool approvedValue = record.getBoolValue(
      'is_approved',
      record.data['metadata']?['last_approval_status'] ?? true,
    );

    return UserModel(
      id: record.id,
      collectionId: record.collectionId,
      username: record.getStringValue('username'),
      email: record.getStringValue('email'),
      code: record.getStringValue('code'),
      tagId: record.getStringValue('tag_id'),
      name: record.getStringValue('name'),
      avatar: record.getStringValue('avatar'),
      department: record.getStringValue('department', 'Unknown'),
      companyId: record.getStringValue('company_id'),
      companyName: expandedCompany?.getStringValue('name'),
      isApproved: approvedValue,
      // 🔥 [수정] DB의 기본 필드인 role을 가져옵니다.
      role: record.getStringValue('role', '일반작업자 (Operator)'),
      isActive: record.getBoolValue('is_active', true),
      remarks: record.getStringValue('remarks'),

      // 메타데이터가 Map(JSON) 형식인지 확인 후 안전하게 형변환합니다.
      metadata: record.data['metadata'] is Map<String, dynamic>
          ? record.data['metadata'] as Map<String, dynamic>
          : {},

      // 날짜 문자열을 Dart의 DateTime 객체로 파싱합니다.
      created: DateTime.parse(record.created),
      updated: DateTime.parse(record.updated),
    );
  }

  /// 팩토리 생성자 (fromJson) - 범용 JSON 파싱용
  /// 로컬 저장소(SharedPreferences)나 외부 REST API 등 일반적인 JSON Map을 읽어들일 때 사용합니다.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? '',
      collectionId: json['collectionId'] as String? ?? 'users',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      code: json['code'] as String? ?? '',
      tagId: json['tag_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatar: json['avatar'] as String?,
      department: json['department'] as String? ?? 'Unknown',
      companyId: json['company_id'] as String?,
      companyName: json['companyName'] as String?,

      // boolean 값 파싱 (기본값 설정)
      isApproved: json['is_approved'] as bool? ?? true,
      // 🔥 [수정] JSON 파싱 시에도 role 값을 맵핑합니다.
      role: json['role'] as String? ?? '일반작업자 (Operator)',
      isActive: json['is_active'] as bool? ?? true,
      remarks: json['remarks'] as String? ?? '',

      // 메타데이터 파싱
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : {},

      // 날짜 문자열이 있으면 파싱하고, 없으면 현재 시간으로 방어 코드를 작성합니다.
      created: json['created'] != null
          ? DateTime.tryParse(json['created'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updated: json['updated'] != null
          ? DateTime.tryParse(json['updated'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// toJson 함수
  /// 애플리케이션의 메모리에 있는 객체를 JSON(Map) 형태로 묶어줍니다.
  /// 포켓베이스(DB)로 전송하거나 로컬에 저장할 때 모두 사용됩니다.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'collectionId': collectionId,
      'username': username,
      'email': email,
      'code': code,
      'tag_id': tagId,
      'name': name,
      if (avatar != null) 'avatar': avatar, // 아바타가 있을 때만 포함시킵니다.
      'department': department,
      'company_id': companyId,
      if (companyName != null) 'companyName': companyName,
      'is_approved': isApproved,
      'role': role, // 🔥 role 필드 전송
      'is_active': isActive,
      'remarks': remarks,
      'metadata': {
        ...metadata,
        'last_approval_status': isApproved, // UI 호환용 상태 백업
      },
      // DateTime 객체는 문자열(ISO 8601)로 변환하여 저장합니다.
      'created': created.toIso8601String(),
      'updated': updated.toIso8601String(),
    };
  }

  /// copyWith 함수
  /// 객체의 불변성(Immutability)을 유지하면서 특정 필드값만 변경한 '새로운 복사본'을 만들 때 사용합니다.
  /// 플러터의 상태 관리(State Management)에서 매우 중요하게 쓰이는 패턴입니다.
  UserModel copyWith({
    String? username,
    String? email,
    String? code,
    String? tagId,
    String? name,
    String? avatar,
    String? department,
    String? companyId,
    String? companyName,
    bool? isApproved,
    String? role,
    bool? isActive,
    String? remarks,
    Map<String, dynamic>? metadata,
  }) {
    return UserModel(
      // 파라미터로 받지 않는 고유 필드들은 this. 생략 (unnecessary_this 경고 해결)
      id: id,
      collectionId: collectionId,

      // 파라미터와 클래스 멤버 이름이 같은 경우는 this.를 유지하여 섀도잉 방지
      username: username ?? this.username,
      email: email ?? this.email,
      code: code ?? this.code,
      tagId: tagId ?? this.tagId,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      department: department ?? this.department,
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      isApproved: isApproved ?? this.isApproved,
      role: role ?? this.role, // 🔥 role 속성 유지
      isActive: isActive ?? this.isActive,
      remarks: remarks ?? this.remarks,
      metadata: metadata ?? this.metadata,

      // 타임스탬프 필드들도 this. 생략
      created: created,
      updated: updated,
    );
  }

  /// 사용자의 프로필 이미지(아바타) URL을 생성하여 반환하는 함수입니다.
  /// 이미지 파일명(avatar)이 있으면 포켓베이스 규칙에 맞는 전체 경로를 만들어줍니다.
  String? getImageUrl(String baseUrl, {String thumb = ''}) {
    // 아바타 파일명이 없거나 비어있으면 null을 반환하여 기본 아이콘을 그리도록 유도합니다.
    if (avatar == null || avatar!.isEmpty) {
      return null;
    }

    // 컬렉션 ID가 비어있을 경우를 대비해 기본값 방어 코드를 작성합니다.
    final cid = collectionId.isEmpty ? 'users' : collectionId;

    // 포켓베이스 파일 접근 URL 규칙: {서버주소}/api/files/{컬렉션ID}/{레코드ID}/{파일명}
    String url = "$baseUrl/api/files/$cid/$id/$avatar";

    // 썸네일 옵션이 있다면 URL 뒤에 쿼리스트링으로 붙여줍니다. (예: ?thumb=100x100)
    if (thumb.isNotEmpty) {
      url += "?thumb=$thumb";
    }

    return url;
  }
}