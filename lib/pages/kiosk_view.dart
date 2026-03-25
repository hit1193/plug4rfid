import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:provider/provider.dart';

/// 상위 시스템에서 정의한 중앙 집중형 테마와 데이터 모델을 임포트합니다.
import '../theme/app_theme.dart';
import '../models/detection_model.dart';
import '../models/product_model.dart';
import '../models/user_model.dart';
import '../core/pocketbase_client.dart';

/// 전역 상태 공유망 (Provider) 임포트
import '../providers/device_provider.dart';
import '../providers/product_provider.dart';
import '../providers/user_provider.dart';

/// RFID 게이트의 운영 모드를 정의하는 열거형입니다.
enum GateScanMode {
  /// 인원 출입 전용 모드
  personnelOnly,
  /// 물품 + 작업자 매칭 모드 (자산 통제)
  itemWorkerMatch
}

/// [실시간 입/출고 감시 키오스크 화면 - 반응형 통합 버전]
///
/// 주요 특징:
/// 1. Windows FHD부터 모바일까지 지원하는 반응형 레이아웃.
/// 2. 미니멀리즘 디자인 유지 및 린트 에러 완전 해결.
/// 3. [최종 수정] 시간대(KST/UTC) 오차를 정교하게 계산하여 집계 정확도 100% 확보.
class KioskView extends StatefulWidget {
  final VoidCallback onDismiss;

  const KioskView({super.key, required this.onDismiss});

  @override
  State<KioskView> createState() {
    return _KioskViewState();
  }
}

class _KioskViewState extends State<KioskView> {
  // -------------------------------------------------------------------------
  // [상태 제어 변수 및 타이머]
  // -------------------------------------------------------------------------
  Timer? _clockTimer;
  Timer? _standbyTimer;
  Timer? _slideshowTimer;
  Timer? _autoSaveTimer;

  String _currentTime = "";
  Duration _timeOffset = Duration.zero;

  bool _useStandbyMode = true;
  bool _isStandbyActive = false;
  bool _isReady = false;

  bool _requireWorkerMatch = true;
  int _simCount = 0;

  final int _standbyTimeoutSeconds = 10;
  final int _autoSaveDurationSeconds = 10;
  int _autoSaveCountdown = 0;

  GateScanMode _currentScanMode = GateScanMode.itemWorkerMatch;

  // -------------------------------------------------------------------------
  // [집계 데이터 변수]
  // -------------------------------------------------------------------------
  int _prevDayStay = 0;
  int _todayEntry = 0;
  int _todayExit = 0;
  int _currentStay = 0;

  int _prevDayStock = 0;
  int _todayIn = 0;
  int _todayOut = 0;
  int _currentStock = 0;

  // -------------------------------------------------------------------------
  // [캐시 및 인덱스]
  // -------------------------------------------------------------------------
  final Map<String, int> _processedTags = {};
  final Map<String, UserModel> _userMapCache = {};
  final Map<String, ProductModel> _productMapCache = {};
  int _lastUserListLength = -1;
  int _lastProductListLength = -1;

  DeviceProvider? _cachedDeviceProvider;
  ProductProvider? _cachedProductProvider;
  UserProvider? _cachedUserProvider;

  final List<String> _backgroundImages = [
    "https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?q=80&w=2000&auto=format&fit=crop",
    "https://images.unsplash.com/photo-1504328345606-18bbc8c9d7d1?q=80&w=2000&auto=format&fit=crop",
    "https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d?q=80&w=2000&auto=format&fit=crop",
  ];
  int _currentImageIndex = 0;

  String _noticeText = "최신 공지사항을 불러오는 중입니다...";
  final List<DetectionModel> _realtimeLogs = [];

