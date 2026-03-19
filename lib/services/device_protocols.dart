// cSpell:disable
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, empty_catches, spell-checker
// noinspection SpellCheckingInspection

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
// 🔥 시리얼 포트 래퍼를 사용합니다.
import 'scanner/app_serial_port.dart';

/// ---------------------------------------------------------------------------
/// [상수 정의] 지원하는 구체적 장치 모델 리스트
/// PocketBase의 'model' 필드 Select 옵션과 1:1 매칭됩니다.
/// Dart Linter 경고를 피하기 위해 원래의 lowerCamelCase 변수명으로 원복했습니다.
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
    m120: '데스크형 리더기 (Hopeland M120 / ClouReader)',
    chafon: '고정식/탁상형 범용 (Chafon)',
    zebra: '프린터 (Zebra)',
    bt200: '프린터 (BT200)',
    sato: '프린터 (Sato)',
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
/// C++Builder의 TDataModule 역할을 수행하며 OS 핸들을 안전하게 관리합니다.
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

  /// 하드웨어와 연결을 시도하는 메인 진입점입니다.
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
    int actualBaudRate = port;

    if (actualBaudRate < 9600) {
      actualBaudRate = 115200;
      emitData("💡 [SYS] 스마트 보정: 시리얼 통신 속도를 기본값인 $actualBaudRate bps로 자동 변경합니다.");
    }

    emitData("🔌 [SYS] 시리얼 포트 연결 시도: $ipAddress (BaudRate: $actualBaudRate)");

    try {
      _serialPort ??= AppSerialPort(ipAddress);

      if (!_serialPort!.openReadWrite()) {
        emitData("❌ [SYS] 시리얼 포트 개방 실패: $ipAddress");
        return false;
      }

      try {
        _serialPort!.configure(baudRate: actualBaudRate);
      } catch (configErr) {
        emitData("⚠️ [SYS] 포트 설정(DCB) 예외 무시: $configErr");
      }

      // 장비 전원/칩셋 부팅 대기 시간 (하드웨어 안정화)
      await Future.delayed(const Duration(milliseconds: 500));

      _startRxThread();

      onConnected();
      return true;
    } catch (e) {
      emitData("❌ [SYS] 시리얼 포트 연결 예외: $e");
      return false;
    }
  }

  /// C++의 TThread Execute() 함수 역할을 수행하는 폴링 루프입니다.
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
          break;
        }
      } else {
        break;
      }

      await Future.delayed(const Duration(milliseconds: 50));
    }

    _rxThreadRunning = false;
    debugPrint("[DEBUG] 시리얼 RX 폴링 스레드 완전히 종료됨");
  }

  /// 사용하던 메모리와 포트를 완벽하게 반환합니다. (메모리 릭 방지)
  Future<void> disconnect() async {
    if (_isDisconnecting) return;

    try {
      await onDisconnecting();
    } catch (e) {}

    _isDisconnecting = true;

    try {
      _socketSubscription?.cancel();
      _socketSubscription = null;
      _socket?.destroy();
      _socket = null;
    } catch (e) {}

    try {
      _terminateRxThread = true;
      int waitCount = 0;
      while (_rxThreadRunning) {
        await Future.delayed(const Duration(milliseconds: 10));
        waitCount++;
        if (waitCount > 100) break;
      }

      if (_serialPort != null) {
        try {
          if (_serialPort!.isOpen) _serialPort!.close();
        } catch (e) {}
      }

      _buffer = "";
    } catch (e) {}
  }

  void sendCommandString(String command) {
    if (command.isEmpty || _isDisconnecting) return;

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
    if (bytes.isEmpty || _isDisconnecting) return;

    String hexLog = bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
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
      if (!_tagStreamController.isClosed) await _tagStreamController.close();
    } catch (e) {}
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

  AutoReportProtocol({required super.ipAddress, required super.port, required this.startCmd, required this.stopCmd});

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

  PollingProtocol({required super.ipAddress, required super.port, required this.pollCmd, this.intervalMs = 500});

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
/// [구현체] Idro900f 전용 프로토콜
/// ===========================================================================
class Idro900fProtocol extends AutoReportProtocol {
  Completer<bool>? _writeCompleter;

