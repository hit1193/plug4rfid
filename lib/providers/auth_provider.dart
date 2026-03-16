import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import '../core/pocketbase_client.dart';

/// ---------------------------------------------------------------------------
/// [인증 및 세션 전역 상태 제공자 (AuthProvider)]
/// C++Builder의 DataModule 역할을 수행하며, 로그인/로그아웃 등 DB 통신만 전담합니다.
/// ---------------------------------------------------------------------------
class AuthProvider extends ChangeNotifier {
  final PocketBase _pb = pb; // 전역 PocketBase 클라이언트

  bool _isLoading = false;
  String? _currentUser;
  bool _isAdmin = false;

  // --- 외부 노출용 Getter ---
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _pb.authStore.isValid;
  bool get isAdmin => _isAdmin;
  String get currentUser => _currentUser ?? "Unknown";

  AuthProvider() {
    // 앱 시작 시, 기존 로그인 세션이 남아있는지 확인하여 자동 복원합니다.
    _checkSession();
  }

  void _checkSession() {
    if (_pb.authStore.isValid) {
      final model = _pb.authStore.model;
      if (model is RecordModel) {
        // 컬렉션 이름이 _superusers 이면 최고 관리자로 판별합니다.
        _isAdmin = model.collectionName == '_superusers';

        _currentUser = model.getStringValue('name');
        if (_currentUser!.isEmpty) {
          _currentUser = model.getStringValue('email');
        }
      } else if (model is AdminModel) {
        _isAdmin = true;
        _currentUser = model.email;
      }
    }
  }

  /// ---------------------------------------------------------------------------
  /// [스마트 통합 로그인 처리]
  /// 포켓베이스의 '이메일 필수' 정책을 우회하기 위해 강제로 이메일 포맷을 만들어 찌릅니다.
  /// ---------------------------------------------------------------------------
  Future<String> login(String loginId, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 🔥 [핵심 보정 로직] 태블릿/폰 키패드의 첫 글자 자동 대문자 현상 방어
      String safeUserId = loginId.trim().toLowerCase();

      // 🔥 [초강력 우회 로직] 포켓베이스가 'email' 인증만 허용하는 경우를 위한 자동 치환
      // UserProvider에서 인원 등록 시 이메일을 '아이디@plug4rfid.local'로 강제 생성했으므로,
      // DB 설정을 건드릴 필요 없이 로그인할 때 이메일 형식으로 자동 완성해서 찔러넣습니다!
      String fallbackEmail = safeUserId;
      if (!safeUserId.contains('@')) {
        fallbackEmail = '$safeUserId@plug4rfid.local';
      }

      // 1단계: 일반 사용자(users 컬렉션) '이메일 형식'으로 로그인 시도 (가장 유력함)
      try {
        await _pb.collection('users').authWithPassword(fallbackEmail, password);
        _checkSession();
        return ""; // 성공 시 빈 문자열 반환

      } catch (e1) {
        // 2단계: 혹시나 username 인증이 켜져있을 경우를 대비해 '아이디 원본'으로 재시도
        try {
          await _pb.collection('users').authWithPassword(safeUserId, password);
          _checkSession();
          return "";
        } catch (e2) {
          // 3단계: 일반 계정이 아니면 최고 관리자(_superusers)로 재시도
          try {
            await _pb.collection('_superusers').authWithPassword(loginId.trim(), password);
            _checkSession();
            return ""; // 성공 시 빈 문자열 반환

          } catch (e3) {
            // 4단계: 양쪽 모두 실패 시, 구체적인 에러 메시지 추출
            debugPrint("❌ 이메일 변환 로그인 실패: $e1");
            debugPrint("❌ 일반 아이디 로그인 실패: $e2");
            debugPrint("❌ 관리자 계정 로그인 실패: $e3");

            if (e1 is ClientException) {
              final errorMsg = e1.response['message'] ?? '';
              if (errorMsg.contains('Failed to authenticate')) {
                return "아이디 또는 비밀번호가 일치하지 않습니다.\n(신규 등록 시 입력한 '로그인 아이디'가 맞는지 확인해 주세요)";
              }
              return "인증 실패: $errorMsg";
            }
            return "데이터베이스에 접근할 수 없습니다. (네트워크 확인)";
          }
        }
      }
    } finally {
      // 성공/실패 여부에 상관없이 로딩 상태를 해제합니다.
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ---------------------------------------------------------------------------
  /// [로그아웃 처리]
  /// 로컬에 저장된 토큰을 파기하고 세션을 초기화합니다.
  /// ---------------------------------------------------------------------------
  void logout() {
    _pb.authStore.clear();
    _currentUser = null;
    _isAdmin = false;
    notifyListeners();
  }
}