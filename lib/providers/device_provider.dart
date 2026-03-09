import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // JSON 디코딩을 위해 추가

import '../models/device_model.dart';
import '../services/pb_service.dart';
import '../services/device_protocols.dart';

/// ---------------------------------------------------------------------------
/// [Data Structure] 개별 태그의 상태와 이력을 기억하는 클래스
/// 태그의 마지막 인식 시간, 위치(리더/안테나), 현재 상태(IN/OUT)를 메모리에 보관하여
/// 중복 인식을 방지하고 동적인 출입 방향을 판별하는데 사용됩니다.
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
/// UI와 완전히 분리되어 백그라운드에서 소켓 세션을 유지하고,
/// 수신된 데이터를 파싱하여 방향을 판별한 후 상태를 보관하는 핵심 통제소입니다.
/// ---------------------------------------------------------------------------
class DeviceProvider extends ChangeNotifier {
  final String _collectionName = 'devices';
  List<DeviceModel> _list = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDisposed = false;

  final Map<String, BaseDeviceProtocol> _activeProtocols = {};

  // [오류 완벽 해결] 원본 문자열(String) 타입만 유지하여 타입 충돌(Map 에러)을 원천 차단합니다.
  final Map<String, List<String>> _packetLogs = {};

  // [핵심 보관소] 시스템 가동 중 인식된 태그들의 상태 이력을 관리하는 메모리 변수
  final Map<String, TagState> _tagStates = {};

  List<DeviceModel> get list => _list;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;

  // 외부 UI(예: 현황판)에서 태그 보관소에 접근할 수 있도록 Getter 제공
  Map<String, TagState> get tagStates => _tagStates;

  DeviceProvider() {
    _initializeSequence();
    _subscribe();
  }

  /// 특정 장치의 로그 리스트 반환 (터미널 UI용)
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

  /// 초기 구동 시퀀스 (DB 로드 -> 활성 장치 자동 연결)
  Future<void> _initializeSequence() async {
    await fetchData();
    _autoConnectDevices();
  }