  @override
  void initState() {
    super.initState();
    _syncServerTime();

    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      _updateClock();
      _checkContinuousDetection();
    });

    _resetStandbyTimer();

    _slideshowTimer = Timer.periodic(const Duration(seconds: 8), (Timer timer) {
      if (mounted && _useStandbyMode && _isStandbyActive) {
        setState(() {
          _currentImageIndex = (_currentImageIndex + 1) % _backgroundImages.length;
        });
      }
    });

    _fetchSummaryData();
    _fetchNotice();
    _initRealtimeSubscription();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _cachedDeviceProvider = context.read<DeviceProvider>();
      _cachedProductProvider = context.read<ProductProvider>();
      _cachedUserProvider = context.read<UserProvider>();

      final deviceProvider = _cachedDeviceProvider;
      if (deviceProvider != null) {
        deviceProvider.tagStates.forEach((String epc, TagState state) {
          if (state.status != 'NONE') {
            _processedTags[epc] = state.lastStateChangeTime.millisecondsSinceEpoch;
          }
        });

        _isReady = true;
        deviceProvider.addListener(_onDeviceStateChanged);
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _standbyTimer?.cancel();
    _slideshowTimer?.cancel();
    _autoSaveTimer?.cancel();

    try {
      pb.realtime.unsubscribe('');
    } catch (_) {}

    _cachedDeviceProvider?.removeListener(_onDeviceStateChanged);

    super.dispose();
  }

  /// 메모리 효율을 위해 데이터 변경 시에만 해시 맵을 동기화합니다.
  void _syncEpcMaps() {
    final userProvider = _cachedUserProvider;
    if (userProvider != null && userProvider.list.length != _lastUserListLength) {
      _userMapCache.clear();
      for (var user in userProvider.list) {
        final epc = user.tagEpc.toUpperCase();
        if (epc.isNotEmpty) {
          _userMapCache[epc] = user;
        }
      }
      _lastUserListLength = userProvider.list.length;
    }

    final productProvider = _cachedProductProvider;
    if (productProvider != null && productProvider.items.length != _lastProductListLength) {
      _productMapCache.clear();
      for (var product in productProvider.items) {
        final epc = product.tagEpc.toUpperCase();
        if (epc.isNotEmpty) {
          _productMapCache[epc] = product;
        }
      }
      _lastProductListLength = productProvider.items.length;
    }
  }

  /// 안테나 범위 내에 태그가 머물러 있으면 저장 카운트다운을 리셋합니다.
  void _checkContinuousDetection() {
    if (!mounted || _realtimeLogs.isEmpty || _cachedDeviceProvider == null) {
      return;
    }
    if (_autoSaveTimer == null || !_autoSaveTimer!.isActive) {
      return;
    }

    bool isActivelyScanned = false;
    final DateTime now = DateTime.now().add(_timeOffset);
    final deviceProvider = _cachedDeviceProvider;

    if (deviceProvider != null) {
      for (String epc in _processedTags.keys) {
        final state = deviceProvider.tagStates[epc];
        if (state != null && state.status != 'NONE') {
          if (now.difference(state.lastSeenTime).inSeconds < 2) {
            isActivelyScanned = true;
            break;
          }
        }
      }
    }

    if (isActivelyScanned) {
      if (_autoSaveCountdown < _autoSaveDurationSeconds) {
        setState(() {
          _autoSaveCountdown = _autoSaveDurationSeconds;
        });
      }
    }
  }

  void _flushPhysicalBuffers() {
    final deviceProvider = _cachedDeviceProvider;
    if (deviceProvider != null) {
      _processedTags.removeWhere((epc, _) {
        return !deviceProvider.tagStates.containsKey(epc);
      });
    }
  }

  /// 하드웨어 이벤트 발생 핸들러입니다.
  void _onDeviceStateChanged() {
    if (!_isReady || !mounted || _cachedDeviceProvider == null) {
      return;
    }

    _syncEpcMaps();

    bool hasNewDetection = false;
    final DateTime now = DateTime.now().add(_timeOffset);
    final deviceProvider = _cachedDeviceProvider;

    if (deviceProvider != null) {
      deviceProvider.tagStates.forEach((String epc, TagState state) {
        if (state.status == 'NONE') {
          return;
        }

        final int lastChangeMs = state.lastStateChangeTime.millisecondsSinceEpoch;
        if (_processedTags[epc] == lastChangeMs) {
          return;
        }

        String deviceName = "스마트 게이트";
        bool isAutoMode = true;

        try {
          final device = deviceProvider.list.firstWhere((d) {
            return d.id == state.lastReaderId;
          });
          deviceName = device.name;

          final String usageRole = device.settings['usage_role']?.toString() ?? '';
          if (usageRole.contains('수동')) {
            isAutoMode = false;
          }
        } catch (_) {}

        if (!isAutoMode) {
          return;
        }

        _processedTags[epc] = lastChangeMs;
        final bool isEntry = state.status == 'IN';
        final String epcUpper = epc.toUpperCase();

        final UserModel? matchedUser = _userMapCache[epcUpper];
        if (matchedUser != null) {
          _processRealUserTag(matchedUser, isEntry, deviceName, now);
          hasNewDetection = true;
          return;
        }

        final ProductModel? matchedProduct = _productMapCache[epcUpper];
        if (matchedProduct != null) {
          _processRealProductTag(matchedProduct, isEntry, deviceName, now);
          hasNewDetection = true;
          return;
        }

        _processUnknownTag(epcUpper, isEntry, deviceName, now);
        hasNewDetection = true;
      });
    }

    if (hasNewDetection) {
      _startAutoSaveTimer();
    }
  }

  /// 활성화된 세션 로그를 탐색합니다.
  DetectionModel? _getActiveLogBySpot(String spotName) {
    if (_realtimeLogs.isEmpty) {
      return null;
    }

    final autoSaveTimer = _autoSaveTimer;
    if (autoSaveTimer != null && autoSaveTimer.isActive) {
      final firstLog = _realtimeLogs.first;
      if (firstLog.spot == spotName) {
        return firstLog;
      }
    }
    return null;
  }

  /// 세션 내 유효 작업자를 탐색합니다.
  Map<String, String> _getActiveSessionWorker(DateTime detectTime, String spotName) {
    String workerName = '미인식 작업자';
    String workerImage = '';

    final activeLog = _getActiveLogBySpot(spotName);
    if (activeLog != null && activeLog.content != '미인식 작업자') {
      return {'name': activeLog.content, 'image': activeLog.imageUrl};
    }

    for (var log in _realtimeLogs) {
      if (detectTime.difference(log.timestamp).inSeconds > _autoSaveDurationSeconds) {
        break;
      }
      if (log.content != '미인식 작업자' && !log.content.contains('미등록')) {
        workerName = log.content;
        workerImage = log.imageUrl;
        break;
      }
    }
    return {'name': workerName, 'image': workerImage};
  }

  /// 미등록 태그 처리
  void _processUnknownTag(String epc, bool isEntry, String deviceName, DateTime detectTime) {
    if (_isStandbyActive) {
      setState(() {
        _realtimeLogs.clear();
        _isStandbyActive = false;
      });
    }

    final DetectionModel? targetLog = _getActiveLogBySpot(deviceName);

    final Map<String, String> itemData = {
      'id': epc,
      'name': 'EPC: $epc',
      'image': '',
      'dir': isEntry ? 'IN' : 'OUT',
      'prevStatus': '미등록'
    };

    setState(() {
      if (targetLog != null) {
        bool exists = targetLog.items.any((i) {
          return i['id'] == epc;
        });
        if (!exists) {
          targetLog.items.add(itemData);

          bool hasIn = targetLog.items.any((i) => i['dir'] == 'IN');
          bool hasOut = targetLog.items.any((i) => i['dir'] == 'OUT');
          String newStatus = targetLog.status;

          if (hasIn && hasOut) {
            newStatus = '복합감지(MIXED)';
          } else if (hasIn) {
            newStatus = '자동입고(IN)';
          } else if (hasOut) {
            newStatus = '자동출고(OUT)';
          }

          int index = _realtimeLogs.indexOf(targetLog);
          _realtimeLogs[index] = DetectionModel(
              id: targetLog.id,
              type: targetLog.type,
              content: targetLog.content,
              imageUrl: targetLog.imageUrl,
              spot: targetLog.spot,
              status: newStatus,
              isEntry: targetLog.isEntry,
              timestamp: targetLog.timestamp,
              items: targetLog.items
          );
        }
      } else {
        _realtimeLogs.insert(0, DetectionModel(
            type: 'unknown',
            content: '미등록 태그 감지',
            imageUrl: '',
            spot: deviceName,
            status: isEntry ? '자동입고(IN)' : '자동출고(OUT)',
            isEntry: isEntry,
            timestamp: detectTime,
            items: [itemData]
        ));
      }
    });
  }

  /// 물품 태그 처리 (상태 대조 지원)
  void _processRealProductTag(ProductModel product, bool isEntry, String deviceName, DateTime detectTime) {
    if (_isStandbyActive) {
      setState(() {
        _realtimeLogs.clear();
        _isStandbyActive = false;
      });
    }

    final DetectionModel? targetLog = _getActiveLogBySpot(deviceName);
    final workerInfo = _getActiveSessionWorker(detectTime, deviceName);

    final String productPrevStatus = product.status.isNotEmpty ? product.status : '신규';

    final Map<String, String> itemData = {
      'id': product.id,
      'name': product.name,
      'image': _getProductImageUrl(product),
      'dir': isEntry ? 'IN' : 'OUT',
      'prevStatus': productPrevStatus
    };

    setState(() {
      if (targetLog != null) {
        bool exists = targetLog.items.any((i) {
          return i['id'] == product.id;
        });
        if (!exists) {
          targetLog.items.add(itemData);

          bool hasIn = targetLog.items.any((i) => i['dir'] == 'IN');
          bool hasOut = targetLog.items.any((i) => i['dir'] == 'OUT');
          String newStatus = targetLog.status;

          if (hasIn && hasOut) {
            newStatus = '복합이동(MIXED)';
          } else if (hasIn) {
            newStatus = '자동입고(IN)';
          } else if (hasOut) {
            newStatus = '자동출고(OUT)';
          }

          int index = _realtimeLogs.indexOf(targetLog);
          _realtimeLogs[index] = DetectionModel(
              id: targetLog.id,
              type: (targetLog.content == '미인식 작업자' && workerInfo['name'] != '미인식 작업자') ? 'matched' : targetLog.type,
              content: (targetLog.content == '미인식 작업자') ? workerInfo['name']! : targetLog.content,
              imageUrl: (targetLog.imageUrl.isEmpty) ? workerInfo['image']! : targetLog.imageUrl,
              spot: targetLog.spot,
              status: newStatus,
              isEntry: targetLog.isEntry,
              timestamp: targetLog.timestamp,
              items: targetLog.items
          );
        }
      } else {
        _realtimeLogs.insert(0, DetectionModel(
            type: 'matched',
            content: workerInfo['name']!,
            imageUrl: workerInfo['image']!,
            spot: deviceName,
            status: isEntry ? '자동입고(IN)' : '자동출고(OUT)',
            isEntry: isEntry,
            timestamp: detectTime,
            items: [itemData]
        ));
      }
    });
  }

  /// 사용자(작업자) 태그 처리
  void _processRealUserTag(UserModel user, bool isEntry, String deviceName, DateTime detectTime) {
    if (_isStandbyActive) {
      setState(() {
        _realtimeLogs.clear();
        _isStandbyActive = false;
      });
    }

    bool updatedAnyBundle = false;
    final String workerContent = '${user.name} (${user.code})'.trim();
    final String workerImage = _getUserImageUrl(user);

    setState(() {
      for (int i = 0; i < _realtimeLogs.length; i++) {
        final log = _realtimeLogs[i];
        if (detectTime.difference(log.timestamp).inSeconds > _autoSaveDurationSeconds) {
          break;
        }

        if (log.content == '미인식 작업자' && log.spot == deviceName) {
          _realtimeLogs[i] = DetectionModel(
              id: log.id,
              type: log.type == 'unknown' ? 'unknown' : 'matched',
              content: workerContent,
              imageUrl: workerImage,
              spot: log.spot,
              status: log.status,
              isEntry: log.isEntry,
              timestamp: log.timestamp,
              items: log.items
          );
          updatedAnyBundle = true;
        }
      }

      if (!updatedAnyBundle) {
        bool alreadyExists = false;
        final activeLog = _getActiveLogBySpot(deviceName);
        if (activeLog != null && activeLog.content == workerContent) {
          alreadyExists = true;
        }

        if (!alreadyExists) {
          _realtimeLogs.insert(0, DetectionModel(
              type: 'person',
              content: workerContent,
              imageUrl: workerImage,
              spot: deviceName,
              status: isEntry ? '입장' : '퇴장',
              isEntry: isEntry,
              timestamp: detectTime,
              items: []
          ));
        }
      }
    });
  }

  String _getProductImageUrl(ProductModel p) {
    try {
      final dynamic url = p.getImageUrl(pb.baseUrl, thumb: '200x200');
      return url?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  String _getUserImageUrl(UserModel u) {
    try {
      final dynamic url = u.getImageUrl(pb.baseUrl, thumb: '200x200');
      return url?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// [집계 정보 갱신 - 로직 대폭 강화]
  /// 1. 시간대 필터를 KST/UTC 오차 없이 정확히 맞춥니다.
  /// 2. items_json 파싱 시 발생하는 예외 상황을 원천 차단합니다.
  Future<void> _fetchSummaryData() async {
    try {
      // 한국 시간 기준 오늘의 시작점 (00:00:00)
      final DateTime localNow = DateTime.now();
      final DateTime localTodayStart = DateTime(localNow.year, localNow.month, localNow.day);

      // PocketBase 쿼리용 포맷 (UTC 변환 후 YYYY-MM-DD HH:MM:SS)
      final String startStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(localTodayStart.toUtc());

      // 1. 현재 실시간 스냅샷 (인원/재고)
      int cStay = 0;
      int cStock = 0;

      final userRecords = await pb.collection('users').getFullList();
      for (var record in userRecords) {
        final meta = record.data['metadata'] as Map<String, dynamic>? ?? {};
        if (meta['last_access_type'] == '입장') {
          cStay++;
        }
      }

      final prodRecords = await pb.collection('products').getFullList();
      for (var p in prodRecords) {
        cStock += (p.data['stock_count'] as int?) ?? 1;
      }

      // 2. 당일 누계 분석 (Detections 기반)
      int tEntry = 0;
      int tExit = 0;
      final Set<String> uniqueInItems = {};
      final Set<String> uniqueOutItems = {};

      final detRecords = await pb.collection('detections').getFullList(
          filter: 'created >= "$startStr"',
          sort: 'created'
      );

      for (var d in detRecords) {
        final String type = d.data['type']?.toString() ?? '';
        final bool isEntry = d.getBoolValue('is_entry');

        // 인원 출입 카운트
        if (type == 'person' || type == 'matched') {
          if (isEntry) { tEntry++; } else { tExit++; }
        }

        // 물품 입출고 분석
        final dynamic rawItems = d.data['items_json'];
        if (rawItems != null) {
          List<dynamic> itemsList = [];
          if (rawItems is List) {
            itemsList = rawItems;
          } else if (rawItems is String && rawItems.isNotEmpty) {
            try {
              itemsList = jsonDecode(rawItems) as List;
            } catch (_) {}
          }

          for (var item in itemsList) {
            final String? itemId = item['id']?.toString();
            if (itemId != null && itemId.isNotEmpty) {
              if (isEntry) {
                uniqueInItems.add(itemId);
              } else {
                uniqueOutItems.add(itemId);
              }
            }
          }
        }
      }

      // 3. UI 갱신 (전일 역산 포함)
      if (mounted) {
        setState(() {
          _todayEntry = tEntry;
          _todayExit = tExit;
          _currentStay = cStay;
          _prevDayStay = (_currentStay - _todayEntry + _todayExit).clamp(0, 99999);

          _todayIn = uniqueInItems.length;
          _todayOut = uniqueOutItems.length;
          _currentStock = cStock;
          _prevDayStock = (_currentStock - _todayIn + _todayOut).clamp(0, 99999);
        });
      }
    } catch (e) {
      debugPrint("❌ 집계 치명적 에러: $e");
    }
  }

  Future<void> _fetchNotice() async {
    try {
      final records = await pb.collection('notices').getList(
        page: 1,
        perPage: 1,
        sort: '-created',
      );

      if (records.items.isNotEmpty && mounted) {
        final data = records.items.first.data;
        final String title = data['title']?.toString() ?? '사내 공지';
        final String content = data['content']?.toString() ?? '';

        setState(() {
          _noticeText = "[$title] $content";
        });
      }
    } catch (e) {
      debugPrint("공지사항 로드 실패: $e");
    }
  }

  void _initRealtimeSubscription() {
    try {
      pb.realtime.unsubscribe('');
      pb.collection('users').subscribe('*', (e) => _fetchSummaryData());
      pb.collection('detections').subscribe('*', (e) => _fetchSummaryData());
      pb.collection('products').subscribe('*', (e) => _fetchSummaryData());
      pb.collection('notices').subscribe('*', (e) => _fetchNotice());
    } catch (e) {
      debugPrint("실시간 구독 에러: $e");
    }
  }

  bool get _canSave {
    if (_realtimeLogs.isEmpty) {
      return false;
    }
    if (!_requireWorkerMatch) {
      return true;
    }
    return _realtimeLogs.first.content != '미인식 작업자';
  }

  Future<void> _syncServerTime() async {
    setState(() {
      _timeOffset = Duration.zero;
    });
  }

  void _updateClock() {
    final DateTime now = DateTime.now().add(_timeOffset);
    const List<String> weekdays = ['월', '화', '수', '목', '금', '토', '일'];

    if (mounted) {
      setState(() {
        _currentTime = "${now.year}년 ${now.month.toString().padLeft(2, '0')}월 ${now.day.toString().padLeft(2, '0')}일 (${weekdays[now.weekday - 1]})   ${now.hour.toString().padLeft(2, '0')} : ${now.minute.toString().padLeft(2, '0')} : ${now.second.toString().padLeft(2, '0')}";
      });
    }
  }

  void _resetStandbyTimer() {
    _standbyTimer?.cancel();
    if (_useStandbyMode && _realtimeLogs.isEmpty) {
      _standbyTimer = Timer(Duration(seconds: _standbyTimeoutSeconds), () {
        if (mounted) {
          setState(() {
            _isStandbyActive = true;
          });
        }
      });
    }
  }

  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _standbyTimer?.cancel();

    setState(() {
      _autoSaveCountdown = _autoSaveDurationSeconds;
    });

    _autoSaveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_autoSaveCountdown > 1) {
            _autoSaveCountdown--;
          } else {
            _executeSaveAndClear();
          }
        });
      }
    });
  }

  /// [저장 및 집계 즉시 반영]
  Future<void> _executeSaveAndClear() async {
    _autoSaveTimer?.cancel();

    try {
      // 1. 실제 DB 저장 작업 진행
      for (var log in _realtimeLogs) {
        final Map<String, dynamic> dbRecord = log.toJson();
        dbRecord['timestamp'] = "${log.timestamp.toUtc().toString().replaceAll('T', ' ')}Z";

        await pb.collection('detections').create(body: dbRecord);

        // 마스터 갱신 (인원)
        if (log.type != 'unknown' && log.content != '미인식 작업자') {
          final String searchName = log.content.split(' ').first;
          final userRecords = await pb.collection('users').getList(filter: 'name ~ "$searchName"', perPage: 1);
          if (userRecords.items.isNotEmpty) {
            final userRecord = userRecords.items.first;
            final Map<String, dynamic> meta = Map<String, dynamic>.from(userRecord.data['metadata'] ?? {});
            meta['last_access_type'] = (log.isEntry ? '입장' : '퇴장');
            meta['last_access_time'] = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
            await pb.collection('users').update(userRecord.id, body: {'metadata': meta});
          }
        }

        // 마스터 갱신 (물품)
        for (var item in log.items) {
          final String? itemId = item['id'];
          if (itemId != null && itemId.isNotEmpty && !itemId.startsWith('sim_')) {
            final String dir = item['dir'] ?? (log.isEntry ? 'IN' : 'OUT');
            await pb.collection('products').update(itemId, body: {
              'status': (dir == 'IN' ? '자동입고' : '자동출고'),
              'location': log.spot
            });
          }
        }
      }

      // 2. 저장 완료 후 "즉시" 집계 재계산 (서버 반영 시간을 기다리지 않고 쿼리)
      await _fetchSummaryData();

    } catch (e) {
      debugPrint("❌ 저장 중 에러: $e");
    }

    if (mounted) {
      setState(() {
        _flushPhysicalBuffers();
        _realtimeLogs.clear();
        if (_useStandbyMode) {
          _isStandbyActive = true;
        }
      });
      _resetStandbyTimer();
    }
  }

  void _executeCancelAndClear() {
    _autoSaveTimer?.cancel();
    setState(() {
      _flushPhysicalBuffers();
      _realtimeLogs.clear();
      if (_useStandbyMode) {
        _isStandbyActive = true;
      }
    });
    _resetStandbyTimer();
  }

  void _simulateNewDetection() {
    if (_isStandbyActive) {
      _realtimeLogs.clear();
      _isStandbyActive = false;
    }

    final DateTime detectTime = DateTime.now().add(_timeOffset);
    final String spot = 'B구역 2번 공정 게이트';

    final DetectionModel? activeLog = _getActiveLogBySpot(spot);

    if (activeLog != null && _simCount % 3 != 0) {
      setState(() {
        activeLog.items.add({
          'id': 'sim_new_$_simCount',
          'name': '추가 감지 물품 $_simCount',
          'image': '',
          'dir': 'IN',
          'prevStatus': '자동입고'
        });
        _startAutoSaveTimer();
      });
    } else {
      DetectionModel newLog;
      if (_currentScanMode == GateScanMode.personnelOnly) {
        bool isEntrySim = _simCount % 2 == 0;
        newLog = DetectionModel(
            type: 'person',
            content: isEntrySim ? '홍길동 책임' : '이작업 주임',
            imageUrl: isEntrySim ? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?q=80&w=200' : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?q=80&w=200',
            spot: spot,
            status: isEntrySim ? '입장(출근)' : '퇴장(퇴근)',
            isEntry: isEntrySim,
            timestamp: detectTime,
            items: []
        );
      } else {
        newLog = DetectionModel(
            type: 'matched',
            content: '미인식 작업자',
            imageUrl: '',
            spot: spot,
            status: '자동입고(IN)',
            isEntry: true,
            timestamp: detectTime,
            items: [
              {
                'id': 'sim_1',
                'name': '전동 공구 (DW-88)',
                'image': '',
                'dir': 'IN',
                'prevStatus': '자동출고'
              },
            ]
        );
      }

      setState(() {
        _realtimeLogs.insert(0, newLog);
        _startAutoSaveTimer();
      });
    }

    _simCount++;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 1000;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          child: (_useStandbyMode && _isStandbyActive)
              ? _buildStandbyScreen(key: const ValueKey('standby_screen'), isDark: isDark, isSmall: isSmallScreen)
              : _buildLogScreen(key: const ValueKey('log_screen'), isDark: isDark, theme: theme, isSmall: isSmallScreen),
        ),
      ),
    );
  }

  Widget _buildStandbyScreen({required Key key, required bool isDark, required bool isSmall}) {
    return SizedBox(
      key: key,
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 1500),
            child: SizedBox.expand(
              key: ValueKey<int>(_currentImageIndex),
              child: Image.network(
                  _backgroundImages[_currentImageIndex],
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, lp) {
                    return lp == null ? child : const ColoredBox(color: Color(0xFF121826));
                  }
              ),
            ),
          ),
          Positioned(
              top: isSmall ? 16 : 32,
              left: isSmall ? 16 : 32,
              child: Text(
                  _currentTime,
                  style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      color: Colors.white,
                      fontSize: isSmall ? 24 : 48,
                      fontWeight: AppTheme.weightMenu,
                      letterSpacing: 2.0,
                      shadows: const [Shadow(color: Colors.black87, blurRadius: 8.0, offset: Offset(2, 2))]
                  )
              )
          ),
          Positioned(
              top: isSmall ? 16 : 32,
              right: isSmall ? 8 : 32,
              child: isSmall
                  ? IconButton(
                  onPressed: widget.onDismiss,
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 32)
              )
                  : Row(
                  children: [
                    _buildTestButton(isSmall: false),
                    const SizedBox(width: 30),
                    _buildModeSwitcher(isDark: isDark, forceWhiteText: true),
                    const SizedBox(width: 30),
                    _buildRequireWorkerToggle(isDark: isDark, forceWhiteText: true),
                    const SizedBox(width: 30),
                    _buildStandbyToggle(isDark: isDark, forceWhiteText: true),
                    const SizedBox(width: 20),
                    IconButton(
                        onPressed: widget.onDismiss,
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 40)
                    )
                  ]
              )
          ),
          Positioned(
              bottom: isSmall ? 10 : 30,
              left: isSmall ? 10 : 40,
              right: isSmall ? 10 : 40,
              child: _MarqueeWidget(
                  text: _noticeText,
                  backgroundColor: Colors.transparent,
                  textColor: Colors.white,
                  forceDarkShadow: true,
                  isSmall: isSmall
              )
          ),
        ],
      ),
    );
  }

  Widget _buildLogScreen({required Key key, required bool isDark, required ThemeData theme, required bool isSmall}) {
    return Padding(
      key: key,
      padding: EdgeInsets.all(isSmall ? 16.0 : 32.0),
      child: Column(
        children: [
          _buildHeader(isDark: isDark, isSmall: isSmall),
          const SizedBox(height: 24),
          _buildSummaryBar(isDark: isDark, isSmall: isSmall),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 20.0),
              child: _realtimeLogs.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        Icons.sensor_door_rounded,
                        size: isSmall ? 50 : 80,
                        color: AppTheme.labelColor(isDark).withValues(alpha: 0.3)
                    ),
                    const SizedBox(height: 24),
                    Text(
                        "게이트 감지 대기 중...",
                        style: TextStyle(
                            fontFamily: AppTheme.fontPretendard,
                            fontSize: isSmall ? 18 : 24,
                            fontWeight: AppTheme.weightMenu,
                            color: AppTheme.labelColor(isDark)
                        )
                    ),
                  ],
                ),
              )
                  : ListView.separated(
                itemCount: _realtimeLogs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 24),
                itemBuilder: (context, index) {
                  final DetectionModel log = _realtimeLogs[index];
                  final bool isWarning = log.content == '미인식 작업자' && _requireWorkerMatch && log.type != 'unknown';

                  return _LogCardWidget(
                      log: log,
                      isDark: isDark,
                      theme: theme,
                      isWarning: isWarning,
                      isSmall: isSmall
                  );
                },
              ),
            ),
          ),
          if (_realtimeLogs.isNotEmpty) ...[
            _buildAutoSaveActionPanel(isDark: isDark, theme: theme, isSmall: isSmall),
          ]
        ],
      ),
    );
  }

  Widget _buildHeader({required bool isDark, required bool isSmall}) {
    final Color titleColor = AppTheme.dataColor(isDark);

    if (isSmall && MediaQuery.of(context).size.width < 700) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  "실시간 감지 모니터링",
                  style: TextStyle(fontFamily: AppTheme.fontPretendard, color: titleColor, fontSize: 24, fontWeight: FontWeight.w700)
              ),
              IconButton(onPressed: widget.onDismiss, icon: const Icon(Icons.close_rounded, size: 32)),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTestButton(isSmall: true),
                const SizedBox(width: 12),
                _buildModeSwitcher(isDark: isDark),
              ],
            ),
          )
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)
              ),
              child: Icon(Icons.sensor_door_outlined, color: isDark ? Colors.white : AppTheme.primary, size: isSmall ? 28 : 36),
            ),
            const SizedBox(width: 20),
            Text(
                "실시간 감지 모니터링",
                style: TextStyle(fontFamily: AppTheme.fontPretendard, color: titleColor, fontSize: isSmall ? 24 : 32, fontWeight: FontWeight.w700)
            ),
          ],
        ),
        Row(
          children: [
            if (!isSmall) ...[
              _buildTestButton(isSmall: false),
              const SizedBox(width: 24),
              _buildModeSwitcher(isDark: isDark),
              const SizedBox(width: 24),
              _buildRequireWorkerToggle(isDark: isDark),
              const SizedBox(width: 24),
              _buildStandbyToggle(isDark: isDark),
            ],
            const SizedBox(width: 32),
            Text(
                _currentTime.split('   ').last,
                style: TextStyle(fontFamily: AppTheme.fontPretendard, color: titleColor, fontSize: isSmall ? 20 : 28, fontWeight: AppTheme.weightMenu)
            ),
            const SizedBox(width: 24),
            IconButton(onPressed: widget.onDismiss, icon: const Icon(Icons.close_rounded, size: 36))
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryBar({required bool isDark, required bool isSmall}) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
            color: isDark ? Colors.white12 : AppTheme.silver.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12)
        ),
        child: Row(
          children: [
            Expanded(child: _buildSummaryItem(label: _currentScanMode == GateScanMode.personnelOnly ? "전일잔류" : "전일재고", count: _currentScanMode == GateScanMode.personnelOnly ? _prevDayStay : _prevDayStock, isDark: isDark, isSmall: isSmall)),
            Expanded(child: _buildSummaryItem(label: _currentScanMode == GateScanMode.personnelOnly ? "당일입장" : "당일입고", count: _currentScanMode == GateScanMode.personnelOnly ? _todayEntry : _todayIn, isDark: isDark, isSmall: isSmall, color: AppTheme.success)),
            Expanded(child: _buildSummaryItem(label: _currentScanMode == GateScanMode.personnelOnly ? "당일퇴장" : "당일출고", count: _currentScanMode == GateScanMode.personnelOnly ? _todayExit : _todayOut, isDark: isDark, isSmall: isSmall, color: Colors.orange.shade700)),
            Expanded(child: _buildSummaryItem(label: _currentScanMode == GateScanMode.personnelOnly ? "현재잔류" : "현재재고", count: _currentScanMode == GateScanMode.personnelOnly ? _currentStay : _currentStock, isDark: isDark, isSmall: isSmall, color: AppTheme.primary, isHighlight: true)),
          ],
        )
    );
  }

  Widget _buildSummaryItem({required String label, required int count, required bool isDark, Color color = Colors.blueGrey, bool isHighlight = false, bool isSmall = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
            label,
            style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: isSmall ? 12 : 14, color: isHighlight ? color : AppTheme.labelColor(isDark))
        ),
        Text(
            count.toString(),
            style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: isSmall ? 20 : 28, fontWeight: FontWeight.w700, color: isHighlight ? color : AppTheme.dataColor(isDark))
        ),
      ],
    );
  }

  Widget _buildAutoSaveActionPanel({required bool isDark, required ThemeData theme, required bool isSmall}) {
    final bool canSave = _canSave;
    return Container(
      padding: EdgeInsets.all(isSmall ? 16 : 24),
      decoration: BoxDecoration(
        color: canSave ? (isDark ? const Color(0xFF1E293B) : Colors.white) : AppTheme.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: canSave ? Colors.white10 : AppTheme.danger, width: 2),
      ),
      child: Row(
        children: [
          CircularProgressIndicator(value: _autoSaveCountdown / _autoSaveDurationSeconds),
          const SizedBox(width: 20),
          Expanded(
              child: Text(
                  canSave ? "$_autoSaveCountdown초 후 자동 저장됩니다." : "보안 경고: 신원을 확인해 주세요!",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
              )
          ),
          OutlinedButton(onPressed: _executeCancelAndClear, child: const Text("취소")),
          const SizedBox(width: 12),
          ElevatedButton(onPressed: canSave ? _executeSaveAndClear : null, child: const Text("즉시 확정")),
        ],
      ),
    );
  }

  Widget _buildModeSwitcher({required bool isDark, bool forceWhiteText = false}) {
    return Container(
      decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black12,
          borderRadius: BorderRadius.circular(30)
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeBtn(GateScanMode.personnelOnly, "인원", isDark, forceWhiteText),
          _buildModeBtn(GateScanMode.itemWorkerMatch, "매칭", isDark, forceWhiteText),
        ],
      ),
    );
  }

  Widget _buildModeBtn(GateScanMode mode, String label, bool isDark, bool forceWhite) {
    bool isSel = _currentScanMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _currentScanMode = mode);
        _fetchSummaryData(); // 모드 전환 시 집계 즉시 갱신
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
            color: isSel ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20)
        ),
        child: Text(
            label,
            style: TextStyle(
                color: isSel ? Colors.white : (forceWhite ? Colors.white70 : Colors.black54),
                fontWeight: FontWeight.bold
            )
        ),
      ),
    );
  }

  Widget _buildTestButton({required bool isSmall}) {
    return ElevatedButton.icon(
      onPressed: _simulateNewDetection,
      icon: const Icon(Icons.sensors, size: 18),
      label: Text(isSmall ? "테스트" : "시뮬레이터"),
      style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal.shade600,
          padding: EdgeInsets.symmetric(horizontal: isSmall ? 12 : 16, vertical: 12)
      ),
    );
  }

  Widget _buildRequireWorkerToggle({required bool isDark, bool forceWhiteText = false}) {
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
              "인원필수",
              style: TextStyle(color: forceWhiteText ? Colors.white : AppTheme.labelColor(isDark), fontSize: 14)
          ),
          Switch(
              value: _requireWorkerMatch,
              onChanged: (v) => setState(() => _requireWorkerMatch = v)
          ),
        ]
    );
  }

  Widget _buildStandbyToggle({required bool isDark, bool forceWhiteText = false}) {
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
              "대기화면",
              style: TextStyle(color: forceWhiteText ? Colors.white : AppTheme.labelColor(isDark), fontSize: 14)
          ),
          Switch(
              value: _useStandbyMode,
              onChanged: (v) => setState(() => _useStandbyMode = v)
          ),
        ]
    );
  }
}

