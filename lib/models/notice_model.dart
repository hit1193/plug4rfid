/// ---------------------------------------------------------------------------
/// [데이터 모델] 공지사항 (NoticeModel)
/// 공지사항 데이터를 담아두는 틀(클래스)입니다.
/// 화면(UI)과 데이터를 분리하는 아키텍처 원칙에 따라 독립된 파일로 작성되었습니다.
/// 나중에 PocketBase 등의 DB에서 데이터를 가져올 때 이 틀에 맞춰서 변환합니다.
/// ---------------------------------------------------------------------------
class NoticeModel {
  final String id;           // 공지사항 고유 식별자 (문서 ID)
  final String title;        // 공지사항 제목
  final String content;      // 공지사항 상세 내용
  final String author;       // 작성자 (또는 부서명)
  final DateTime createdAt;  // 작성 일시
  final bool isImportant;    // 중요 공지 여부 (상단 고정 및 빨간색 강조용)
  final int viewCount;       // 조회수

  /// 생성자: 객체를 만들 때 필요한 값들을 받아옵니다.
  NoticeModel({
    required this.id,
    required this.title,
    required this.content,
    required this.author,
    required this.createdAt,
    this.isImportant = false, // 기본값은 '일반 공지(false)'로 설정합니다.
    this.viewCount = 0,       // 기본 조회수는 0입니다.
  });

  /// 데이터베이스(Map 형태)에서 데이터를 읽어와서 NoticeModel 객체로 변환하는 팩토리 함수입니다.
  factory NoticeModel.fromMap(Map<String, dynamic> map, String documentId) {
    return NoticeModel(
      id: documentId,
      title: map['title'] ?? '제목 없음',
      content: map['content'] ?? '내용 없음',
      author: map['author'] ?? '관리자',
      // 데이터베이스의 날짜 형식을 Dart의 DateTime으로 안전하게 변환합니다.
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'].toString())
          : DateTime.now(),
      isImportant: map['isImportant'] ?? false,
      viewCount: map['viewCount'] ?? 0,
    );
  }

  /// NoticeModel 객체를 데이터베이스에 저장하기 좋은 Map 형태로 변환하는 함수입니다.
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'content': content,
      'author': author,
      'createdAt': createdAt.toIso8601String(),
      'isImportant': isImportant,
      'viewCount': viewCount,
    };
  }

  /// 날짜를 'YYYY-MM-DD' 형태의 보기 편한 문자열로 바꿔주는 보조 함수입니다.
  /// 외부 패키지 없이 기본 기능만으로 깔끔하게 처리하여 의존성을 낮춥니다.
  String getFormattedDate() {
    String year = createdAt.year.toString();
    String month = createdAt.month.toString().padLeft(2, '0');
    String day = createdAt.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}