import 'package:flutter/foundation.dart';

/// [인터페이스] 장비별 통신 규격 추상 클래스
/// C++의 class BaseProtocol { virtual String getStartCommand() = 0; } 구조와 동일합니다.
abstract class DeviceProtocol {
  /// 장비 가동 시작 명령 (RFID 리딩 시작 등)
  String get startCommand;

  /// 장비 가동 중지 명령 (RFID 리딩 중단 등)
  String get stopCommand;

  /// 하드웨어에서 들어온 Raw Data를 규격에 맞게 파싱 (태그 ID 추출)
  String parseTagId(String rawData);
}

/// ---------------------------------------------------------
/// [상수 정의] 지원하는 구체적 장치 모델 리스트
/// PocketBase의 'model' 필드 Select 옵션과 1:1 매칭하십시오.
/// ---------------------------------------------------------
class SupportedDeviceModels {
  // 1. 내부 로직 및 DB 저장용 고유 키 (Value)
  static const String idro900f   = 'IDRO900F';
  static const String cf815      = 'CF815';
  static const String cfRU5102   = 'CF_RU5102';
  static const String cf601      = 'CF601';
  static const String ats200     = 'ATS200';
  static const String m120       = 'M120';
  static const String zebra      = 'ZEBRA';
  static const String bt200      = 'BT200';
  static const String sato       = 'SATO';
  static const String genericTcp = 'GENERIC_TCP';

  // 2. 관리자 화면(UI)에서 보여줄 한글 이름 매핑 (Label)
  static const Map<String, String> labels = {
    idro900f: '고정식 리더기 (IDRO900F)',
    cf815: '고정식 리더기 (CF815)',
    cfRU5102: '데스크형 리더기 (CF_RU5102)',
    cf601: '데스크형 리더기 (CF601)',
    ats200: '휴대형 리더기 (ATS200)',
    m120: '데스크형 리더기 (M120)',
    zebra: '프린터 (Zebra)',
    bt200: '프린터 (BT200)',
    sato: '프린터 (SATO)',
    genericTcp: '범용 TCP 장치',
  };

  /// UI(Dropdown) 등에서 사용할 순수 키 리스트
  static List<String> get list => labels.keys.toList();
}

/// ---------------------------------------------------------
/// [구현체] 각 모델별 드라이버 로직 (C++의 개별 드라이버 Unit 역할)
/// ---------------------------------------------------------

/// 표준 RFID 리더기 프로토콜 (IDRO, CF 시리즈 등 ASCII 기반 장비 공용)
class StandardRfidProtocol extends DeviceProtocol {
  final String startCmd;
  StandardRfidProtocol(this.startCmd);

  @override
  String get startCommand => "$startCmd\r\n";
  @override
  String get stopCommand => ">3\r\n";
  @override
  String parseTagId(String rawData) {
    // 하드웨어 특성에 따라 접두어(>)나 공백 제거
    return rawData.trim().replaceAll(">", "");
  }
}

/// ATS200 휴대형 리더기 프로토콜
class Ats200Protocol extends DeviceProtocol {
  @override
  String get startCommand => "SCAN_ON\n";
  @override
  String get stopCommand => "SCAN_OFF\n";
  @override
  String parseTagId(String rawData) {
    // 콤마로 구분된 데이터 중 첫 번째 항목(EPC)만 추출
    if (rawData.contains(',')) return rawData.split(',')[0].trim();
    return rawData.trim();
  }
}

/// Zebra 프린터 프로토콜 (ZPL 규격)
class ZebraPrinterProtocol extends DeviceProtocol {
  @override
  String get startCommand => "~HS"; // Zebra Host Status 체크
  @override
  String get stopCommand => "";
  @override
  String parseTagId(String rawData) => rawData.trim();
}

/// SATO 프린터 프로토콜 (SBPL 규격)
class SatoPrinterProtocol extends DeviceProtocol {
  @override
  String get startCommand => "\x1bA"; // SATO 시작 시퀀스
  @override
  String get stopCommand => "\x1bZ";
  @override
  String parseTagId(String rawData) => rawData.trim();
}

/// 기본/테스트용 프로토콜
class DefaultProtocol extends DeviceProtocol {
  @override
  String get startCommand => "START\n";
  @override
  String get stopCommand => "STOP\n";
  @override
  String parseTagId(String rawData) => rawData.trim();
}

/// ---------------------------------------------------------
/// [팩토리] 모델 식별자에 따른 적절한 프로토콜 객체 생성 (Driver Factory)
/// ---------------------------------------------------------
class ProtocolFactory {
  static DeviceProtocol getProtocol(String modelValue) {
    switch (modelValue) {
      case SupportedDeviceModels.idro900f:
        return StandardRfidProtocol(">f");
      case SupportedDeviceModels.cf815:
      case SupportedDeviceModels.cfRU5102:
      case SupportedDeviceModels.cf601:
        return StandardRfidProtocol("INV_START");
      case SupportedDeviceModels.m120:
        return StandardRfidProtocol("GET_TAG");
      case SupportedDeviceModels.ats200:
        return Ats200Protocol();
      case SupportedDeviceModels.zebra:
        return ZebraPrinterProtocol();
      case SupportedDeviceModels.sato:
        return SatoPrinterProtocol();
      case SupportedDeviceModels.bt200:
      case SupportedDeviceModels.genericTcp:
      default:
        return DefaultProtocol();
    }
  }
}