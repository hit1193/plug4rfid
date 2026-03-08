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
    m120: '데스크형 리더기 (Hopeland M120)', // [수정됨] Hopeland 제조품으로 명시
    chafon: '고정식 리더기 (CHAFON 범용)',
    zebra: '프린터 (Zebra)',
    bt200: '프린터 (BT200)',
    sato: '프린터 (SATO)',
    genericTcp: '범용 TCP 장치',
    genericRs232c: '범용 RS232C 장치 (시리얼)',
  };

  /// UI(Dropdown) 등에서 사용할 순수 키 리스트
  static List<String> get list => labels.keys.toList();
}

/// ---------------------------------------------------------------------------
/// [최상위 통신 엔진] 장비별 통신 규격 추상 클래스 (Abstract Base Class)
/// ---------------------------------------------------------------------------
abstract class BaseDeviceProtocol {
  final String ipAddress;
  final int port;

  Socket? _socket;

  // 안드로이드 블루투스(SPP) 통신 객체를 담을 변수 (추후 패키지 추가 시 활성화)
  // BluetoothConnection? _btConnection;

  StreamSubscription<Uint8List>? _socketSubscription;

  // [버퍼링 엔진] TCP 스트림 쪼개짐 방어용 버퍼 (ASCII 방식용)
  String _buffer = "";

  // 장비에서 읽어들인 태그 데이터를 Provider 쪽으로 쏘아주는 데이터 파이프
  final StreamController<String> _tagStreamController = StreamController<String>.broadcast();
  Stream<String> get tagStream => _tagStreamController.stream;

  bool get isConnected => _socket != null;

  BaseDeviceProtocol({required this.ipAddress, required this.port});

  /// [공통] 장치 소켓 연결 로직 (Timeout 3초 방어 적용)
  Future<bool> connect() async {
    try {
      bool isBluetoothMac = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$').hasMatch(ipAddress);

      if (isBluetoothMac) {
        debugPrint("📱 안드로이드 블루투스(SPP) 장비 감지! MAC: $ipAddress");
        // _btConnection = await BluetoothConnection.toAddress(ipAddress);
        // ... 추후 활성화
        return false;
      } else {
        _socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 3));
        _socketSubscription = _socket!.listen(
          _internalOnDataReceived,
          onError: (error) => disconnect(),
          onDone: () => disconnect(),
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
    }
  }

  /// [공통] 바이너리(Hex) 데이터를 쏘기 위한 함수
  void sendCommandBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    if (_socket != null) {
      _socket!.add(bytes);
    }
  }

  void dispose() {
    disconnect();
    _tagStreamController.close();
  }

  /// -------------------------------------------------------------------------
  /// [핵심 아키텍처 변경] 수신 데이터 라우팅 엔진
  /// 장비가 ASCII 방식이냐 Binary 방식이냐에 따라 자식 클래스에서
  /// 버퍼 처리 방식을 완전히 다르게 가져갈 수 있도록 가상 함수(Virtual)로 분리했습니다.
  /// -------------------------------------------------------------------------
  void _internalOnDataReceived(Uint8List data) {
    onDataReceived(data);
  }

  /// 기본 동작은 기존과 동일한 ASCII (엔터 \n 기준 자르기) 방식입니다.
  /// Hopeland 같은 바이너리 장비는 이 함수를 오버라이딩하여 독자적으로 처리합니다.
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
  void onDisconnecting() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }
}

