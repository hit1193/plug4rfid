import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../models/device_model.dart'; // 장치 데이터 구조체 참조
import '../services/pb_service.dart';
// 다형성이 적용된 새로운 프로토콜 팩토리를 임포트합니다.
import '../services/device_protocols.dart';

/// ---------------------------------------------------------------------------
/// [Logic] 장치 상태 관리 및 실시간 통신 전담 클래스 (Global DataModule)
/// C++Builder의 TDataModule 역할로, UI와 독립적으로 백그라운드에서
/// 장비들과의 소켓(Socket) 세션을 유지하고 상태를 관리하는 중앙 통제소입니다.
/// ---------------------------------------------------------------------------
class DeviceProvider extends ChangeNotifier {
  final String _collectionName = 'devices';
  List<DeviceModel> _list = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDisposed = false;

  // -------------------------------------------------------------------------
  // [다형성 기반의 통신 세션 관리]
  // C++의 TList<BaseDeviceProtocol*> 개념과 같습니다.
  // 장비가 자동형(Event)이든 폴링형(Timer)이든 상관없이 부모 클래스 타입으로 통합 관리합니다.
  // -------------------------------------------------------------------------
  final Map<String, BaseDeviceProtocol> _activeProtocols = {};

  // 장치별 실시간 패킷 로그 저장소 (C++의 TStringList Map 역할)
  final Map<String, List<String>> _packetLogs = {};

  List<DeviceModel> get list => _list;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;

  DeviceProvider() {
    _initializeSequence();
    _subscribe();
  }

  /// 특정 장치의 로그 리스트 반환 (상황판이나 관리화면의 TMemo 창에서 호출)
  List<String> getLogs(String deviceId) => _packetLogs[deviceId] ?? [];

  /// 로그 초기화 (C++의 Memo1->Clear() 기능)
  void clearLogs(String deviceId) {
    _packetLogs[deviceId]?.clear();
    notifyListeners();
  }

  /// 초기 구동 시퀀스 (DB 로드 -> 활성 장치 자동 연결)
  Future<void> _initializeSequence() async {
    await fetchData();
    _autoConnectDevices();
  }

  /// -------------------------------------------------------------------------
  /// [자동 연결 로직] 앱이 켜질 때 DB 설정을 읽어 자동으로 장비들에 접속합니다.
  /// -------------------------------------------------------------------------
  void _autoConnectDevices() {
    if (_isDisposed) return;
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
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) super.notifyListeners();
  }

  /// PocketBase에서 최신 장치 리스트 로드
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

  /// -------------------------------------------------------------------------
  /// [통신 제어] 팩토리를 통한 장치 소켓 연결 및 리스너(OnRead) 바인딩
  /// -------------------------------------------------------------------------
  Future<void> connectDevice(DeviceModel device) async {
    if (device.ipAddress.isEmpty || _activeProtocols.containsKey(device.id)) return;

    // 1. Factory를 통해 모델에 맞는 정확한 프로토콜 객체를 찍어냅니다.
    final protocol = DeviceProtocolFactory.create(device.model, device.ipAddress, device.port);
    _activeProtocols[device.id] = protocol;

    _packetLogs[device.id] = ["[시스템] 접속 시도 중: ${device.ipAddress}:${device.port}"];
    notifyListeners();

    // 2. 비동기 소켓 연결 시도
    bool success = await protocol.connect();

    if (success) {
      _packetLogs[device.id]!.add("[시스템] 접속 성공. 데이터 수신(OnRead) 대기 중...");

      // 3. 실시간 데이터 수신 이벤트 리스너 바인딩
      protocol.tagStream.listen((tagData) {
        _onDataReceived(device.id, tagData);
      });

      await handleSave(d: device, data: {'status': 'Online'});
    } else {
      _packetLogs[device.id]!.add("[시스템] 접속 실패 (Timeout 또는 거부).");
      protocol.dispose();
      _activeProtocols.remove(device.id);
      await handleSave(d: device, data: {'status': 'Error'});
    }
    notifyListeners();
  }

  /// -------------------------------------------------------------------------
  /// [통신 제어] 소켓 연결 해제 및 세션 종료 (메모리 릭 방지 핵심)
  /// -------------------------------------------------------------------------
  void disconnectDevice(String deviceId) {
    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;
      protocol.dispose();
      _activeProtocols.remove(deviceId);
      _packetLogs[deviceId]?.add("[시스템] 통신 세션 안전 종료.");

      try {
        final device = _list.firstWhere((d) => d.id == deviceId);
        handleSave(d: device, data: {'status': 'Offline'});
      } catch(e) {
        // 리스트에 장비가 없는 경우 무시
      }
      notifyListeners();
    }
  }

  /// -------------------------------------------------------------------------
  /// [신규 브릿지 로직] 안테나 파워(출력) 조절 명령 하달
  /// UI(DevicePage)에서 슬라이더 조작 후 호출하면, 하드웨어 객체로 명령을 넘깁니다.
  /// -------------------------------------------------------------------------
  Future<void> setDevicePower(String deviceId, int antennaIndex, int powerLevel) async {
    if (_activeProtocols.containsKey(deviceId)) {
      final protocol = _activeProtocols[deviceId]!;

      // 로그 기록
      _packetLogs[deviceId]?.add("[시스템] 안테나($antennaIndex) 파워 변경 명령 하달: ${powerLevel/10}dBm");
      notifyListeners();

      // 실제 하드웨어 프로토콜에 구현된 비동기 파워 설정(일시정지->설정->재가동)을 실행합니다.
      await protocol.setAntennaPower(antennaIndex, powerLevel);

      _packetLogs[deviceId]?.add("[시스템] 파워 변경 완료 및 재가동");
      notifyListeners();
    }
  }

  /// -------------------------------------------------------------------------
  /// [이벤트] 팩토리 내부에서 태그를 성공적으로 읽어냈을 때 발생하는 콜백
  /// -------------------------------------------------------------------------
  void _onDataReceived(String deviceId, String data) {
    if (!_packetLogs.containsKey(deviceId)) _packetLogs[deviceId] = [];

    final timestamp = DateTime.now().toString().substring(11, 19);
    _packetLogs[deviceId]!.add("[$timestamp] <<< $data");

    if (_packetLogs[deviceId]!.length > 100) {
      _packetLogs[deviceId]!.removeAt(0);
    }
    notifyListeners();
  }

  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) {
      if (!_isDisposed) fetchData();
    });
  }

  Future<bool> handleSave({
    required DeviceModel? d,
    required Map<String, dynamic> data,
    XFile? imageXFile,
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

      if (d == null) {
        await PBService.pb.collection(_collectionName).create(body: data, files: files);
      } else {
        await PBService.pb.collection(_collectionName).update(d.id, body: data, files: files);
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