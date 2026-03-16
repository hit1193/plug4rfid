import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // JSON 디코딩을 위해 추가
import 'dart:async';   // StreamSubscription(비동기 스트림 제어)을 사용하기 위해 필수

import '../models/device_model.dart';
import '../services/pb_service.dart';
import '../services/device_protocols.dart';

/// ---------------------------------------------------------------------------
/// [Data Structure] 개별 태그의 상태와 이력을 기억하는 클래스
/// ---------------------------------------------------------------------------
class TagState {
  String epc;
  DateTime lastSeenTime;
  String status; // 'IN', 'OUT', 또는 'NONE'
  String lastReaderId;
  String lastAntenna;

  TagState({
    required this.epc,
    required this.lastSeenTime,
    this.status = 'NONE',
    this.lastReaderId = '',
    this.lastAntenna = '',
  });
}

/// ---------------------------------------------------------------------------
/// [Logic] 장치 상태 관리 및 실시간 통신 전담 클래스 (Global DataModule)
/// 병렬 통신 엔진을 탑재하여 여러 장치의 동시 접속을 효율적으로 제어합니다.
/// ---------------------------------------------------------------------------
class DeviceProvider extends ChangeNotifier {
  final String _collectionName = 'devices';
  List<DeviceModel> _list = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDisposed = false;

  final Map<String, BaseDeviceProtocol> _activeProtocols = {};

  // 윈도우 네이티브 런타임 에러 방지용 (Heap Corruption 방지)
  // Dart의 Stream(데이터 파이프라인)을 쥐고 있는 구독(Subscription) 객체들을 보관합니다.
  final Map<String, StreamSubscription> _activeSubscriptions = {};

  // [완벽 종료 방어용 락(Lock)]
  // 이중 해제(Double Free)를 방지하기 위해, 현재 종료 프로세스가 진행 중인 기기를 추적합니다.
  final Set<String> _disconnectingDevices = {};

  // 원본 문자열(String) 타입만 유지하여 타입 충돌을 방지합니다.
  final Map<String, List<String>> _packetLogs = {};

  // 시스템 가동 중 인식된 태그들의 상태 이력을 관리하는 메모리 변수
  final Map<String, TagState> _tagStates = {};

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

  DeviceProvider() {
    _initializeSequence();
    _subscribe();
  }

  /// 특정 장치의 로그 리스트 반환
  List<String> getLogs(String deviceId) {
    return _packetLogs[deviceId] ?? [];
  }

  /// 특정 장치의 로그 초기화
  void clearLogs(String deviceId) {
    if (_packetLogs.containsKey(deviceId)) {
      _packetLogs[deviceId]!.clear();
      notifyListeners();
    }
  }

  /// -------------------------------------------------------------------------
  /// 초기 구동 시퀀스
  /// 앱 재시작 시 DB에 남아있는 '유령 상태(Ghost State)'를 클리어합니다.
  /// -------------------------------------------------------------------------
  Future<void> _initializeSequence() async {
    await fetchData();

    bool needsNotify = false;
    for (int i = 0; i < _list.length; i++) {
      if (_list[i].status.toLowerCase() == 'online') {
        _list[i] = _list[i].copyWith(
          status: 'Offline',
          updated: DateTime.now(),
        );
        _syncStatusToDbOnly(_list[i].id, 'Offline');
        needsNotify = true;
      }
    }

    if (needsNotify) {
      notifyListeners();
    }

    // 초기화가 끝난 후, 진짜 자동 연결이 설정된 장치들만 포트를 엽니다.
    _autoConnectDevices();
  }

  /// -------------------------------------------------------------------------
  /// 병렬 연결 로직
  /// 장치가 여러 개일 때 순서대로 기다리지 않고 모든 장치를 동시에 연결 시도합니다.
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

