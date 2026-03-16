import 'dart:convert';
import 'package:flutter/foundation.dart'; // debugPrint를 사용하기 위해 추가
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // 로컬 설정 저장을 위해 추가

// -----------------------------------------------------------------------------
// [RFID API 통신 서비스 (RfidApiService)]
// 온라인(클라우드), 사내 폐쇄망(로컬 네트워크), 단독망 등 다양한 납품 환경에
// 유연하게 대응하기 위해 동적 URL 및 회사코드(Company Code) 헤더 주입 기능을 갖춘
// 엔터프라이즈급 REST API 전담 모듈입니다.
// -----------------------------------------------------------------------------
class RfidApiService {
  // 데이터를 조회할 때 사용하는 기본 URL (ERP 수신용)
  String receiveBaseUrl;

  // 데이터를 전송할 때 사용하는 기본 URL (ERP 송신용)
  String sendBaseUrl;

  // 고객사를 식별하는 회사 코드 (멀티 테넌트 및 라이선스 검증용)
  String companyCode;

  // ---------------------------------------------------------------------------
  // 생성자 (Constructor)
  // 초기화 시 기본값을 받을 수 있도록 하되, 이후 loadSettingsFromLocal()를 통해
  // 환경설정 창(SettingsPage)에서 저장된 값으로 덮어쓸 수 있도록 설계되었습니다.
  // ---------------------------------------------------------------------------
  RfidApiService({
    required this.receiveBaseUrl,
    required this.sendBaseUrl,
    this.companyCode = 'DEFAULT_COMP', // 기본 회사 코드
  });

  // ---------------------------------------------------------------------------
  // [환경 설정 로드]
  // 앱 실행 시 (main.dart) 가장 먼저 호출됩니다.
  // 기기 로컬에 저장된 URL과 회사코드 정보를 불러와 API 서비스에 즉시 반영합니다.
  // ---------------------------------------------------------------------------
  Future<void> loadSettingsFromLocal() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // SettingsPage에서 저장하는 키값과 정확히 일치하여 동기화됩니다.
      receiveBaseUrl = prefs.getString('pref_erp_receive_url') ?? receiveBaseUrl;
      sendBaseUrl = prefs.getString('pref_erp_send_url') ?? sendBaseUrl;
      companyCode = prefs.getString('pref_company_code') ?? companyCode;

      debugPrint('✅ API 설정 로드 완료 - 회사코드: $companyCode');
      debugPrint('➡️ ERP 수신 URL: $receiveBaseUrl');
      debugPrint('➡️ ERP 송신 URL: $sendBaseUrl');
    } catch (e) {
      debugPrint('❌ API 설정 로드 중 오류 발생: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // [환경 설정 저장]
  // 납품 현장에서 관리자가 새로운 IP나 회사코드를 입력하면 로컬에 영구 저장합니다.
  // ---------------------------------------------------------------------------
  Future<bool> saveSettingsToLocal({
    required String newReceiveUrl,
    required String newSendUrl,
    required String newCompanyCode,
  }) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // 로컬 디바이스에 값 영구 보관
      await prefs.setString('pref_erp_receive_url', newReceiveUrl);
      await prefs.setString('pref_erp_send_url', newSendUrl);
      await prefs.setString('pref_company_code', newCompanyCode);

      // 현재 메모리에 올라가 있는 서비스 객체의 상태도 즉시 업데이트
      receiveBaseUrl = newReceiveUrl;
      sendBaseUrl = newSendUrl;
      companyCode = newCompanyCode;

      return true;
    } catch (e) {
      debugPrint('❌ API 설정 저장 중 오류 발생: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // [데이터 조회 (GET)]
  // 주어진 엔드포인트(endpoint)로 GET 요청을 보내어 데이터를 가져옵니다.
  // 반환값: 성공 시 Map 형식의 JSON 데이터, 실패 시 null
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> fetchData(String endpoint) async {
    // URL이 비어있는 등 설정이 안 된 완전 오프라인 상태를 방어합니다.
    if (receiveBaseUrl.isEmpty) {
      debugPrint('⚠️ 수신(조회) 서버 URL이 설정되지 않았습니다. (오프라인 모드 대기)');
      return null;
    }

    final String requestUrl = '$receiveBaseUrl$endpoint';

    try {
      // http.get을 사용하여 서버에 데이터를 요청합니다.
      final http.Response response = await http.get(
        Uri.parse(requestUrl),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          // [핵심 보안] 서버가 어떤 고객사의 요청인지 식별할 수 있도록 헤더에 주입
          'X-Company-Code': companyCode,
        },
      ).timeout(
        // 무한정 대기(프리징) 방지를 위해 10초 타임아웃 설정
        const Duration(seconds: 10),
      );

      // HTTP 상태 코드가 200(성공)인 경우
      if (response.statusCode == 200) {
        // 수신된 JSON 문자열을 플러터에서 사용하기 쉬운 Map 형태로 변환하여 반환
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('데이터 조회 실패: 서버 상태 코드 ${response.statusCode}');
        return null;
      }
    } catch (error) {
      // 네트워크 끊김, 타임아웃 등의 예외 상황을 안전하게 잡아냅니다.
      debugPrint('데이터 조회 중 오류 발생 (폐쇄망 연결 확인 필요): $error');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // [데이터 전송 (POST)]
  // 주어진 엔드포인트(endpoint)로 POST 요청을 보내어 데이터를 저장/전송합니다.
  // 반환값: 전송 성공 시 true, 실패 시 false
  // ---------------------------------------------------------------------------
  Future<bool> sendData(String endpoint, Map<String, dynamic> data) async {
    // 송신 URL이 없는 경우 전송을 차단하여 안전성을 확보합니다.
    if (sendBaseUrl.isEmpty) {
      debugPrint('⚠️ 송신(전송) 서버 URL이 설정되지 않았습니다. (데이터가 로컬에만 보관됩니다)');
      return false;
    }

    final String requestUrl = '$sendBaseUrl$endpoint';

    try {
      // http.post를 사용하여 서버에 데이터를 전송합니다.
      final http.Response response = await http.post(
        Uri.parse(requestUrl),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          // [핵심 보안] 전송할 때도 반드시 회사 코드를 동봉하여 데이터 소유주 명확화
          'X-Company-Code': companyCode,
        },
        // Map 형태의 데이터를 JSON 문자열로 직렬화(Serialize)하여 전송
        body: jsonEncode(data),
      ).timeout(
        const Duration(seconds: 10),
      );

      // HTTP 상태 코드가 200(성공) 또는 201(새로운 리소스 생성됨)인 경우 성공
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        debugPrint('데이터 전송 실패: 상태 코드 ${response.statusCode}, 서버 응답: ${response.body}');
        return false;
      }
    } catch (error) {
      debugPrint('데이터 전송 중 네트워크 오류 발생: $error');
      return false;
    }
  }
}