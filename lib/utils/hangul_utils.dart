/// 한글 초성 추출 및 검색을 위한 유틸리티 클래스
class HangulUtils {
  static const List<String> _choseongList = [
    'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
    'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'
  ];

  /// 텍스트에서 초성만 추출 (예: "홍길동" -> "ㅎㄱㄷ")
  static String getChoseong(String text) {
    String result = "";
    for (int i = 0; i < text.length; i++) {
      int code = text.codeUnitAt(i) - 0xAC00;
      if (code >= 0 && code <= 11172) {
        result += _choseongList[code ~/ 588];
      } else {
        result += text[i];
      }
    }
    return result;
  }

  /// 초성 검색 및 일반 검색 포함 여부 확인
  static bool matches(String query, String target) {
    if (query.isEmpty) return true;
    final lowerTarget = target.toLowerCase();
    final lowerQuery = query.toLowerCase();

    // 1. 일반 텍스트 포함 검색
    if (lowerTarget.contains(lowerQuery)) return true;

    // 2. 초성 일치 검색
    String targetChoseong = getChoseong(target);
    if (targetChoseong.contains(query)) return true;

    return false;
  }
}