  /// 장치 자동 연결 로직
  void _autoConnectDevices() {
    if (_isDisposed) {
      return;
    }

    for (var device in _list) {
      if (device.isActive && device.isAutoConnect && device.ipAddress.isNotEmpty) {
        connectDevice(device);
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (var protocol in _activeProtocols.values) {
      protocol.dispose();
    }
    _activeProtocols.clear();
    _packetLogs.clear();
    _tagStates.clear();
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

  /// -------------------------------------------------------------------------
  /// [시스템 로그 헬퍼]
  /// 장치의 접속, 해제, 오류 등의 시스템 알림을 터미널 창에 띄우기 위한 함수입니다.
  /// -------------------------------------------------------------------------
  void _logSystem(String deviceId, String message) {
    if (!_packetLogs.containsKey(deviceId)) {
      _packetLogs[deviceId] = [];
    }
    final timestamp = DateTime.now().toString().substring(11, 19);
    // 화면에서 'SYS' 타입으로 파싱할 수 있도록 식별자를 붙여 저장합니다.
    _packetLogs[deviceId]!.add("[$timestamp] <<< [SYS] $message");

    // 메모리 과부하 방지를 위해 로그는 100줄까지만 유지
    if (_packetLogs[deviceId]!.length > 100) {
      _packetLogs[deviceId]!.removeAt(0);
    }
    notifyListeners();
  }

  /// 장치 접속 및 통신 시작
  Future<void> connectDevice(DeviceModel device) async {
    if (device.ipAddress.isEmpty || _activeProtocols.containsKey(device.id)) {
      return;
    }

    final protocol = DeviceProtocolFactory.create(device.model, device.ipAddress, device.port);
    _activeProtocols[device.id] = protocol;

    _logSystem(device.id, "접속 시도 중: ${device.ipAddress}:${device.port}");

    bool success = await protocol.connect();

    if (success) {
      _logSystem(device.id, "접속 성공. 자동 Inventory 시작 대기 중...");

      protocol.tagStream.listen((tagData) {
        _onDataReceived(device.id, tagData);
      });

      try {
        await protocol.startInventory();
        _logSystem(device.id, "자동 Inventory 명령 전송 완료. 태그 수신 시작!");
      } catch (e) {
        _logSystem(device.id, "Inventory 자동 시작 실패: $e");
      }

      await handleSave(d: device, data: {'status': 'Online'});
    } else {
      _logSystem(device.id, "접속 실패 (Timeout 또는 IP/Port 오류).");
      protocol.dispose();
      _activeProtocols.remove(device.id);
      await handleSave(d: device, data: {'status': 'Offline'});
    }
  }

  /// 장치 통신 수동 종료
  void disconnectDevice(String deviceId) {
    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;
      protocol.dispose();
      _activeProtocols.remove(deviceId);

      _logSystem(deviceId, "통신 세션 수동 종료 완료.");

      try {
        final device = _list.firstWhere((d) => d.id == deviceId);
        // 재연결 루프 방지 플래그(skipAutoConnect) 사용
        handleSave(d: device, data: {'status': 'Offline'}, skipAutoConnect: true);
      } catch(e) {
        debugPrint(e.toString());
      }
    }
  }

  /// 하드웨어 안테나 출력 제어
  Future<void> setDevicePower(String deviceId, int antennaIndex, int powerLevel) async {
    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;

      _logSystem(deviceId, "안테나($antennaIndex) 파워 변경 명령 하달: ${powerLevel/10}dBm");

      await protocol.setAntennaPower(antennaIndex, powerLevel);

      _logSystem(deviceId, "파워 변경 완료 및 재가동");
    }
  }

  /// -------------------------------------------------------------------------
  /// [데이터 수신 이벤트 파이프라인]
  /// 프로토콜 단(device_protocols.dart)에서 넘겨준 데이터를 받아 터미널에 표출하고,
  /// JSON 형태일 경우 디코딩하여 개발자님의 방향 판별 로직으로 태그 정보를 넘깁니다.
  /// -------------------------------------------------------------------------
  void _onDataReceived(String deviceId, String data) {
    if (!_packetLogs.containsKey(deviceId)) {
      _packetLogs[deviceId] = [];
    }

    final timestamp = DateTime.now().toString().substring(11, 19);

    // 1. 프로토콜에서 가변 데이터를 정밀하게 가공하여 보낸 JSON 마커 데이터인 경우
    if (data.startsWith('JSON:')) {
      try {
        // "JSON:" 마커를 잘라내고 순수 JSON 문자열로 디코딩
        String jsonString = data.substring(5);
        Map<String, dynamic> parsed = jsonDecode(jsonString);

        String epc = parsed['epc'] ?? "";
        String ant = parsed['ant']?.toString() ?? "1";
        String rssi = parsed['rssi'] ?? "";
        String tid = parsed['tid'] ?? "";

        // 깔끔하게 포맷팅하여 관리자 터미널에 출력
        _packetLogs[deviceId]!.add("[$timestamp] 🎯 [태그 인식] EPC:$epc | Ant:$ant | RSSI:$rssi");

        // 개발자님이 작성하신 고도화된 방향 판별(비즈니스 로직) 및 상태 보관으로 넘김
        if (epc.isNotEmpty) {
          _processTagDirection(deviceId, epc, ant);
        }
      } catch (e) {
        // 혹시 파싱 오류가 나도 시스템이 죽지 않고 원문을 출력하도록 방어
        _packetLogs[deviceId]!.add("[$timestamp] <<< $data");
      }
    }
    // 2. 그 외 Raw 데이터 및 일반 로그 문자열 (IDRO Raw Hex 등)
    else {
      // 이미 프로토콜(device_protocols.dart) 단에서 "<== [수신 RX]" 등
      // 직관적인 형태로 보내주고 있으므로 그대로 화면에 표출합니다.
      _packetLogs[deviceId]!.add("[$timestamp] $data");
    }

    // 메모리 누수 방지 (최근 100개 로그만 유지)
    if (_packetLogs[deviceId]!.length > 100) {
      _packetLogs[deviceId]!.removeAt(0);
    }

    notifyListeners();
  }

  /// -------------------------------------------------------------------------
  /// [방향 결정 핵심 비즈니스 로직] (개발자님 작성 원본 유지)
  /// 물류센터, 공정 등 각 현장 상황에 맞춰 등록된 장비의 Setting값을 읽어와
  /// 안테나 시퀀스, 리더 시퀀스 등으로 입/출고 방향을 매우 스마트하게 결정합니다.
  /// -------------------------------------------------------------------------
  void _processTagDirection(String deviceId, String epc, String ant) {
    try {
      final deviceIndex = _list.indexWhere((d) => d.id == deviceId);
      if (deviceIndex == -1) {
        return;
      }

      final device = _list[deviceIndex];
      // 장치 설정값에 저장된 모드를 바탕으로 판별. 기본값 방어 적용.
      final String mode = device.settings['dir_mode']?.toString() ?? 'none';
      final String option = device.settings['dir_option']?.toString() ?? '3';

      // 메모리에서 태그 상태를 가져오고, 처음 인식된 태그면 초기화하여 가져옵니다.
      TagState state = _tagStates[epc] ?? TagState(epc: epc, lastSeenTime: DateTime.fromMillisecondsSinceEpoch(0));
      DateTime now = DateTime.now();

      String determinedDirection = "";
      bool shouldLog = false;

      // 현장의 레이아웃(게이트, 지게차, 컨베이어)에 맞춘 다중 판별 로직
      switch (mode) {
        case 'none':
        // 단순 교차 모드: 일정 시간(option)이 지나고 다시 읽히면 상태 반전(Toggle)
          int discardSeconds = int.tryParse(option) ?? 3;
          if (now.difference(state.lastSeenTime).inSeconds < discardSeconds) {
            return; // 연속 스캔 무시 (디바운싱 효과)
          }

          determinedDirection = (state.status == 'IN') ? '출고(OUT)' : '입고(IN)';
          state.status = (state.status == 'IN') ? 'OUT' : 'IN';
          shouldLog = true;
          break;

        case 'reader_seq':
        // 리더기 시퀀스: A리더기 -> B리더기로의 이동을 추적하여 방향 판별
          if (state.lastReaderId.isNotEmpty && state.lastReaderId != deviceId) {
            determinedDirection = '이동 [리더 변경: ${state.lastReaderId} ➔ ${device.name}]';
            shouldLog = true;
          }
          break;

        case 'ant_seq':
        // 안테나 시퀀스: 게이트를 통과할 때 안테나1 -> 안테나2 로의 연속성을 보고 판별
          if (state.lastAntenna.isNotEmpty && state.lastAntenna != ant) {
            if (state.lastAntenna == '1' && ant == '2') {
              determinedDirection = '입고(IN) [Ant 1➔2]';
              state.status = 'IN';
            } else if (state.lastAntenna == '2' && ant == '1') {
              determinedDirection = '출고(OUT) [Ant 2➔1]';
              state.status = 'OUT';
            } else {
              determinedDirection = '이동 [Ant ${state.lastAntenna}➔$ant]';
            }
            shouldLog = true;
          }
          break;

        case 'reader_fixed':
        // 고정 리더기: 이 리더기에 읽히는 순간 조건 없이 무조건 IN 또는 OUT 처리
          determinedDirection = option.contains('OUT') ? '출고(OUT)' : '입고(IN)';
          String newStatus = determinedDirection.contains('IN') ? 'IN' : 'OUT';

          if (state.status != newStatus || now.difference(state.lastSeenTime).inSeconds > 3) {
            state.status = newStatus;
            shouldLog = true;
          }
          break;

        case 'ant_fixed':
        // 고정 안테나: 홀수 번호는 IN, 짝수 번호는 OUT 처리 (가장 대중적인 키오스크형 모델)
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

      // 메모리에 현재 상태값 덮어쓰기 (업데이트)
      state.lastSeenTime = now;
      state.lastReaderId = deviceId;
      state.lastAntenna = ant;
      _tagStates[epc] = state;

      // 방향이 확정되고 로그 기록이 필요한 경우 시스템 터미널에 특별히 알림
      if (shouldLog && determinedDirection.isNotEmpty) {
        _logSystem(deviceId, "★★★ [방향 판별 완료] EPC: $epc ➔ $determinedDirection");
      }
    } catch (e) {
      debugPrint("방향 판단 로직 오류: $e");
    }
  }

  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) {
      if (!_isDisposed) {
        fetchData();
      }
    });
  }

  /// 장비 설정 저장 로직 (자동 연결 처리 포함)
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
        final savedDevice = _list.firstWhere((item) => item.id == savedId);
        // 저장이 완료된 후 활성화 & 자동연결 상태라면 통신 세션을 즉시 백그라운드로 올립니다.
        if (savedDevice.isActive && savedDevice.isAutoConnect && !skipAutoConnect) {
          Future.delayed(const Duration(milliseconds: 300), () {
            connectDevice(savedDevice);
          });
        }
      } catch (e) {
        debugPrint("자동 연결 트리거 에러: $e");
      }

      return true;
    } catch (e) {
      debugPrint("장치 데이터 저장 에러: $e");
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