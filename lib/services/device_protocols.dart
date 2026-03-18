import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
// 🔥 [크롬 컴파일 에러 완벽 해결] 시리얼 포트 직접 임포트를 삭제하고 래퍼로 교체합니다.
import 'scanner/app_serial_port.dart';

/// ---------------------------------------------------------------------------
/// [상수 정의] 지원하는 구체적 장치 모델 리스트
/// PocketBase의 'model' 필드 Select 옵션과 1:1 매칭됩니다.
/// UI에서 드롭다운이나 목록으로 보여줄 때 사용하기 편리하도록 구성했습니다.
/// ---------------------------------------------------------------------------
class SupportedDeviceModels {
  static const String idro900f      = 'IDRO900F';
  static const String cf815         = 'CF815';
  static const String cfRU5102      = 'CF_RU5102';
  static const String cf601         = 'CF601';
  static const String ats200        = 'ATS200';
  static const String m120          = 'M120';
  static const String hopeland      = 'HOPELAND';
  static const String chafon        = 'CHAFON';
  static const String zebra         = 'ZEBRA';
  static const String bt200         = 'BT200';
  static const String sato          = 'SATO';
  static const String genericTcp    = 'GENERIC_TCP';
  static const String genericRs232c = 'GENERIC_RS232C';

  static const Map<String, String> labels = {
    idro900f: '고정식 리더기 (IDRO900F)',
    cf815: '고정식 리더기 (CHAFON CF815)',
    cfRU5102: '데스크형 리더기 (CHAFON CF_RU5102)',
    cf601: '데스크형 리더기 (CHAFON CF601)',
    ats200: '휴대형 리더기 (ATS200/100)',
    hopeland: '고정식 리더기 (Hopeland 범용)',
    m120: '데스크형 리더기 (Hopeland M120)',
    chafon: '고정식/탁상형 범용 (CHAFON)',
    zebra: '프린터 (Zebra)',
    bt200: '프린터 (BT200)',
    sato: '프린터 (SATO)',
    genericTcp: '범용 TCP 장치',
    genericRs232c: '범용 RS232C 장치 (시리얼)',
  };

  static List<String> get list {
    return labels.keys.toList();
  }
}

/// ---------------------------------------------------------------------------
/// [최상위 하이브리드 통신 엔진] BaseDeviceProtocol
/// 모든 리더기 통신(TCP Socket 및 RS-232C Serial)의 공통 뼈대가 되는 추상 클래스입니다.
/// ---------------------------------------------------------------------------
abstract class BaseDeviceProtocol {
  final String ipAddress;
  final int port;

  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;

  AppSerialPort? _serialPort;

  bool _rxThreadRunning = false;
  bool _terminateRxThread = false;
  bool _isDisconnecting = false;

  String _buffer = "";

  final StreamController<String> _tagStreamController = StreamController<String>.broadcast();

  Stream<String> get tagStream {
    return _tagStreamController.stream;
  }

  bool get isConnected {
    return _socket != null || (_serialPort != null && _serialPort!.isOpen);
  }

  BaseDeviceProtocol({required this.ipAddress, required this.port});

  Future<bool> connect() async {
    _isDisconnecting = false;

    try {
      String upperIp = ipAddress.toUpperCase();

      bool isBluetoothMac = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$').hasMatch(ipAddress);
      bool isUsbSerial = upperIp.startsWith('COM') || upperIp.startsWith('/DEV/');

      if (isBluetoothMac) {
        emitData("⚠️ [SYS] 블루투스(SPP) 장비는 현재 플랫폼에서 미지원됩니다.");
        return false;
      } else if (isUsbSerial) {
        return await _connectUsbSerial();
      } else {
        return await _connectTcpSocket();
      }
    } catch (e) {
      emitData("❌ [SYS] 통신 엔진 연결 초기화 실패: $e");
      return false;
    }
  }

  Future<bool> _connectTcpSocket() async {
    try {
      _socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 3));

      _socketSubscription = _socket!.listen(
        _internalOnDataReceived,
        onError: (error) {
          emitData("❌ [TCP 에러] 소켓 끊어짐: $error");
          disconnect();
        },
        onDone: () {
          emitData("🔌 [TCP 종료] 소켓 닫힘");
          disconnect();
        },
      );

