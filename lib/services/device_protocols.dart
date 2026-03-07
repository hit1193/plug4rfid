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
  static const String m120          = 'M120';
  static const String zebra         = 'ZEBRA';
  static const String bt200         = 'BT200';
  static const String sato          = 'SATO';
  static const String genericTcp    = 'GENERIC_TCP';

  // [신규 추가] 범용 RS232C 통신 장비 키
  static const String genericRs232c = 'GENERIC_RS232C';

  // 2. 관리자 화면(UI)에서 보여줄 한글 이름 매핑 (Label)
  static const Map<String, String> labels = {
    idro900f: '고정식 리더기 (IDRO900F)',
    cf815: '고정식 리더기 (CF815)',
    cfRU5102: '데스크형 리더기 (CF_RU5102)',
    cf601: '데스크형 리더기 (CF601)',
    ats200: '휴대형 리더기 (ATS200)',
    m120: '데스크형 리더기 (M120) - 폴링방식',
    zebra: '프린터 (Zebra)',
    bt200: '프린터 (BT200)',
    sato: '프린터 (SATO)',
    genericTcp: '범용 TCP 장치',
    // [신규 추가] 드롭다운에 표시될 라벨
    genericRs232c: '범용 RS232C 장치 (시리얼)',
  };

  /// UI(Dropdown) 등에서 사용할 순수 키 리스트
  static List<String> get list => labels.keys.toList();
}

/// ---------------------------------------------------------------------------
/// [최상위 통신 엔진] 장비별 통신 규격 추상 클래스 (Abstract Base Class)
/// C++Builder의 class BaseProtocol { virtual ... } 구조의 완성형입니다.
/// TCP Fragmentation(패킷 쪼개짐)을 방어하는 버퍼링 엔진이 내장되어 있습니다.
/// ---------------------------------------------------------------------------
abstract class BaseDeviceProtocol {
  final String ipAddress;
  final int port;

  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;

  // [버퍼링 엔진] TCP 스트림 쪼개짐 방어용 버퍼 (C++의 AnsiString 덧붙이기와 동일)
  String _buffer = "";

  // 장비에서 읽어들인 태그 데이터를 Provider 쪽으로 쏘아주는 데이터 파이프
  final StreamController<String> _tagStreamController = StreamController<String>.broadcast();
  Stream<String> get tagStream => _tagStreamController.stream;

  bool get isConnected => _socket != null;

  BaseDeviceProtocol({required this.ipAddress, required this.port});

  /// [공통] 장치 소켓 연결 로직 (Timeout 3초 방어 적용)
  Future<bool> connect() async {
    try {
      _socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 3));

      _socketSubscription = _socket!.listen(
        _internalOnDataReceived,
        onError: (error) => disconnect(),
        onDone: () => disconnect(),
      );

      onConnected();
      return true;
    } catch (e) {
      _socket = null;
      return false;
    }
  }

  /// [공통] 장치 연결 해제 및 메모리 정리
  void disconnect() {
    onDisconnecting();

    _socketSubscription?.cancel();
    _socketSubscription = null;

    _socket?.destroy();
    _socket = null;
    _buffer = ""; // 버퍼 초기화
  }

  /// [공통] String 형태의 명령어를 소켓으로 전송
  void sendCommandString(String command) {
    if (_socket != null && command.isNotEmpty) {
      _socket!.write(command);
    }
  }

  /// 메모리 완전 해제 (Provider가 파괴될 때 호출됨)
  void dispose() {
    disconnect();
    _tagStreamController.close();
  }

  /// -------------------------------------------------------------------------
  /// [핵심 방어 로직] TCP 스트림 파싱 버퍼 엔진
  /// 소켓에 데이터가 들어오면 무조건 파싱하는 것이 아니라, \n(엔터) 단위로
  /// 완벽한 패킷 한 줄이 완성되었을 때만 자식 클래스(parseTagId)로 넘깁니다.
  /// -------------------------------------------------------------------------
  void _internalOnDataReceived(Uint8List data) {
    _buffer += String.fromCharCodes(data);

    // 개행문자(\n)가 포함되어 있다면 최소 한 줄 이상의 완성된 패킷이 존재함
    while (_buffer.contains('\n')) {
      int index = _buffer.indexOf('\n');
      // \r\n 에서 \r까지 제거하여 깔끔한 패킷 한 줄만 추출
      String line = _buffer.substring(0, index).replaceAll('\r', '');

      // 처리한 패킷은 버퍼에서 날려버림
      _buffer = _buffer.substring(index + 1);

      if (line.isNotEmpty) {
        String parsedTag = parseTagId(line); // 자식 클래스의 오버라이딩 함수 호출

        // 파싱된 유효한 데이터가 있다면 Provider로 발송
        if (parsedTag.isNotEmpty && !_tagStreamController.isClosed) {
          _tagStreamController.add(parsedTag);
        }
      }
    }
  }

  // =========================================================================
  // [가상 함수 (Virtual Methods)] 자식 클래스가 구현해야 할 핵심 로직
  // =========================================================================
  void onConnected();
  void onDisconnecting();
  String parseTagId(String rawData);

  /// -------------------------------------------------------------------------
  /// [신규 가상 함수] 장비의 안테나별 RF 출력 파워를 설정합니다. (C++ 가상 함수 역할)
  /// 향후 UI의 Slider 바 등을 움직일 때 호출될 인터페이스입니다.
  /// [antennaIndex]: 0(전체 안테나 공통 설정), 1~4(개별 안테나 번호)
  /// [powerLevel]: 장비 규격에 맞는 파워 값 (예: IDRO의 경우 50 ~ 310)
  /// -------------------------------------------------------------------------
  Future<void> setAntennaPower(int antennaIndex, int powerLevel) async {
    // 기본적으로는 아무 동작도 하지 않습니다.
    // 이를 지원하는 IDRO900F 등의 자식 클래스에서만 오버라이딩하여 구현합니다.
  }
}