  Idro900fProtocol(String ip, int port) : super(ipAddress: ip, port: port, startCmd: ">f\r\n", stopCmd: ">3\r\n");

  @override
  void onDataReceived(Uint8List data) {
    String rawHex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("<== [Raw] $rawHex");
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

          if (parts.length > 1) {
            rssi = parts[1];
          }
          if (parts.length > 2) {
            tid = parts[2];
          }
        } else {
          if (remainData.length > 4) {
            epc = remainData.substring(4);
          } else {
            epc = remainData;
          }
        }

        if (epc.isNotEmpty) {
          emitData('JSON:{"epc":"$epc", "ant":$antNo, "rssi":"$rssi", "tid":"$tid"}');
          emitData('🎯 [태그 인식] EPC: $epc | Ant: $antNo | RSSI: $rssi | TID: $tid');
        }

      } catch (e) {
        emitData("⚠️ [Idro 파싱 오류] 규격 외 데이터: $line");
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

    emitData("📝 [Idro 쓰기 준비] Bank:$bank, Offset:$offset, Length:$wordLength Words");

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
/// [구현체] Ats200/100 휴대형 리더기
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
/// 🔥 [에러 완전 정복] M120 / CL7206 "0xAA 특수 프로토콜" 지능형 엔진
/// Timeout을 막기 위한 5초 대기 락온 및 DLL 100% 모방 조립기 적용
/// ===========================================================================
class M120ClouReaderProtocol extends BaseDeviceProtocol {
  final List<int> _byteBuffer = [];
  Timer? _pollingTimer;
  Completer<bool>? _writeCompleter;
  Completer<String?>? _singleReadCompleter;

  M120ClouReaderProtocol(String ip, int port) : super(ipAddress: ip, port: port);

  @override
  void onConnected() {
    emitData("🚀 [SYS] M120 (0xAA 특수 프로토콜) 로우레벨 엔진 접속 완료!");
  }

  /// -------------------------------------------------------------------------
  /// 🛠️ [로우레벨 암호화] PR9200 칩셋의 CCITT-16 CRC 생성 함수
  /// -------------------------------------------------------------------------
  int _calculatePR9200CRC(List<int> data) {
    int crc = 0xFFFF;
    for (int i = 1; i < data.length; i++) { // 첫번째 0xAA는 계산에서 반드시 제외!
      crc ^= (data[i] << 8);
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x8000) != 0) {
          crc = (crc << 1) ^ 0x1021;
        } else {
          crc = crc << 1;
        }
      }
    }
    return crc & 0xFFFF;
  }

  /// 0xAA 프로토콜 패킷 발송기 (명령어 길이 1바이트를 Length 필드에서 제외합니다)
  void _sendAAPacket(int cmd, List<int> payload) {
    int txLen = payload.length;
    int lenH = (txLen >> 8) & 0xFF;
    int lenL = txLen & 0xFF;

    List<int> packet = [0xAA, 0x02, cmd, lenH, lenL];
    packet.addAll(payload);

    int crc = _calculatePR9200CRC(packet);
    packet.add((crc >> 8) & 0xFF);
    packet.add(crc & 0xFF);

    sendCommandBytes(packet);
  }

  @override
  Future<void> startInventory() async {
    emitData("▶️ [명령] 0xAA 규격 다중 스캔(Inventory) 가동!");
    if (_pollingTimer != null && _pollingTimer!.isActive) return;

    _pollingTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!isConnected || _isDisconnecting) {
        timer.cancel();
        return;
      }
      List<int> scanPacket = [0xAA, 0x02, 0x10, 0x00, 0x05, 0x01, 0x00, 0x02, 0x00, 0x06, 0x14, 0xE7];
      sendCommandBytes(scanPacket);
    });
  }

  @override
  Future<void> stopInventory() async {
    if (_pollingTimer != null) {
      _pollingTimer!.cancel();
      _pollingTimer = null;
      emitData("⏹️ [명령] 스캔 중지 완료");
    }
  }

  @override
  Future<void> onDisconnecting() async {
    await stopInventory();
  }

  @override
  void onDataReceived(Uint8List data) {
    String rawHex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    emitData("<== [Raw] $rawHex");

    _byteBuffer.addAll(data);

    while (_byteBuffer.isNotEmpty) {
      int startIdx = _byteBuffer.indexOf(0xAA);
      if (startIdx == -1) {
        _byteBuffer.clear();
        break;
      }
      if (startIdx > 0) {
        _byteBuffer.removeRange(0, startIdx);
      }

      if (_byteBuffer.length < 7) break;

      int payloadLen = (_byteBuffer[3] << 8) | _byteBuffer[4];
      if (payloadLen > 1024) {
        _byteBuffer.removeAt(0);
        continue;
      }

      int totalPacketSize = payloadLen + 7;
      if (_byteBuffer.length < totalPacketSize) break;

      List<int> packet = _byteBuffer.sublist(0, totalPacketSize);
      _byteBuffer.removeRange(0, totalPacketSize);

      int cmd = packet[2];
      List<int> payload = packet.sublist(5, 5 + payloadLen);

      _parseAAPayload(cmd, payload);
    }

    if (_byteBuffer.length > 8192) _byteBuffer.clear();
  }

  void _parseAAPayload(int cmd, List<int> payload) {
    if (cmd == 0x10 || cmd == 0x00) {
      if (payload.length <= 1) return;

      int ptr = 0;
      while (ptr + 2 < payload.length) {
        int epcLen = (payload[ptr] << 8) | payload[ptr + 1];

        if ((epcLen == 12 || epcLen == 16 || epcLen == 24) && ptr + 2 + epcLen <= payload.length) {
          List<int> epcData = payload.sublist(ptr + 2, ptr + 2 + epcLen);

          if (epcData.length >= 2) {
            List<int> pureEpcBytes = epcData.sublist(2); // 맨앞 2바이트(PC) 도려내기
            String epc = pureEpcBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

            if (_singleReadCompleter != null && !_singleReadCompleter!.isCompleted) {
              _singleReadCompleter!.complete(epc);
            }

            emitData('JSON:{"epc":"$epc", "ant":1, "rssi":"-", "tid":"-"}');
            emitData('🎯 [태그 인식] EPC: $epc | Ant: 1 | RSSI: - | TID: -');
          }
          ptr += 2 + epcLen + 8;
        } else {
          ptr++;
        }
      }
    }
    else if (cmd == 0x11 || cmd == 0x12 || cmd == 0x49) {
      if (payload.isNotEmpty) {
        int status = payload[0];
        if (status == 0x00 || status == 0x01) {
          emitData("✅ [장비 응답] 태그 데이터 쓰기 완벽 성공!");
          if (_writeCompleter != null && !_writeCompleter!.isCompleted) {
            _writeCompleter!.complete(true);
          }
        } else {
          String errMsg = "쓰기 거절";
          if (status == 0x16) errMsg = "입력 길이 오류(0x16) 또는 패스워드 불일치";

          emitData("❌ [장비 응답] $errMsg (에러코드: 0x${status.toRadixString(16).toUpperCase()})");
          if (_writeCompleter != null && !_writeCompleter!.isCompleted) {
            _writeCompleter!.complete(false);
          }
        }
      }
    }
  }

  @override
  String parseTagId(String rawData) => "";

  /// -------------------------------------------------------------------------
  /// 🔥 [쓰기 코어] 완벽한 조립 및 타임아웃 5초 대기 부여
  /// -------------------------------------------------------------------------
  @override
  Future<void> writeTagMemory(int bank, int offset, String dataHex, {String? targetEpc}) async {
    if (!isConnected) {
      emitData("⚠️ [쓰기 실패] 장비가 연결되어 있지 않습니다.");
      return;
    }

    await stopInventory();
    // 🔥 [타임아웃 해결] 장비가 완전히 쉴 수 있도록 0.5초간 통신을 중지합니다.
    await Future.delayed(const Duration(milliseconds: 500));
    _byteBuffer.clear();

    String paddedData = dataHex.toUpperCase().trim();
    if (paddedData.length % 4 != 0) {
      int neededChars = 4 - (paddedData.length % 4);
      paddedData = paddedData.padRight(paddedData.length + neededChars, '0');
    }

    List<int> dataBytes = [];
    for (int i = 0; i < paddedData.length; i += 2) {
      dataBytes.add(int.parse(paddedData.substring(i, i + 2), radix: 16));
    }

    List<int> finalDataBytes = [];
    int actualOffset = offset;

    // 🔥 [핵심 1] 입력 데이터가 뭐든 무조건 12바이트로 패딩을 꽉 채웁니다!
    if (bank == 1) {
      actualOffset = 1;

      while (dataBytes.length < 12) {
        dataBytes.add(0x00);
      }
      if (dataBytes.length > 12) {
        dataBytes = dataBytes.sublist(0, 12);
      }

      int epcWordCount = 6;
      int pc = (epcWordCount << 11);
      finalDataBytes.add((pc >> 8) & 0xFF);
      finalDataBytes.add(pc & 0xFF);
      finalDataBytes.addAll(dataBytes); // 14바이트 고정!
    } else {
      finalDataBytes.addAll(dataBytes);
    }

    emitData("📝 [M120 쓰기 준비] Bank:$bank, Offset:$actualOffset, Data Bytes:${finalDataBytes.length}");
    int maxRetries = 3;
    bool writeSuccess = false;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      emitData("▶️ [시도 $attempt/$maxRetries] 1단계: 단일 스캔(Read)으로 대상 태그 탐색...");
      _singleReadCompleter = Completer<String?>();

      List<int> scanPacket = [0xAA, 0x02, 0x10, 0x00, 0x05, 0x01, 0x00, 0x02, 0x00, 0x06, 0x14, 0xE7];
      sendCommandBytes(scanPacket);

      String? currentEpc;
      try {
        currentEpc = await _singleReadCompleter!.future.timeout(const Duration(milliseconds: 600));
      } catch (_) {}
      _singleReadCompleter = null;

      if (currentEpc == null || currentEpc.isEmpty) {
        emitData("⚠️ 주변에 태그가 없습니다. 재시도합니다...");
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }

      String epcToWriteTo = (targetEpc != null && targetEpc.isNotEmpty) ? targetEpc : currentEpc;
      emitData("🎯 2단계: 대상 락온($epcToWriteTo)! 즉시 쓰기(Write) 발사!");

      // 🔥 [핵심 2] 타겟 EPC 역시 무조건 12바이트(96비트)로 패딩을 꽉 채웁니다!
      List<int> targetBytes = [];
      String cleanEpc = epcToWriteTo.replaceAll(' ', '').toUpperCase();

      if (cleanEpc.length % 2 != 0) cleanEpc += '0';
      for (int i = 0; i < cleanEpc.length; i += 2) {
        targetBytes.add(int.parse(cleanEpc.substring(i, i + 2), radix: 16));
      }

      while (targetBytes.length < 12) {
        targetBytes.add(0x00);
      }
      if (targetBytes.length > 12) {
        targetBytes = targetBytes.sublist(0, 12);
      }

      int matchBitLength = targetBytes.length * 8; // 무조건 96(0x60) 비트

      // 완벽한 44바이트 Payload 배열을 조립합니다!
      List<int> payload = [];

      // [Write 영역] (20 바이트)
      payload.add(0x01); // Antenna
      payload.add(bank); // Write Bank
      payload.add((actualOffset >> 8) & 0xFF);
      payload.add(actualOffset & 0xFF);
      payload.add((finalDataBytes.length >> 8) & 0xFF);
      payload.add(finalDataBytes.length & 0xFF);
      payload.addAll(finalDataBytes);

      // [Target Match 영역] (19 바이트)
      payload.addAll([0x01, 0x00, 0x10, 0x02, 0x00, 0x00, matchBitLength]);
      payload.addAll(targetBytes);

      // [Password 영역] (5 바이트) 스니핑 로그와 동일하게 고정!
      payload.addAll([0x02, 0x00, 0x00, 0x00, 0x00]);

      _writeCompleter = Completer<bool>();

      // 0x11 (Write) 명령어 발사! 배열 길이는 정확히 44(0x2C)가 됩니다.
      _sendAAPacket(0x11, payload);

      try {
        // 🔥 [타임아웃 해결의 핵심] 하드웨어의 처리 시간을 넉넉하게 5초(5000ms)까지 허용합니다!
        writeSuccess = await _writeCompleter!.future.timeout(const Duration(milliseconds: 5000));
      } catch (e) {
        debugPrint("Write Timeout Exception: $e");
        writeSuccess = false;
      }

      if (writeSuccess) {
        emitData("🎉 [최종 성공] 태그에 데이터가 안전하게 기록되었습니다!");
        break;
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    if (!writeSuccess) {
      emitData("💥 [최종 실패] 3회 시도했으나 장비가 응답하지 않았거나 쓰기에 실패했습니다.");
    }
    _writeCompleter = null;
  }

  @override
  Future<void> setAntennaPower(int antennaIndex, int powerLevel) async {
    // 출력 변경 기능 보류
  }
}

