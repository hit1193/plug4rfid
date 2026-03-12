import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart'; // 시리얼 통신 패키지

/// ---------------------------------------------------------------------------
/// [상수 정의] 지원하는 구체적 장치 모델 리스트
/// PocketBase의 'model' 필드 Select 옵션과 1:1 매칭됩니다.
/// ---------------------------------------------------------------------------
class SupportedDeviceModels {
  static const String idro900f      = 'IDRO900F';
  static const String cf815         = 'CF815';
  static const String cfRU5102      = 'CF_RU5102';
  static const String cf601         = 'CF601';
  static const String ats200        = 'ATS200';
  static const String m120          = 'M120';         // Hopeland 계열 데스크형 리더기
  static const String hopeland      = 'HOPELAND';     // Hopeland 리더기 범용
  static const String chafon        = 'CHAFON';       // CHAFON 리더기 범용
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
/// [최상위 하이브리드 통신 엔진]
/// 🚀 데드락 방지를 위해 논블로킹(Non-blocking) 커스텀 리더 구조를 적용했습니다.
/// ---------------------------------------------------------------------------
abstract class BaseDeviceProtocol {
  final String ipAddress;
  final int port;

  // 1. TCP/IP 통신용 변수
  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;

  // 2. USB 시리얼 통신용 변수 (데드락 방지 엔진)
  SerialPort? _serialPort;
  // 🔥 말썽을 일으키는 SerialPortReader를 버리고 커스텀 타이머 폴링 방식을 사용합니다!
  Timer? _serialPollingTimer;

  // [버퍼링 엔진] 누적 버퍼
  String _buffer = "";

  // 장비에서 읽어들인 데이터를 Provider로 쏘아주는 파이프
  final StreamController<String> _tagStreamController = StreamController<String>.broadcast();

  Stream<String> get tagStream {
    return _tagStreamController.stream;
  }

  bool get isConnected {
    return _socket != null || _serialPort != null;
  }

  BaseDeviceProtocol({required this.ipAddress, required this.port});

  Future<bool> connect() async {
    try {
      String upperIp = ipAddress.toUpperCase();

      bool isBluetoothMac = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$').hasMatch(ipAddress);
      bool isUsbSerial = upperIp.startsWith('COM') || upperIp.startsWith('/DEV/');

      if (isBluetoothMac) {
        debugPrint("⚠️ 안드로이드 블루투스(SPP) 장비 감지! 현재 플랫폼 미지원.");
        return false;
      } else if (isUsbSerial) {
        return await _connectUsbSerial();
      } else {
        return await _connectTcpSocket();
      }
    } catch (e) {
      debugPrint("통신 엔진 연결 초기화 실패: $e");
      _socket = null;
      _serialPort = null;
      return false;
    }
  }

  Future<bool> _connectTcpSocket() async {
    try {
      _socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 3));

      _socketSubscription = _socket!.listen(
        _internalOnDataReceived,
        onError: (error) {
          disconnect();
        },
        onDone: () {
          disconnect();
        },
      );