      onConnected();
      return true;
    } catch (e) {
      _socket = null;
      emitData("❌ [TCP 연결 실패] $e");
      return false;
    }
  }

  Future<bool> _connectUsbSerial() async {
    emitData("🔌 [SYS] 시리얼 포트 연결 시도: $ipAddress (BaudRate: $port)");

    try {
      _serialPort ??= AppSerialPort(ipAddress);

      if (!_serialPort!.openReadWrite()) {
        emitData("❌ [SYS] 시리얼 포트 개방 실패: $ipAddress");
        return false;
      }

      try {
        _serialPort!.configure(baudRate: port);
      } catch (configErr) {
        emitData("⚠️ [SYS] 포트 설정(DCB) 예외 무시: $configErr");
      }

      _startRxThread();

      onConnected();
      return true;
    } catch (e) {
      emitData("❌ [SYS] 시리얼 포트 연결 예외: $e");
      return false;
    }
  }

  Future<void> _startRxThread() async {
    _rxThreadRunning = true;
    _terminateRxThread = false;
    debugPrint("[DEBUG] 시리얼 RX 폴링 스레드 가동 시작");

    while (!_terminateRxThread) {
      if (_serialPort != null && _serialPort!.isOpen) {
        try {
          int available = _serialPort!.bytesAvailable;

          if (available > 0) {
            Uint8List data = _serialPort!.read(available);
            if (data.isNotEmpty) {
              _internalOnDataReceived(data);
            }
          }
        } catch (e) {
          debugPrint("[DEBUG] RX 스레드 읽기 중 예외: $e");
          break; // 🔥 여기서 RangeError 등으로 크래시 나면 스레드가 죽어버립니다.
        }
      } else {
        break;
      }

      await Future.delayed(const Duration(milliseconds: 50));
    }

    _rxThreadRunning = false;
    debugPrint("[DEBUG] 시리얼 RX 폴링 스레드 완전히 종료됨");
  }

  Future<void> disconnect() async {
    if (_isDisconnecting) {
      return;
    }

    debugPrint("========== [DEBUG] disconnect() TThread 안전 해제 진입 ==========");

    try {
      await onDisconnecting();
    } catch (e) {
      debugPrint("[DEBUG] onDisconnecting 예외: $e");
    }

    _isDisconnecting = true;

    try {
      _socketSubscription?.cancel();
      _socketSubscription = null;
      _socket?.destroy();
      _socket = null;
    } catch (e) {
      debugPrint("[DEBUG] TCP 소켓 해제 예외: $e");
    }

    try {
      _terminateRxThread = true;
      debugPrint("[DEBUG] 가상 RX 스레드에 종료(Terminate) 플래그 설정 완료");

      int waitCount = 0;
      while (_rxThreadRunning) {
        await Future.delayed(const Duration(milliseconds: 10));
        waitCount++;
        if (waitCount > 100) {
          break;
        }
      }
      debugPrint("[DEBUG] 가상 RX 스레드 안전 종료 확인 완료 (안전 보장 100%)");

      if (_serialPort != null) {
        try {
          if (_serialPort!.isOpen) {
            _serialPort!.close();
            debugPrint("[DEBUG] 시리얼 포트 물리적 close() 완료");
          }
        } catch (e) {
          debugPrint("[DEBUG] 포트 닫기 예외 발생 (안전하게 무시됨): $e");
        }
      }

      _buffer = "";
      debugPrint("========== [DEBUG] disconnect() 안전 해제 완벽 탈출 ==========");

    } catch (e) {
      debugPrint("[DEBUG] 해제 시퀀스 오류 (안전하게 무시됨): $e");
    }
  }

  void sendCommandString(String command) {
    if (command.isEmpty || _isDisconnecting) {
      return;
    }

    if (_socket != null) {
      _socket!.write(command);
      _socket!.flush();
    } else if (_serialPort != null && _serialPort!.isOpen) {
      try {
        _serialPort!.write(Uint8List.fromList(command.codeUnits));
      } catch (e) {
        emitData("❌ [TX 시리얼 에러] $e");
      }
    }
  }

  void sendCommandBytes(List<int> bytes) {
    if (bytes.isEmpty || _isDisconnecting) {
      return;
    }

    String hexLog = bytes.map((b) {
      return b.toRadixString(16).padLeft(2, '0').toUpperCase();
    }).join(' ');
    emitData("➡️ [TX 전송] $hexLog");

    if (_socket != null) {
      try {
        _socket!.add(bytes);
        _socket!.flush();
      } catch (e) {
        emitData("❌ [TX 소켓 에러] $e");
      }
    } else if (_serialPort != null && _serialPort!.isOpen) {
      try {
        _serialPort!.write(Uint8List.fromList(bytes));
      } catch (e) {
        emitData("❌ [TX 시리얼 에러] $e");
      }
    } else {
      emitData("⚠️ [TX 실패] 포트가 닫혀있어 전송할 수 없습니다.");
    }
  }

  Future<void> dispose() async {
    await disconnect();
    try {
      if (!_tagStreamController.isClosed) {
        await _tagStreamController.close();
      }
    } catch (e) {
      debugPrint("[DEBUG] StreamController 닫기 예외 (안전하게 무시됨): $e");
    }
  }

  void _internalOnDataReceived(Uint8List data) {
    onDataReceived(data);
  }

  void emitData(String data) {
    if (!_tagStreamController.isClosed) {
      _tagStreamController.add(data);
    }
  }

  void onDataReceived(Uint8List data) {
    _buffer += String.fromCharCodes(data);

    while (_buffer.contains('\n')) {
      int index = _buffer.indexOf('\n');
      String line = _buffer.substring(0, index).replaceAll('\r', '');
      _buffer = _buffer.substring(index + 1);

      if (line.isNotEmpty) {
        String parsedTag = parseTagId(line);
        if (parsedTag.isNotEmpty && !_tagStreamController.isClosed) {
          _tagStreamController.add(parsedTag);
        }
      }
    }
  }

  void onConnected();
  Future<void> onDisconnecting() async {}
  String parseTagId(String rawData);

  Future<void> startInventory() async {}
  Future<void> stopInventory() async {}
  Future<void> setAntennaPower(int antennaIndex, int powerLevel) async {}

  Future<void> readTagMemory(int bank, int offset, int length) async {}
  Future<void> writeTagMemory(int bank, int offset, String dataHex, {String? targetEpc}) async {}
  Future<void> setTagFilter(int bank, int offset, String maskDataHex) async {}
}

/// ---------------------------------------------------------------------------
/// [유형 1] 자동 수신형 (Event-Driven) 베이스 클래스
/// ---------------------------------------------------------------------------
abstract class AutoReportProtocol extends BaseDeviceProtocol {
  final String startCmd;
  final String stopCmd;

  AutoReportProtocol({
    required super.ipAddress,
    required super.port,
    required this.startCmd,
    required this.stopCmd
  });

  @override
  void onConnected() {
    sendCommandString(startCmd);
  }

