import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async'; // 백그라운드에서 주기적으로 실행되는 타이머를 사용하기 위해 필수입니다.
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // [신규 추가] 중앙 집중식 URL 관리를 위해 추가

import '../theme/app_theme.dart';
import '../core/pocketbase_client.dart';

/// ---------------------------------------------------------------------------
/// [공용 모듈] ERP 시스템 양방향 연동 헬퍼 (ErpSyncHelper)
/// 앱 전체에서 외부 ERP 시스템과 데이터를 주고받는 네트워크 통신을 전담하는 중앙 집중식 클래스입니다.
/// 수동 수신(Fetch), 수동 송신(Push) 기능은 물론, UI 간섭 없는 백그라운드 자동 동기화 기능이 포함되어 있습니다.
///
/// [핵심 변경 사항]
/// 이제 UI 화면에서 전체 API 주소(apiUrl)를 전달할 필요가 없습니다.
/// 'items', 'users' 같은 목적지(endpoint)만 전달하면, 이 클래스가 내부 저장소(SharedPreferences)에서
/// 수신용/송신용 URL을 스스로 판단하여 안전하게 조합한 뒤 통신합니다.
/// ---------------------------------------------------------------------------
class ErpSyncHelper {

  // 앱이 켜져 있는 동안 백그라운드에서 주기적으로 실행될 타이머 객체입니다.
  static Timer? _backgroundTimer;

  /// -------------------------------------------------------------------------
  /// [내부 유틸리티] 안전한 URL 조합기 (_buildUrl)
  /// 슬래시(/)가 중복되거나 누락되어 발생하는 404 네트워크 에러를 원천적으로 차단합니다.
  /// type: 'receive'(데이터 조회/수신) 또는 'send'(데이터 등록/송신)
  /// endpoint: 목적지 (예: 'items')
  /// -------------------------------------------------------------------------
  static Future<String> _buildUrl(String type, String endpoint) async {
    final prefs = await SharedPreferences.getInstance();
    String baseUrl = '';

    // 1. 요청 타입에 따라 환경설정에서 저장된 기본 URL(Base URL)을 가져옵니다.
    if (type == 'receive') {
      baseUrl = prefs.getString('pref_erp_receive_url') ?? 'https://api.erp-system.com/v1/read';
    } else {
      baseUrl = prefs.getString('pref_erp_send_url') ?? 'https://api.erp-system.com/v1/write';
    }

    // 2. URL 문자열 조작: 기본 주소 끝의 슬래시와 목적지 앞의 슬래시를 정리하여 깔끔하게 이어 붙입니다.
    String cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    String cleanEndpoint = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;

    return '$cleanBase/$cleanEndpoint';
  }