      onConnected();
      return true;
    } catch (e) {
      _socket = null;
      return false;
    }
  }

  /// [파이프라인 2] USB / RS-232C 기반 가상 시리얼 포트 연결 (데드락 완벽 방어)
  Future<bool> _connectUsbSerial() async {
    debugPrint("🔌 USB/시리얼 포트 연결 시도: $ipAddress (BaudRate: $port)");

    try {
      _serialPort = SerialPort(ipAddress);

      if (!_serialPort!.openReadWrite()) {
        debugPrint("❌ 시리얼 포트 개방 실패: $ipAddress");
        return false;
      }

      SerialPortConfig config = _serialPort!.config;
      config.baudRate = port;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;
      _serialPort!.config = config;

      // 🚀 핵심: Blocking Stream(SerialPortReader) 대신
      // 50ms마다 포트에 데이터가 쌓였는지 물어보고(Polling) 읽어오는 논블로킹 타이머!
      _serialPollingTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (_serialPort != null && _serialPort!.isOpen) {
          try {
            // bytesAvailable: 포트 버퍼에 들어있는 읽을 수 있는 바이트 수
            if (_serialPort!.bytesAvailable > 0) {
              // 쌓인 만큼만 딱 읽어옵니다. (블로킹이 걸리지 않음)
              Uint8List data = _serialPort!.read(_serialPort!.bytesAvailable);
              if (data.isNotEmpty) {
                _internalOnDataReceived(data);
              }
            }
          } catch (readError) {
            debugPrint("시리얼 읽기 폴링 에러: $readError");
          }
        } else {
          // 포트가 닫히면 타이머 자폭
          timer.cancel();
        }
      });

      onConnected();
      return true;
    } catch (e) {
      debugPrint("시리얼 포트 연결 예외 발생: $e");
      _serialPort = null;
      return false;
    }
  }

  /// 연결 종료 및 메모리 완전 해제 (Garbage Collection)
  void disconnect() {
    debugPrint("========== [DEBUG] disconnect() 진입 ==========");
    try {
      onDisconnecting();
    } catch (e) {
      debugPrint("[DEBUG] onDisconnecting 예외 무시: $e");
    }

    // TCP 해제
    try {
      _socketSubscription?.cancel();
      _socketSubscription = null;
      _socket?.destroy();
      _socket = null;
    } catch (e) {
      debugPrint("[DEBUG] TCP 소켓 해제 예외 무시: $e");
    }

    // USB 시리얼 자원 해제
    try {
      // 1. 가장 먼저 데이터 읽어오는 타이머부터 확실하게 죽입니다!
      _serialPollingTimer?.cancel();
      _serialPollingTimer = null;
      debugPrint("[DEBUG] 시리얼 폴링 타이머 종료 완료");

      if (_serialPort != null) {
        if (_serialPort!.isOpen) {
          // 블로킹 스트림이 없으므로 이제 close()가 멈추지 않고 즉시 반환됩니다!
          _serialPort!.close();
          debugPrint("[DEBUG] 시리얼 포트 close() 완료");
        }
        _serialPort!.dispose();
        debugPrint("[DEBUG] 시리얼 포트 dispose() 완료");
        _serialPort = null;
      }
    } catch (e) {
      debugPrint("[DEBUG] USB 시리얼 포트 해제 예외: $e");
    }

    _buffer = "";
    debugPrint("========== [DEBUG] disconnect() 정상 탈출 ==========");
  }

  void sendCommandString(String command) {
    if (command.isEmpty) {
      return;
    }

    if (_socket != null) {
      _socket!.write(command);
      _socket!.flush();
    } else if (_serialPort != null && _serialPort!.isOpen) {
      _serialPort!.write(Uint8List.fromList(command.codeUnits));
    }
  }

  void sendCommandBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }

    if (_socket != null) {
      _socket!.add(bytes);
      _socket!.flush();
    } else if (_serialPort != null && _serialPort!.isOpen) {
      _serialPort!.write(Uint8List.fromList(bytes));
    }
  }

  void dispose() {
    disconnect();
    try {
      if (!_tagStreamController.isClosed) {
        _tagStreamController.close();
      }
    } catch (e) {
      debugPrint("[DEBUG] StreamController 닫기 오류 무시: $e");
    }
  }

  void _internalOnDataReceived(Uint8List data) {
    onDataReceived(data);
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

  // 자식 클래스에서 구현할 추상 메서드들
  void onConnected();
  void onDisconnecting();
  String parseTagId(String rawData);

  Future<void> startInventory() async {}
  Future<void> setAntennaPower(int antennaIndex, int powerLevel) async {}
  Future<void> readTagMemory(int bank, int offset, int length) async {}
  Future<void> writeTagMemory(int bank, int offset, String dataHex) async {}
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
  void onDisconnecting() {
    sendCommandString(stopCmd);
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
  void onDisconnecting() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }
}

/// ===========================================================================
/// [구현체] IDRO900F 전용 프로토콜
/// ===========================================================================
class Idro900fProtocol extends AutoReportProtocol {
  Idro900fProtocol(String ip, int port) : super(ipAddress: ip, port: port, startCmd: ">f\r\n", stopCmd: ">3\r\n");

  @override
  void onDataReceived(Uint8List data) {
    String rawHex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
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
          if (remainData.length > 4) {
            epc = remainData.substring(4);
          } else {
            epc = remainData;
          }
        }