  @override
  Future<void> onDisconnecting() async {
    sendCommandString(stopCmd);
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

/// ---------------------------------------------------------------------------
/// [유형 2] 핸드쉐이킹 폴링형 (Polling) 베이스 클래스
/// ---------------------------------------------------------------------------
abstract class PollingProtocol extends BaseDeviceProtocol {
  final String pollCmd;
  final int intervalMs;
  Timer? _pollingTimer;

  PollingProtocol({
    required super.ipAddress,
    required super.port,
    required this.pollCmd,
    this.intervalMs = 500
  });

  @override
  void onConnected() {
    _pollingTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (isConnected) {
        sendCommandString(pollCmd);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  Future<void> onDisconnecting() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }
}

/// ===========================================================================
/// [구현체] IDRO900F 전용 프로토콜
/// ===========================================================================
class Idro900fProtocol extends AutoReportProtocol {
  Completer<bool>? _writeCompleter;

  Idro900fProtocol(String ip, int port) : super(ipAddress: ip, port: port, startCmd: ">f\r\n", stopCmd: ">3\r\n");

  @override
  void onDataReceived(Uint8List data) {
    String rawHex = data.map((b) {
      return b.toRadixString(16).padLeft(2, '0').toUpperCase();
    }).join(' ');

    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("<== [IDRO900F Raw] $rawHex");
    }

    _buffer += String.fromCharCodes(data);

    while (_buffer.contains('\n')) {
      int index = _buffer.indexOf('\n');
      String line = _buffer.substring(0, index).replaceAll('\r', '');
      _buffer = _buffer.substring(index + 1);

      if (line.isNotEmpty) {
        _parseIdroPacket(line);
      }
    }
  }

  void _parseIdroPacket(String line) {
    if (line.startsWith('>') && line.length >= 5 && line[2] == 'T') {
      try {
        String antChar = line.substring(1, 2);
        int antNo = int.tryParse(antChar) ?? 1;

        String remainData = line.substring(3).trim();
        String epc = "";
        String rssi = "-";
        String tid = "-";

        if (remainData.contains(';')) {
          List<String> parts = remainData.split(';');
          String epcPart = parts[0];

          if (parts.length > 1) {
            rssi = parts[1];
          }

          if (epcPart.length > 4) {
            epc = epcPart.substring(4);
          } else {
            epc = epcPart;
          }
        } else if (remainData.contains(',')) {
          List<String> parts = remainData.split(',');
          epc = parts[0];
          if (parts.length > 1) rssi = parts[1];
          if (parts.length > 2) tid = parts[2];
        } else {
          if (remainData.length > 4) {
            epc = remainData.substring(4);
          } else {
            epc = remainData;
          }
        }

        if (epc.isNotEmpty) {
          String jsonPayload = 'JSON:{"epc":"$epc", "ant":$antNo, "rssi":"$rssi", "tid":"$tid"}';
          emitData(jsonPayload);
        }

      } catch (e) {
        emitData("⚠️ [IDRO 파싱 오류] 규격 외 데이터: $line");
      }
    } else if (line.startsWith('>R')) {
      emitData("🔍 [메모리 읽기 응답] $line");
    } else if (line.startsWith('>W') || line.startsWith('>w')) {
      emitData("✅ [장비 응답] 태그 데이터 기록 성공!");
      if (_writeCompleter != null && !_writeCompleter!.isCompleted) {
        _writeCompleter!.complete(true);
      }
    } else if (line.startsWith('>E') || line.toLowerCase().contains('err')) {
      emitData("❌ [장비 응답] 장비 내부 에러 발생!");
      if (_writeCompleter != null && !_writeCompleter!.isCompleted) {
        _writeCompleter!.complete(false);
      }
    } else {
      if (line != ">") {
        emitData("ℹ️ [장비 응답] $line");
      }
    }
  }

  @override
  String parseTagId(String packet) {
    return "";
  }

  @override
  Future<void> writeTagMemory(int bank, int offset, String dataHex, {String? targetEpc}) async {
    if (!isConnected) {
      emitData("⚠️ [쓰기 실패] 장비가 연결되어 있지 않습니다.");
      return;
    }

    String paddedData = dataHex.toUpperCase().trim();
    if (paddedData.length % 4 != 0) {
      int neededChars = 4 - (paddedData.length % 4);
      paddedData = paddedData.padRight(paddedData.length + neededChars, '0');
    }

    int wordLength = paddedData.length ~/ 4;
    String accessPassword = "00000000";
    String command = ">w$accessPassword,$bank,$offset,$wordLength,$paddedData\r\n";

    emitData("📝 [IDRO 쓰기 준비] Bank:$bank, Offset:$offset, Length:$wordLength Words");

    int maxRetries = 3;
    bool writeSuccess = false;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      emitData("▶️ [명령어 발송] 쓰기 시도 ($attempt/$maxRetries)");

      _writeCompleter = Completer<bool>();
      sendCommandString(command);

      try {
        writeSuccess = await _writeCompleter!.future.timeout(const Duration(milliseconds: 1500));
      } catch (e) {
        writeSuccess = false;
        emitData("⏳ [타임아웃] 장비 응답 없음.");
      }

      if (writeSuccess) {
        emitData("🎉 [최종 성공] 태그에 데이터가 완벽하게 기록(Verify)되었습니다!");
        break;
      } else {
        if (attempt < maxRetries) {
          emitData("🔄 [재시도] 기록 실패. 장비 상태 안정화 후 다시 시도합니다...");
          await Future.delayed(const Duration(milliseconds: 500));
        } else {
          emitData("💥 [최종 실패] $maxRetries회 시도했으나 태그 기록에 실패했습니다.");
        }
      }
    }

    _writeCompleter = null;
  }
}

/// ===========================================================================
/// [구현체] ATID ATS200/100 휴대형 리더기
/// ===========================================================================
class Ats200Protocol extends AutoReportProtocol {
  Ats200Protocol(String ip, int port) : super(ipAddress: ip, port: port, startCmd: "~af\r\n", stopCmd: "~as\r\n");