/// ---------------------------------------------------------------------------
/// [유형 1] 자동 수신형 (Event-Driven) 베이스 클래스
/// 연결 시 Start 명령을 주고, 끊을 때 Stop 명령을 주는 장비용입니다.
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
/// C++Builder의 TTimer를 돌리며 주기적으로 "데이터 있어?"라고 묻는 장비용입니다.
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
/// [구현체] 각 장비별 프로토콜 정의 영역
/// ===========================================================================

/// IDRO900F 및 CF 시리즈 등 ASCII 기반 자동 송신 장비 프로토콜
class Idro900fProtocol extends AutoReportProtocol {
  // 매뉴얼에 따라 시작은 '>f\r\n', 중지는 '>3\r\n' 입니다.
  Idro900fProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: ">f\r\n", stopCmd: ">3\r\n");

  @override
  String parseTagId(String packet) {
    // -----------------------------------------------------------------
    // 매뉴얼 분석 기반 파싱 로직
    // 정상 패킷: >1T3000111122223333444455550000
    // 인덱스 정보: [0]: >, [1]: 안테나번호, [2]: T(데이터) or C(에러),
    //              [3~6]: PC값(4자리), [7~]: 실제 EPC 데이터
    // -----------------------------------------------------------------
    if (packet.startsWith('>') && packet.length > 7) {
      String replyType = packet.substring(2, 3);

      // 'T'는 매뉴얼상 정상 태그 데이터 응답을 의미합니다.
      if (replyType == 'T') {
        // 앞의 헤더와 PC값 4자리를 떼어내고 순수 EPC만 추출합니다.
        String epc = packet.substring(7);
        return epc.trim();
      }
    }
    return ""; // 에러 패킷이거나 엉뚱한 문자열이면 무시 (버림)
  }

  /// -------------------------------------------------------------------------
  /// [IDRO900F 파워 제어] C++Builder 하드웨어 통신 안정화 기법(Sleep) 적용
  /// -------------------------------------------------------------------------
  @override
  Future<void> setAntennaPower(int antennaIndex, int powerLevel) async {
    // 1. 유효성 검사: 매뉴얼 기준 파워 입력값은 50 ~ 310 (0.1dBm 단위) 사이여야 합니다.
    int safePower = powerLevel;
    if (safePower < 50) safePower = 50;
    if (safePower > 310) safePower = 310;

    // 2. 명령어 타입 결정: p(전체공통), p1(안테나1) ~ p4(안테나4)
    String type = antennaIndex == 0 ? "p" : "p$antennaIndex";

    // Step 1: 현재 태그 읽기 일시 정지 (Stop Command: >3\r\n)
    sendCommandString(stopCmd);
    await Future.delayed(const Duration(milliseconds: 100)); // Sleep(100) 역할

    // Step 2: 파워 변경 명령어 전송 (Set Control Packet)
    sendCommandString(">x $type $safePower\r\n");
    await Future.delayed(const Duration(milliseconds: 100));

    // Step 3: 다시 원래대로 태그 읽기 재개
    sendCommandString(startCmd);
  }
}