        String direction = (antNo <= 2) ? "IN (입고/입장)" : "OUT (출고/퇴장)";
        String jsonPayload = 'JSON:{"epc":"$epc", "ant":$antNo, "rssi":"$rssi", "tid":"$tid", "direction":"$direction"}';
        _tagStreamController.add(jsonPayload);

      } catch (e) {
        _tagStreamController.add("⚠️ [IDRO 파싱 오류] 규격 외 데이터: $line");
      }
    } else if (line.startsWith('>R')) {
      _tagStreamController.add("🔍 [메모리 읽기 응답] $line");
    } else {
      if (line != ">") {
        _tagStreamController.add("ℹ️ [장비 응답] $line");
      }
    }
  }

  @override
  String parseTagId(String packet) {
    return "";
  }

  @override
  Future<void> writeTagMemory(int bank, int offset, String dataHex) async {
    if (!isConnected) {
      if (!_tagStreamController.isClosed) {
        _tagStreamController.add("⚠️ [쓰기 실패] 장비가 연결되어 있지 않습니다.");
      }
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

    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("📝 [IDRO 쓰기 준비] Bank:$bank, Offset:$offset, Length:$wordLength Words");
      _tagStreamController.add("▶️ [명령어 발송] $command");
    }

    sendCommandString(command);
    await Future.delayed(const Duration(milliseconds: 500));
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
/// [구현체] Hopeland 리더기 (0xAA 헤더 규격)
/// ===========================================================================
class HopelandProtocol extends BaseDeviceProtocol {
  final List<int> _byteBuffer = [];

  HopelandProtocol(String ip, int port) : super(ipAddress: ip, port: port);

  @override
  void onConnected() {}

  @override
  void onDisconnecting() {}

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

      // Inventory 응답(0x0102) 패킷인 경우 EPC 추출
      if (commandCode == 0x0102) {
        List<int> epcBytes = completePacket.sublist(5, completePacket.length - 2);
        String epcHex = epcBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();

        if (epcHex.isNotEmpty && !_tagStreamController.isClosed) {
          _tagStreamController.add(epcHex);
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
  Future<void> writeTagMemory(int bank, int offset, String dataHex) async {
    if (!isConnected) {
      if (!_tagStreamController.isClosed) {
        _tagStreamController.add("⚠️ [쓰기 실패] Hopeland 장비가 연결되어 있지 않습니다.");
      }
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

    // Hopeland 프레임 조립 (Write Tag: 0x09)
    int payloadLen = 1 + 4 + 1 + 1 + 1 + dataBytes.length;

    List<int> packet = [
      0xAA, 0x00,
      (payloadLen >> 8) & 0xFF, payloadLen & 0xFF,
      0x00, 0x00,
      0x09, // Command 0x09
      0x00, 0x00, 0x00, 0x00, // Password
      bank, offset, wordLength
    ];
    packet.addAll(dataBytes);

    int checksum = 0;
    for (int i = 1; i < packet.length; i++) {
      checksum = (checksum + packet[i]) & 0xFF;
    }
    packet.add(checksum);

    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("📝 [Hopeland 쓰기 준비] Bank:$bank, Offset:$offset, WordCnt:$wordLength");
      String hexLog = packet.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
      _tagStreamController.add("▶️ [Hopeland 명령어 발송] $hexLog");
    }

    sendCommandBytes(packet);

    await Future.delayed(const Duration(milliseconds: 600));
  }
}

/// ===========================================================================
/// [최종 완성형] Marktrace (UHFReader09) 전용 해독 엔진
/// ===========================================================================
class ChafonProtocol extends BaseDeviceProtocol {
  final List<int> _byteBuffer = [];
  Timer? _pollingTimer;

  int _discoveryStep = 0;
  int _lockedProtocol = -1; // -1: 탐색중, 0: UHFReader09, 1: R2000, 2: BB, 3: 5A

  // 탐색 모드 핑 리스트
  final List<Map<String, dynamic>> _hardcodedPings = [
    {
      'name': 'UHFReader09 (Marktrace)',
      'desc': 'Inventory (0x01)',
      'cmd': 0x01
    },
    {
      'name': 'R2000 / E710 (0xA0)',
      'desc': 'Inventory (0x89)',
      'cmd': 0x89
    },
    {
      'name': 'CHAFON 범용 (0xBB)',
      'desc': 'Inventory (0x22)',
      'cmd': 0x22
    },
    {
      'name': 'EVEN 프로토콜 (0x5A)',
      'desc': 'Inventory (0x39)',
      'cmd': 0x39
    }
  ];

  ChafonProtocol(String ip, int port) : super(ipAddress: ip, port: port);

  @override
  void onConnected() {
    debugPrint("장치 통신 포트 접속 성공: $ipAddress:$port");
  }

  @override
  Future<void> startInventory() async {
    await Future.delayed(const Duration(milliseconds: 500));

    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("=========================================");
      _tagStreamController.add("🎯 [시스템] Marktrace 정밀 해독 엔진 가동!");
      _tagStreamController.add("🔥 파라미터가 장착된 0x01 모드로 타격합니다.");
      _tagStreamController.add("=========================================");
    }

    _pollingTimer?.cancel();

    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (!isConnected) {
        timer.cancel();
        return;
      }

      if (_lockedProtocol == -1) {
        if (_discoveryStep == 0) {
          sendUHFReader09Command(0x01, [0x04, 0x00], address: 0xFF);
        } else if (_discoveryStep == 1) {
          sendR2000Command(0x89, [0x01], address: 0xFF);
        } else if (_discoveryStep == 2) {
          sendCommandHex("BB 00 22 00 00 22 7E");
        } else {
          _sendRawBytes([0x5A, 0x00, 0x04, 0x01, 0x39, 0x3E], "EVEN", "Inventory");
        }

        _discoveryStep = (_discoveryStep + 1) % _hardcodedPings.length;
      } else {
        _pollLockedProtocol();
      }
    });
  }

  @override
  void onDisconnecting() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _pollLockedProtocol() {
    if (_lockedProtocol == 0) {
      sendUHFReader09Command(0x01, [0x04, 0x00], address: 0xFF);
    } else if (_lockedProtocol == 1) {
      sendR2000Command(0x89, [0x01], address: 0xFF);
    } else if (_lockedProtocol == 2) {
      sendCommandHex("BB 00 22 00 00 22 7E");
    } else if (_lockedProtocol == 3) {
      _sendRawBytes([0x5A, 0x00, 0x04, 0x01, 0x39, 0x3E], "EVEN", "Inventory");
    }
  }

  void _lockOnProtocol(int protocolType, String name) {
    if (_lockedProtocol != -1) {
      return;
    }

    _lockedProtocol = protocolType;

    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("======================================");
      _tagStreamController.add("✅ [장비 응답 확인!] $name 규격 락온 완료!");
      _tagStreamController.add("🚀 고속(200ms) 실시간 태그 수집 엔진 전환!");
      _tagStreamController.add("======================================");
    }

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (isConnected) {
        _pollLockedProtocol();
      } else {
        timer.cancel();
      }
    });
  }

  void _sendRawBytes(List<int> bytes, String targetName, String desc) {
    sendCommandBytes(bytes);
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
    String rawSocketHex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("<== [수신 RX] $rawSocketHex");
    }

    _byteBuffer.addAll(data);

    while (_byteBuffer.isNotEmpty) {
      int header = _byteBuffer[0];

      if (header == 0xA0) {
        _lockOnProtocol(1, "R2000 (0xA0)");
        if (_byteBuffer.length < 2) {
          break;
        }

        int dataLen = _byteBuffer[1];
        int totalLen = dataLen + 2;
        if (_byteBuffer.length < totalLen) {
          break;
        }
        _byteBuffer.removeRange(0, totalLen);
      }
      else if (header == 0x5A) {
        _lockOnProtocol(3, "E710 EVEN (0x5A)");
        if (_byteBuffer.length < 2) {
          break;
        }

        int dataLen = _byteBuffer[1];
        int totalLen = dataLen + 2;
        if (_byteBuffer.length < totalLen) {
          break;
        }
        _byteBuffer.removeRange(0, totalLen);
      }
      else if (header >= 0x03 && header <= 0x80) {
        _lockOnProtocol(0, "UHFReader09 (Marktrace)");

        int totalLen = header + 1;
        if (_byteBuffer.length < totalLen) {
          break;
        }

        List<int> packet = _byteBuffer.sublist(0, totalLen);
        _byteBuffer.removeRange(0, totalLen);

        _parseUHFReader09(packet);
      }
      else if (header == 0xBB) {
        _lockOnProtocol(2, "CHAFON (0xBB)");
        if (_byteBuffer.length < 5) {
          break;
        }

        int dataLen = (_byteBuffer[3] << 8) | _byteBuffer[4];
        int totalLen = 5 + dataLen + 2;
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

    String fullPacketHex = packet.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("🧩 [Raw 프레임] $fullPacketHex");
    }

    int cmd = packet[2];
    List<int> payload = packet.sublist(3, packet.length - 2);

    if (payload.isNotEmpty && payload.length == 1 && payload[0] == 0xFF) {
      return;
    }

    if (cmd == 0x01 || cmd == 0x02 || cmd == 0x27) {
      if (payload.length > 5) {
        int epcLen = payload[1];
        int startIndex = 2;

        if (epcLen > 0 && startIndex + epcLen <= payload.length) {
          List<int> epcBytes = payload.sublist(startIndex, startIndex + epcLen);

          String epcHex = epcBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

          String asciiStr = "";
          try {
            asciiStr = String.fromCharCodes(epcBytes);
            if (!RegExp(r'^[\x20-\x7E]+$').hasMatch(asciiStr)) {
              asciiStr = "";
            }
          } catch (_) {}

          if (!_tagStreamController.isClosed) {
            _tagStreamController.add(epcHex);

            if (asciiStr.isNotEmpty) {
              _tagStreamController.add("🎯 [태그 인식] $epcHex ($asciiStr)");
            } else {
              _tagStreamController.add("🎯 [태그 인식] $epcHex");
            }
          }
        }
      }
    }
  }

  @override
  String parseTagId(String rawData) {
    return "";
  }
}

/// ===========================================================================
/// 프린터 / 범용 장비 파서
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
/// [팩토리] 모델 식별자에 따른 적절한 프로토콜 객체 생성 (Driver Factory)
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