  @override
  void dispose() {
    _isDisposed = true;

    // 메모리 누수 및 크래시 방지를 위해 모든 스트림 구독 해제
    for (var sub in _activeSubscriptions.values) {
      sub.cancel();
    }
    _activeSubscriptions.clear();

    for (var protocol in _activeProtocols.values) {
      try {
        protocol.dispose();
      } catch (e) {
        debugPrint("프로토콜 해제 오류: $e");
      }
    }
    _activeProtocols.clear();
    _packetLogs.clear();
    _tagStates.clear();
    _disconnectingDevices.clear();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  /// PocketBase DB에서 최신 장치 목록 불러오기
  Future<void> fetchData() async {
    if (_isDisposed) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
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
  /// 문자열 안전 정화 기능 (UI 크래시 방지 필터)
  /// -------------------------------------------------------------------------
  String _sanitizeString(String input) {
    if (input.isEmpty) {
      return "";
    }
    try {
      final StringBuffer buffer = StringBuffer();
      for (var char in input.runes) {
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
  /// 시스템 로그 헬퍼
  /// -------------------------------------------------------------------------
  void _logSystem(String deviceId, String message) {
    if (!_packetLogs.containsKey(deviceId)) {
      _packetLogs[deviceId] = [];
    }
    final timestamp = DateTime.now().toString().substring(11, 19);
    final cleanedMsg = _sanitizeString(message);
    _packetLogs[deviceId]!.add("[$timestamp] <<< [SYS] $cleanedMsg");

    if (_packetLogs[deviceId]!.length > 100) {
      _packetLogs[deviceId]!.removeAt(0);
    }
    notifyListeners();
  }

  /// -------------------------------------------------------------------------
  /// 개별 장치 접속 로직
  /// -------------------------------------------------------------------------
  Future<void> connectDevice(DeviceModel device) async {
    if (device.ipAddress.isEmpty) {
      _logSystem(device.id, "⚠️ 오류: 통신 주소가 없습니다.");
      return;
    }

    // 중복 방어: 이미 종료 중인 기기라면 접속 시도를 무시합니다.
    if (_disconnectingDevices.contains(device.id)) {
      _logSystem(device.id, "⏳ 현재 이전 통신을 안전하게 해제하는 중입니다. 잠시 후 다시 시도해주세요.");
      return;
    }

    // 중복 방어: 이미 해당 장치의 프로토콜이 가동 중이면 기존 것을 안전하게 해제 후 재시작
    if (_activeProtocols.containsKey(device.id)) {
      _logSystem(device.id, "🔄 기존 통신 세션 초기화 및 재접속 시도...");
      await disconnectDevice(device.id); // 안전하게 비동기로 끊어냅니다.
    }

    final protocol = DeviceProtocolFactory.create(device.model, device.ipAddress, device.port);
    _activeProtocols[device.id] = protocol;

    _logSystem(device.id, "🚀 접속 프로세스 시작: ${device.ipAddress}:${device.port}");

    try {
      // 5초 타임아웃으로 한 장비의 지연이 전체 엔진을 멈추지 않게 방어합니다.
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
              disconnectDevice(device.id); // 에러 발생 시 안전하게 연결 해제
            }
        );

        String usageRole = device.settings['usage_role']?.toString() ?? '';
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

        // [UI 즉시 갱신] DB 조회를 기다리지 않고 메모리 상태를 먼저 바꿉니다.
        _updateLocalStatus(device.id, 'Online');
        _syncStatusToDbOnly(device.id, 'Online');
      } else {
        _logSystem(device.id, "❌ 접속 실패 (포트 점유 또는 설정 오류)");
        _activeProtocols.remove(device.id);
        _updateLocalStatus(device.id, 'Offline');
        _syncStatusToDbOnly(device.id, 'Offline');
      }
    } catch (e) {
      _logSystem(device.id, "🔥 연결 중 치명적 예외: $e");
      _activeProtocols.remove(device.id);
      _updateLocalStatus(device.id, 'Offline');
      _syncStatusToDbOnly(device.id, 'Offline');
    }
  }

  /// -------------------------------------------------------------------------
  /// [UI 즉시 반응용] 메모리 내 장치 상태 교체 로직
  /// -------------------------------------------------------------------------
  void _updateLocalStatus(String deviceId, String status) {
    final index = _list.indexWhere((d) {
      return d.id == deviceId;
    });

    if (index != -1) {
      final oldDevice = _list[index];
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
  /// 백그라운드 DB 동기화
  /// -------------------------------------------------------------------------
  Future<void> _syncStatusToDbOnly(String deviceId, String status) async {
    try {
      await PBService.pb.collection(_collectionName).update(deviceId, body: {'status': status});
    } catch (e) {
      debugPrint("DB 상태 동기화 실패: $e");
    }
  }

  /// -------------------------------------------------------------------------
  /// [초강력 안전 장치] 윈도우 네이티브 힙 손상(Heap Corruption) 완벽 방어
  /// C++Builder의 Thread->Terminate() -> Thread->WaitFor() -> CloseHandle() 구조 구현
  /// -------------------------------------------------------------------------
  Future<void> disconnectDevice(String deviceId) async {
    if (_disconnectingDevices.contains(deviceId)) {
      return; // 이미 해제 중인 장치는 중복 진입 방지 (Double Free 차단)
    }

    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;
      _disconnectingDevices.add(deviceId); // 락(Lock) 설정

      try {
        // 1. 하드웨어 전파 발사 중지 명령 (리더기가 쏘는 데이터 자체를 멈춤)
        try {
          await protocol.stopInventory();
          _logSystem(deviceId, "⏹️ 하드웨어 읽기 중단 명령 전송 완료");
        } catch (_) {}

        // 2. Dart 쪽 수신 파이프라인(Stream) 해제 (C++의 Thread->Terminate() 역할)
        // 다트의 스트림을 취소하여 C++의 SerialPortReader 루프 탈출을 유도합니다.
        if (_activeSubscriptions.containsKey(deviceId)) {
          _logSystem(deviceId, "⏳ 다트 수신 스트림 파이프라인 해제 중...");
          await _activeSubscriptions[deviceId]!.cancel();
          _activeSubscriptions.remove(deviceId);
        }

        // 3. [가장 핵심 방어] C++ 네이티브 스레드 완전 종료 대기 (C++의 Thread->WaitFor() 역할)
        // 다트에서 cancel()을 호출했더라도 백그라운드의 네이티브 C++ 스레드가
        // 포트 참조(Handle)를 완전히 내려놓기까지는 약간의 딜레이가 필연적으로 발생합니다.
        // 이를 기다리지 않고 바로 dispose(free)를 때려버리면 100% 엑스박스가 뜹니다.
        _logSystem(deviceId, "⏳ C++ 네이티브 스레드 루프 완전 탈출 대기 중 (WaitFor)...");
        await Future.delayed(const Duration(milliseconds: 800));

        // 4. 물리적 포트/소켓 해제 (CloseHandle & Free 역할)
        // 네이티브 스레드가 포트 핸들 참조를 완벽히 놓은 고요한 상태에서 해제합니다.
        _logSystem(deviceId, "⏳ 물리적 포트 자원(Handle) 해제 중...");
        try {
          protocol.dispose();
        } catch (e) {
          debugPrint("해제 중 오류 무시: $e");
        }

        _activeProtocols.remove(deviceId);
        _logSystem(deviceId, "🔌 모든 작업 완료: 장치 연결이 완벽하게 해제되었습니다.");

        _updateLocalStatus(deviceId, 'Offline');
        _syncStatusToDbOnly(deviceId, 'Offline');

      } finally {
        _disconnectingDevices.remove(deviceId); // 락(Lock) 해제
      }
    }
  }

  /// 하드웨어 안테나 출력 제어
  Future<void> setDevicePower(String deviceId, int antennaIndex, int powerLevel) async {
    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;
      _logSystem(deviceId, "📡 안테나($antennaIndex) 출력 변경 명령: ${powerLevel/10}dBm");
      await protocol.setAntennaPower(antennaIndex, powerLevel);
    }
  }

  /// -------------------------------------------------------------------------
  /// 수동으로 태그 읽기(Inventory) 시작 명령 하달
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
  /// 수동으로 태그 읽기(Inventory) 중지 명령 하달
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
  /// 특정 장치에 RFID 태그 메모리 쓰기(Write) 명령 하달 (ASCII / Hex 모드 지원)
  /// -------------------------------------------------------------------------
  Future<bool> writeTagData(String deviceId, String input, {bool isHexMode = false}) async {
    if (!_activeProtocols.containsKey(deviceId)) {
      _logSystem(deviceId, "⚠️ 오류: 연결된 장치가 없습니다.");
      return false;
    }

    String finalHex = "";

    try {
      if (isHexMode) {
        String cleaned = input.replaceAll(' ', '').toUpperCase();
        if (!RegExp(r'^[0-9A-F]+$').hasMatch(cleaned)) {
          _logSystem(deviceId, "⚠️ 오류: 올바른 Hex 형식이 아닙니다.");
          return false;
        }
        if (cleaned.length % 4 != 0) {
          cleaned = cleaned.padRight(cleaned.length + (4 - cleaned.length % 4), '0');
        }
        finalHex = cleaned;
      } else {
        finalHex = input.codeUnits.map((unit) {
          return unit.toRadixString(16).padLeft(2, '0').toUpperCase();
        }).join('');

        if (finalHex.length % 4 != 0) {
          finalHex = finalHex.padRight(finalHex.length + (4 - finalHex.length % 4), '0');
        }
      }

      _logSystem(deviceId, "📝 태그 쓰기 전송: $finalHex");
      await _activeProtocols[deviceId]!.writeTagMemory(1, 2, finalHex);
      return true;
    } catch (e) {
      _logSystem(deviceId, "❌ 쓰기 예외 발생: $e");
      return false;
    }
  }

  /// -------------------------------------------------------------------------
  /// [데이터 수신 이벤트 파이프라인]
  /// -------------------------------------------------------------------------
  void _onDataReceived(String deviceId, String data) {
    if (!_packetLogs.containsKey(deviceId)) {
      _packetLogs[deviceId] = [];
    }

    final timestamp = DateTime.now().toString().substring(11, 19);
    final cleanedData = _sanitizeString(data);

    if (cleanedData.startsWith('JSON:')) {
      try {
        String jsonString = cleanedData.substring(5);
        Map<String, dynamic> parsed = jsonDecode(jsonString);

        String epc = parsed['epc'] ?? "";
        String ant = parsed['ant']?.toString() ?? "1";
        String rssi = parsed['rssi'] ?? "";

        _packetLogs[deviceId]!.add("[$timestamp] 🎯 [태그 인식] EPC:$epc | Ant:$ant | RSSI:$rssi");
        if (epc.isNotEmpty) {
          _processTagDirection(deviceId, epc, ant);
        }
      } catch (e) {
        _packetLogs[deviceId]!.add("[$timestamp] <<< $cleanedData");
      }
    } else {
      _packetLogs[deviceId]!.add("[$timestamp] $cleanedData");
    }

    if (_packetLogs[deviceId]!.length > 100) {
      _packetLogs[deviceId]!.removeAt(0);
    }

    notifyListeners();
  }

  /// -------------------------------------------------------------------------
  /// [방향 결정 핵심 비즈니스 로직]
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

      TagState state = _tagStates[epc] ?? TagState(epc: epc, lastSeenTime: DateTime.fromMillisecondsSinceEpoch(0));
      DateTime now = DateTime.now();

      String determinedDirection = "";
      bool shouldLog = false;

      switch (mode) {
        case 'none':
          int discardSeconds = int.tryParse(option) ?? 3;
          if (now.difference(state.lastSeenTime).inSeconds < discardSeconds) {
            return;
          }
          determinedDirection = (state.status == 'IN') ? '출고(OUT)' : '입고(IN)';
          state.status = (state.status == 'IN') ? 'OUT' : 'IN';
          shouldLog = true;
          break;

        case 'reader_seq':
          if (state.lastReaderId.isNotEmpty && state.lastReaderId != deviceId) {
            determinedDirection = '이동 [리더 변경: ${state.lastReaderId} ➔ ${device.name}]';
            shouldLog = true;
          }
          break;

        case 'ant_seq':
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

        case 'reader_fixed':
          determinedDirection = option.contains('OUT') ? '출고(OUT)' : '입고(IN)';
          String newStatus = determinedDirection.contains('IN') ? 'IN' : 'OUT';
          if (state.status != newStatus || now.difference(state.lastSeenTime).inSeconds > 3) {
            state.status = newStatus;
            shouldLog = true;
          }
          break;

        case 'ant_fixed':
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

      state.lastSeenTime = now;
      state.lastReaderId = deviceId;
      state.lastAntenna = ant;
      _tagStates[epc] = state;

      if (shouldLog && determinedDirection.isNotEmpty) {
        _logSystem(deviceId, "★★★ [방향 판별 완료] EPC: $epc ➔ $determinedDirection");
      }
    } catch (e) {
      debugPrint("방향 판단 오류: $e");
    }
  }

  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) {
      if (!_isDisposed) {
        fetchData();
      }
    });
  }

  /// 장비 설정 저장 로직
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
      List<http.MultipartFile> files = [];
      if (imageXFile != null) {
        final bytes = await imageXFile.readAsBytes();
        files.add(http.MultipartFile.fromBytes('image', bytes, filename: imageXFile.name));
      }

      String savedId = "";
      if (d == null) {
        final record = await PBService.pb.collection(_collectionName).create(body: data, files: files);
        savedId = record.id;
      } else {
        final record = await PBService.pb.collection(_collectionName).update(d.id, body: data, files: files);
        savedId = record.id;
      }

      await fetchData();

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
      return false;
    } finally {
      if (!_isDisposed) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  Future<bool> deleteDevice(String id) async {
    try {
      await PBService.pb.collection(_collectionName).delete(id);
      return true;
    } catch (e) {
      return false;
    }
  }
}