/// ===========================================================================
/// [구현체] Chafon 전용 엔진 (CF_RU5102, CF815 등)
/// 스니퍼 로그를 완벽하게 분석하여 0x01(스캔)과 0x03(쓰기) 명령어로 재구성했습니다.
/// ===========================================================================
class ChafonProtocol extends BaseDeviceProtocol {
  final List<int> _byteBuffer = [];
  Timer? _pollingTimer;
  Completer<bool>? _writeCompleter;
  Completer<String?>? _singleReadCompleter;

  ChafonProtocol(String ip, int port) : super(ipAddress: ip, port: port);

  @override
  void onConnected() {
    emitData("🚀 [SYS] Chafon(CF_RU5102) 로우레벨 엔진 접속 성공!");
  }

  /// 하드웨어로 명령어를 전송하는 공통 함수 (CRC16 자동 계산 적용)
  /// 스니퍼 로그 분석 결과 Address는 기본적으로 0x00을 사용합니다.
  void _sendCommand(int cmd, List<int> data, {int address = 0x00}) {
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

  @override
  Future<void> startInventory() async {
    emitData("▶️ [명령] CF_RU5102 전용 단일 스캔(0x01) 폴링 가동!");
    if (_pollingTimer != null && _pollingTimer!.isActive) return;

    // 스니퍼 로그처럼 150ms 간격으로 스캔 명령(0x01)을 폴링합니다.
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!isConnected || _isDisconnecting) {
        timer.cancel();
        return;
      }
      _sendCommand(0x01, [], address: 0x00);
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
    String rawHex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    emitData("<== [Raw] $rawHex");

    _byteBuffer.addAll(data);

    // 패킷 조립기: 길이를 기반으로 완전한 패킷만 추출하여 파싱합니다.
    while (_byteBuffer.isNotEmpty) {
      int header = _byteBuffer[0];

      // Length 바이트는 통상적으로 최소 3 이상, 최대 128 이하로 들어옵니다.
      if (header >= 0x03 && header <= 0x80) {
        int totalPacketSize = header + 1; // Length 바이트 자체의 크기 1바이트 추가

        // 버퍼에 전체 패킷이 아직 다 안 들어왔으면 대기
        if (_byteBuffer.length < totalPacketSize) break;

        List<int> packet = _byteBuffer.sublist(0, totalPacketSize);
        _byteBuffer.removeRange(0, totalPacketSize);

        int cmd = packet[2];
        List<int> payload = packet.sublist(3, packet.length - 2); // CRC 2바이트 제외

        _parsePayload(cmd, payload);
      }
      else {
        // 쓰레기 데이터 폐기
        _byteBuffer.removeAt(0);
      }
    }

    if (_byteBuffer.length > 8192) _byteBuffer.clear(); // 메모리 보호
  }