/// ===========================================================================
/// [구현체] IDRO900F 전용 프로토콜
/// ===========================================================================
class Idro900fProtocol extends AutoReportProtocol {
  Idro900fProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: ">f\r\n", stopCmd: ">3\r\n");

  @override
  String parseTagId(String packet) {
    if (packet.startsWith('>') && packet.length >= 3) {
      String replyType = packet.substring(2, 3);
      if (replyType == 'T') {
        if (packet.length > 7) return packet.substring(7).trim();
      } else if (replyType == 'R') {
        return "[메모리 읽기 결과] 데이터: ${packet.substring(3).trim()}";
      } else if (replyType == 'W') {
        return "[메모리 쓰기 결과] 응답코드: ${packet.substring(3).trim()}";
      } else if (replyType == 'M') {
        return "[필터(Mask) 설정 결과] 응답코드: ${packet.substring(3).trim()}";
      }
    }
    return "";
  }

  @override
  Future<void> setAntennaPower(int antennaIndex, int powerLevel) async {
    int safePower = powerLevel;
    if (safePower < 50) safePower = 50;
    if (safePower > 310) safePower = 310;
    String type = antennaIndex == 0 ? "p" : "p$antennaIndex";
    sendCommandString(stopCmd);
    await Future.delayed(const Duration(milliseconds: 100));
    sendCommandString(">x $type $safePower\r\n");
    await Future.delayed(const Duration(milliseconds: 100));
    sendCommandString(startCmd);
  }

  @override
  Future<void> readTagMemory(int bank, int offset, int length) async {
    sendCommandString(stopCmd);
    await Future.delayed(const Duration(milliseconds: 100));
    sendCommandString(">r $bank $offset $length\r\n");
    await Future.delayed(const Duration(milliseconds: 100));
    sendCommandString(startCmd);
  }

  @override
  Future<void> writeTagMemory(int bank, int offset, String dataHex) async {
    sendCommandString(stopCmd);
    await Future.delayed(const Duration(milliseconds: 100));
    sendCommandString(">w $bank $offset $dataHex\r\n");
    await Future.delayed(const Duration(milliseconds: 100));
    sendCommandString(startCmd);
  }

  @override
  Future<void> setTagFilter(int bank, int offset, String maskDataHex) async {
    sendCommandString(stopCmd);
    await Future.delayed(const Duration(milliseconds: 100));
    int bitLength = maskDataHex.length * 4;
    sendCommandString(">m $bank $offset $bitLength $maskDataHex\r\n");
    await Future.delayed(const Duration(milliseconds: 100));
    sendCommandString(startCmd);
  }
}

/// ===========================================================================
/// [구현체] ATID ATS200/100 휴대형 리더기
/// ===========================================================================
class Ats200Protocol extends AutoReportProtocol {
  Ats200Protocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: "~af\r\n", stopCmd: "~as\r\n");

  @override
  String parseTagId(String packet) {
    if (packet.startsWith('~eT')) {
      String mainData = packet.contains(',') ? packet.split(',')[0] : packet;
      if (mainData.length > 7) return mainData.substring(7).trim();
    }
    else if (packet.startsWith('~eA')) {
      List<String> parts = packet.split(',');
      if (parts.length >= 3) {
        String status = parts[0].substring(3);
        String action = parts[1];
        String epcData = parts[2];
        if (status == '0000') {
          if (action == 'r') {
            String readData = parts.sublist(3).join('');
            return "[메모리 읽기 성공] 대상 EPC: $epcData / 데이터: $readData";
          } else if (action == 'w') {
            return "[메모리 쓰기 성공] 대상 EPC: $epcData";
          }
        } else {
          return "[메모리 접근 에러] 대상 EPC: $epcData / 에러코드: $status";
        }
      }
    }
    return "";
  }

  @override
  Future<void> setAntennaPower(int antennaIndex, int powerLevel) async {
    int safePower = powerLevel;
    if (safePower < 0) safePower = 0;
    if (safePower > 300) safePower = 300;
    sendCommandString(stopCmd);
    await Future.delayed(const Duration(milliseconds: 100));
    sendCommandString("~wP$safePower\r\n");
  }

  @override
  Future<void> readTagMemory(int bank, int offset, int length) async {
    sendCommandString(stopCmd);
    await Future.delayed(const Duration(milliseconds: 100));
    sendCommandString("~ar$bank,$offset,$length\r\n");
  }

  @override
  Future<void> writeTagMemory(int bank, int offset, String dataHex) async {
    sendCommandString(stopCmd);
    await Future.delayed(const Duration(milliseconds: 100));
    List<String> chunks = [];
    for (int i = 0; i < dataHex.length; i += 4) {
      int end = (i + 4 > dataHex.length) ? dataHex.length : (i + 4);
      chunks.add(dataHex.substring(i, end));
    }
    String dataStr = chunks.join(',');
    int length = chunks.length;
    sendCommandString("~aw$bank,$offset,$length,$dataStr\r\n");
  }

  @override
  Future<void> setTagFilter(int bank, int offset, String maskDataHex) async {
    sendCommandString(stopCmd);
    await Future.delayed(const Duration(milliseconds: 100));
    int bitLength = maskDataHex.length * 4;
    sendCommandString("~aM1,$bank,$offset,$bitLength,$maskDataHex\r\n");
  }
}

