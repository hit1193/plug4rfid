import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // JSON 디코딩을 위해 추가
import 'dart:async';   // StreamSubscription(비동기 스트림 제어)을 사용하기 위해 필수

import '../models/device_model.dart';
import '../services/pb_service.dart';
import '../services/device_protocols.dart';

/// ---------------------------------------------------------------------------
/// [Data Structure] TagState (태그 상태 관리 구조체)
/// 현장에서 인식된 개별 RFID 태그의 상태와 이동 이력을 기억하는 클래스입니다.
/// C++의 struct 역할과 동일하며, 태그가 언제, 어느 리더기/안테나에서 인식되었고
/// 현재 IN(입고) 상태인지 OUT(출고) 상태인지를 추적합니다.
/// ---------------------------------------------------------------------------
class TagState {
  String epc;             // 태그의 고유 식별자 (Electronic Product Code)
  DateTime lastSeenTime;  // 가장 마지막으로 태그가 인식된 시간
  String status;          // 현재 판별된 상태 ('IN', 'OUT', 또는 'NONE')
  String lastReaderId;    // 마지막으로 이 태그를 읽어들인 장치(리더기)의 ID
  String lastAntenna;     // 마지막으로 이 태그를 읽어들인 안테나 번호

  TagState({
    required this.epc,
    required this.lastSeenTime,
    this.status = 'NONE',
    this.lastReaderId = '',
    this.lastAntenna = '',
  });
}

/// ---------------------------------------------------------------------------
/// [Logic] DeviceProvider (장치 상태 관리 및 실시간 통신 전담 DataModule)
/// C++Builder의 DataModule과 완벽하게 동일한 역할을 수행하는 전역 상태 관리자입니다.
/// 병렬 통신 엔진을 탑재하여 여러 대의 리더기/스캐너/프린터를 동시에 제어하고,
/// UI(화면)와 통신 로직을 분리하여 시스템의 안정성을 극대화합니다.
/// ---------------------------------------------------------------------------
class DeviceProvider extends ChangeNotifier {
  final String _collectionName = 'devices'; // DB(PocketBase) 테이블명

  // 상태 변수들
  List<DeviceModel> _list = [];             // 화면에 표시할 전체 장치 목록
  bool _isLoading = false;                  // DB에서 데이터를 불러오는 중인지 여부
  bool _isSaving = false;                   // 데이터를 DB에 저장(업데이트) 중인지 여부
  bool _isDisposed = false;                 // 메모리에서 해제(Free) 되었는지 확인하는 플래그

  // [핵심 자원 관리 맵]
  // 현재 통신이 연결되어 가동 중인 프로토콜(드라이버) 객체들을 보관합니다.
  final Map<String, BaseDeviceProtocol> _activeProtocols = {};

  // 윈도우 네이티브 런타임 에러 방지용 (Heap Corruption 방지)
  // Dart의 Stream(데이터 파이프라인)을 쥐고 있는 구독(Subscription) 핸들들을 보관합니다.
  final Map<String, StreamSubscription> _activeSubscriptions = {};

  // [완벽 종료 방어용 락(Lock)]
  // 이중 해제(Double Free)를 방지하기 위해, 현재 종료 프로세스가 진행 중인 기기를 추적합니다.
  final Set<String> _disconnectingDevices = {};

  // 각 장치별 터미널 로그를 저장하는 맵 (타입 충돌을 막기 위해 순수 String만 사용)
  final Map<String, List<String>> _packetLogs = {};

  // 시스템 가동 중 인식된 태그들의 상태 이력을 관리하는 메모리 변수
  final Map<String, TagState> _tagStates = {};

  // Getter 메서드들 (외부에서 읽기 전용으로 접근)
  List<DeviceModel> get list {
    return _list;
  }

  bool get isLoading {
    return _isLoading;
  }

  bool get isSaving {
    return _isSaving;
  }

  Map<String, TagState> get tagStates {
    return _tagStates;
  }

  // 생성자: Provider가 메모리에 올라갈 때 자동 실행되는 초기화 루틴
  DeviceProvider() {
    _initializeSequence();
    _subscribe(); // DB 실시간 변경사항 구독
  }

