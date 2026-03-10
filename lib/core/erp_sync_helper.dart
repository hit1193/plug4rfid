import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async'; // [신규 추가] 백그라운드 타이머(TTimer 역할)를 사용하기 위해 필수입니다.
import 'package:http/http.dart' as http;

import '../theme/app_theme.dart';
import '../core/pocketbase_client.dart';

/// ---------------------------------------------------------------------------
/// [공용 모듈] ERP 시스템 양방향 연동 헬퍼 (ErpSyncHelper)
/// 앱 전체에서 외부 ERP 시스템과 데이터를 주고받는 통신을 전담하는 클래스입니다.
/// 수동 수신(Fetch), 수동 송신(Push) 기능은 물론,
/// [신규] UI 간섭 없이 백그라운드에서 주기적으로 통신하는 자동 동기화 기능이 추가되었습니다.
/// ---------------------------------------------------------------------------
class ErpSyncHelper {

  // 백그라운드에서 주기적으로 실행될 타이머 객체입니다. (C++Builder의 TTimer 객체와 동일한 역할)
  static Timer? _backgroundTimer;

  /// =========================================================================
  /// [1] 수동 수신 (Fetch & Sync) : 거래처 ERP -> 우리 DB (UI 포함)
  /// 사용자가 직접 [ERP 연동] 버튼을 눌렀을 때 팝업과 로딩 화면을 띄우며 데이터를 가져옵니다.
  /// =========================================================================
  static Future<void> fetchAndSync({
    required BuildContext context,
    required ThemeData theme,
    required String moduleName,
    required String apiUrl,
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
                  "거래처 ERP 시스템에서 최신 [$moduleName] 데이터를 가져와 자동으로 등록하시겠습니까?",
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
                      Navigator.pop(ctx);

                      onLoadingStart(); // 로딩 UI 켜기

                      try {
                        final Uri apiUri = Uri.parse(apiUrl);
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
                            await pb.collection(targetCollection).create(body: bodyData);
                          }

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('✅ ERP 시스템에서 ${erpDataList.length}건의 데이터를 성공적으로 가져왔습니다.', style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
                              elevation: 0,
                            ));
                          }

