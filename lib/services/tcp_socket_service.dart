import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// [서비스] TCP/IP 소켓 통신 관리자
/// C++Builder의 TIdTCPClient와 유사한 역할을 수행합니다.
class TcpSocketService {
  Socket? _socket;
  final String host;
  final int port;

  // 데이터 수신을 외부(Provider)에서 관찰하기 위한 스트림 컨트롤러
  final _dataController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataController.stream;

  // 연결 상태 확인용
  bool get isConnected => _socket != null;

  TcpSocketService({required this.host, required this.port});

  /// [연결] 소켓 오픈 (Connect)
  Future<bool> connect() async {
    try {
      // 5초 타임아웃 설정
      _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));

      debugPrint("[$host:$port] 연결 성공");

      // 수신 대기 (C++의 Read 스레드 역할)
      _socket!.listen(
            (Uint8List data) {
          final response = utf8.decode(data);
          debugPrint("[$host:$port] 수신 데이터: $response");
          _dataController.add(response); // 스트림에 데이터 전달
        },
        onError: (error) {
          debugPrint("[$host:$port] 통신 에러: $error");
          disconnect();
        },
        onDone: () {
          debugPrint("[$host:$port] 서버에 의해 연결 종료");
          disconnect();
        },
        cancelOnError: true,
      );

      return true;
    } catch (e) {
      debugPrint("[$host:$port] 연결 실패: $e");
      _socket = null;
      return false;
    }
  }

  /// [전송] 명령 보내기 (Write)
  void sendCommand(String command) {
    if (_socket != null) {
      debugPrint("[$host:$port] 명령 전송: $command");
      // FA 장비들은 보통 명령어 끝에 CR(\r)이나 LF(\n)를 요구합니다.
      _socket!.write(command.endsWith('\n') ? command : '$command\n');
    } else {
      debugPrint("[$host:$port] 전송 실패: 소켓이 연결되어 있지 않습니다.");
    }
  }

  /// [해제] 소켓 닫기 (Disconnect)
  void disconnect() {
    _socket?.destroy();
    _socket = null;
    debugPrint("[$host:$port] 연결 해제 완료");
  }

  /// 자원 정리
  void dispose() {
    disconnect();
    _dataController.close();
  }
}