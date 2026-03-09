import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// ---------------------------------------------------------------------------
/// [상수 정의] 지원하는 구체적 장치 모델 리스트
/// PocketBase의 'model' 필드 Select 옵션과 1:1 매칭됩니다.
/// ---------------------------------------------------------------------------
class SupportedDeviceModels {
  // 1. 내부 로직 및 DB 저장용 고유 키 (Value)
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

  // 2. 관리자 화면(UI)에서 보여줄 한글 이름 매핑 (Label)
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

  /// UI(Dropdown) 등에서 사용할 순수 키 리스트
  static List<String> get list {
    return labels.keys.toList();
  }
}

/// ---------------------------------------------------------------------------
/// [최상위 통신 엔진] 장비별 통신 규격 추상 클래스
/// ---------------------------------------------------------------------------
abstract class BaseDeviceProtocol {
  final String ipAddress;
  final int port;

  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;

  // [버퍼링 엔진] TCP 스트림 쪼개짐 방어용 버퍼
  String _buffer = "";

  // 장비에서 읽어들인 태그 데이터를 Provider 쪽으로 쏘아주는 데이터 파이프
  final StreamController<String> _tagStreamController = StreamController<String>.broadcast();
  Stream<String> get tagStream {
    return _tagStreamController.stream;
  }

  bool get isConnected {
    return _socket != null;
  }

  BaseDeviceProtocol({required this.ipAddress, required this.port});

  Future<bool> connect() async {
    try {
      bool isBluetoothMac = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$').hasMatch(ipAddress);

      if (isBluetoothMac) {
        debugPrint("?? 안드로이드 블루투스(SPP) 장비 감지! MAC: $ipAddress");
        return false;
      } else {
        _socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 3));

        // 데이터 수신 이벤트 바인딩 (C++ OnRead 대응)
        _socketSubscription = _socket!.listen(
          _internalOnDataReceived,
          onError: (error) {
            disconnect();
          },
          onDone: () {
            disconnect();
          },
        );
      }