  /// 특정 장치의 실시간 로그 리스트를 반환합니다.
  List<String> getLogs(String deviceId) {
    return _packetLogs[deviceId] ?? [];
  }

  /// 특정 장치의 로그 터미널 창을 깨끗하게 비웁니다.
  void clearLogs(String deviceId) {
    if (_packetLogs.containsKey(deviceId)) {
      _packetLogs[deviceId]!.clear();
      notifyListeners(); // UI 강제 갱신
    }
  }

  /// -------------------------------------------------------------------------
  /// [초기 구동 시퀀스]
  /// 앱 재시작 시 프로그램이 비정상 종료되어 DB에 남아있는 '유령 상태(Ghost State)'
  /// 즉, 실제로는 끊겼는데 DB에는 'Online'으로 남아있는 장치들을 'Offline'으로 초기화합니다.
  /// -------------------------------------------------------------------------
  Future<void> _initializeSequence() async {
    await fetchData();

    bool needsNotify = false;
    for (int i = 0; i < _list.length; i++) {
      if (_list[i].status.toLowerCase() == 'online') {
        _list[i] = _list[i].copyWith(
          status: 'Offline', // 🔥 DB 스키마 검증에 맞게 대문자로 원복
          updated: DateTime.now(),
        );
        _syncStatusToDbOnly(_list[i].id, 'Offline'); // 🔥 DB 스키마 검증에 맞게 대문자로 원복
        needsNotify = true;
      }
    }

    if (needsNotify) {
      notifyListeners(); // 화면 갱신
    }

    // 초기화가 끝난 후, 진짜 자동 연결(Auto Connect)이 설정된 장치들만 포트를 엽니다.
    _autoConnectDevices();
  }

  /// -------------------------------------------------------------------------
  /// [병렬 자동 연결 로직]
  /// 장치가 여러 개일 때 순서대로 기다리지 않고 모든 장치를 동시에(Parallel) 연결 시도합니다.
  /// -------------------------------------------------------------------------
  void _autoConnectDevices() {
    if (_isDisposed) {
      return;
    }

    int autoConnectCount = 0;
    for (var device in _list) {
      if (device.isActive && device.isAutoConnect && device.ipAddress.isNotEmpty) {
        autoConnectCount++;
      }
    }

    if (autoConnectCount > 0) {
      debugPrint("🚀 [시스템] $autoConnectCount개의 등록 장치에 대해 병렬 자동 연결 시퀀스 가동");
      for (var device in _list) {
        if (device.isActive && device.isAutoConnect && device.ipAddress.isNotEmpty) {
          connectDevice(device);
        }
      }
    } else {
      debugPrint("ℹ️ [시스템] 자동 연결(AutoConnect) 설정된 장치가 없습니다.");
    }
  }

  /// -------------------------------------------------------------------------
  /// [메모리 완전 해제] C++의 ~Destructor() 역할
  /// 앱이 종료되거나 Provider가 파괴될 때 모든 스트림과 소켓, 포트를 안전하게 닫습니다.
  /// -------------------------------------------------------------------------
  @override
  void dispose() {
    _isDisposed = true;

    // 1. 메모리 누수 및 크래시 방지를 위해 모든 스트림 구독(Subscription) 해제
    for (var sub in _activeSubscriptions.values) {
      sub.cancel();
    }
    _activeSubscriptions.clear();

    // 2. 가동 중인 모든 통신 드라이버 안전 종료
    for (var protocol in _activeProtocols.values) {
      try {
        protocol.dispose();
      } catch (e) {
        debugPrint("프로토콜 해제 오류: $e");
      }
    }

    // 3. 자원 비우기 (메모리 Free)
    _activeProtocols.clear();
    _packetLogs.clear();
    _tagStates.clear();
    _disconnectingDevices.clear();

    super.dispose();
  }