/// ===========================================================================
/// [완벽 대비] Hopeland 리더기 프로토콜 (바이너리/Hex 통신 기반)
/// C++Builder의 TMemoryStream 슬라이딩 윈도우 파싱 기법을 Dart로 완벽 재현!
///
/// [클래스 역할 설명]
/// 기존의 IDRO나 ATID 장비가 텍스트(ASCII, \r\n 기준) 기반으로 데이터를 주고받았다면,
/// Hopeland (및 M120 데스크형) 장비는 16진수(Hex) 형태의 '바이너리 데이터'로 통신합니다.
/// 이 클래스는 소켓으로 들어오는 쪼개진 바이트(Byte) 조각들을 모아서
/// 완벽한 하나의 패킷(프레임)으로 조립해내는 가장 핵심적인 심장 역할을 수행합니다.
/// ===========================================================================
class HopelandProtocol extends BaseDeviceProtocol {
  // -------------------------------------------------------------------------
  // 바이너리 데이터를 꼬리표처럼 계속 이어붙이기 위한 전용 동적 바이트 버퍼입니다.
  // C++Builder에서 사용하시던 std::vector<BYTE> 또는 TMemoryStream과 정확히 같은 역할입니다.
  // -------------------------------------------------------------------------
  final List<int> _byteBuffer = [];

  HopelandProtocol(String ip, int port) : super(ipAddress: ip, port: port);

  @override
  void onConnected() {
    // [명령 하달] 인벤토리(읽기) 시작 Hex Command 전송
    // 구조: AA(헤더) + 01 00(컨트롤워드) ...
    debugPrint("Hopeland/M120 Device Connected: $ipAddress:$port");
  }

  @override
  void onDisconnecting() {
    // 인벤토리 중지 Hex Command 전송
  }

  void sendCommandHex(String hexString) {
    String cleanHex = hexString.replaceAll(' ', '').toUpperCase();
    if (cleanHex.length % 2 != 0) return;

    List<int> bytes = [];
    for (int i = 0; i < cleanHex.length; i += 2) {
      bytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
    }
    sendCommandBytes(bytes);
  }

  @override
  void onDataReceived(Uint8List data) {
    _byteBuffer.addAll(data);

    while (_byteBuffer.isNotEmpty) {
      // [방어 로직 1] Hopeland의 프레임 시작 헤더인 '0xAA'를 찾습니다.
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

      _processBinaryPacket(completePacket);
    }

    if (_byteBuffer.length > 8192) {
      _byteBuffer.clear();
    }
  }

  void _processBinaryPacket(List<int> packet) {
    int commandCode = (packet[1] << 8) | packet[2];

    // -----------------------------------------------------------------------
    // [응답 분기 처리] 매뉴얼의 Command Code에 따라 알맞은 결과를 전파합니다.
    // -----------------------------------------------------------------------
    if (commandCode == 0x0102) {
      // 1. 일반 인벤토리 (태그 읽기) 응답
      List<int> epcBytes = packet.sublist(5, packet.length - 2);
      String epcHex = epcBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();

      if (epcHex.isNotEmpty && !_tagStreamController.isClosed) {
        _tagStreamController.add(epcHex);
      }
    } else if (commandCode == 0x0104) {
      // 2. [신규] 메모리 읽기(Read) 결과 응답 예시
      _tagStreamController.add("[메모리 읽기 성공] Hopeland 응답 수신");
    } else if (commandCode == 0x0105) {
      // 3. [신규] 메모리 쓰기(Write) 결과 응답 예시
      _tagStreamController.add("[메모리 쓰기 성공] Hopeland 응답 수신");
    }
  }

  @override
  String parseTagId(String rawData) {
    return "";
  }

  // =========================================================================
  // [신규 기능 구현] Hopeland 바이너리 제어 명령어 (Power, Read, Write, Filter)
  // =========================================================================

  @override
  Future<void> setAntennaPower(int antennaIndex, int powerLevel) async {
    await Future.delayed(const Duration(milliseconds: 100)); // 상태 안정화

    // TODO: 매뉴얼 획득 후 파워 설정 HEX 코드로 교체
    // 예시: AA [명령어] [길이] [안테나번호] [파워값] [체크섬]
    // sendCommandHex("AA 01 07 00 02 $antennaHex $powerHex ... ");

    debugPrint("Hopeland 파워 설정 명령 준비됨: 안테나 $antennaIndex, 파워 $powerLevel");
  }

  @override
  Future<void> readTagMemory(int bank, int offset, int length) async {
    await Future.delayed(const Duration(milliseconds: 100));

    // TODO: 매뉴얼 획득 후 메모리 읽기 HEX 코드로 교체
    // 뱅크(User=3 등), 오프셋, 길이를 HEX로 변환하여 조립합니다.

    debugPrint("Hopeland 메모리 읽기 명령 준비됨: Bank $bank, Offset $offset, Length $length");
  }

