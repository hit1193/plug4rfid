import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // JSON 디코딩을 위해 추가
import 'dart:async';   // StreamSubscription 및 Timer(비동기 제어)를 사용하기 위해 필수

import '../models/device_model.dart';
import '../services/pb_service.dart';
import '../services/device_protocols.dart';

/// ---------------------------------------------------------------------------
/// [Data Structure] TagState (태그 상태 관리 구조체)
/// 현장에서 인식된 개별 RFID 태그의 상태와 이동 이력을 기억하는 클래스입니다.
/// ---------------------------------------------------------------------------
class TagState {
  String epc;             // 태그의 고유 식별자 (Electronic Product Code)
  DateTime lastSeenTime;  // 가장 마지막으로 태그가 인식된 시간
  DateTime lastStateChangeTime; // 상태가 마지막으로 전환된 시간 (핑퐁 방어용)
  String status;          // 현재 판별된 상태 ('IN', 'OUT', 또는 'NONE')

  // 🔥 [핵심 추가] 현재 태그가 안테나 영역에 물리적으로 존재하는가?
  bool isPresent;

  String lastReaderId;    // 마지막으로 이 태그를 읽어들인 장치(리더기)의 ID
  String lastAntenna;     // 마지막으로 이 태그를 읽어들인 안테나 번호

  // 화면 도배(동일 상태 반복 추가) 방지용 변수
  String lastLoggedDirection;
  DateTime lastLogTime;

  TagState({
    required this.epc,
    required this.lastSeenTime,
    required this.lastStateChangeTime,
    this.status = 'NONE',
    this.isPresent = false, // 처음 스캔될 때는 물리적으로 들어온 것이므로 false -> true로 토글 유도
    this.lastReaderId = '',
    this.lastAntenna = '',
    this.lastLoggedDirection = '',
    required this.lastLogTime,
  });
}

/// ---------------------------------------------------------------------------
/// [Logic] DeviceProvider (장치 상태 관리 및 실시간 통신 전담 DataModule)
/// ---------------------------------------------------------------------------
class DeviceProvider extends ChangeNotifier {
  final String _collectionName = 'devices'; // DB(PocketBase) 테이블명

  List<DeviceModel> _list = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDisposed = false;

  final Map<String, BaseDeviceProtocol> _activeProtocols = {};
  final Map<String, StreamSubscription> _activeSubscriptions = {};
  final Set<String> _disconnectingDevices = {};
  final Map<String, List<String>> _packetLogs = {};
  final Map<String, TagState> _tagStates = {};

  // 🔥 [오지랖 타이머 철거]
  // 선배님의 기획에 따라 시간이 지나면 자동으로 OUT 시키는 멍청한 타이머(_missingTimers)를
  // 완벽하게 소거했습니다. 오직 사람의 '물리적 재진입'만을 토글(Toggle)의 조건으로 삼습니다.
  Timer? _watchdogTimer;

  List<DeviceModel> get list => _list;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  Map<String, TagState> get tagStates => _tagStates;