  /// 명령어 종류에 따라 응답을 분석합니다.
  void _parsePayload(int cmd, List<int> payload) {
    // [명령어 0x03] 쓰기(Write Data) 응답 처리
    if (cmd == 0x03) {
      if (payload.isNotEmpty) {
        int status = payload[0];
        // 스니퍼에서 FF는 에러/실패를 의미했습니다. 00이면 성공으로 처리합니다.
        if (status == 0x00 || status == 0x01) {
          emitData("✅ [장비 응답] 쓰기(Write) 완벽 성공!");
          if (_writeCompleter != null && !_writeCompleter!.isCompleted) _writeCompleter!.complete(true);
        } else {
          emitData("❌ [장비 응답] 쓰기 실패 (상태코드: 0x${status.toRadixString(16).toUpperCase()})");
          if (_writeCompleter != null && !_writeCompleter!.isCompleted) _writeCompleter!.complete(false);
        }
      }
      return;
    }

    // [명령어 0x01] 인벤토리(스캔) 응답 처리
    // 스니퍼 로그(0d 00 01 01 01 0c 4b...) 구조를 반영합니다.
    if (cmd == 0x01) {
      if (payload.isNotEmpty) {
        int tagCount = payload[0];
        int offset = 1;

        for (int i = 0; i < tagCount; i++) {
          if (offset >= payload.length) break;

          // CF_RU5102 스니퍼 분석: Ant(1) + EpcLen(1) + EPC(EpcLen)
          int ant = payload[offset];
          int epcLen = payload[offset + 1];
          offset += 2;

          if (offset + epcLen <= payload.length) {
            List<int> epcBytes = payload.sublist(offset, offset + epcLen);
            String rawHexEpc = epcBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

            // 단일 스캔(쓰기 작업의 1단계) 대기 중이라면 대상 EPC를 넘겨줍니다.
            if (_singleReadCompleter != null && !_singleReadCompleter!.isCompleted) {
              _singleReadCompleter!.complete(rawHexEpc);
            }

            emitData('JSON:{"epc":"$rawHexEpc", "ant":$ant, "rssi":"-", "tid":"-"}');
            emitData('🎯 [태그 인식] EPC: $rawHexEpc | Ant: $ant | RSSI: - | TID: -');
            offset += epcLen;
          } else {
            break; // 데이터 짤림 방지
          }
        }
      }
    }
  }

