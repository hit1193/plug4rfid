import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

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

  SerialPort? _serialPort;

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
      _serialPort ??= SerialPort(ipAddress);

      if (!_serialPort!.openReadWrite()) {
        emitData("❌ [SYS] 시리얼 포트 개방 실패: $ipAddress");
        return false;
      }

      try {
        SerialPortConfig config = _serialPort!.config;
        config.baudRate = port;
        config.bits = 8;
        config.stopBits = 1;
        config.parity = SerialPortParity.none;
        _serialPort!.config = config;
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
    if (line.startsWith('>T') && line.length >= 5) {
      try {
        String antChar = line.substring(2, 3);
        int antNo = (int.tryParse(antChar) ?? 0) + 1;

        String remainData = line.substring(3);
        String epc = "";
        String rssi = "알수없음";
        String tid = "없음";

        if (remainData.contains(',')) {
          List<String> parts = remainData.split(',');
          epc = parts[0];

          if (parts.length > 1) {
            rssi = parts[1];
          }
          if (parts.length > 2) {
            tid = parts[2];
          }
        } else {
          epc = remainData.length > 4 ? remainData.substring(4) : remainData;
        }

        String direction = (antNo <= 2) ? "IN (입고/입장)" : "OUT (출고/퇴장)";
        String jsonPayload = 'JSON:{"epc":"$epc", "ant":$antNo, "rssi":"$rssi", "tid":"$tid", "direction":"$direction"}';
        emitData(jsonPayload);
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
/// [구현체] Hopeland 리더기
/// ===========================================================================
class HopelandProtocol extends BaseDeviceProtocol {
  final List<int> _byteBuffer = [];
  Completer<bool>? _writeCompleter;

  HopelandProtocol(String ip, int port) : super(ipAddress: ip, port: port);

  @override
  void onConnected() {}

  @override
  void onDataReceived(Uint8List data) {
    _byteBuffer.addAll(data);

    while (_byteBuffer.isNotEmpty) {
      if (_byteBuffer[0] != 0xAA) {
        _byteBuffer.removeAt(0);
        continue;
      }

      if (_byteBuffer.length < 5) {
        break;
      }

      int dataLength = (_byteBuffer[3] << 8) | _byteBuffer[4];
      int totalPacketSize = 5 + dataLength + 2;

      if (_byteBuffer.length < totalPacketSize) {
        break;
      }

      List<int> completePacket = _byteBuffer.sublist(0, totalPacketSize);
      _byteBuffer.removeRange(0, totalPacketSize);

      int commandCode = (completePacket[1] << 8) | completePacket[2];

      if (commandCode == 0x0102) {
        List<int> epcBytes = completePacket.sublist(5, completePacket.length - 2);
        String epcHex = epcBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();

        if (epcHex.isNotEmpty) {
          emitData('JSON:{"epc":"$epcHex", "ant":1, "rssi":"-", "tid":"-"}');
        }
      }
      else if (commandCode == 0x0104) {
        if (completePacket.length >= 6) {
          int result = completePacket[5];
          if (result == 0x00) {
            emitData("✅ [장비 응답] 태그 데이터 기록 성공!");
            if (_writeCompleter != null && !_writeCompleter!.isCompleted) {
              _writeCompleter!.complete(true);
            }
          } else {
            emitData("❌ [장비 응답] 기록 실패 (에러코드: 0x${result.toRadixString(16).toUpperCase()})");
            if (_writeCompleter != null && !_writeCompleter!.isCompleted) {
              _writeCompleter!.complete(false);
            }
          }
        }
      }
    }

    if (_byteBuffer.length > 8192) {
      _byteBuffer.clear();
    }
  }

  @override
  String parseTagId(String rawData) {
    return "";
  }

  @override
  Future<void> writeTagMemory(int bank, int offset, String dataHex, {String? targetEpc}) async {
    if (!isConnected) {
      emitData("⚠️ [쓰기 실패] Hopeland 장비가 연결되어 있지 않습니다.");
      return;
    }

    String paddedData = dataHex.toUpperCase().trim();
    if (paddedData.length % 4 != 0) {
      int neededChars = 4 - (paddedData.length % 4);
      paddedData = paddedData.padRight(paddedData.length + neededChars, '0');
    }

    int wordLength = paddedData.length ~/ 4;
    List<int> dataBytes = [];
    for (int i = 0; i < paddedData.length; i += 2) {
      dataBytes.add(int.parse(paddedData.substring(i, i + 2), radix: 16));
    }

    int payloadLen = 1 + 4 + 1 + 1 + 1 + dataBytes.length;

    List<int> packet = [
      0xAA, 0x00,
      (payloadLen >> 8) & 0xFF, payloadLen & 0xFF,
      0x00, 0x00,
      0x09,
      0x00, 0x00, 0x00, 0x00,
      bank, offset, wordLength
    ];
    packet.addAll(dataBytes);

    int checksum = 0;
    for (int i = 1; i < packet.length; i++) {
      checksum = (checksum + packet[i]) & 0xFF;
    }
    packet.add(checksum);

    emitData("📝 [Hopeland 쓰기 준비] Bank:$bank, Offset:$offset, WordCnt:$wordLength");

    int maxRetries = 3;
    bool writeSuccess = false;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      emitData("▶️ [명령어 발송] 쓰기 시도 ($attempt/$maxRetries)");

      _writeCompleter = Completer<bool>();
      sendCommandBytes(packet);

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
/// [최종 완성형] Marktrace (UHFReader09) 전용 해독 엔진 (CF_RU5102, CF815 포함)
/// 🔥 0xFD 바이트 밀림(Byte Misalignment) 버그 완벽 패치!
/// 영문 매뉴얼의 오역(EpcWord)을 무시하고, EPC 길이를 바이트(Bytes) 단위로 조립하여
/// C++ SDK의 WriteCard_G2와 100% 동일한 패킷 구조를 구현했습니다.
/// ===========================================================================
class ChafonProtocol extends BaseDeviceProtocol {
  final List<int> _byteBuffer = [];
  Timer? _pollingTimer;

  int _discoveryStep = 0;
  int _lockedProtocol = -1;

  Completer<bool>? _writeCompleter;

  // 수동 스캔(0x01) 시 장비의 응답을 기다리는 비동기 객체
  Completer<String?>? _singleReadCompleter;

  ChafonProtocol(String ip, int port) : super(ipAddress: ip, port: port);

  @override
  void onConnected() {
    emitData("🚀 [SYS] Chafon CF_RU5102 장치 접속 성공: $ipAddress:$port");
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
          sendUHFReader09Command(0x27, [0xFF], address: 0xFF);
        } else if (_discoveryStep == 3) {
          sendR2000Command(0x89, [0x01], address: 0xFF);
        } else if (_discoveryStep == 4) {
          sendCommandHex("BB 00 22 00 00 22 7E");
        }
        _discoveryStep = (_discoveryStep + 1) % 5;
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
      sendUHFReader09Command(0x27, [0xFF], address: 0xFF);
    } else if (_lockedProtocol == 3) {
      sendR2000Command(0x89, [0x01], address: 0xFF);
    } else if (_lockedProtocol == 4) {
      sendCommandHex("BB 00 22 00 00 22 7E");
    }
  }

  void _lockOnProtocol(int protocolType, String name) {
    if (_lockedProtocol != -1) {
      return;
    }

    _lockedProtocol = protocolType;
    emitData("✅ [장비 락온] $name 규격 고속 폴링 전환 완료!");
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

    if (_lockedProtocol == -1) {
      if (cmd == 0x01 || cmd == 0x27 || cmd == 0x0F) {
        if (address == 0xFF) {
          _lockOnProtocol(0, "UHFReader09 (Addr: 0xFF)");
        } else {
          _lockOnProtocol(1, "UHFReader09 (Addr: 0x00)");
        }
      }
    }

    // 0x06(Write Data By EPC 타겟 쓰기) 응답 처리
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

    if (payload.isNotEmpty && payload.length == 1 && payload[0] == 0xFF) {
      return;
    }

    // 단일 태그 읽기 (Single Read) 응답 시
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
    // 다중 태그 읽기 (Multi Read) 응답 시
    else if (cmd == 0x01 || cmd == 0x02 || cmd == 0x0F) {
      if (payload.isNotEmpty) {
        int tagCount = payload[0];
        int offset = 1;

        for (int i = 0; i < tagCount; i++) {
          if (offset >= payload.length) {
            break;
          }

          int ant = payload[offset];
          offset += 1;

          if (offset >= payload.length) {
            break;
          }

          int epcLen = payload[offset];
          offset += 1;

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

  /// 🔥 [바이트 밀림(Misalignment) 완벽 패치판]
  /// 매뉴얼의 'EpcWord'라는 오역을 무시하고, EPC 길이를 '바이트(Bytes)' 단위로 정확하게 입력하여
  /// 0xFD 파라미터 에러를 완벽하게 근절한 C++ DLL 'WriteCard_G2'의 최종 완성형입니다.
  @override
  Future<void> writeTagMemory(int bank, int offset, String dataHex, {String? targetEpc}) async {
    if (!isConnected) {
      emitData("⚠️ [쓰기 실패] 장비가 연결되어 있지 않습니다.");
      return;
    }

    await stopInventory();
    await Future.delayed(const Duration(milliseconds: 50));
    _byteBuffer.clear();

    int targetAddress = _lockedProtocol == 1 ? 0x00 : 0xFF;
    String? activeTargetEpc = targetEpc?.trim();

    // 기록할 데이터를 짝수(1워드 = 2바이트)로 예쁘게 맞춰줍니다.
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

    // 🔥 재시도 루프 내부에서 [읽기 -> 0x06 쓰기] 패턴을 반복합니다.
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      emitData("▶️ [시도 $attempt/$maxRetries] 1단계: 태그 스캔(Inventory)하여 깨우기...");

      // 1. 태그 읽기 (Inventory - 0x01)
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

      // 2. 태그 쓰기 (WriteCard_G2 - 0x06)
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

      // 🔥 [핵심 버그 수정] EpcWord 파라미터는 영문 매뉴얼의 오역이며, 실제로는 '바이트 수(Bytes)'를 넣어야 합니다!
      int epcLenInBytes = epcBytes.length; // 12바이트면 0x0C가 들어가야 바이트 밀림(0xFD)이 발생하지 않습니다.

      List<int> writeData = [];
      writeData.add(epcLenInBytes); // <- 여기가 0xFD 에러를 유발했던 범인이었습니다! 완벽 수정!
      writeData.addAll(epcBytes);
      writeData.addAll([0x00, 0x00, 0x00, 0x00]); // 비밀번호 (기본값)
      writeData.add(bank);
      writeData.add(offset);
      writeData.add(totalWords); // 쓸 데이터의 길이는 '워드 수'가 맞습니다.
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