  DeviceProvider() {
    _initializeSequence();
    _subscribe();

    // 1초마다 태그 물리적 이탈(가비지 컬렉션)을 검사하는 주기적 감시 스레드 가동
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      _checkMissingTags();
    });
  }

  List<String> getLogs(String deviceId) {
    return _packetLogs[deviceId] ?? [];
  }

  void clearLogs(String deviceId) {
    if (_packetLogs.containsKey(deviceId)) {
      _packetLogs[deviceId]!.clear();
      notifyListeners();
    }
  }

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
    _autoConnectDevices();
  }

  void _autoConnectDevices() {
    if (_isDisposed) return;

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
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _watchdogTimer?.cancel();

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

  Future<void> fetchData() async {
    if (_isDisposed) return;

    _isLoading = true;
    notifyListeners();

    try {
      final records = await PBService.pb.collection(_collectionName).getFullList(sort: '-created');
      if (_isDisposed) return;

      _list = records.map((r) => DeviceModel.fromRecord(r)).toList();
    } catch (e) {
      debugPrint("장치 로드 실패: $e");
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  String _sanitizeString(String input) {
    if (input.isEmpty) return "";
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

  void _logSystem(String deviceId, String message) {
    if (!_packetLogs.containsKey(deviceId)) {
      _packetLogs[deviceId] = [];
    }

    final timestamp = DateTime.now().toString().substring(11, 19);
    final cleanedMsg = _sanitizeString(message);

    _packetLogs[deviceId]!.add("[$timestamp] <<< $cleanedMsg");

    if (_packetLogs[deviceId]!.length > 100) {
      _packetLogs[deviceId]!.removeAt(0);
    }
    notifyListeners();
  }

  Future<void> connectDevice(DeviceModel device) async {
    if (device.ipAddress.isEmpty) {
      _logSystem(device.id, "⚠️ 오류: 통신 주소를 확인하세요.");
      return;
    }

    if (_disconnectingDevices.contains(device.id)) {
      return;
    }

    if (_activeProtocols.containsKey(device.id)) {
      await disconnectDevice(device.id);
    }

    final protocol = DeviceProtocolFactory.create(device.model, device.ipAddress, device.port);
    _activeProtocols[device.id] = protocol;
    _logSystem(device.id, "🚀 접속 프로세스 시작: ${device.ipAddress}:${device.port}");

    try {
      bool success = await protocol.connect().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _logSystem(device.id, "⏰ 타임아웃: 포트 응답 없음");
            return false;
          }
      );

      if (success) {
        _logSystem(device.id, "✅ 접속 성공! 데이터 수집 대기 중...");

        _activeSubscriptions[device.id] = protocol.tagStream.listen(
                (tagData) {
              _onDataReceived(device.id, tagData);
            },
            onError: (err) {
              _logSystem(device.id, "❌ 수신 오류: $err");
              disconnectDevice(device.id);
            }
        );

        String usageRole = device.settings['usage_role']?.toString() ?? '';
        if (usageRole == '수동스캔(단일등록)') {
          _logSystem(device.id, "🤫 발급 모드: 대기 중");
        } else {
          try {
            await protocol.startInventory();
            _logSystem(device.id, "📡 실시간 태그 수집 시작");
          } catch (e) {
            _logSystem(device.id, "⚠️ 명령 실패: $e");
          }
        }

        _updateLocalStatus(device.id, 'Online');
        _syncStatusToDbOnly(device.id, 'Online');
      } else {
        _activeProtocols.remove(device.id);
        _updateLocalStatus(device.id, 'Offline');
        _syncStatusToDbOnly(device.id, 'Offline');
      }
    } catch (e) {
      _activeProtocols.remove(device.id);
      _updateLocalStatus(device.id, 'Offline');
      _syncStatusToDbOnly(device.id, 'Offline');
    }
  }

  void _updateLocalStatus(String deviceId, String status) {
    final index = _list.indexWhere((d) => d.id == deviceId);
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

  Future<void> _syncStatusToDbOnly(String deviceId, String status) async {
    try {
      await PBService.pb.collection(_collectionName).update(deviceId, body: {'status': status});
    } catch (e) {
      debugPrint("DB 상태 동기화 실패: $e");
    }
  }

  Future<void> disconnectDevice(String deviceId) async {
    if (_disconnectingDevices.contains(deviceId)) return;

    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;
      _disconnectingDevices.add(deviceId);

      try {
        try {
          await protocol.stopInventory();
        } catch (_) {}

        if (_activeSubscriptions.containsKey(deviceId)) {
          await _activeSubscriptions[deviceId]!.cancel();
          _activeSubscriptions.remove(deviceId);
        }

        await Future.delayed(const Duration(milliseconds: 800));

        try {
          protocol.dispose();
        } catch (e) {
          debugPrint("해제 무시: $e");
        }

        _activeProtocols.remove(deviceId);
        _logSystem(deviceId, "🔌 장치 연결 해제 완료.");

        _updateLocalStatus(deviceId, 'Offline');
        _syncStatusToDbOnly(deviceId, 'Offline');
      } finally {
        _disconnectingDevices.remove(deviceId);
      }
    }
  }

  Future<void> setDevicePower(String deviceId, int antennaIndex, int powerLevel) async {
    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;
      _logSystem(deviceId, "📡 안테나($antennaIndex) 출력 설정: ${powerLevel/10}dBm");
      await protocol.setAntennaPower(antennaIndex, powerLevel);
    }
  }

  Future<void> triggerDeviceRead(String deviceId) async {
    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;
      _logSystem(deviceId, "▶️ 수동 읽기 시작");
      try {
        await protocol.startInventory();
      } catch (e) {}
    }
  }

  Future<void> stopDeviceRead(String deviceId) async {
    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;
      _logSystem(deviceId, "⏹️ 태그 읽기 중단");
      try {
        await protocol.stopInventory();
      } catch (e) {}
    }
  }

  Future<bool> writeTagData(String deviceId, String input, {bool isHexMode = false}) async {
    if (!_activeProtocols.containsKey(deviceId)) {
      _logSystem(deviceId, "⚠️ 오류: 연결 없음");
      return false;
    }

    String finalHex = "";
    try {
      if (isHexMode) {
        String cleaned = input.replaceAll(' ', '').toUpperCase();
        if (!RegExp(r'^[0-9A-F]+$').hasMatch(cleaned)) return false;
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

      await _activeProtocols[deviceId]!.writeTagMemory(1, 2, finalHex);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// -------------------------------------------------------------------------
  /// [데이터 수신 파이프라인]
  /// -------------------------------------------------------------------------
  void _onDataReceived(String deviceId, String data) {
    final cleanedData = _sanitizeString(data);

    if (cleanedData.startsWith('JSON:')) {
      try {
        String jsonString = cleanedData.substring(5);
        Map<String, dynamic> parsed = jsonDecode(jsonString);

        String rawEpc = parsed['epc']?.toString() ?? "";
        String epc = rawEpc.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
        String ant = parsed['ant']?.toString() ?? "1";

        if (epc.isNotEmpty) {
          _processTagDirection(deviceId, epc, ant);
        }
      } catch (e) {}
    } else {
      _logSystem(deviceId, cleanedData);
    }
  }

  /// -------------------------------------------------------------------------
  /// 🔥 [백그라운드 물리 버퍼 청소 (Garbage Collection)]
  /// 유령 타이머(Watchdog)는 폐기하고, 물리적 이탈(isPresent) 판별만 남겼습니다.
  /// -------------------------------------------------------------------------
  void _checkMissingTags() {
    if (_isDisposed) return;

    final DateTime now = DateTime.now();
    final List<String> gcKeys = [];

    _tagStates.forEach((String epc, TagState state) {
      if (now.difference(state.lastSeenTime).inSeconds > 3600) {
        // 1시간 초과 시 다음날을 위해 메모리 완전 초기화
        gcKeys.add(epc);
      }
      else if (state.isPresent) {
        // 안테나에서 태그가 3초 동안 안 보이면 물리적 이탈(Away)로 마킹합니다.
        // 타이머를 돌려 OUT으로 바꾸거나 로그를 뿌리지 않고,
        // 오직 "지금 이 자리에 없다"고 조용히 상태만 변경합니다.
        if (now.difference(state.lastSeenTime).inSeconds >= 3) {
          state.isPresent = false;
        }
      }
    });

    for (String epc in gcKeys) {
      _tagStates.remove(epc);
    }
  }

  /// -------------------------------------------------------------------------
  /// [비즈니스 로직 코어] 현장 출입/이동 방향 결정 로직
  /// 🔥 오직 물리적 재접근 시에만 발동하는 순수 토글(True Toggle) 엔진 탑재!
  /// -------------------------------------------------------------------------
  void _processTagDirection(String deviceId, String epc, String ant) {
    try {
      final int deviceIndex = _list.indexWhere((d) => d.id == deviceId);
      if (deviceIndex == -1) return;

      final device = _list[deviceIndex];
      final String mode = device.settings['dir_mode']?.toString() ?? 'none';
      final String option = device.settings['dir_option']?.toString() ?? '3';

      DateTime now = DateTime.now();

      // 태그가 메모리에 없으면 최초 상태(isPresent: false)로 뼈대를 올립니다.
      TagState state = _tagStates[epc] ?? TagState(
          epc: epc,
          lastSeenTime: now,
          lastStateChangeTime: DateTime.fromMillisecondsSinceEpoch(0),
          lastLogTime: DateTime.fromMillisecondsSinceEpoch(0),
          isPresent: false // 초기값: 처음 스캔 시 무조건 토글되도록 false로 세팅
      );

      String determinedDirection = "";
      bool shouldLog = false;
      String newStatus = state.status;

      // =========================================================================
      // 1. [단일 안테나 토글 모드 (none)]
      // 선배님 기획안 반영: "입고로 판단하고 저장했는데, 다시 감지된다면 출고로 판단"
      // =========================================================================
      if (mode == 'none') {
        // 태그가 물리적으로 안테나에서 벗어난 상태(isPresent == false)였다가
        // 지금 방금 다시 감지되어 들어왔을 때만 토글(Toggle) 스위치를 작동시킵니다!!
        if (!state.isPresent) {
          newStatus = (state.status == 'IN') ? 'OUT' : 'IN';
        }
      }
      // =========================================================================
      // 2. [고정 모드 및 시퀀스 모드] - 기존의 견고한 로직 그대로 유지
      // =========================================================================
      else if (mode == 'reader_fixed') {
        newStatus = option.contains('OUT') ? 'OUT' : 'IN';
      } else if (mode == 'ant_fixed') {
        int antNum = int.tryParse(ant) ?? 1;
        newStatus = (antNum % 2 != 0) ? 'IN' : 'OUT';
      }

      // 🔥 Edge Trigger: 이전 상태와 새로운 목표 상태(newStatus)가 달라졌을 때만 기록 로직에 진입!
      if (state.status != newStatus) {
        // 교차 모드(U-Turn) 전파 핑퐁 방지를 위한 최소 2초 쿨다운 적용
        if (now.difference(state.lastStateChangeTime).inSeconds >= 2) {
          state.status = newStatus;
          state.lastStateChangeTime = now;

          determinedDirection = (newStatus == 'IN') ? '입고(IN)' : '출고(OUT)';
          if (mode == 'ant_fixed') {
            determinedDirection += ' [Ant $ant]';
          }
          shouldLog = true;
        }
      }

      // [시퀀스 모드 U-Turn 즉시 허용 구역]
      if (mode == 'reader_seq') {
        if (state.lastReaderId.isNotEmpty && state.lastReaderId != deviceId) {
          if (now.difference(state.lastStateChangeTime).inSeconds >= 2) {
            determinedDirection = '이동 [리더 변경: ${state.lastReaderId} ➔ ${device.name}]';
            state.lastStateChangeTime = now;
            shouldLog = true;
          }
        }
      } else if (mode == 'ant_seq') {
        if (state.lastAntenna.isNotEmpty && state.lastAntenna != ant) {
          if (now.difference(state.lastStateChangeTime).inSeconds >= 2) {
            if (state.lastAntenna == '1' && ant == '2' && state.status != 'IN') {
              determinedDirection = '입고(IN) [Ant 1➔2]';
              state.status = 'IN';
              state.lastStateChangeTime = now;
              shouldLog = true;
            } else if (state.lastAntenna == '2' && ant == '1' && state.status != 'OUT') {
              determinedDirection = '출고(OUT) [Ant 2➔1]';
              state.status = 'OUT';
              state.lastStateChangeTime = now;
              shouldLog = true;
            }
          }
        }
      }

      // 4. 상태 최신화 (태그가 안테나 위에 존재함을 강력히 마킹)
      state.isPresent = true;
      state.lastSeenTime = now;
      state.lastReaderId = deviceId;
      state.lastAntenna = ant;

      // =========================================================================
      // 5. 동일 상태 무한 도배(Debouncing) 완벽 차단
      // =========================================================================
      if (shouldLog && determinedDirection.isNotEmpty) {
        if (state.lastLoggedDirection == determinedDirection &&
            now.difference(state.lastLogTime).inSeconds < 10) {
          shouldLog = false; // 10초 이내 완전 동일 방향 로그 무시
        } else {
          state.lastLoggedDirection = determinedDirection;
          state.lastLogTime = now;
        }
      }

      // 수정된 상태 객체를 Map 메모리에 즉시 덮어씁니다. (C++ 포인터 업데이트 효과)
      _tagStates[epc] = state;

      // 화면에 단 1줄만 깔끔하게 출력
      if (shouldLog && determinedDirection.isNotEmpty) {
        _logSystem(deviceId, "★★★ [방향 판별 완료] EPC: $epc ➔ $determinedDirection");
        notifyListeners(); // 화면(UI)에 즉시 갱신 통보!
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

  Future<bool> handleSave({
    required DeviceModel? d,
    required Map<String, dynamic> data,
    XFile? imageXFile,
    bool skipAutoConnect = false,
  }) async {
    if (_isDisposed) return false;

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
        final savedDevice = _list.firstWhere((item) => item.id == savedId);
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