  @override
  String parseTagId(String rawData) => "";

  /// 스니퍼 로그를 완벽 재현한 CF_RU5102 전용 쓰기 엔진입니다.
  /// 명령어 0x03과 정밀한 Payload 조립을 사용합니다.
  @override
  Future<void> writeTagMemory(int bank, int offset, String dataHex, {String? targetEpc}) async {
    if (!isConnected) {
      emitData("⚠️ [쓰기 실패] 장비가 연결되어 있지 않습니다.");
      return;
    }

    await stopInventory();
    await Future.delayed(const Duration(milliseconds: 100)); // 하드웨어 안정화 대기
    _byteBuffer.clear();

    String? activeTargetEpc = targetEpc?.trim();

    // 1. 기록할 데이터 패딩 (Word 단위, 4자리 Hex = 2 Bytes = 1 Word)
    String paddedData = dataHex.toUpperCase().trim();
    if (paddedData.length % 4 != 0) {
      int neededChars = 4 - (paddedData.length % 4);
      paddedData = paddedData.padRight(paddedData.length + neededChars, '0');
    }

    List<int> dataBytes = [];
    for (int i = 0; i < paddedData.length; i += 2) {
      dataBytes.add(int.parse(paddedData.substring(i, i + 2), radix: 16));
    }
    int dataWordCount = dataBytes.length ~/ 2;

    int maxRetries = 3;
    bool writeSuccess = false;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      emitData("▶️ [시도 $attempt/$maxRetries] 1단계: 주변 태그 스캔...");
      _singleReadCompleter = Completer<String?>();

      // 0x01 명령어로 주변 태그를 깨우고 EPC를 확보합니다.
      _sendCommand(0x01, [], address: 0x00);

      String? currentEpc;
      try {
        currentEpc = await _singleReadCompleter!.future.timeout(const Duration(milliseconds: 800));
      } catch (e) {
        currentEpc = null;
      }
      _singleReadCompleter = null;

      if (currentEpc == null || currentEpc.isEmpty) {
        emitData("⚠️ 응답하는 태그가 없습니다. 재시도합니다...");
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }

      String epcToWriteTo = (activeTargetEpc != null && activeTargetEpc.isNotEmpty) ? activeTargetEpc : currentEpc;
      emitData("🎯 2단계: 대상 락온($epcToWriteTo)! Cmd: 0x03 쓰기 발사!");

      // 2. 타겟 EPC 패딩 준비 (헥사 변환)
      String cleanEpc = epcToWriteTo.replaceAll(' ', '').toUpperCase();
      if (cleanEpc.length % 4 != 0) {
        int needed = 4 - (cleanEpc.length % 4);
        cleanEpc = cleanEpc.padRight(cleanEpc.length + needed, '0');
      }

      List<int> epcBytes = [];
      try {
        for (int i = 0; i < cleanEpc.length; i += 2) {
          epcBytes.add(int.parse(cleanEpc.substring(i, i + 2), radix: 16));
        }
      } catch (e) {
        emitData("❌ [EPC 파싱 오류] 올바른 Hex 형식이 아닙니다.");
        return;
      }
      int epcWordCount = epcBytes.length ~/ 2;

      // 3. 스니퍼 로그 완벽 대응 Payload 조립 (Cmd: 0x03)
      // 패킷 구조: [데이터 Word 수] + [EPC Word 수] + [EPC 데이터] + [Bank] + [Offset] + [기록할 데이터] + [Password]
      List<int> writePayload = [];
      writePayload.add(dataWordCount);
      writePayload.add(epcWordCount);
      writePayload.addAll(epcBytes);
      writePayload.add(bank);
      writePayload.add(offset & 0xFF); // Offset은 1바이트 크기 보장
      writePayload.addAll(dataBytes);
      writePayload.addAll([0x00, 0x00, 0x00, 0x00]); // 비밀번호 (기본값)

      _writeCompleter = Completer<bool>();
      _sendCommand(0x03, writePayload, address: 0x00); // 스니퍼에서 본 0x03 커맨드로 전송

      try {
        writeSuccess = await _writeCompleter!.future.timeout(const Duration(milliseconds: 2000));
      } catch (e) {
        writeSuccess = false;
      }

      if (writeSuccess) {
        emitData("🎉 [최종 성공] 태그에 데이터가 안전하게 기록되었습니다!");
        break; // 성공 시 루프 탈출
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    _writeCompleter = null;
  }

  @override
  Future<void> setAntennaPower(int antennaIndex, int powerLevel) async {
    if (!isConnected) return;
    int pwr = powerLevel ~/ 10;
    if (pwr > 30) pwr = 30;
    // 기존 0x2F 파워 설정 커맨드는 유지합니다.
    _sendCommand(0x2F, [pwr], address: 0x00);
  }
}

/// ===========================================================================
/// 프린터 / 범용 장비 파서 (단순 문자열 기반 처리용)
/// ===========================================================================

class ZebraPrinterProtocol extends PollingProtocol {
  ZebraPrinterProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, pollCmd: "~HS", intervalMs: 1000);