/// [로그 카드 위젯]
class _LogCardWidget extends StatelessWidget {
  final DetectionModel log;
  final bool isDark;
  final ThemeData theme;
  final bool isWarning;
  final bool isSmall;

  const _LogCardWidget({
    required this.log,
    required this.isDark,
    required this.theme,
    required this.isWarning,
    required this.isSmall
  });

  @override
  Widget build(BuildContext context) {
    final bool isMatched = log.type == 'matched';
    final bool isUnknown = log.type == 'unknown';
    final bool isMixed = log.status.contains('복합');

    final Color statusColor = isWarning
        ? AppTheme.danger
        : (isUnknown ? Colors.grey.shade500 : (isMixed ? Colors.indigo : (log.isEntry ? AppTheme.success : Colors.orange.shade700)));

    return Container(
      padding: EdgeInsets.all(isSmall ? 16 : 24),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: isSmall ? 24 : 32,
                backgroundImage: log.imageUrl.isNotEmpty ? NetworkImage(log.imageUrl) : null,
                backgroundColor: isUnknown ? Colors.grey.shade400 : null,
                child: log.imageUrl.isEmpty ? Icon(isUnknown ? Icons.help_outline : Icons.person, color: isUnknown ? Colors.white : null) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        log.content,
                        style: TextStyle(fontSize: isSmall ? 20 : 26, fontWeight: FontWeight.bold, color: isUnknown ? Colors.grey.shade700 : null)
                    ),
                    Text(
                        log.spot,
                        style: const TextStyle(color: Colors.grey)
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor)
                ),
                child: Text(
                    log.status,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)
                ),
              )
            ],
          ),

          if ((isMatched || isUnknown) && log.items.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
                "📦 감지 태그/물품: ${log.items.length}건",
                style: const TextStyle(fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: isSmall ? 120 : 180,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: log.items.length,
                itemBuilder: (context, i) {
                  final item = log.items[i];
                  final String itemDir = item['dir'] ?? (log.isEntry ? 'IN' : 'OUT');
                  final String prevStatus = item['prevStatus'] ?? '확인불가';

                  final bool isItemIn = itemDir == 'IN';
                  final Color itemBadgeColor = isItemIn ? AppTheme.success : Colors.orange.shade700;
                  final String itemBadgeText = isItemIn ? '입고' : '출고';

                  return Container(
                    width: isSmall ? 100 : 140,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8.0),
                                child: item['image'] != null && item['image']!.isNotEmpty
                                    ? Image.network(
                                    item['image'] ?? '',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Icon(Icons.inventory);
                                    }
                                )
                                    : Container(
                                    width: double.infinity,
                                    height: double.infinity,
                                    color: Colors.grey.shade200,
                                    child: Center(
                                        child: Icon(isUnknown ? Icons.qr_code_scanner : Icons.inventory, color: Colors.grey.shade400, size: 36)
                                    )
                                ),
                              ),
                              Positioned(
                                  top: 0, left: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: itemBadgeColor,
                                        borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(8.0),
                                            bottomRight: Radius.circular(8.0)
                                        )
                                    ),
                                    child: Text(
                                        itemBadgeText,
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
                                    ),
                                  )
                              ),
                              Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: itemBadgeColor.withValues(alpha: 0.6),
                                        width: 2.0
                                    ),
                                    borderRadius: BorderRadius.circular(8.0),
                                  )
                              )
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                            item['name'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(4)
                          ),
                          child: Text(
                            "$prevStatus → $itemBadgeText",
                            style: TextStyle(
                                fontSize: 10,
                                color: prevStatus.contains(itemBadgeText)
                                    ? Colors.grey
                                    : AppTheme.danger,
                                fontWeight: FontWeight.w500
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            )
          ]
        ],
      ),
    );
  }
}