      onConnected();
      return true;
    } catch (e) {
      _socket = null;
      return false;
    }
  }

  void disconnect() {
    onDisconnecting();
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _socket?.destroy();
    _socket = null;
    _buffer = "";
  }

  void sendCommandString(String command) {
    if (command.isEmpty) return;
    if (_socket != null) {
      _socket!.write(command);
      _socket!.flush(); // 플러터 소켓 버퍼 비우기 (즉시 전송)
    }
  }

  void sendCommandBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    if (_socket != null) {
      _socket!.add(bytes);
      _socket!.flush(); // 확실한 하드웨어 전송을 위해 Flush 강제 호출!
    }
  }

  void dispose() {
    disconnect();
    _tagStreamController.close();
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

  /// 부모 클래스의 onDataReceived를 완전히 덮어써서(Override)
  /// IDRO900F만의 특수한 Raw 패킷 출력 및 정밀 파싱 로직을 수행합니다.
  @override
  void onDataReceived(Uint8List data) {
    // 1. Raw 패킷 그대로 터미널에 출력 (사용자 요청: 수신 패킷 그대로 보여주기)
    String rawHex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("<== [IDRO900F Raw] $rawHex");
    }

    // 2. ASCII 문자열 누적 버퍼링 (네트워크 통신 시 패킷 쪼개짐 현상 방어)
    _buffer += String.fromCharCodes(data);

    // 3. 개행문자(\n) 기준으로 완벽한 한 줄이 완성되었을 때만 파싱 시도
    while (_buffer.contains('\n')) {
      int index = _buffer.indexOf('\n');
      String line = _buffer.substring(0, index).replaceAll('\r', '');
      _buffer = _buffer.substring(index + 1);

      if (line.isNotEmpty) {
        _parseIdroPacket(line);
      }
    }
  }

  /// [핵심 기능] 가변적으로 들어오는 IDRO 패킷(Ant, EPC, TID, RSSI 등) 정밀 파싱
  /// 및 출입 방향 판별 로직 적용
  void _parseIdroPacket(String line) {
    // IDRO900F의 태그 응답은 주로 '>T' 로 시작합니다. (예: >T03000E200001606080226177033,-54)
    if (line.startsWith('>T') && line.length >= 5) {
      try {
        // 1. 안테나 번호 파싱 (문자열의 index 2 위치. 하드웨어상 보통 0부터 시작하므로 +1 처리하여 1~4번으로 맞춤)
        String antChar = line.substring(2, 3);
        int antNo = (int.tryParse(antChar) ?? 0) + 1; // 1번 안테나 ~ 4번 안테나

        // 2. 남은 데이터 추출 (PC + EPC + RSSI + TID 등 가변 데이터)
        String remainData = line.substring(3);

        String epc = "";
        String rssi = "알수없음";
        String tid = "없음";

        // IDRO 세팅(예: >o 명령어)에 따라 쉼표(,)로 데이터가 묶여서 들어올 수 있도록 방어적 대응
        if (remainData.contains(',')) {
          List<String> parts = remainData.split(',');
          epc = parts[0]; // 보통 첫 번째 파트가 EPC (PC값 포함)
          if (parts.length > 1) rssi = parts[1]; // 두 번째 파트가 보통 RSSI
          if (parts.length > 2) tid = parts[2]; // 세 번째 파트가 있다면 TID
        } else {
          // 쉼표 구분자가 없는 경우 (보통 앞 4자리는 Protocol Control(PC)값, 그 이후가 순수 EPC)
          if (remainData.length > 4) {
            epc = remainData.substring(4);
          } else {
            epc = remainData;
          }
        }

        // 3. 출입의 방향(Direction) 판단 로직 (요청하신 필수 업무 요구사항)
        // 안테나 번호에 따라: Ant 1,2는 입고(IN) / Ant 3,4는 출고(OUT)로 판별합니다.
        String direction = (antNo <= 2) ? "IN (입고/입장)" : "OUT (출고/퇴장)";

        // 4. 나중에 쉽게 처리하고 보관할 수 있도록 JSON 문자열 형태로 데이터 파이프에 전송!
        // "JSON:" 이라는 마커를 앞에 붙여서 Provider가 이를 가로채서 구조체(Map)로 변환/저장하게 합니다.
        String jsonPayload = 'JSON:{"epc":"$epc", "ant":$antNo, "rssi":"$rssi", "tid":"$tid", "direction":"$direction"}';
        _tagStreamController.add(jsonPayload);

      } catch (e) {
        _tagStreamController.add("⚠️ [IDRO 파싱 오류] 규격 외 데이터: $line");
      }
    } else if (line.startsWith('>R')) {
      // TID 영역 등 별도 메모리 읽기 응답일 경우
      _tagStreamController.add("🔍 [메모리 읽기 응답] $line");
    } else {
      // 기타 장비 기본 응답 패킷 (예: 설정 변경 성공 여부 등)
      if (line != ">") {
        _tagStreamController.add("ℹ️ [장비 응답] $line");
      }
    }
  }

  @override
  String parseTagId(String packet) {
    // onDataReceived를 완벽하게 재정의(Override)했으므로 기본 추상 메서드는 사용되지 않습니다.
    return "";
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

  @override void onConnected() {}
  @override void onDisconnecting() {}

  @override
  void onDataReceived(Uint8List data) {
    _byteBuffer.addAll(data);
    while (_byteBuffer.isNotEmpty) {
      if (_byteBuffer[0] != 0xAA) {
        _byteBuffer.removeAt(0);
        continue;
      }
      if (_byteBuffer.length < 5) break;

      int dataLength = (_byteBuffer[3] << 8) | _byteBuffer[4];
      int totalPacketSize = 5 + dataLength + 2;

      if (_byteBuffer.length < totalPacketSize) break;

      List<int> completePacket = _byteBuffer.sublist(0, totalPacketSize);
      _byteBuffer.removeRange(0, totalPacketSize);

      int commandCode = (completePacket[1] << 8) | completePacket[2];
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

  @override String parseTagId(String rawData) { return ""; }
}

/// ===========================================================================
/// [최종 완성형] Marktrace (UHFReader09) 전용 해독 엔진
/// 성공했던 그 조합(0x01 명령 + 파라미터 장착 + 브로드캐스트 주소 FF)으로
/// 다시 원상복구 및 고정시켰습니다.
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
    debugPrint("장치 소켓 접속 성공: $ipAddress:$port");
  }

  @override
  Future<void> startInventory() async {
    await Future.delayed(const Duration(milliseconds: 500));

    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("=========================================");
      _tagStreamController.add("?? [시스템] Marktrace 정밀 해독 엔진 가동!");
      _tagStreamController.add("?? 파라미터가 장착된 0x01 모드로 타격합니다.");
      _tagStreamController.add("=========================================");
    }

    _pollingTimer?.cancel();

    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (!isConnected) {
        timer.cancel();
        return;
      }

      if (_lockedProtocol == -1) {
        // [탐색 모드] 성공했던 파라미터 세팅으로 발사합니다.
        if (_discoveryStep == 0) {
          // Command: 0x01, Data: Q=0x04, Session=0x00, Address: 0xFF(모든 장비)
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
        // [락온 모드]
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
      // [성공 확정 명령] Q=4, Session=0 파라미터를 담아 완벽하게 전송!
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
    if (_lockedProtocol != -1) return; // 이미 락온됨

    _lockedProtocol = protocolType;

    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("======================================");
      _tagStreamController.add("?? [장비 응답 확인!] $name 규격 락온 완료!");
      _tagStreamController.add("?? 고속(200ms) 실시간 태그 수집 엔진 전환!");
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
    if (bytes.isEmpty || _socket == null) return;
    try {
      _socket!.add(bytes);
      _socket!.flush();
    } catch(e) {
      debugPrint("Socket TX Error: $e");
    }
  }

  /// -------------------------------------------------------------------------
  /// [완벽 검증] CRC16-CCITT (Polynomial 0x8408)
  /// -------------------------------------------------------------------------
  void sendUHFReader09Command(int cmd, List<int> data, {int address = 0xFF}) {
    int len = data.length + 4; // Length Byte = Address(1) + Cmd(1) + Data(N) + CRC(2)
    List<int> packet = [len, address, cmd];
    packet.addAll(data);

    int crc = 0xFFFF;
    for (int i = 0; i < packet.length; i++) {
      crc ^= packet[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x0001) != 0) crc = (crc >> 1) ^ 0x8408;
        else crc >>= 1;
      }
    }

    packet.add(crc & 0xFF);
    packet.add((crc >> 8) & 0xFF);

    if (_socket != null) {
      _socket!.add(packet);
      _socket!.flush();
    }
  }

  void sendCommandHex(String hexString) {
    String cleanHex = hexString.replaceAll(' ', '').toUpperCase();
    if (cleanHex.length % 2 != 0) return;
    List<int> bytes = [];
    for (int i = 0; i < cleanHex.length; i += 2) {
      bytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
    }
    if (_socket != null) {
      _socket!.add(bytes);
      _socket!.flush();
    }
  }

  void sendR2000Command(int cmd, List<int> data, {int address = 0xFF}) {
    int len = data.length + 3;
    List<int> packet = [0xA0, len, address, cmd];
    packet.addAll(data);

    int sum = 0;
    for (int i = 1; i < packet.length; i++) sum += packet[i];
    int checksum = (~sum + 1) & 0xFF;
    packet.add(checksum);

    if (_socket != null) {
      _socket!.add(packet);
      _socket!.flush();
    }
  }

  /// -------------------------------------------------------------------------
  /// [RX 파서] 들어오는 모든 데이터를 검증합니다.
  /// -------------------------------------------------------------------------
  @override
  void onDataReceived(Uint8List data) {
    // [추가] 수신된 날 것 그대로의 원본 바이트(Raw Hex)를 길이에 구애받지 않고 터미널에 즉시 출력합니다!
    String rawSocketHex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("<== [수신 RX] $rawSocketHex");
    }

    _byteBuffer.addAll(data);

    while (_byteBuffer.isNotEmpty) {
      int header = _byteBuffer[0];

      if (header == 0xA0) {
        _lockOnProtocol(1, "R2000 (0xA0)");
        if (_byteBuffer.length < 2) break;
        int dataLen = _byteBuffer[1];
        int totalLen = dataLen + 2;
        if (_byteBuffer.length < totalLen) break;
        _byteBuffer.removeRange(0, totalLen);
      }
      else if (header == 0x5A) {
        _lockOnProtocol(3, "E710 EVEN (0x5A)");
        if (_byteBuffer.length < 2) break;
        int dataLen = _byteBuffer[1];
        int totalLen = dataLen + 2;
        if (_byteBuffer.length < totalLen) break;
        _byteBuffer.removeRange(0, totalLen);
      }
      // [3] UHFReader09 (Marktrace) 계열
      else if (header >= 0x03 && header <= 0x80) {
        _lockOnProtocol(0, "UHFReader09 (Marktrace)");

        int totalLen = header + 1; // Length(1) + Length값(Address~CRC)
        if (_byteBuffer.length < totalLen) break;

        List<int> packet = _byteBuffer.sublist(0, totalLen);
        _byteBuffer.removeRange(0, totalLen);

        _parseUHFReader09(packet);
      }
      else if (header == 0xBB) {
        _lockOnProtocol(2, "CHAFON (0xBB)");
        if (_byteBuffer.length < 5) break;
        int dataLen = (_byteBuffer[3] << 8) | _byteBuffer[4];
        int totalLen = 5 + dataLen + 2;
        if (_byteBuffer.length < totalLen) break;
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

  /// -------------------------------------------------------------------------
  /// [완벽 해독 완료] UHFReader09 정밀 EPC 추출기
  /// -------------------------------------------------------------------------
  void _parseUHFReader09(List<int> packet) {
    if (packet.length < 5) return;

    // [추가] 프레임 단위로 예쁘게 잘려진 완벽한 패킷(Raw Packet)을 해독 전에 먼저 출력합니다.
    String fullPacketHex = packet.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    if (!_tagStreamController.isClosed) {
      _tagStreamController.add("?? [Raw 프레임] $fullPacketHex");
    }

    // 대표님이 주셨던 패킷: 03 01 01 0C 55 53 45 52 40 30 30 30 30 31 39 32 69
    // 위 데이터는 Address(03), Cmd(01), Ant(01), Len(0C) 로 구성되어 있습니다.
    int cmd = packet[2];
    List<int> payload = packet.sublist(3, packet.length - 2);

    if (payload.isNotEmpty && payload.length == 1 && payload[0] == 0xFF) {
      // 0x01에 파라미터를 채웠기 때문에 이제 거의 뜨지 않을 것입니다.
      return;
    }

    if (cmd == 0x01 || cmd == 0x02 || cmd == 0x27) {
      if (payload.length > 5) {
        int epcLen = payload[1]; // 두번째 바이트가 태그 길이(0x0C = 12바이트)
        int startIndex = 2;      // 세번째 바이트부터 실제 태그 시작

        if (epcLen > 0 && startIndex + epcLen <= payload.length) {
          List<int> epcBytes = payload.sublist(startIndex, startIndex + epcLen);

          // 1. 순수 Hex 추출
          String epcHex = epcBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

          // 2. ASCII 문자열 역변환 시도 (USER@0000192)
          String asciiStr = "";
          try {
            asciiStr = String.fromCharCodes(epcBytes);
            if (!RegExp(r'^[\x20-\x7E]+$').hasMatch(asciiStr)) {
              asciiStr = "";
            }
          } catch (_) {}

          if (!_tagStreamController.isClosed) {
            _tagStreamController.add(epcHex); // 프로바이더로 전송되어 리스트 갱신

            if (asciiStr.isNotEmpty) {
              _tagStreamController.add("? [태그 인식] $epcHex ($asciiStr)");
            } else {
              _tagStreamController.add("? [태그 인식] $epcHex");
            }
          }
        }
      }
    }
  }

  @override
  String parseTagId(String rawData) { return ""; }
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