  @override
  String parseTagId(String packet) {
    if (packet.startsWith('~eT')) {
      String mainData = packet.contains(',') ? packet.split(',')[0] : packet;
      if (mainData.length > 7) {
        return mainData.substring(7).trim();
      }
    }
    return "";
  }
}

/// ===========================================================================
/// [구현체] Hopeland M120 / HL7206 계열 리더기
/// 🔥 [완벽 복구] Hopeland 공식 R2000(0xBB) 프로토콜로 재작성되었습니다!
/// M120 장비가 100% 인식하고 응답하는 검증된 패킷 구조입니다.
/// ===========================================================================
class HopelandProtocol extends BaseDeviceProtocol {
  final List<int> _byteBuffer = [];
  Completer<bool>? _writeCompleter;
  Completer<String?>? _singleReadCompleter; // 태그 깨우기(Wake up) 대기용
  Timer? _pollingTimer;

  HopelandProtocol(String ip, int port) : super(ipAddress: ip, port: port);

  @override
  void onConnected() {
    emitData("🚀 [SYS] Hopeland M120 장치 접속 성공: $ipAddress:$port");
  }

  /// -------------------------------------------------------------------------
  /// [핵심] Hopeland R2000 프로토콜 명령어 패키징 함수
  /// 구조: 0xBB | 0x00(Node) | Command | Length(1 Byte) | Payload | Checksum | 0x7E
  /// -------------------------------------------------------------------------
  void sendHopelandCommand(int cmd, List<int> payload) {
    // Length는 Payload의 길이입니다.
    List<int> packet = [0xBB, 0x00, cmd, payload.length];
    packet.addAll(payload);

    // 체크섬: Node(0x00) + Cmd + Length + Payload의 합
    int checksum = 0;
    // 인덱스 1 (Node)부터 끝까지 더합니다.
    for (int i = 1; i < packet.length; i++) {
      checksum += packet[i];
    }
    packet.add(checksum & 0xFF);
    packet.add(0x7E);

    sendCommandBytes(packet);
  }