  @override
  String parseTagId(String packet) => packet.trim();
}

class SatoPrinterProtocol extends AutoReportProtocol {
  SatoPrinterProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: "\x1bA", stopCmd: "\x1bZ");

  @override
  String parseTagId(String packet) => packet.trim();
}

class GenericRs232cProtocol extends AutoReportProtocol {
  GenericRs232cProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: "", stopCmd: "");

  @override
  String parseTagId(String packet) => packet.trim();
}

class DefaultProtocol extends AutoReportProtocol {
  DefaultProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: "START\n", stopCmd: "STOP\n");

  @override
  String parseTagId(String packet) => packet.trim();
}

/// ---------------------------------------------------------------------------
/// [팩토리] 모델 식별자에 따른 적절한 프로토콜 객체 생성 (Driver Factory 패턴)
/// ---------------------------------------------------------------------------
class DeviceProtocolFactory {
  static BaseDeviceProtocol create(String modelValue, String ip, int port) {
    switch (modelValue) {
      case SupportedDeviceModels.idro900f: return Idro900fProtocol(ip, port);
      case SupportedDeviceModels.ats200: return Ats200Protocol(ip, port);
      case SupportedDeviceModels.hopeland:
      case SupportedDeviceModels.m120: return M120ClouReaderProtocol(ip, port);
      case SupportedDeviceModels.chafon:
      case SupportedDeviceModels.cf815:
      case SupportedDeviceModels.cfRU5102:
      case SupportedDeviceModels.cf601: return ChafonProtocol(ip, port);
      case SupportedDeviceModels.sato: return SatoPrinterProtocol(ip, port);
      case SupportedDeviceModels.zebra: return ZebraPrinterProtocol(ip, port);
      case SupportedDeviceModels.genericRs232c: return GenericRs232cProtocol(ip, port);
      case SupportedDeviceModels.bt200:
      case SupportedDeviceModels.genericTcp:
      default: return DefaultProtocol(ip, port);
    }
  }
}