                          onSuccess(); // 목록 새로고침
                        } else {
                          throw Exception('ERP 서버 응답 오류 (상태 코드: ${response.statusCode})');
                        }
                      } catch (e, stackTrace) {
                        debugPrint('\n=============================================================');
                        debugPrint('🚨 [ERP 연동 수신 실패 - $moduleName] 🚨');
                        debugPrint('오류 내용: $e');
                        debugPrint('발생 위치:\n$stackTrace');
                        debugPrint('=============================================================\n');

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('❌ ERP 연동 실패: $e', style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white, fontWeight: FontWeight.bold)),
                            backgroundColor: Colors.redAccent,
                            duration: const Duration(seconds: 7),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      } finally {
                        onLoadingComplete(); // 로딩 UI 끄기
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
  /// 우리 시스템에서 발생한 데이터(예: 물품 출고, 인원 체크)를 거래처 ERP로 전송합니다.
  /// =========================================================================
  static Future<bool> pushToERP({
    required String apiUrl,
    required Map<String, dynamic> payload,
    String httpMethod = 'POST',
    Map<String, String>? headers,
  }) async {
    try {
      final Uri apiUri = Uri.parse(apiUrl);

      final Map<String, String> requestHeaders = {
        'Content-Type': 'application/json; charset=UTF-8',
      };

      if (headers != null) {
        requestHeaders.addAll(headers);
      }

      final String jsonBody = jsonEncode(payload);
      http.Response response;

      if (httpMethod.toUpperCase() == 'POST') {
        response = await http.post(apiUri, headers: requestHeaders, body: jsonBody);
      } else if (httpMethod.toUpperCase() == 'PUT') {
        response = await http.put(apiUri, headers: requestHeaders, body: jsonBody);
      } else {
        throw Exception('지원하지 않는 HTTP 메서드입니다: $httpMethod');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ [ERP 송신 성공] 대상: $apiUrl');
        return true;
      } else {
        debugPrint('❌ [ERP 송신 실패] 상태 코드: ${response.statusCode}, 응답: ${response.body}');
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('\n=============================================================');
      debugPrint('🚨 [ERP 시스템으로 데이터 전송 실패] 🚨');
      debugPrint('대상 API: $apiUrl');
      debugPrint('오류 내용: $e');
      debugPrint('발생 위치:\n$stackTrace');
      debugPrint('=============================================================\n');
      return false;
    }
  }

  /// =========================================================================
  /// [3] 백그라운드 조용한 수신 (Silent Sync) : UI 간섭 없음
  /// 다이얼로그 팝업이나 화면 로딩 없이, 오직 뒤에서 통신만 하고 DB에 밀어 넣습니다.
  /// =========================================================================
  static Future<bool> syncSilent({
    required String apiUrl,
    required String targetCollection,
    required Map<String, dynamic> Function(Map<String, dynamic> erpItem) dataMapper,
  }) async {
    try {
      final Uri apiUri = Uri.parse(apiUrl);
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

          // [실무 참고] 현재는 무조건 새 문서를 생성(Insert)합니다.
          // 실제 현장에서는 거래처 데이터의 ID를 확인하여 이미 있는 데이터면 Update하고, 없으면 Create하는
          // 'Upsert' 로직을 여기에 구현하면 중복 저장을 막을 수 있습니다.
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
  /// 지정한 시간(Interval)마다 무한히 백그라운드 수신(syncSilent)을 실행하는 타이머를 켭니다.
  /// 키오스크나 대시보드 화면이 켜질 때 한 번 호출해 두면 알아서 돌아갑니다.
  /// =========================================================================
  static void startAutoSync({
    required Duration interval,       // 얼마나 자주 실행할 것인지 (예: 5분마다)
    required String apiUrl,           // ERP REST API 주소
    required String targetCollection, // 저장할 PocketBase 컬렉션명
    required Map<String, dynamic> Function(Map<String, dynamic> erpItem) dataMapper,
  }) {
    // 이미 타이머가 돌고 있다면 중복 실행을 막기 위해 무시합니다.
    if (_backgroundTimer != null && _backgroundTimer!.isActive) {
      debugPrint('ℹ️ 자동 동기화 타이머가 이미 실행 중입니다.');
      return;
    }

    debugPrint('▶️ 자동 동기화 타이머를 시작합니다. (주기: ${interval.inMinutes}분)');

    // 지정된 간격마다 내부 콜백 함수가 실행됩니다.
    _backgroundTimer = Timer.periodic(interval, (Timer timer) async {
      debugPrint('⏳ [백그라운드] ERP 데이터 자동 동기화 시작...');

      bool isSuccess = await syncSilent(
          apiUrl: apiUrl,
          targetCollection: targetCollection,
          dataMapper: dataMapper
      );

      if (isSuccess) {
        debugPrint('✅ [백그라운드] ERP 데이터 자동 동기화 완료!');
      } else {
        debugPrint('❌ [백그라운드] ERP 데이터 자동 동기화 실패!');
      }
    });
  }

  /// =========================================================================
  /// [5] 자동 동기화 종료 (Stop Auto Sync)
  /// 앱이 종료되거나 동기화를 멈춰야 할 때 호출하여 타이머 메모리를 해제합니다.
  /// =========================================================================
  static void stopAutoSync() {
    if (_backgroundTimer != null && _backgroundTimer!.isActive) {
      _backgroundTimer!.cancel(); // 타이머 작동 중지
      _backgroundTimer = null;    // 객체 초기화
      debugPrint('⏹️ 자동 동기화 타이머가 중지되었습니다.');
    }
  }
}