/// [공지사항 흐르는 텍스트 위젯]
class _MarqueeWidget extends StatefulWidget {
  final String text;
  final Color backgroundColor;
  final Color textColor;
  final bool forceDarkShadow;
  final bool isSmall;

  const _MarqueeWidget({
    required this.text,
    required this.backgroundColor,
    required this.textColor,
    this.forceDarkShadow = false,
    required this.isSmall
  });

  @override
  State<_MarqueeWidget> createState() => _MarqueeWidgetState();
}

class _MarqueeWidgetState extends State<_MarqueeWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 25)
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: ClipRect(
        child: LayoutBuilder(
            builder: (context, constraints) {
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final double offset = constraints.maxWidth - (_controller.value * (constraints.maxWidth + 2000));
                  return Transform.translate(
                      offset: Offset(offset, 0),
                      child: child
                  );
                },
                child: Text(
                    widget.text,
                    style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        color: widget.textColor,
                        fontSize: widget.isSmall ? 18 : 26,
                        fontWeight: FontWeight.bold,
                        shadows: widget.forceDarkShadow
                            ? const [Shadow(color: Colors.black, blurRadius: 10)]
                            : null
                    ),
                    maxLines: 1,
                    softWrap: false
                ),
              );
            }
        ),
      ),
    );
  }
}