  /// Provider가 파괴된 후에 UI를 갱신하려고 시도해서 앱이 뻗는 것을 방지하는 안전 래퍼입니다.
  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  /// -------------------------------------------------------------------------
  /// [데이터 조회] PocketBase DB에서 최신 장치 목록 불러오기
  /// -------------------------------------------------------------------------
  Future<void> fetchData() async {
    if (_isDisposed) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // DB에서 생성일 기준 내림차순(최신순)으로 장치 목록을 가져옵니다.
      final records = await PBService.pb.collection(_collectionName).getFullList(sort: '-created');
      if (_isDisposed) {
        return;
      }

      _list = records.map((r) {
        return DeviceModel.fromRecord(r);
      }).toList();
    } catch (e) {
      debugPrint("장치 로드 실패: $e");
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// -------------------------------------------------------------------------
  /// [데이터 정화] 문자열 안전 정화 기능 (UI 크래시 방지 필터)
  /// 통신 중 깨진 바이트(Garbage Data)가 텍스트 위젯에 들어가서 화면이 터지는 것을 막습니다.
  /// -------------------------------------------------------------------------
  String _sanitizeString(String input) {
    if (input.isEmpty) {
      return "";
    }
    try {
      final StringBuffer buffer = StringBuffer();
      for (var char in input.runes) {
        // 일반 ASCII 제어문자 및 한국어 영역만 허용하고 나머지는 '?'로 치환합니다.
        if ((char >= 32 && char <= 126) || (char >= 0xAC00 && char <= 0xD7A3) || char == 10 || char == 13) {
          buffer.writeCharCode(char);
        } else {
          buffer.write('?');
        }
      }
      return buffer.toString();
    } catch (e) {
      return "[데이터 손상됨]";
    }
  }

  /// -------------------------------------------------------------------------
  /// [로깅 시스템] 시스템 메시지를 터미널 화면에 출력하기 위한 헬퍼 함수
  /// -------------------------------------------------------------------------
  void _logSystem(String deviceId, String message) {
    if (!_packetLogs.containsKey(deviceId)) {
      _packetLogs[deviceId] = [];
    }

    final timestamp = DateTime.now().toString().substring(11, 19);
    final cleanedMsg = _sanitizeString(message);

    _packetLogs[deviceId]!.add("[$timestamp] <<< [SYS] $cleanedMsg");

    // 메모리 과부하를 막기 위해 로그는 항상 최근 100줄만 유지합니다. (선입선출)
    if (_packetLogs[deviceId]!.length > 100) {
      _packetLogs[deviceId]!.removeAt(0);
    }
    notifyListeners();
  }

  /// -------------------------------------------------------------------------
  /// [통신 엔진 코어] 개별 장치 접속 제어 로직
  /// 선택된 장치의 IP(또는 COM포트)로 연결을 시도하고 스트림 파이프라인을 엽니다.
  /// -------------------------------------------------------------------------
  Future<void> connectDevice(DeviceModel device) async {
    if (device.ipAddress.isEmpty) {
      _logSystem(device.id, "⚠️ 오류: 통신 주소가 없습니다.");
      return;
    }

    // 중복 방어 1: 이미 종료(Disconnect)가 진행 중인 기기라면 접속 시도를 무시합니다.
    if (_disconnectingDevices.contains(device.id)) {
      _logSystem(device.id, "⏳ 현재 이전 통신을 안전하게 해제하는 중입니다. 잠시 후 다시 시도해주세요.");
      return;
    }

    // 중복 방어 2: 이미 해당 장치의 프로토콜이 가동 중이면 기존 것을 안전하게 해제 후 재시작합니다.
    if (_activeProtocols.containsKey(device.id)) {
      _logSystem(device.id, "🔄 기존 통신 세션 초기화 및 재접속 시도...");
      await disconnectDevice(device.id); // 안전하게 비동기로 끊어냅니다.
    }

    // 팩토리 패턴을 이용해 장치 모델에 맞는 통신 객체(Driver)를 생성합니다.
    final protocol = DeviceProtocolFactory.create(device.model, device.ipAddress, device.port);
    _activeProtocols[device.id] = protocol;

    _logSystem(device.id, "🚀 접속 프로세스 시작: ${device.ipAddress}:${device.port}");

    try {
      // 5초 타임아웃 방어: 특정 한 장비의 통신 지연이 전체 앱을 멈추게(Freezing) 하지 않도록 합니다.
      bool success = await protocol.connect().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _logSystem(device.id, "⏰ 타임아웃: 포트 응답 없음");
            return false;
          }
      );

      if (success) {
        _logSystem(device.id, "✅ 접속 성공! 데이터 수집 대기 중...");

        // 스트림을 닫을 때 완벽한 제어를 위해 구독(Subscription) 객체를 맵에 저장해 둡니다.
        _activeSubscriptions[device.id] = protocol.tagStream.listen(
                (tagData) {
              _onDataReceived(device.id, tagData);
            },
            onError: (err) {
              _logSystem(device.id, "❌ 수신 스트림 오류: $err");
              disconnectDevice(device.id); // 에러 발생 시 뻗지 않고 안전하게 연결만 해제합니다.
            }
        );

        String usageRole = device.settings['usage_role']?.toString() ?? '';

        // 발급/등록용 장비는 먼저 읽기를 시작하지 않고 대기합니다.
        if (usageRole == '수동스캔(단일등록)') {
          _logSystem(device.id, "🤫 발급 리더기 모드: 명령 대기 중(Idle)");
        } else {
          try {
            await protocol.startInventory();
            _logSystem(device.id, "📡 감시 모드 가동: 실시간 태그 수집 시작");
          } catch (e) {
            _logSystem(device.id, "⚠️ 인벤토리 명령 실패: $e");
          }
        }

        // [UI 즉시 갱신] DB 조회를 기다리지 않고 메모리 상태를 먼저 'Online'으로 바꿉니다. (빠른 반응성)
        _updateLocalStatus(device.id, 'Online'); // 🔥 대문자로 원복
        _syncStatusToDbOnly(device.id, 'Online'); // 🔥 대문자로 원복
      } else {
        _logSystem(device.id, "❌ 접속 실패 (포트 점유 또는 설정 오류)");
        _activeProtocols.remove(device.id);
        _updateLocalStatus(device.id, 'Offline'); // 🔥 대문자로 원복
        _syncStatusToDbOnly(device.id, 'Offline'); // 🔥 대문자로 원복
      }
    } catch (e) {
      _logSystem(device.id, "🔥 연결 중 치명적 예외: $e");
      _activeProtocols.remove(device.id);
      _updateLocalStatus(device.id, 'Offline'); // 🔥 대문자로 원복
      _syncStatusToDbOnly(device.id, 'Offline'); // 🔥 대문자로 원복
    }
  }

  /// -------------------------------------------------------------------------
  /// [UI 즉시 반응용] 메모리 내 장치 상태 교체 로직
  /// DB 업데이트를 기다리지 않고 화면의 상태 배지를 즉시 변경해 줍니다.
  /// -------------------------------------------------------------------------
  void _updateLocalStatus(String deviceId, String status) {
    final index = _list.indexWhere((d) {
      return d.id == deviceId;
    });

    if (index != -1) {
      final oldDevice = _list[index];
      // 플러터의 불변성(Immutability) 원칙에 따라 기존 객체를 복사(copyWith)하여 업데이트합니다.
      _list[index] = DeviceModel(
        id: oldDevice.id,
        collectionId: oldDevice.collectionId,
        name: oldDevice.name,
        model: oldDevice.model,
        ipAddress: oldDevice.ipAddress,
        port: oldDevice.port,
        status: status,
        commMethod: oldDevice.commMethod,
        isActive: oldDevice.isActive,
        isAutoConnect: oldDevice.isAutoConnect,
        settings: oldDevice.settings,
        clientId: oldDevice.clientId,
        image: oldDevice.image,
        posX: oldDevice.posX,
        posY: oldDevice.posY,
        created: oldDevice.created,
        updated: DateTime.now(),
      );
      notifyListeners();
    }
  }

  /// -------------------------------------------------------------------------
  /// [DB 동기화] 백그라운드 DB 상태 동기화
  /// 화면을 가리지 않고 백그라운드에서 조용히 DB의 접속 상태를 업데이트합니다.
  /// -------------------------------------------------------------------------
  Future<void> _syncStatusToDbOnly(String deviceId, String status) async {
    try {
      await PBService.pb.collection(_collectionName).update(deviceId, body: {'status': status});
    } catch (e) {
      debugPrint("DB 상태 동기화 실패: $e");
    }
  }

  /// -------------------------------------------------------------------------
  /// [초강력 안전 장치] 윈도우 네이티브 힙 손상(Heap Corruption) 완벽 방어 엔진
  /// C++Builder의 Thread->Terminate() -> Thread->WaitFor() -> CloseHandle()
  /// 순서를 완벽하게 재현하여 포트 엉킴이나 강제 종료 현상을 원천 차단했습니다.
  /// -------------------------------------------------------------------------
  Future<void> disconnectDevice(String deviceId) async {
    if (_disconnectingDevices.contains(deviceId)) {
      return; // 이미 해제 중인 장치는 중복 진입 방지 (Double Free 차단)
    }

    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;
      _disconnectingDevices.add(deviceId); // 해제 중 락(Lock) 설정

      try {
        // 1. 하드웨어 전파 발사 중지 명령 (리더기가 쏘는 데이터 자체를 멈춤)
        try {
          await protocol.stopInventory();
          _logSystem(deviceId, "⏹️ 하드웨어 읽기 중단 명령 전송 완료");
        } catch (_) {}

        // 2. Dart 쪽 수신 파이프라인(Stream) 해제 (C++의 Thread->Terminate() 역할)
        // 다트의 스트림을 취소하여 C++ 라이브러리의 SerialPortReader 루프 탈출을 유도합니다.
        if (_activeSubscriptions.containsKey(deviceId)) {
          _logSystem(deviceId, "⏳ 다트 수신 스트림 파이프라인 해제 중...");
          await _activeSubscriptions[deviceId]!.cancel();
          _activeSubscriptions.remove(deviceId);
        }

        // 3. [가장 핵심 방어] C++ 네이티브 스레드 완전 종료 대기 (C++의 Thread->WaitFor() 역할)
        // 다트에서 cancel()을 호출했더라도 백그라운드의 네이티브 C++ 스레드가
        // 포트 핸들(Handle) 참조를 완전히 내려놓기까지는 약간의 딜레이가 필연적으로 발생합니다.
        // 이를 기다리지 않고 바로 dispose(free)를 때려버리면 100% 엑스박스가 뜨며 뻗어버립니다.
        _logSystem(deviceId, "⏳ C++ 네이티브 스레드 루프 완전 탈출 대기 중 (WaitFor)...");
        await Future.delayed(const Duration(milliseconds: 800));

        // 4. 물리적 포트/소켓 해제 (CloseHandle & Free 역할)
        // 네이티브 스레드가 포트 핸들 참조를 완벽히 놓은 고요한 상태에서 해제합니다.
        _logSystem(deviceId, "⏳ 물리적 포트 자원(Handle) 해제 중...");
        try {
          protocol.dispose();
        } catch (e) {
          debugPrint("해제 중 오류 무시: $e"); // 여기서 에러가 나도 앱이 죽지 않게 씹어버립니다.
        }

        _activeProtocols.remove(deviceId);
        _logSystem(deviceId, "🔌 모든 작업 완료: 장치 연결이 완벽하게 해제되었습니다.");

        // 접속 해제 완료 후 상태를 갱신합니다.
        _updateLocalStatus(deviceId, 'Offline'); // 🔥 대문자로 원복
        _syncStatusToDbOnly(deviceId, 'Offline'); // 🔥 대문자로 원복

      } finally {
        _disconnectingDevices.remove(deviceId); // 안전하게 락(Lock) 해제
      }
    }
  }

  /// -------------------------------------------------------------------------
  /// [제어 명령] 하드웨어 안테나 출력(RF Power) 제어
  /// -------------------------------------------------------------------------
  Future<void> setDevicePower(String deviceId, int antennaIndex, int powerLevel) async {
    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;
      _logSystem(deviceId, "📡 안테나($antennaIndex) 출력 변경 명령: ${powerLevel/10}dBm");
      await protocol.setAntennaPower(antennaIndex, powerLevel);
    }
  }

  /// -------------------------------------------------------------------------
  /// [제어 명령] 수동으로 태그 읽기(Inventory) 시작 명령 하달
  /// -------------------------------------------------------------------------
  Future<void> triggerDeviceRead(String deviceId) async {
    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;
      _logSystem(deviceId, "▶️ 수동 읽기(Scan) 시작 명령 하달 완료");

      try {
        await protocol.startInventory();
      } catch (e) {
        _logSystem(deviceId, "❌ 수동 읽기 시작 명령 전송 중 오류 발생: $e");
      }
    } else {
      _logSystem(deviceId, "⚠️ 오류: 연결된 장치가 없습니다. 통신을 먼저 시작해주세요.");
    }
  }

  /// -------------------------------------------------------------------------
  /// [제어 명령] 수동으로 태그 읽기(Inventory) 중지 명령 하달
  /// -------------------------------------------------------------------------
  Future<void> stopDeviceRead(String deviceId) async {
    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;
      _logSystem(deviceId, "⏹️ 태그 읽기(Scan) 중단 명령 하달 완료");

      try {
        await protocol.stopInventory();
      } catch (e) {
        _logSystem(deviceId, "❌ 수동 읽기 중단 명령 전송 중 오류 발생: $e");
      }
    } else {
      debugPrint("⚠️ 경고: 장치($deviceId) 연결이 이미 끊어져 있어 중단 명령을 무시합니다.");
    }
  }

  /// -------------------------------------------------------------------------
  /// [핵심 수정 포인트 🔥] 메모리 쓰기 시 스레드 락/대기 처리 (Blocking)
  /// C++Builder의 Thread->WaitFor() 원리와 동일합니다.
  /// 하위 프로토콜에서 완료 신호(ACK)가 떨어지기 전까지 절대 넘어가선 안 됩니다!
  /// -------------------------------------------------------------------------
  Future<bool> writeTagData(String deviceId, String input, {bool isHexMode = false}) async {
    if (!_activeProtocols.containsKey(deviceId)) {
      _logSystem(deviceId, "⚠️ 오류: 연결된 장치가 없습니다.");
      return false; // 통신 객체가 없으면 즉시 실패 (대기망 유지됨)
    }

    String finalHex = "";

    try {
      if (isHexMode) {
        // Hex 모드: 공백 제거 후 순수 16진수만 남깁니다.
        String cleaned = input.replaceAll(' ', '').toUpperCase();
        if (!RegExp(r'^[0-9A-F]+$').hasMatch(cleaned)) {
          _logSystem(deviceId, "⚠️ 오류: 올바른 Hex 형식이 아닙니다.");
          return false;
        }
        // RFID 메모리 블록(Word) 단위인 4자리(2바이트) 배수로 0을 패딩합니다.
        if (cleaned.length % 4 != 0) {
          cleaned = cleaned.padRight(cleaned.length + (4 - cleaned.length % 4), '0');
        }
        finalHex = cleaned;
      } else {
        // ASCII 모드: 일반 문자를 16진수 헥사코드로 변환합니다.
        finalHex = input.codeUnits.map((unit) {
          return unit.toRadixString(16).padLeft(2, '0').toUpperCase();
        }).join('');

        // 마찬가지로 4자리 배수로 패딩합니다.
        if (finalHex.length % 4 != 0) {
          finalHex = finalHex.padRight(finalHex.length + (4 - finalHex.length % 4), '0');
        }
      }

      // [버그 완벽 해결!]
      // `writeTagMemory`가 반환형이 없는(void) 함수이므로 변수에 값을 담으려 하면
      // Dart 문법 에러(Type of 'void')가 발생합니다.
      // 단순히 await로 실행만 하고, 만약 하드웨어 쪽에서 에러나 타임아웃이 발생하면
      // 프로토콜 단에서 던진 예외(Exception)를 바로 아래의 catch가 받도록 처리합니다!
      await _activeProtocols[deviceId]!.writeTagMemory(1, 2, finalHex);

      // 여기까지 무사히 넘어왔다는 것은 하드웨어 쪽에서 아무 에러 없이 잘 기록했다는 뜻입니다.
      return true;

    } catch (e) {
      // 통신 단절이나 예외 발생 시(태그 없음 등) 앱이 뻗지 않도록 씹어버리고 false 반환!
      // 이렇게 false가 반환되어야 ProductPage의 while 루프가 깨지지 않고 무한 대기합니다.
      _logSystem(deviceId, "❌ 쓰기 실패 (태그 없음 또는 타임아웃)");
      return false;
    }
  }

  /// -------------------------------------------------------------------------
  /// [수신 이벤트 중앙 처리 엔진] 데이터 수신 파이프라인
  /// 하위 드라이버(Protocol)에서 올라온 원시 데이터나 JSON 브릿지 데이터를 분석하여
  /// 로그 화면에 출력하고, 방향 판별 로직으로 태그 정보를 넘깁니다.
  /// -------------------------------------------------------------------------
  void _onDataReceived(String deviceId, String data) {
    if (!_packetLogs.containsKey(deviceId)) {
      _packetLogs[deviceId] = [];
    }

    final timestamp = DateTime.now().toString().substring(11, 19);
    final cleanedData = _sanitizeString(data);

    if (cleanedData.startsWith('JSON:')) {
      try {
        // 드라이버가 넘겨준 JSON 규격 데이터를 파싱합니다.
        String jsonString = cleanedData.substring(5);
        Map<String, dynamic> parsed = jsonDecode(jsonString);

        String epc = parsed['epc'] ?? "";
        String ant = parsed['ant']?.toString() ?? "1";
        String rssi = parsed['rssi'] ?? "";

        _packetLogs[deviceId]!.add("[$timestamp] 🎯 [태그 인식] EPC:$epc | Ant:$ant | RSSI:$rssi");
        if (epc.isNotEmpty) {
          // 태그가 정상 인식되었다면 비즈니스 로직(방향 판별)으로 넘깁니다.
          _processTagDirection(deviceId, epc, ant);
        }
      } catch (e) {
        _packetLogs[deviceId]!.add("[$timestamp] <<< $cleanedData");
      }
    } else {
      // JSON 규격이 아닌 일반 시스템 메시지나 RAW 패킷은 그대로 출력합니다.
      _packetLogs[deviceId]!.add("[$timestamp] $cleanedData");
    }

    if (_packetLogs[deviceId]!.length > 100) {
      _packetLogs[deviceId]!.removeAt(0);
    }

    notifyListeners();
  }

  /// -------------------------------------------------------------------------
  /// [비즈니스 로직 코어] 현장 출입/이동 방향 결정 로직
  /// 각 장비에 설정된 'dir_mode(방향 판별 모드)'에 따라 태그가 들어왔는지 나갔는지 판별합니다.
  /// -------------------------------------------------------------------------
  void _processTagDirection(String deviceId, String epc, String ant) {
    try {
      final int deviceIndex = _list.indexWhere((d) {
        return d.id == deviceId;
      });
      if (deviceIndex == -1) {
        return;
      }

      final device = _list[deviceIndex];
      final String mode = device.settings['dir_mode']?.toString() ?? 'none';
      final String option = device.settings['dir_option']?.toString() ?? '3';

      // 메모리에 기존 태그 상태가 없다면 신규 객체를 생성합니다.
      TagState state = _tagStates[epc] ?? TagState(epc: epc, lastSeenTime: DateTime.fromMillisecondsSinceEpoch(0));
      DateTime now = DateTime.now();

      String determinedDirection = "";
      bool shouldLog = false;

      switch (mode) {
        case 'none': // [단순 교차 모드] 설정된 시간 이후에 다시 읽히면 IN <-> OUT 상태 반전
          int discardSeconds = int.tryParse(option) ?? 3;
          if (now.difference(state.lastSeenTime).inSeconds < discardSeconds) {
            return; // 중복 읽기(채터링) 방어
          }
          determinedDirection = (state.status == 'IN') ? '출고(OUT)' : '입고(IN)';
          state.status = (state.status == 'IN') ? 'OUT' : 'IN';
          shouldLog = true;
          break;

        case 'reader_seq': // [리더기 시퀀스 모드] A리더기에서 B리더기로 이동한 이력 추적
          if (state.lastReaderId.isNotEmpty && state.lastReaderId != deviceId) {
            determinedDirection = '이동 [리더 변경: ${state.lastReaderId} ➔ ${device.name}]';
            shouldLog = true;
          }
          break;

        case 'ant_seq': // [안테나 시퀀스 모드] 1번 안테나 ➔ 2번 안테나 순차 통과 시 방향 인정
          if (state.lastAntenna.isNotEmpty && state.lastAntenna != ant) {
            if (state.lastAntenna == '1' && ant == '2') {
              determinedDirection = '입고(IN) [Ant 1➔2]';
              state.status = 'IN';
            } else if (state.lastAntenna == '2' && ant == '1') {
              determinedDirection = '출고(OUT) [Ant 2➔1]';
              state.status = 'OUT';
            }
            shouldLog = true;
          }
          break;

        case 'reader_fixed': // [리더기 고정 모드] 이 장치에서 읽히면 무조건 지정된 방향으로 강제 고정
          determinedDirection = option.contains('OUT') ? '출고(OUT)' : '입고(IN)';
          String newStatus = determinedDirection.contains('IN') ? 'IN' : 'OUT';

          if (state.status != newStatus || now.difference(state.lastSeenTime).inSeconds > 3) {
            state.status = newStatus;
            shouldLog = true;
          }
          break;

        case 'ant_fixed': // [안테나 고정 모드] 홀수 안테나=IN, 짝수 안테나=OUT 으로 맵핑
          int antNum = int.tryParse(ant) ?? 1;
          if (antNum % 2 != 0) {
            determinedDirection = '입고(IN) [Ant $ant]';
            state.status = 'IN';
          } else {
            determinedDirection = '출고(OUT) [Ant $ant]';
            state.status = 'OUT';
          }
          if (now.difference(state.lastSeenTime).inSeconds > 3) {
            shouldLog = true;
          }
          break;
      }

      // 판별이 끝나면 상태 객체를 최신 시간과 위치로 갱신하여 맵에 저장합니다.
      state.lastSeenTime = now;
      state.lastReaderId = deviceId;
      state.lastAntenna = ant;
      _tagStates[epc] = state;

      if (shouldLog && determinedDirection.isNotEmpty) {
        _logSystem(deviceId, "★★★ [방향 판별 완료] EPC: $epc ➔ $determinedDirection");
        // 나중에 여기서 서버 API 전송이나 알림 등을 트리거할 수 있습니다.
      }
    } catch (e) {
      debugPrint("방향 판단 오류: $e");
    }
  }

  /// -------------------------------------------------------------------------
  /// [실시간 감시] PocketBase의 SSE(Server-Sent Events)를 구독하여
  /// 외부 웹이나 다른 기기에서 장치가 추가/수정/삭제될 경우 화면을 즉시 동기화합니다.
  /// -------------------------------------------------------------------------
  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) {
      if (!_isDisposed) {
        fetchData();
      }
    });
  }

  /// -------------------------------------------------------------------------
  /// [데이터 등록/수정] 장비 설정 저장 로직
  /// -------------------------------------------------------------------------
  Future<bool> handleSave({
    required DeviceModel? d,
    required Map<String, dynamic> data,
    XFile? imageXFile,
    bool skipAutoConnect = false,
  }) async {
    if (_isDisposed) {
      return false;
    }
    _isSaving = true;
    notifyListeners();

    try {
      // 이미지 첨부파일 처리 (Multipart)
      List<http.MultipartFile> files = [];
      if (imageXFile != null) {
        final bytes = await imageXFile.readAsBytes();
        files.add(http.MultipartFile.fromBytes('image', bytes, filename: imageXFile.name));
      }

      String savedId = "";
      // d가 null이면 신규 Insert, 값이 있으면 Update 쿼리 실행
      if (d == null) {
        final record = await PBService.pb.collection(_collectionName).create(body: data, files: files);
        savedId = record.id;
      } else {
        final record = await PBService.pb.collection(_collectionName).update(d.id, body: data, files: files);
        savedId = record.id;
      }

      // 저장이 끝나면 DB를 새로고침하여 메모리 리스트를 최신화합니다.
      await fetchData();

      // 자동 연결 옵션이 켜져있다면 저장 후 약간 대기했다가 바로 통신을 엽니다.
      try {
        final savedDevice = _list.firstWhere((item) {
          return item.id == savedId;
        });
        if (savedDevice.isActive && savedDevice.isAutoConnect && !skipAutoConnect) {
          Future.delayed(const Duration(milliseconds: 300), () {
            connectDevice(savedDevice);
          });
        }
      } catch (_) {}

      return true;
    } catch (e) {
      return false; // 저장 실패
    } finally {
      if (!_isDisposed) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  /// -------------------------------------------------------------------------
  /// [데이터 삭제] 특정 장치를 DB에서 영구 삭제합니다.
  /// -------------------------------------------------------------------------
  Future<bool> deleteDevice(String id) async {
    try {
      await PBService.pb.collection(_collectionName).delete(id);
      return true;
    } catch (e) {
      return false;
    }
  }
}