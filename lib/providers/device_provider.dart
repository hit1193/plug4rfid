import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../models/device_model.dart'; // 장치 데이터 구조체 참조
import '../services/pb_service.dart';
import '../services/tcp_socket_service.dart';
import '../services/device_protocols.dart';

/// [Logic] 장치 상태 관리 및 실시간 통신 전담 클래스 (Global DataModule)
/// 이 클래스는 앱의 생명주기 동안 백그라운드에서 소켓 통신을 유지하고 상태를 관리합니다.
class DeviceProvider extends ChangeNotifier {
  final String _collectionName = 'devices';
  List<DeviceModel> _list = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDisposed = false;

  // 장치별 소켓 세션 및 프로토콜 관리 (C++의 TList<TTcpClient*> 개념)
  final Map<String, TcpSocketService> _socketSessions = {};
  final Map<String, DeviceProtocol> _protocols = {};

  // [핵심] 장치별 실시간 패킷 로그 저장소 (C++의 TStringList Map 역할)
  // TMemo 컴포넌트에 실시간으로 한 줄씩 추가되는 로그를 메모리에 들고 있습니다.
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

  /// 설정상 활성화된 장치들에 대해 자동으로 소켓 연결 시도
  void _autoConnectDevices() {
    if (_isDisposed) return;
    for (var device in _list) {
      if (device.isActive && device.ipAddress.isNotEmpty) {
        connectDevice(device);
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    // 모든 소켓 세션 정리 (소멸자 역할)
    for (var session in _socketSessions.values) {
      session.dispose();
    }
    _socketSessions.clear();
    _protocols.clear();
    _packetLogs.clear();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) super.notifyListeners();
  }

  /// PocketBase에서 최신 장치 리스트 로드 (VCL의 Query->Open()과 동일)
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

  /// [통신 제어] 장치 소켓 연결 및 데이터 수신 이벤트 등록 (OnConnect)
  Future<void> connectDevice(DeviceModel device) async {
    if (device.ipAddress.isEmpty || _socketSessions.containsKey(device.id)) return;

    final service = TcpSocketService(host: device.ipAddress, port: device.port);
    final protocol = ProtocolFactory.getProtocol(device.model);
    _protocols[device.id] = protocol;

    // 연결 로그 기록 시작
    _packetLogs[device.id] = ["[시스템] 연결 시도 중: ${device.ipAddress}"];
    notifyListeners();

    bool success = await service.connect();

    if (success) {
      _socketSessions[device.id] = service;
      _packetLogs[device.id]!.add("[시스템] 연결 성공. 시작 명령(Read) 전송.");

      // 실시간 데이터 수신 이벤트 리스너 바인딩 (C++의 OnReceive 이벤트 핸들러)
      service.dataStream.listen((data) {
        _onDataReceived(device.id, data);
      });

      // 장치별 프로토콜에 정의된 시작 명령 전송
      service.sendCommand(protocol.startCommand);

      // DB 상태 업데이트
      await handleSave(d: device, data: {'status': 'Online'});
    } else {
      _packetLogs[device.id]!.add("[시스템] 연결 실패.");
      await handleSave(d: device, data: {'status': 'Error'});
    }
    notifyListeners();
  }

  /// [통신 제어] 소켓 연결 해제 및 세션 종료
  void disconnectDevice(String deviceId) {
    if (_socketSessions.containsKey(deviceId)) {
      _socketSessions[deviceId]!.dispose();
      _socketSessions.remove(deviceId);
      _packetLogs[deviceId]?.add("[시스템] 연결 세션 종료.");

      final device = _list.firstWhere((d) => d.id == deviceId);
      handleSave(d: device, data: {'status': 'Offline'});
      notifyListeners();
    }
  }

  /// [이벤트] 소켓으로부터 패킷 데이터 수신 시 처리 로직 (C++ OnReceive 구현부)
  void _onDataReceived(String deviceId, String data) {
    if (!_packetLogs.containsKey(deviceId)) _packetLogs[deviceId] = [];

    final timestamp = DateTime.now().toString().substring(11, 19);
    // 수신된 패킷을 로그 리스트에 추가 (TMemo 스타일에 한 줄 추가)
    _packetLogs[deviceId]!.add("[$timestamp] <<< ${data.trim()}");

    // 메모리 관리를 위해 최근 100개 로그만 유지
    if (_packetLogs[deviceId]!.length > 100) {
      _packetLogs[deviceId]!.removeAt(0);
    }

    // 상태 변경 알림 -> UI(상황판 터미널 등)가 실시간으로 다시 그려짐
    notifyListeners();
  }

  /// PocketBase 서버로부터 실시간 데이터 변경 감지 (SSE 구독)
  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) {
      if (!_isDisposed) fetchData();
    });
  }

  /// 장치 정보 수정 및 사진 업로드 (PocketBase API 연동)
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

  /// 장치 레코드 삭제
  Future<bool> deleteDevice(String id) async {
    try {
      await PBService.pb.collection(_collectionName).delete(id);
      return true;
    } catch (e) {
      return false;
    }
  }
}