  @override
  Future<void> writeTagMemory(int bank, int offset, String dataHex) async {
    await Future.delayed(const Duration(milliseconds: 100));

    // TODO: 매뉴얼 획득 후 메모리 쓰기 HEX 코드로 교체
    // 가변 길이의 dataHex를 바이트 배열로 변환 후 체크섬(Checksum)을 동적 계산하여 쏴야 합니다.

    debugPrint("Hopeland 메모리 쓰기 명령 준비됨: Bank $bank, Offset $offset, Data $dataHex");
  }

  @override
  Future<void> setTagFilter(int bank, int offset, String maskDataHex) async {
    await Future.delayed(const Duration(milliseconds: 100));

    // TODO: 매뉴얼 획득 후 마스킹(필터) HEX 코드로 교체

    debugPrint("Hopeland 필터 설정 명령 준비됨: Bank $bank, Offset $offset, Mask $maskDataHex");
  }
}

/// ===========================================================================
/// [신규 추가] CHAFON 리더기 프로토콜 (바이너리/Hex 통신 기반)
/// CF815, CF_RU5102, CF601 등 CHAFON 계열의 모든 리더기들이 공통으로 사용하는
/// 중국계 표준 바이너리 프로토콜(주로 0xBB 헤더 사용)을 처리하는 엔진입니다!
/// ===========================================================================
class ChafonProtocol extends BaseDeviceProtocol {
  // 바이너리 슬라이딩 윈도우 파서용 바이트 버퍼
  final List<int> _byteBuffer = [];

  ChafonProtocol(String ip, int port) : super(ipAddress: ip, port: port);

  @override
  void onConnected() {
    // -----------------------------------------------------------------
    // CHAFON 리더기의 전형적인 인벤토리(Multi-Read) 시작 명령
    // 구조 예시: 0xBB(헤더) 0x00(타입) 0x27(커맨드) 0x00 0x03(길이) 0x22 0x27 0x10 0x83(체크섬) 0x7E(종료)
    // -----------------------------------------------------------------
    // sendCommandHex("BB 00 27 00 03 22 27 10 83 7E");
    debugPrint("CHAFON Device Connected: $ipAddress:$port");
  }

  @override
  void onDisconnecting() {
    // 인벤토리 중지 명령 (예: BB 00 28 00 00 28 7E)
    // sendCommandHex("BB 00 28 00 00 28 7E");
  }

  /// 사용의 편의를 위해 16진수 문자열을 바이트 배열로 변환하여 쏩니다.
  void sendCommandHex(String hexString) {
    String cleanHex = hexString.replaceAll(' ', '').toUpperCase();
    if (cleanHex.length % 2 != 0) return;

    List<int> bytes = [];
    for (int i = 0; i < cleanHex.length; i += 2) {
      bytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
    }
    sendCommandBytes(bytes);
  }

  /// -------------------------------------------------------------------------
  /// [CHAFON 전용 바이너리 파서]
  /// CHAFON 장비의 가장 큰 특징인 시작 헤더(0xBB)와 종료 테일(0x7E)을 감지합니다.
  /// -------------------------------------------------------------------------
  @override
  void onDataReceived(Uint8List data) {
    _byteBuffer.addAll(data);

    while (_byteBuffer.isNotEmpty) {
      // [방어 로직 1] CHAFON의 프레임 시작 헤더인 '0xBB'를 찾을 때까지 쓰레기 버림
      if (_byteBuffer[0] != 0xBB) {
        _byteBuffer.removeAt(0);
        continue;
      }

      // [방어 로직 2] 길이를 계산하기 위한 최소 길이 (보통 Header + Type + Cmd + Length = 5바이트)
      if (_byteBuffer.length < 5) {
        break;
      }

      // [핵심 로직] CHAFON 프로토콜의 Payload 길이는 보통 인덱스 3, 4(또는 4번 1바이트)에 위치합니다.
      // (매뉴얼을 확보하시면 이 Length 파싱 위치만 살짝 조정하시면 됩니다.)
      int dataLength = (_byteBuffer[3] << 8) | _byteBuffer[4];

      // 전체 길이 = 5(헤더부) + Payload + 2(체크섬+엔드코드 0x7E)
      int totalPacketSize = 5 + dataLength + 2;

      if (_byteBuffer.length < totalPacketSize) {
        break;
      }

      // 하나의 완벽한 CHAFON 패킷 추출 완료!
      List<int> completePacket = _byteBuffer.sublist(0, totalPacketSize);
      _byteBuffer.removeRange(0, totalPacketSize);

      _processBinaryPacket(completePacket);
    }

    // 메모리 누수 방어
    if (_byteBuffer.length > 8192) {
      _byteBuffer.clear();
    }
  }

