import 'package:pocketbase/pocketbase.dart';

/// RFID 인원 관리 시스템을 위한 데이터 모델 클래스 (단일 객체: Person)
/// PocketBase의 'persons' 컬렉션 규격에 맞추어 업데이트되었습니다.
class Person {
  final String id;
  final String collectionId; // PocketBase 컬렉션 ID (URL 생성용)
  final String code;         // UNIQUE INDEX (사번/코드)
  final String tagId;        // UNIQUE INDEX (RFID 태그 ID)
  final String name;         // 성명
  final String? image;       // 파일명
  final Map<String, dynamic> metadata; // JSON 형식의 추가 정보
  final DateTime created;
  final DateTime updated;

  Person({
    required this.id,
    this.collectionId = 'persons', // 컬렉션 명칭: persons
    required this.code,
    required this.tagId,
    required this.name,
    this.image,
    this.metadata = const {},
    required this.created,
    required this.updated,
  });

  /// PocketBase의 RecordModel을 받아 Person 객체로 변환하는 생성자
  factory Person.fromRecord(RecordModel record) {
    return Person(
      id: record.id,
      collectionId: record.collectionId,
      code: record.getStringValue('code'),
      tagId: record.getStringValue('tag_id'),
      name: record.getStringValue('name'),
      image: record.getStringValue('image'),
      metadata: record.data['metadata'] is Map<String, dynamic>
          ? record.data['metadata'] as Map<String, dynamic>
          : {},
      created: DateTime.parse(record.created),
      updated: DateTime.parse(record.updated),
    );
  }

  /// PocketBase 서버에 데이터를 전송하거나 업데이트할 때 사용하는 Map 변환
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'tag_id': tagId,
      'name': name,
      if (image != null) 'image': image,
      'metadata': metadata,
    };
  }

  /// 객체의 데이터 일부만 수정할 때 사용하는 함수 (C++ 복사 생성자 개념)
  Person copyWith({
    String? code,
    String? tagId,
    String? name,
    String? image,
    Map<String, dynamic>? metadata,
  }) {
    return Person(
      id: id,
      collectionId: collectionId,
      code: code ?? this.code,
      tagId: tagId ?? this.tagId,
      name: name ?? this.name,
      image: image ?? this.image,
      metadata: metadata ?? this.metadata,
      created: created,
      updated: updated,
    );
  }

  /// 이미지 파일의 전체 URL을 생성하는 헬퍼 함수
  String? getImageUrl(String baseUrl, {String thumb = ''}) {
    if (image == null || image!.isEmpty) {
      return null;
    }

    // 기본값인 'persons'를 사용하여 경로를 생성합니다.
    final cid = collectionId.isEmpty ? 'persons' : collectionId;
    String url = "$baseUrl/api/files/$cid/$id/$image";
    if (thumb.isNotEmpty) {
      url += "?thumb=$thumb";
    }
    return url;
  }
}