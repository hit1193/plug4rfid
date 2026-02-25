import 'package:pocketbase/pocketbase.dart';

/// [서비스] PocketBase 클라이언트 싱글톤
/// C++Builder의 DataModule과 유사한 역할을 수행합니다.
class PBService {
  static final pb = PocketBase('http://127.0.0.1:8090');

  // 컬렉션 이름 정의
  static const String collectionPeople = 'people';
  static const String collectionDevices = 'devices';
}