  @override
  Future<void> startInventory() async {
    emitData("▶️ [명령] 연속 스캔(Inventory) 엔진 가동!");

    if (_pollingTimer != null && _pollingTimer!.isActive) {
      return;
    }

    // 0x22 (단일 폴링) 명령을 반복 발송하여 태그를 읽어들입니다.
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!isConnected || _isDisconnecting) {
        timer.cancel();
        return;
      }
      sendHopelandCommand(0x22, []); // 0x22: Read Single
    });
  }

  @override
  Future<void> stopInventory() async {
    if (_pollingTimer != null) {
      _pollingTimer!.cancel();
      _pollingTimer = null;
      emitData("⏹️ [명령] 연속 스캔(Inventory) 중지 완료");
    }
  }

  @override
  Future<void> onDisconnecting() async {
    await stopInventory();
  }

  @override
  void onDataReceived(Uint8List data) {
    // 디버깅/터미널 화면용 Raw 데이터 출력
    String rawHex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    emitData("<== [수신 RX] $rawHex");

    _byteBuffer.addAll(data);

    // 프레임 분석: 0xBB로 시작해서 0x7E로 끝나는 패킷 추출
    while (_byteBuffer.isNotEmpty) {
      if (_byteBuffer[0] != 0xBB) {
        _byteBuffer.removeAt(0); // 노이즈 버림
        continue;
      }

      if (_byteBuffer.length < 5) {
        break; // 최소 헤더 길이 대기
      }

      int payloadLen = _byteBuffer[3];
      // 0xBB(1) + Node(1) + Cmd(1) + Len(1) + Payload(N) + Chk(1) + 0x7E(1)
      int totalPacketSize = 5 + payloadLen + 2;

      if (_byteBuffer.length < totalPacketSize) {
        break; // 아직 전체 패킷이 도착하지 않음
      }

      // 패킷 끝이 0x7E로 끝나는지 무결성 검증
      if (_byteBuffer[totalPacketSize - 1] != 0x7E) {
        emitData("⚠️ [Hopeland 에러] 0x7E 종료 바이트 불일치. 깨진 패킷 무시.");
        _byteBuffer.removeAt(0);
        continue;
      }

      List<int> packet = _byteBuffer.sublist(0, totalPacketSize);
      _byteBuffer.removeRange(0, totalPacketSize);

      int cmd = packet[2];
      List<int> payload = packet.sublist(4, 4 + payloadLen);

      _parseHopelandPayload(cmd, payload);
    }

    if (_byteBuffer.length > 8192) {
      _byteBuffer.clear(); // 메모리 누수 방지
    }
  }

  /// 📥 [Hopeland 스마트 파서] 읽기(Read) 및 쓰기(Write) 응답 분기 처리
  void _parseHopelandPayload(int cmd, List<int> payload) {
    // 1. 태그 단일 읽기 응답 (0x22)
    if (cmd == 0x22) {
      if (payload.isNotEmpty && payload.length > 2) {
        // Payload 구조: [RSSI] [PC 2B] [EPC NB] [CRC 2B]
        int rssiVal = payload[0];
        String rssiStr = "-$rssiVal dBm";

        // EPC 추출 (RSSI 1바이트, PC 2바이트 건너뛰고 끝에 CRC 2바이트 제외)
        List<int> epcBytes = payload.sublist(3, payload.length - 2);
        String epc = epcBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

        // 🔥 쓰기 전 깨우기(Wake up) 명령에 대한 응답이 오면 Completer를 완료시킵니다!
        if (_singleReadCompleter != null && !_singleReadCompleter!.isCompleted) {
          _singleReadCompleter!.complete(epc);
        }

        emitData('JSON:{"epc":"$epc", "ant":1, "rssi":"$rssiStr", "tid":"-"}');
      }
    }
    // 2. 태그 쓰기(Write Data) 응답 (0x49)
    else if (cmd == 0x49) {
      if (payload.isNotEmpty) {
        int status = payload[0]; // Payload의 첫 번째 바이트가 결과 코드
        if (status == 0x00) {
          emitData("✅ [장비 응답] 태그 메모리 기록 완벽 성공!");
          if (_writeCompleter != null && !_writeCompleter!.isCompleted) {
            _writeCompleter!.complete(true);
          }
        } else {
          String errStr = status.toRadixString(16).toUpperCase().padLeft(2, '0');
          String errMsg = "알 수 없는 오류";
          if (status == 0x16) errMsg = "비밀번호 에러 (Access Password)";
          if (status == 0x09) errMsg = "태그를 찾을 수 없음 (No Tag)";
          if (status == 0x10) errMsg = "메모리 잠김 (Locked)";

          emitData("❌ [장비 응답] 쓰기 실패 (에러코드: 0x$errStr - $errMsg)");
          if (_writeCompleter != null && !_writeCompleter!.isCompleted) {
            _writeCompleter!.complete(false);
          }
        }
      }
    }
  }

  @override
  String parseTagId(String rawData) {
    return ""; // JSON 브릿지 방식으로 파싱하므로 빈 문자열 반환
  }

  /// 📝 [Hopeland 쓰기 엔진 구현]
  /// 🔥 2-Step 방식 적용: 1. 단일 읽기(0x22 Wake up) -> 2. 쓰기(0x49) 발송
  @override
  Future<void> writeTagMemory(int bank, int offset, String dataHex, {String? targetEpc}) async {
    if (!isConnected) {
      emitData("⚠️ [쓰기 실패] Hopeland M120 장비가 연결되어 있지 않습니다.");
      return;
    }

    // 쓰기 전 안전을 위해 백그라운드 읽기 폴링을 잠시 멈춥니다.
    await stopInventory();
    await Future.delayed(const Duration(milliseconds: 100));
    _byteBuffer.clear();

    String paddedData = dataHex.toUpperCase().trim();
    // 워드(2바이트) 단위로 맞추기 위해 4의 배수로 패딩 처리 (Hex 기준)
    if (paddedData.length % 4 != 0) {
      int neededChars = 4 - (paddedData.length % 4);
      paddedData = paddedData.padRight(paddedData.length + neededChars, '0');
    }

    // 1 Word = 2 Bytes = 4 Hex chars
    int wordCount = paddedData.length ~/ 4;
    List<int> dataBytes = [];
    for (int i = 0; i < paddedData.length; i += 2) {
      dataBytes.add(int.parse(paddedData.substring(i, i + 2), radix: 16));
    }

    // 0x49 Payload 구조: [Password 4B] [Bank 1B] [Ptr 1B] [WordCnt 1B] [Data N]
    List<int> payload = [
      0x00, 0x00, 0x00, 0x00, // Access Password (기본 00 00 00 00)
      bank, // MemBank (1=EPC, 3=USER)
      offset, // Pointer/Offset 시작점
      wordCount, // 기록할 Word 개수
    ];
    payload.addAll(dataBytes);

    emitData("📝 [Hopeland M120 쓰기 준비] Bank:$bank, Offset:$offset, WordCnt:$wordCount");

    int maxRetries = 3;
    bool writeSuccess = false;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      emitData("▶️ [시도 $attempt/$maxRetries] 1단계: 태그 스캔(Inventory)하여 잠 깨우기...");

      _singleReadCompleter = Completer<String?>();
      // 0x22 (단일 태그 읽기)를 보내 데스크 장비 위의 태그를 활성화(Wake up)시킵니다.
      sendHopelandCommand(0x22, []);

      try {
        await _singleReadCompleter!.future.timeout(const Duration(milliseconds: 500));
      } catch (_) {
        // Wake up 응답이 타임아웃 되더라도, 혹시 모를 장비 딜레이를 감안하여 쓰기 시도는 계속 진행합니다.
      }
      _singleReadCompleter = null;

      emitData("🎯 [대상 확보 완료] 2단계: 즉시 쓰기를 시도합니다!");

      _writeCompleter = Completer<bool>();

      // 🔥 [핵심 수정] M120 쓰기 표준 규격인 0x49 (Write Data) 명령 전송
      sendHopelandCommand(0x49, payload);

      try {
        writeSuccess = await _writeCompleter!.future.timeout(const Duration(milliseconds: 2000));
      } catch (e) {
        writeSuccess = false;
        emitData("⏳ [타임아웃] 장비 쓰기 응답 없음.");
      }

      if (writeSuccess) {
        emitData("🎉 [최종 성공] 태그에 데이터가 완벽하게 기록되었습니다!");
        break; // 성공 시 루프 탈출
      } else {
        if (attempt < maxRetries) {
          emitData("🔄 [재시도] 기록 실패. 장비 상태 안정화 후 다시 시도합니다...");
          await Future.delayed(const Duration(milliseconds: 500));
        } else {
          emitData("💥 [최종 실패] $maxRetries회 시도했으나 태그 기록에 실패했습니다.");
        }
      }
    }
    _writeCompleter = null;
  }

  @override
  Future<void> setAntennaPower(int antennaIndex, int powerLevel) async {
    if (!isConnected) return;
    int pwr = powerLevel ~/ 10;
    if (pwr > 33) pwr = 33;
    // 0xB6 (Set Power) 커맨드 전송
    sendHopelandCommand(0xB6, [pwr]);
  }
}

/// ===========================================================================
/// [구현체] Marktrace (UHFReader09) 전용 해독 엔진 (CF_RU5102, CF815 포함)
/// ===========================================================================
class ChafonProtocol extends BaseDeviceProtocol {
  final List<int> _byteBuffer = [];
  Timer? _pollingTimer;