  void _processBinaryPacket(List<int> packet) {
    // 패킷의 마지막이 0x7E로 끝나는지 확인하여 정상 프레임인지 2차 검증
    if (packet.last != 0x7E) return;

    // 명령어 코드 추출 (예: 0x22 = EPC Read 응답, 0x39 = Read Memory, 0x49 = Write Memory)
    int commandCode = packet[2];

    // -----------------------------------------------------------------------
    // [응답 분기 처리] CHAFON 매뉴얼 기준 응답 파싱
    // -----------------------------------------------------------------------
    if (commandCode == 0x22) {
      // 1. 일반 인벤토리 응답
      List<int> epcBytes = packet.sublist(5, packet.length - 2);
      String epcHex = epcBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();

      if (epcHex.isNotEmpty && !_tagStreamController.isClosed) {
        _tagStreamController.add(epcHex);
      }
    } else if (commandCode == 0x39) {
      // 2. [신규] 메모리 읽기 성공 (Read Data)
      _tagStreamController.add("[메모리 읽기 성공] CHAFON 응답 수신");
    } else if (commandCode == 0x49) {
      // 3. [신규] 메모리 쓰기 성공 (Write Data)
      _tagStreamController.add("[메모리 쓰기 성공] CHAFON 응답 수신");
    }
  }

  @override
  String parseTagId(String rawData) {
    return ""; // 바이너리 처리를 하므로 사용 안함
  }

  // =========================================================================
  // [신규 기능 구현] CHAFON 바이너리 제어 명령어 (Power, Read, Write, Filter)
  // =========================================================================

  @override
  Future<void> setAntennaPower(int antennaIndex, int powerLevel) async {
    await Future.delayed(const Duration(milliseconds: 100)); // 인벤토리 정지 후 딜레이

    // TODO: 매뉴얼 획득 후 파워 설정 HEX 코드로 교체 (예: BB 00 B6 ...)
    // sendCommandHex("BB 00 B6 00 02 $powerHex $checksumHex 7E");

    debugPrint("CHAFON 파워 설정 명령 준비됨: 파워 $powerLevel");
  }

  @override
  Future<void> readTagMemory(int bank, int offset, int length) async {
    await Future.delayed(const Duration(milliseconds: 100));

    // TODO: CHAFON Read Memory(Cmd: 0x39) 명령 전송

    debugPrint("CHAFON 메모리 읽기 명령 준비됨: Bank $bank, Offset $offset, Length $length");
  }

  @override
  Future<void> writeTagMemory(int bank, int offset, String dataHex) async {
    await Future.delayed(const Duration(milliseconds: 100));

    // TODO: CHAFON Write Memory(Cmd: 0x49) 명령 전송

    debugPrint("CHAFON 메모리 쓰기 명령 준비됨: Bank $bank, Offset $offset, Data $dataHex");
  }

  @override
  Future<void> setTagFilter(int bank, int offset, String maskDataHex) async {
    await Future.delayed(const Duration(milliseconds: 100));

    // TODO: CHAFON Set Filter(Cmd: 0x98 등) 명령 전송

    debugPrint("CHAFON 필터 설정 명령 준비됨: Bank $bank, Offset $offset, Mask $maskDataHex");
  }
}

/// ===========================================================================
/// 프린터 / 범용 장비 프로토콜
/// [알림] M120은 Hopeland로 통합되었으므로 이 구역의 M120PollingProtocol은 삭제되었습니다.
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
/// [팩토리] 모델 식별자에 따른 적절한 프로토콜 객체 생성 (Driver Factory)
/// ---------------------------------------------------------------------------
class DeviceProtocolFactory {
  static BaseDeviceProtocol create(String modelValue, String ip, int port) {
    switch (modelValue) {
    // 1. IDRO 전용 (문자열 방식)
      case SupportedDeviceModels.idro900f:
        return Idro900fProtocol(ip, port);

    // 2. ATID 전용
      case SupportedDeviceModels.ats200:
        return Ats200Protocol(ip, port);

    // 3. [핵심 수정] Hopeland 및 M120 통합!
    // M120 장비가 Hopeland 제조품이므로, 동일한 0xAA 헤더의 바이너리 엔진을 타도록 묶었습니다.
      case SupportedDeviceModels.hopeland:
      case SupportedDeviceModels.m120:
        return HopelandProtocol(ip, port);

    // 4. CHAFON 및 동일 칩셋(CF계열) 리더기 묶음 처리!
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