/// ATS200 휴대형 리더기 (자동 송신)
class Ats200Protocol extends AutoReportProtocol {
  Ats200Protocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: "SCAN_ON\n", stopCmd: "SCAN_OFF\n");

  @override
  String parseTagId(String packet) {
    // 콤마로 구분된 데이터 중 첫 번째 항목(EPC)만 추출
    if (packet.contains(',')) return packet.split(',')[0].trim();
    return packet.trim();
  }
}

/// M120 데스크형 리더기 (핸드쉐이킹 / 폴링 방식)
class M120PollingProtocol extends PollingProtocol {
  M120PollingProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, pollCmd: "GET_TAG\r\n", intervalMs: 500);

  @override
  String parseTagId(String packet) {
    String data = packet.trim();
    if (data.isEmpty || data == "NO_TAG" || data == "ERROR") return "";
    return data;
  }
}

/// Zebra 프린터 프로토콜 (ZPL 상태 체크용 - 폴링 방식)
class ZebraPrinterProtocol extends PollingProtocol {
  ZebraPrinterProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, pollCmd: "~HS", intervalMs: 1000);

  @override
  String parseTagId(String packet) => packet.trim();
}

/// SATO 프린터 프로토콜 (자동 송신)
class SatoPrinterProtocol extends AutoReportProtocol {
  SatoPrinterProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: "\x1bA", stopCmd: "\x1bZ");

  @override
  String parseTagId(String packet) => packet.trim();
}

/// ---------------------------------------------------------------------------
/// [신규 추가] 범용 RS232C 장치 프로토콜
/// Serial to TCP/IP 컨버터(Moxa NPort 등)를 통해 네트워크로 들어오는 시리얼 장비용.
/// 별도의 시작/중지 명령 없이 들어오는 Raw 데이터를 그대로(Pass-through) 수신합니다.
/// ---------------------------------------------------------------------------
class GenericRs232cProtocol extends AutoReportProtocol {
  // 범용이므로 특정 시작/종료 명령을 전송하지 않습니다.
  GenericRs232cProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: "", stopCmd: "");

  @override
  String parseTagId(String packet) {
    // 시리얼로 들어온 문자열의 공백이나 특수문자만 정리해서 그대로 UI나 Provider로 보냅니다.
    // 현장 장비(바코드 리더, 온도 센서, 무게계 등)의 순수 출력값을 얻을 때 사용됩니다.
    return packet.trim();
  }
}

/// 기본/테스트용 프로토콜
class DefaultProtocol extends AutoReportProtocol {
  DefaultProtocol(String ip, int port)
      : super(ipAddress: ip, port: port, startCmd: "START\n", stopCmd: "STOP\n");

  @override
  String parseTagId(String packet) => packet.trim();
}

/// ---------------------------------------------------------------------------
/// [팩토리] 모델 식별자에 따른 적절한 프로토콜 객체 생성 (Driver Factory)
/// DeviceProvider에서 DeviceProtocolFactory.create() 로 호출하여 사용합니다.
/// ---------------------------------------------------------------------------
class DeviceProtocolFactory {
  static BaseDeviceProtocol create(String modelValue, String ip, int port) {
    switch (modelValue) {
    // 1. 자동 송신(Event) 기반 장비들
      case SupportedDeviceModels.idro900f:
      case SupportedDeviceModels.cf815:
      case SupportedDeviceModels.cfRU5102:
      case SupportedDeviceModels.cf601:
        return Idro900fProtocol(ip, port);

      case SupportedDeviceModels.ats200:
        return Ats200Protocol(ip, port);
      case SupportedDeviceModels.sato:
        return SatoPrinterProtocol(ip, port);

    // 2. 핸드쉐이킹(Polling) 기반 장비들
      case SupportedDeviceModels.m120:
        return M120PollingProtocol(ip, port);
      case SupportedDeviceModels.zebra:
        return ZebraPrinterProtocol(ip, port);

    // 3. [신규] 범용 시리얼(RS232C) 컨버터 장비
      case SupportedDeviceModels.genericRs232c:
        return GenericRs232cProtocol(ip, port);

    // 4. 기본값 (범용 TCP)
      case SupportedDeviceModels.bt200:
      case SupportedDeviceModels.genericTcp:
      default:
        return DefaultProtocol(ip, port);
    }
  }
}