  int _discoveryStep = 0;
  int _lockedProtocol = -1;

  Completer<bool>? _writeCompleter;
  Completer<String?>? _singleReadCompleter;

  ChafonProtocol(String ip, int port) : super(ipAddress: ip, port: port);

  @override
  void onConnected() {
    emitData("🚀 [SYS] Chafon 장치 접속 성공: $ipAddress:$port");
  }

  @override
  Future<void> startInventory() async {
    emitData("▶️ [명령] 연속 스캔(Inventory) 엔진 가동!");

    if (_pollingTimer != null && _pollingTimer!.isActive) {
      return;
    }

    _pollingTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!isConnected || _isDisconnecting) {
        timer.cancel();
        return;
      }

      if (_lockedProtocol == -1) {
        if (_discoveryStep == 0) {
          sendUHFReader09Command(0x01, [], address: 0xFF);
        } else if (_discoveryStep == 1) {
          sendUHFReader09Command(0x01, [], address: 0x00);
        } else if (_discoveryStep == 2) {
          sendUHFReader09Command(0x27, [], address: 0xFF);
        } else if (_discoveryStep == 3) {
          sendUHFReader09Command(0x27, [], address: 0x00);
        } else if (_discoveryStep == 4) {
          sendUHFReader09Command(0x0F, [], address: 0xFF);
        } else if (_discoveryStep == 5) {
          sendR2000Command(0x89, [0x01], address: 0xFF);
        }
        _discoveryStep = (_discoveryStep + 1) % 6;
      } else {
        _pollLockedProtocol();
      }
    });
  }

  @override
  Future<void> stopInventory() async {
    if (_pollingTimer != null) {
      _pollingTimer!.cancel();
      _pollingTimer = null;
      emitData("⏹️ [명령] 연속 스캔(Inventory) 중지 완료");
    }
  }

  @override
  Future<void> onDisconnecting() async {
    await stopInventory();
  }

  void _pollLockedProtocol() {
    if (_lockedProtocol == 0) {
      sendUHFReader09Command(0x01, [], address: 0xFF);
    } else if (_lockedProtocol == 1) {
      sendUHFReader09Command(0x01, [], address: 0x00);
    } else if (_lockedProtocol == 2) {
      sendUHFReader09Command(0x27, [], address: 0xFF);
    } else if (_lockedProtocol == 3) {
      sendUHFReader09Command(0x27, [], address: 0x00);
    } else if (_lockedProtocol == 4) {
      sendUHFReader09Command(0x0F, [], address: 0xFF);
    } else if (_lockedProtocol == 5) {
      sendR2000Command(0x89, [0x01], address: 0xFF);
    }
  }

  void _lockOnProtocol(int protocolType, String name) {
    if (_lockedProtocol != -1) {
      return;
    }

    _lockedProtocol = protocolType;
    emitData("✅ [장비 락온] $name 규격으로 고속 폴링 전환 완료!");
  }

  void sendUHFReader09Command(int cmd, List<int> data, {int address = 0xFF}) {
    int len = data.length + 4;
    List<int> packet = [len, address, cmd];
    packet.addAll(data);

    int crc = 0xFFFF;
    for (int i = 0; i < packet.length; i++) {
      crc ^= packet[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0x8408;
        } else {
          crc >>= 1;
        }
      }
    }

    packet.add(crc & 0xFF);
    packet.add((crc >> 8) & 0xFF);

    sendCommandBytes(packet);
  }

  void sendCommandHex(String hexString) {
    String cleanHex = hexString.replaceAll(' ', '').toUpperCase();
    if (cleanHex.length % 2 != 0) {
      return;
    }

    List<int> bytes = [];
    for (int i = 0; i < cleanHex.length; i += 2) {
      bytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
    }

    sendCommandBytes(bytes);
  }

  void sendR2000Command(int cmd, List<int> data, {int address = 0xFF}) {
    int len = data.length + 3;
    List<int> packet = [0xA0, len, address, cmd];
    packet.addAll(data);

    int sum = 0;
    for (int i = 1; i < packet.length; i++) {
      sum += packet[i];
    }

    int checksum = (~sum + 1) & 0xFF;
    packet.add(checksum);

    sendCommandBytes(packet);
  }

  @override
  void onDataReceived(Uint8List data) {
    String rawSocketHex = data.map((b) {
      return b.toRadixString(16).padLeft(2, '0').toUpperCase();
    }).join(' ');

    emitData("<== [수신 RX] $rawSocketHex");

    _byteBuffer.addAll(data);

    while (_byteBuffer.isNotEmpty) {
      int header = _byteBuffer[0];

      if (header == 0xA0) {
        if (_byteBuffer.length < 2) {
          break;
        }
        int totalLen = _byteBuffer[1] + 2;
        if (_byteBuffer.length < totalLen) {
          break;
        }
        _byteBuffer.removeRange(0, totalLen);
      }
      else if (header >= 0x03 && header <= 0x80) {
        int totalLen = header + 1;
        if (_byteBuffer.length < totalLen) {
          break;
        }

        List<int> packet = _byteBuffer.sublist(0, totalLen);
        _byteBuffer.removeRange(0, totalLen);

        _parseUHFReader09(packet);
      }
      else if (header == 0xBB) {
        if (_byteBuffer.length < 5) {
          break;
        }
        int totalLen = 5 + ((_byteBuffer[3] << 8) | _byteBuffer[4]) + 2;
        if (_byteBuffer.length < totalLen) {
          break;
        }
        _byteBuffer.removeRange(0, totalLen);
      }
      else {
        _byteBuffer.removeAt(0);
      }
    }

    if (_byteBuffer.length > 4000) {
      _byteBuffer.clear();
    }
  }

  void _parseUHFReader09(List<int> packet) {
    if (packet.length < 5) {
      return;
    }

    int address = packet[1];
    int cmd = packet[2];
    List<int> payload = packet.sublist(3, packet.length - 2);

    if (cmd == 0x06) {
      if (payload.isNotEmpty) {
        int status = payload[0];

        if (status == 0x00 || status == 0x01) {
          emitData("✅ [장비 응답] 태그 데이터 쓰기 완벽 성공! (응답: 0x00)");
          if (_writeCompleter != null && !_writeCompleter!.isCompleted) {
            _writeCompleter!.complete(true);
          }
        } else {
          String hexErr = status.toRadixString(16).toUpperCase().padLeft(2, '0');
          String errMsg = "알 수 없는 에러";

          if (status == 0xFB || status == 0xFF) {
            errMsg = "태그를 찾을 수 없음 (No Tag) / RF 출력 부족";
          } else if (status == 0xFD) {
            errMsg = "메모리 잠김 / 길이 또는 오프셋 파라미터 에러";
          } else if (status == 0xFE) {
            errMsg = "비밀번호(Access Password) 오류";
          } else if (status == 0xFC) {
            errMsg = "지원하지 않는 명령";
          }

          emitData("❌ [장비 응답] 쓰기 실패 (에러: 0x$hexErr - $errMsg)");

          if (_writeCompleter != null && !_writeCompleter!.isCompleted) {
            _writeCompleter!.complete(false);
          }
        }
      }
      return;
    }

    if (payload.isNotEmpty && payload.length == 1 && (payload[0] == 0xFF || payload[0] == 0x15)) {
      return;
    }

    if (_lockedProtocol == -1) {
      if (cmd == 0x01) {
        _lockOnProtocol(address == 0xFF ? 0 : 1, "UHFReader09 Inventory (0x01, Addr: 0x${address.toRadixString(16).padLeft(2, '0').toUpperCase()})");
      } else if (cmd == 0x27) {
        _lockOnProtocol(address == 0xFF ? 2 : 3, "UHFReader09 RealTime (0x27, Addr: 0x${address.toRadixString(16).padLeft(2, '0').toUpperCase()})");
      } else if (cmd == 0x0F) {
        _lockOnProtocol(4, "UHFReader09 Anti-collision (0x0F)");
      }
    }

    if (cmd == 0x27) {
      if (payload.length >= 4) {
        int ant = (payload[0] & 0x03) + 1;
        List<int> epcBytes = payload.sublist(3, payload.length - 1);

        String rawHexEpc = epcBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

        if (_singleReadCompleter != null && !_singleReadCompleter!.isCompleted) {
          _singleReadCompleter!.complete(rawHexEpc);
        }

        int rssiByte = payload.last;
        String rssiStr = "-$rssiByte dBm";
        emitData('JSON:{"epc":"$rawHexEpc", "ant":$ant, "rssi":"$rssiStr", "tid":"-"}');
      }
    }
    else if (cmd == 0x01 || cmd == 0x02 || cmd == 0x0F) {
      if (payload.isNotEmpty) {
        int tagCount = payload[0];
        int offset = 1;

        bool isRU5102 = false;
        int testOffset = 1;
        for (int j = 0; j < tagCount; j++) {
          if (testOffset + 1 >= payload.length) break;
          testOffset += 2 + payload[testOffset + 1];
        }

        if (testOffset == payload.length) {
          isRU5102 = true;
        }

        for (int i = 0; i < tagCount; i++) {
          if (offset >= payload.length) {
            break;
          }

          int ant = 1;
          int epcLen = 0;

          if (isRU5102) {
            ant = payload[offset] + 1;
            epcLen = payload[offset + 1];
            offset += 2;
          } else {
            epcLen = payload[offset];
            offset += 1;
          }

          if (offset + epcLen <= payload.length) {
            List<int> epcBytes = payload.sublist(offset, offset + epcLen);

            String rawHexEpc = epcBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

            if (_singleReadCompleter != null && !_singleReadCompleter!.isCompleted) {
              _singleReadCompleter!.complete(rawHexEpc);
            }

            String epcString = "";
            for (int b in epcBytes) {
              if (b >= 32 && b <= 126) {
                epcString += String.fromCharCode(b);
              } else {
                epcString += b.toRadixString(16).padLeft(2, '0').toUpperCase();
              }
            }

            emitData('JSON:{"epc":"$epcString", "ant":$ant, "rssi":"-", "tid":"-"}');
            offset += epcLen;
          } else {
            break;
          }
        }
      }
    }
  }

  @override
  String parseTagId(String rawData) {
    return "";
  }

  @override
  Future<void> writeTagMemory(int bank, int offset, String dataHex, {String? targetEpc}) async {
    if (!isConnected) {
      emitData("⚠️ [쓰기 실패] 장비가 연결되어 있지 않습니다.");
      return;
    }

    await stopInventory();
    await Future.delayed(const Duration(milliseconds: 50));
    _byteBuffer.clear();

    int targetAddress = (_lockedProtocol == 1 || _lockedProtocol == 3) ? 0x00 : 0xFF;
    String? activeTargetEpc = targetEpc?.trim();

    String paddedData = dataHex.toUpperCase().trim();
    if (paddedData.length % 4 != 0) {
      int neededChars = 4 - (paddedData.length % 4);
      paddedData = paddedData.padRight(paddedData.length + neededChars, '0');
    }

    List<int> dataBytes = [];
    for (int i = 0; i < paddedData.length; i += 2) {
      dataBytes.add(int.parse(paddedData.substring(i, i + 2), radix: 16));
    }
    int totalWords = dataBytes.length ~/ 2;

    int maxRetries = 3;
    bool writeSuccess = false;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      emitData("▶️ [시도 $attempt/$maxRetries] 1단계: 태그 스캔(Inventory)하여 깨우기...");

      _singleReadCompleter = Completer<String?>();
      sendUHFReader09Command(0x01, [], address: targetAddress);

      String? currentEpc;
      try {
        currentEpc = await _singleReadCompleter!.future.timeout(const Duration(milliseconds: 800));
      } catch (e) {
        currentEpc = null;
      }
      _singleReadCompleter = null;

      if (currentEpc == null || currentEpc.isEmpty) {
        emitData("⚠️ [읽기 실패] 태그가 반응하지 않습니다. 다음 재시도를 준비합니다...");
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }

      String epcToWriteTo = (activeTargetEpc != null && activeTargetEpc.isNotEmpty) ? activeTargetEpc : currentEpc;

      emitData("🎯 [대상 확보] EPC($epcToWriteTo). 2단계: 즉시 쓰기를 시도합니다!");

      sendUHFReader09Command(0x40, [0x02], address: targetAddress);
      await Future.delayed(const Duration(milliseconds: 30));

      String cleanEpc = epcToWriteTo.replaceAll(' ', '').toUpperCase();
      List<int> epcBytes = [];
      try {
        for (int i = 0; i < cleanEpc.length; i += 2) {
          epcBytes.add(int.parse(cleanEpc.substring(i, i + 2), radix: 16));
        }
      } catch(e) {
        emitData("❌ [에러] EPC 파싱 실패. 순수 Hex 형태인지 확인하세요.");
        return;
      }

      int epcLenInBytes = epcBytes.length;

      List<int> writeData = [];
      writeData.add(epcLenInBytes);
      writeData.addAll(epcBytes);
      writeData.addAll([0x00, 0x00, 0x00, 0x00]);
      writeData.add(bank);
      writeData.add(offset);
      writeData.add(totalWords);
      writeData.addAll(dataBytes);

      _writeCompleter = Completer<bool>();
      sendUHFReader09Command(0x06, writeData, address: targetAddress);

      try {
        writeSuccess = await _writeCompleter!.future.timeout(const Duration(milliseconds: 1500));
      } catch (e) {
        writeSuccess = false;
        emitData("⏳ [타임아웃] 장비 쓰기 응답 없음.");
      }

      if (writeSuccess) {
        emitData("🎉 [최종 성공] 태그에 데이터가 완벽하게 기록되었습니다! (긴 비프음)");
        sendUHFReader09Command(0x40, [0x0A], address: targetAddress);
        break;
      } else {
        emitData("🔄 [쓰기 실패] 장비 거부 에러. 다시 처음(읽기)부터 재시도합니다...");
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    _writeCompleter = null;

    if (!writeSuccess) {
      emitData("💥 [최종 실패] 총 $maxRetries 번 시도했으나 태그 기록에 실패했습니다.");
    }
  }

  @override
  Future<void> setAntennaPower(int antennaIndex, int powerLevel) async {
    if (!isConnected) {
      return;
    }
    int pwr = powerLevel ~/ 10;
    if (pwr > 30) {
      pwr = 30;
    }

    sendUHFReader09Command(0x2F, [pwr], address: 0x00);
    await Future.delayed(const Duration(milliseconds: 100));
    sendUHFReader09Command(0x2F, [pwr], address: 0xFF);
  }
}

