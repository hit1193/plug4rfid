import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import '../core/pocketbase_client.dart';

/// ---------------------------------------------------------------------------
/// [인증 및 세션 전역 상태 제공자 (AuthProvider)]
/// C++Builder의 DataModule 역할을 수행하며, 로그인/로그아웃 등 데이터베이스 통신만 전담합니다.
/// UI 화면에서는 이 클래스의 함수만 호출하여 결과를 받아보게 됩니다.
/// ---------------------------------------------------------------------------
class AuthProvider extends ChangeNotifier {
  final PocketBase _pb = pb; // 전역 PocketBase 클라이언트

  bool _isLoading = false;
  String? _currentUser;
  String? _currentUserId; // 🔥 [추가] 현재 로그인한 사용자의 고유 ID
  bool _isAdmin = false;
  String _role = '일반작업자 (Operator)';

  // --- 외부 노출용 Getter ---
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _pb.authStore.isValid;
  bool get isAdmin => _isAdmin;
  String get currentUser => _currentUser ?? "Unknown";
  String get currentUserId => _currentUserId ?? ""; // 🔥 [추가] 화면에서 내 정보인지 식별하기 위해 노출
  String get role => _role;

  AuthProvider() {
    // 앱 시작 시, 기존 로그인 세션이 남아있는지 확인하여 자동 복원합니다.
    _checkSession();
  }

  void _checkSession() {
    if (_pb.authStore.isValid) {
      final model = _pb.authStore.model;
      if (model is RecordModel) {
        // 컬렉션 이름이 _superusers 이면 최고 시스템 관리자로 판별합니다.
        _isAdmin = model.collectionName == '_superusers';

        _currentUser = model.getStringValue('name');
        if (_currentUser!.isEmpty) {
          _currentUser = model.getStringValue('email');
        }

        _currentUserId = model.id; // 🔥 현재 사용자 ID 저장

        // DB 기본 필드인 'role'을 다이렉트로 파싱합니다.
        if (_isAdmin) {
          _role = '시스템 최고관리자';
        } else {
          String fetchedRole = model.getStringValue('role');

          if (fetchedRole.isNotEmpty) {
            _role = fetchedRole;
          } else {
            // 과거 버전 호환성
            final dynamic meta = model.data['metadata'];
            if (meta is Map<String, dynamic> && meta.containsKey('grade') && meta['grade'].toString().trim().isNotEmpty) {
              _role = meta['grade'].toString().trim();
            } else {
              _role = '일반작업자 (Operator)';
            }
          }
        }
      } else if (model is AdminModel) {
        _isAdmin = true;
        _currentUser = model.email;
        _currentUserId = model.id; // 🔥 현재 사용자 ID 저장
        _role = '시스템 최고관리자';
      }
    } else {
      _currentUser = null;
      _currentUserId = null; // 🔥 초기화
      _isAdmin = false;
      _role = '일반사용자';
    }
  }

  /// ---------------------------------------------------------------------------
  /// [스마트 통합 로그인 처리]
  /// ---------------------------------------------------------------------------
  Future<String> login(String loginId, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      String safeUserId = loginId.trim().toLowerCase();

      String fallbackEmail = safeUserId;
      if (!safeUserId.contains('@')) {
        fallbackEmail = '$safeUserId@plug4rfid.local';
      }

      try {
        await _pb.collection('users').authWithPassword(fallbackEmail, password);
        _checkSession();
        return "";

      } catch (e1) {
        try {
          await _pb.collection('users').authWithPassword(safeUserId, password);
          _checkSession();
          return "";
        } catch (e2) {
          try {
            await _pb.collection('_superusers').authWithPassword(loginId.trim(), password);
            _checkSession();
            return "";

          } catch (e3) {
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
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ---------------------------------------------------------------------------
  /// [로그아웃 처리]
  /// ---------------------------------------------------------------------------
  void logout() {
    _pb.authStore.clear();
    _currentUser = null;
    _currentUserId = null; // 🔥 초기화
    _isAdmin = false;
    _role = '일반사용자';
    notifyListeners();
  }
}