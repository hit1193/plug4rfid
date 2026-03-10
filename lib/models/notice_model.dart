import 'package:pocketbase/pocketbase.dart';

/// ---------------------------------------------------------------------------
/// [데이터 모델] 공지사항 (NoticeModel)
/// 공지사항 데이터를 담아두는 틀(클래스)입니다.
/// PocketBase 연동에 최적화하여 RecordModel 파싱 및 JSON 변환 기능을 완벽히 갖췄습니다.
/// ---------------------------------------------------------------------------
class NoticeModel {
  // ---------------------------------------------------------------------------
  // 1. 포켓베이스 시스템 기본 필드
  // ---------------------------------------------------------------------------
  final String id;           // 공지사항 고유 식별자 (문서 ID)
  final DateTime created;    // 작성 일시 (포켓베이스 기본 필드명 'created'로 통일)
  final DateTime updated;    // 수정 일시 (포켓베이스 기본 필드명 'updated')

  // ---------------------------------------------------------------------------
  // 2. 공지사항 커스텀 필드
  // ---------------------------------------------------------------------------
  final String title;        // 공지사항 제목
  final String content;      // 공지사항 상세 내용
  final String author;       // 작성자 (또는 부서명)
  final bool isImportant;    // 중요 공지 여부 (상단 고정 및 빨간색 강조용)
  final int viewCount;       // 조회수

  // [수정] DB에 미리 만들어두신 'attachments' 필드명에 맞추어 변수명을 변경했습니다.
  final String attachment;

  /// 생성자: 객체를 만들 때 필요한 값들을 받아옵니다.
  NoticeModel({
    required this.id,
    required this.title,
    required this.content,
    required this.author,
    required this.created,
    required this.updated,
    this.isImportant = false,
    this.viewCount = 0,
    this.attachment = '',     // 기본값은 빈 문자열(이미지 없음)로 설정합니다.
  });

  /// [핵심 1] 팩토리 생성자 (fromRecord) - 포켓베이스 조회용
  factory NoticeModel.fromRecord(RecordModel record) {
    // [견고한 방어 코드]
    // PocketBase의 File 필드는 설정에 따라 문자열(단일 파일)이거나 배열(다중 파일)일 수 있습니다.
    // 어떤 형태로 데이터가 넘어오더라도 앱이 뻗지 않고 첫 번째 파일명을 안전하게 가져오도록 처리합니다.
    String parsedAttachment = '';
    var rawAttachmentData = record.data['attachments'];

    if (rawAttachmentData is List && rawAttachmentData.isNotEmpty) {
      // 다중 파일 설정일 경우 첫 번째 파일의 이름을 사용합니다.
      parsedAttachment = rawAttachmentData.first.toString();
    } else if (rawAttachmentData is String) {
      // 단일 파일 설정일 경우 그대로 사용합니다.
      parsedAttachment = rawAttachmentData;
    }

    return NoticeModel(
      id: record.id,
      title: record.getStringValue('title', '제목 없음'),
      content: record.getStringValue('content', '내용 없음'),
      author: record.getStringValue('author', '관리자'),
      isImportant: record.getBoolValue('is_important', false),
      viewCount: record.getIntValue('view_count', 0),
      // 파싱된 파일명을 모델에 담아줍니다.
      attachment: parsedAttachment,
      created: DateTime.tryParse(record.created) ?? DateTime.now(),
      updated: DateTime.tryParse(record.updated) ?? DateTime.now(),
    );
  }

  /// [핵심 2] toJson 함수 - 포켓베이스 저장/수정용
  /// (주의: 파일 업로드는 일반 JSON과 별도로 처리되므로 attachment는 여기서 제외합니다)
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'content': content,
      'author': author,
      'is_important': isImportant,
      'view_count': viewCount,
    };
  }

  /// 날짜를 'YYYY-MM-DD' 형태의 보기 편한 문자열로 바꿔주는 보조 함수입니다.
  String getFormattedDate() {
    String year = created.year.toString();
    String month = created.month.toString().padLeft(2, '0');
    String day = created.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// [기능 추가] PocketBase 규칙에 맞추어 실제 이미지를 불러올 수 있는 전체 URL을 생성합니다.
  /// 포켓베이스 파일 URL 규칙: http://서버주소/api/files/컬렉션명/레코드ID/파일명
  String getImageUrl(String baseUrl) {
    if (attachment.isEmpty) return '';
    return '$baseUrl/api/files/notices/$id/$attachment';
  }
}