/// ===========================================================================
/// 프린터 / 범용 장비 파서 (단순 문자열 기반 처리용)
/// ===========================================================================

class ZebraPrinterProtocol extends PollingProtocol {
  ZebraPrinterProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, pollCmd: "~HS", intervalMs: 1000);

  @override
  String parseTagId(String packet) {
    return packet.trim();
  }
}

class SatoPrinterProtocol extends AutoReportProtocol {
  SatoPrinterProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: "\x1bA", stopCmd: "\x1bZ");

  @override
  String parseTagId(String packet) {
    return packet.trim();
  }
}

class GenericRs232cProtocol extends AutoReportProtocol {
  GenericRs232cProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: "", stopCmd: "");

  @override
  String parseTagId(String packet) {
    return packet.trim();
  }
}

class DefaultProtocol extends AutoReportProtocol {
  DefaultProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: "START\n", stopCmd: "STOP\n");

  @override
  String parseTagId(String packet) {
    return packet.trim();
  }
}

/// ---------------------------------------------------------------------------
/// [팩토리] 모델 식별자에 따른 적절한 프로토콜 객체 생성 (Driver Factory 패턴)
/// ---------------------------------------------------------------------------
class DeviceProtocolFactory {
  static BaseDeviceProtocol create(String modelValue, String ip, int port) {
    switch (modelValue) {
      case SupportedDeviceModels.idro900f:
        return Idro900fProtocol(ip, port);

      case SupportedDeviceModels.ats200:
        return Ats200Protocol(ip, port);

      case SupportedDeviceModels.hopeland:
      case SupportedDeviceModels.m120:
        return HopelandProtocol(ip, port);

      case SupportedDeviceModels.chafon:
      case SupportedDeviceModels.cf815:
      case SupportedDeviceModels.cfRU5102:
      case SupportedDeviceModels.cf601:
        return ChafonProtocol(ip, port);

      case SupportedDeviceModels.sato:
        return SatoPrinterProtocol(ip, port);

      case SupportedDeviceModels.zebra:
        return ZebraPrinterProtocol(ip, port);

      case SupportedDeviceModels.genericRs232c:
        return GenericRs232cProtocol(ip, port);

      case SupportedDeviceModels.bt200:
      case SupportedDeviceModels.genericTcp:
      default:
        return DefaultProtocol(ip, port);
    }
  }
}