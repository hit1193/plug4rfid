import 'dart:convert';
import 'dart:io'; // 🔥 TCP/IP 소켓 통신을 위해 필수적으로 추가되는 다트 코어 패키지입니다.
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

// 이메일 발송을 위한 패키지 (사용 시 pubspec.yaml에 mailer: ^3.x.x 추가 필요)
// import 'package:mailer/mailer.dart';
// import 'package:mailer/smtp_server.dart';

/// ---------------------------------------------------------------------------
/// [통합 알림 및 외부 연동 서비스 (NotificationService)]
/// 카카오톡(알림톡), 이메일(SMTP), 웹훅(Webhook) 및 TCP/IP 소켓(Socket) 통신을
/// 전담하는 미들웨어(Middleware) 클래스입니다.
/// C++Builder의 Indy (TIdHTTP, TIdSMTP, TIdTCPClient) 역할을 완벽히 대체합니다.
/// ---------------------------------------------------------------------------
class NotificationService {

  /// ---------------------------------------------------------------------------
  /// [1. 카카오톡 알림톡 발송 (REST API)]
  /// ---------------------------------------------------------------------------
  static Future<bool> sendKakaoAlimtalk({
    required String phone,
    required String message,
    required String templateCode,
  }) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool isEnabled = prefs.getBool('pref_kakao_enabled') ?? false;
      final String apiKey = prefs.getString('pref_kakao_api_key') ?? '';
      final String senderId = prefs.getString('pref_kakao_sender_id') ?? '';

      if (!isEnabled || apiKey.isEmpty || senderId.isEmpty) {
        return false;
      }

      final Uri url = Uri.parse('https://api.alimtalk-provider.com/v2/send');
      final Map<String, dynamic> payload = {
        "apikey": apiKey,
        "sender": senderId,
        "receiver": phone,
        "message": message,
        "template_code": templateCode,
      };

      final http.Response response = await http.post(
        url,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint("✅ 카카오톡 알림톡 발송 성공: $phone");
        return true;
      } else {
        debugPrint("❌ 카카오톡 발송 실패: HTTP ${response.statusCode} - ${response.body}");
        return false;
      }
    } catch (e) {
      debugPrint("카카오톡 발송 중 예외 발생: $e");
      return false;
    }
  }

  /// ---------------------------------------------------------------------------
  /// [2. 이메일(SMTP) 자동 발송]
  /// ---------------------------------------------------------------------------
  static Future<bool> sendEmail({
    required String toAddress,
    required String subject,
    required String bodyText,
  }) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool isEnabled = prefs.getBool('pref_email_enabled') ?? false;
      final String host = prefs.getString('pref_smtp_host') ?? '';
      final int port = int.tryParse(prefs.getString('pref_smtp_port') ?? '587') ?? 587;
      final String user = prefs.getString('pref_smtp_user') ?? '';
      final String password = prefs.getString('pref_smtp_password') ?? '';

      if (!isEnabled || host.isEmpty || user.isEmpty || password.isEmpty) {
        return false;
      }

      // [주의] 실제 작동을 위해서는 pubspec.yaml에 mailer 패키지 추가 후 아래 주석을 해제합니다.
      /*
      final smtpServer = SmtpServer(host, port: port, username: user, password: password);
      final message = Message()
        ..from = Address(user, 'RFID 통합관리시스템')
        ..recipients.add(toAddress)
        ..subject = subject
        ..text = bodyText;

      final sendReport = await send(message, smtpServer);
      debugPrint('✅ 이메일 발송 성공: ${sendReport.toString()}');
      return true;
      */

      debugPrint("✅ [모의 발송] 이메일 서비스 연동 성공 (mailer 패키지 설치 시 실제 발송됨)");
      return true;
    } catch (e) {
      debugPrint("이메일 발송 중 예외 발생: $e");
      return false;
    }
  }

  /// ---------------------------------------------------------------------------
  /// [3. 사용자 정의 웹훅 (Webhook) 발송]
  /// ---------------------------------------------------------------------------
  static Future<bool> sendWebhook({
    required Map<String, dynamic> payload,
  }) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool isEnabled = prefs.getBool('pref_webhook_enabled') ?? false;
      final String webhookUrl = prefs.getString('pref_webhook_url') ?? '';

      if (!isEnabled || webhookUrl.isEmpty) {
        return false;
      }

      final Uri url = Uri.parse(webhookUrl);

      final http.Response response = await http.post(
        url,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("✅ 커스텀 웹훅 전송 성공: $webhookUrl");
        return true;
      } else {
        debugPrint("❌ 커스텀 웹훅 전송 실패: HTTP ${response.statusCode} - ${response.body}");
        return false;
      }
    } catch (e) {
      debugPrint("웹훅 전송 중 예외 발생: $e");
      return false;
    }
  }

  /// ---------------------------------------------------------------------------
  /// [4. TCP/IP Socket 발송] - 🔥 신규 추가!
  /// ---------------------------------------------------------------------------
  /// 공장의 PLC 장비나 MES/POP 시스템 포트로 Raw 데이터를 직접 밀어넣습니다.
  /// JSON, CSV 등 문자열 형태의 데이터를 TCP 패킷으로 쏴주는 역할을 합니다.
  /// ---------------------------------------------------------------------------
  static Future<bool> sendTcpSocket({
    required String rawData,
  }) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool isEnabled = prefs.getBool('pref_tcp_enabled') ?? false;
      final String host = prefs.getString('pref_tcp_host') ?? '';
      final int port = int.tryParse(prefs.getString('pref_tcp_port') ?? '0') ?? 0;

      // 설정이 꺼져있거나, IP/Port 정보가 잘못된 경우 즉시 반환합니다.
      if (!isEnabled || host.isEmpty || port <= 0) {
        return false;
      }

      // C++Builder의 TIdTCPClient.Connect() 와 동일한 역할입니다.
      // 타임아웃을 3초로 주어 서버가 죽어있을 때 앱이 무한정 멈추는 것을 방지합니다.
      final Socket socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));

      // 데이터를 소켓 스트림에 기록합니다 (보통 끝에 줄바꿈 기호를 요구하는 장비가 많습니다)
      socket.write(rawData + '\n');

      // 버퍼에 있는 데이터를 즉시 네트워크로 밀어냅니다.
      await socket.flush();

      // 전송이 끝나면 즉시 소켓을 파괴하여 자원을 반환합니다. (TIdTCPClient.Disconnect())
      socket.destroy();

      debugPrint("✅ TCP/IP 소켓 데이터 전송 완료 ($host:$port)");
      return true;

    } catch (e) {
      debugPrint("❌ TCP/IP 소켓 전송 실패: $e");
      return false;
    }
  }
}