  /// =========================================================================
  /// [1] 수동 수신 (Fetch & Sync) : 외부 ERP -> 우리 DB (UI 팝업 포함)
  /// 사용자가 직접 화면에서 [데이터 연동] 버튼을 눌렀을 때 실행됩니다.
  /// 팝업 다이얼로그로 의사를 묻고, 로딩 화면을 띄운 뒤 데이터를 가져와 로컬 DB에 저장합니다.
  /// =========================================================================
  static Future<void> fetchAndSync({
    required BuildContext context,
    required ThemeData theme,
    required String moduleName,
    required String endpoint, // [변경됨] 전체 apiUrl이 아닌 목적지(endpoint)만 입력받습니다.
    required String targetCollection,
    required Map<String, dynamic> Function(Map<String, dynamic> erpItem) dataMapper,
    required VoidCallback onLoadingStart,
    required VoidCallback onLoadingComplete,
    required VoidCallback onSuccess,
  }) async {
    final bool isDarkMode = theme.brightness == Brightness.dark;

    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
              title: AppTheme.dialogTitle("ERP $moduleName 수신", Icons.download_rounded, color: AppTheme.primary),
              content: Text(
                  "외부 시스템에서 최신 [$moduleName] 데이터를 가져와 자동으로 등록하시겠습니까?",
                  style: const TextStyle(fontFamily: AppTheme.fontPretendard, height: 1.5)
              ),
              actions: [
                AppTheme.actionButton(
                    label: "취소",
                    color: Colors.transparent,
                    textColor: AppTheme.labelColor(isDarkMode),
                    onPressed: () => Navigator.pop(ctx)
                ),
                AppTheme.actionButton(
                    label: "데이터 가져오기",
                    color: AppTheme.primary,
                    onPressed: () async {
                      Navigator.pop(ctx); // 다이얼로그 닫기

                      onLoadingStart(); // 호출한 화면의 로딩 스피너 켜기

                      try {
                        // [핵심 로직] 내부 유틸리티를 사용하여 완벽한 수신용 URL을 생성합니다.
                        final String fullUrl = await _buildUrl('receive', endpoint);
                        final Uri apiUri = Uri.parse(fullUrl);

                        final http.Response response = await http.get(apiUri);

                        if (response.statusCode == 200) {
                          final String responseBody = utf8.decode(response.bodyBytes); // 한글 깨짐 방지
                          final dynamic decodedData = jsonDecode(responseBody);

                          List<dynamic> erpDataList = [];
                          if (decodedData is List) {
                            erpDataList = decodedData;
                          } else if (decodedData is Map<String, dynamic>) {
                            erpDataList = [decodedData];
                          }

                          // 매퍼 함수를 통해 외부 데이터를 우리 시스템 규격으로 변환하여 순차 저장합니다.
                          for (var item in erpDataList) {
                            final Map<String, dynamic> bodyData = dataMapper(item as Map<String, dynamic>);
                            await pb.collection(targetCollection).create(body: bodyData);
                          }

                          // 통신 성공 알림 (미니멀리즘 디자인 적용)
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('✅ 시스템에서 ${erpDataList.length}건의 데이터를 성공적으로 가져왔습니다.', style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
                              elevation: 0,
                            ));
                          }

                          onSuccess(); // 호출한 화면의 데이터 목록 새로고침
                        } else {
                          throw Exception('서버 응답 오류 (상태 코드: ${response.statusCode})');
                        }
                      } catch (e, stackTrace) {
                        // 예외 발생 시 개발자 확인용 디버그 로그 및 사용자 알림
                        debugPrint('\n=============================================================');
                        debugPrint('🚨 [데이터 수신 실패 - $moduleName] 🚨');
                        debugPrint('오류 내용: $e');
                        debugPrint('발생 위치:\n$stackTrace');
                        debugPrint('=============================================================\n');

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('❌ 데이터 연동 실패: $e', style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white, fontWeight: FontWeight.bold)),
                            backgroundColor: Colors.redAccent,
                            duration: const Duration(seconds: 7),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      } finally {
                        onLoadingComplete(); // 성공/실패 여부에 상관없이 로딩 스피너 끄기
                      }
                    }
                )
              ]
          );
        }
    );
  }

  /// =========================================================================
  /// [2] 송신 (Push to ERP) : 우리 시스템 -> 외부 ERP
  /// 우리 시스템에서 발생한 데이터(예: 물품 출고, RFID 인원 체크)를 외부로 전송합니다.
  /// =========================================================================
  static Future<bool> pushToERP({
    required String endpoint, // [변경됨] 전체 apiUrl이 아닌 송신용 목적지(endpoint)만 입력받습니다.
    required Map<String, dynamic> payload,
    String httpMethod = 'POST',
    Map<String, String>? headers,
  }) async {
    try {
      // [핵심 로직] 내부 유틸리티를 사용하여 완벽한 송신용 URL을 생성합니다.
      final String fullUrl = await _buildUrl('send', endpoint);
      final Uri apiUri = Uri.parse(fullUrl);

      final Map<String, String> requestHeaders = {
        'Content-Type': 'application/json; charset=UTF-8',
      };

      if (headers != null) {
        requestHeaders.addAll(headers);
      }

      final String jsonBody = jsonEncode(payload);
      http.Response response;

      // HTTP 메서드에 따른 분기 처리
      if (httpMethod.toUpperCase() == 'POST') {
        response = await http.post(apiUri, headers: requestHeaders, body: jsonBody);
      } else if (httpMethod.toUpperCase() == 'PUT') {
        response = await http.put(apiUri, headers: requestHeaders, body: jsonBody);
      } else {
        throw Exception('지원하지 않는 HTTP 메서드입니다: $httpMethod');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ [데이터 송신 성공] 대상: $fullUrl');
        return true;
      } else {
        debugPrint('❌ [데이터 송신 실패] 상태 코드: ${response.statusCode}, 응답: ${response.body}');
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('\n=============================================================');
      debugPrint('🚨 [시스템으로 데이터 전송 실패] 🚨');
      debugPrint('오류 내용: $e');
      debugPrint('발생 위치:\n$stackTrace');
      debugPrint('=============================================================\n');
      return false;
    }
  }

  /// =========================================================================
  /// [3] 백그라운드 조용한 수신 (Silent Sync) : UI 간섭 없음
  /// 다이얼로그 팝업이나 화면 로딩 없이, 보이지 않는 곳에서 데이터를 갱신합니다.
  /// 자동 동기화 타이머에서 주로 호출하여 사용합니다.
  /// =========================================================================
  static Future<bool> syncSilent({
    required String endpoint, // [변경됨] 수신용 목적지(endpoint)만 입력받습니다.
    required String targetCollection,
    required Map<String, dynamic> Function(Map<String, dynamic> erpItem) dataMapper,
  }) async {
    try {
      // 수신용 URL 자동 조합
      final String fullUrl = await _buildUrl('receive', endpoint);
      final Uri apiUri = Uri.parse(fullUrl);

      final http.Response response = await http.get(apiUri);

      if (response.statusCode == 200) {
        final String responseBody = utf8.decode(response.bodyBytes);
        final dynamic decodedData = jsonDecode(responseBody);

        List<dynamic> erpDataList = [];
        if (decodedData is List) {
          erpDataList = decodedData;
        } else if (decodedData is Map<String, dynamic>) {
          erpDataList = [decodedData];
        }

        for (var item in erpDataList) {
          final Map<String, dynamic> bodyData = dataMapper(item as Map<String, dynamic>);

          // 실무 권장 사항: 무조건 Create(생성) 대신, 데이터 중복을 피하기 위해
          // 고유 ID를 비교하여 없으면 Create, 있으면 Update하는 Upsert 로직을 적용하는 것이 좋습니다.
          await pb.collection(targetCollection).create(body: bodyData);
        }
        return true;
      } else {
        debugPrint('백그라운드 통신 오류: 상태 코드 ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('백그라운드 통신 실패: $e');
      return false;
    }
  }

  /// =========================================================================
  /// [4] 자동 동기화 시작 (Start Auto Sync)
  /// 앱 구동 시 한 번 호출해 두면, 지정한 주기(Interval)마다 백그라운드 수신(syncSilent)을 무한 반복합니다.
  /// 키오스크와 같이 항상 켜져 있는 시스템에 필수적인 기능입니다.
  /// =========================================================================
  static void startAutoSync({
    required Duration interval,       // 얼마나 자주 실행할 것인지 (예: 5분마다)
    required String endpoint,         // [변경됨] 수신할 데이터의 목적지
    required String targetCollection, // 데이터를 저장할 로컬 데이터베이스 컬렉션명
    required Map<String, dynamic> Function(Map<String, dynamic> erpItem) dataMapper,
  }) {
    // 이미 타이머가 돌고 있다면 중복 실행을 막기 위해 무시합니다.
    if (_backgroundTimer != null && _backgroundTimer!.isActive) {
      debugPrint('ℹ️ 자동 동기화 타이머가 이미 실행 중입니다.');
      return;
    }

    debugPrint('▶️ 자동 동기화 타이머를 시작합니다. (주기: ${interval.inMinutes}분)');

    // 지정된 시간 간격마다 내부 콜백 함수가 실행됩니다.
    _backgroundTimer = Timer.periodic(interval, (Timer timer) async {
      debugPrint('⏳ [백그라운드] 데이터 자동 동기화 시작...');

      bool isSuccess = await syncSilent(
          endpoint: endpoint,
          targetCollection: targetCollection,
          dataMapper: dataMapper
      );

      if (isSuccess) {
        debugPrint('✅ [백그라운드] 데이터 자동 동기화 완료!');
      } else {
        debugPrint('❌ [백그라운드] 데이터 자동 동기화 실패!');
      }
    });
  }

  /// =========================================================================
  /// [5] 자동 동기화 종료 (Stop Auto Sync)
  /// 시스템 자원 관리를 위해 앱이 백그라운드로 가거나 종료될 때 호출하여 타이머를 해제합니다.
  /// =========================================================================
  static void stopAutoSync() {
    if (_backgroundTimer != null && _backgroundTimer!.isActive) {
      _backgroundTimer!.cancel(); // 타이머 작동을 즉시 멈춥니다.
      _backgroundTimer = null;    // 메모리에서 객체를 초기화합니다.
      debugPrint('⏹️ 자동 동기화 타이머가 중지되었습니다.');
    }
  }
}