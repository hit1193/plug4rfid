import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:pocketbase/pocketbase.dart';

import '../models/user_model.dart';
// 기존 PBService를 지우고, DataModule 역할을 하는 전역 클라이언트를 임포트합니다.
import '../core/pocketbase_client.dart';

/// ---------------------------------------------------------------------------
/// [엑셀 파싱 전용 백그라운드 워커 (Isolate)]
/// 메인 UI 스레드의 프리징을 방지하기 위해 엑셀 데이터를 독립된 메모리 공간에서 분석합니다.
/// C++Builder의 별도 Worker Thread 작업과 동일한 개념입니다.
/// ---------------------------------------------------------------------------
Map<String, dynamic>? _parseExcelIsolate(Uint8List bytes) {
  try {
    var excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      return null;
    }

    // 첫 번째 시트를 대상으로 작업합니다.
    String sheetName = excel.tables.keys.first;
    var table = excel.tables[sheetName]!;
    if (table.maxRows < 1) {
      return null;
    }

    // 첫 번째 행을 헤더(컬럼명)로 추출합니다.
    List<String> headers = table.rows.first.map((cell) {
      return (cell?.value?.toString() ?? "").trim();
    }).toList();

    List<Map<String, dynamic>> rows = [];
    for (int i = 1; i < table.maxRows; i++) {
      Map<String, dynamic> rowData = {};
      for (int j = 0; j < headers.length; j++) {
        if (j < table.rows[i].length) {
          rowData[headers[j]] = table.rows[i][j]?.value?.toString() ?? "";
        }
      }
      // 데이터가 한 줄이라도 있는 경우에만 리스트에 추가합니다.
      if (rowData.values.any((v) => v.toString().isNotEmpty)) {
        rows.add(rowData);
      }
    }
    return {"data_count": rows.length, "details": rows};
  } catch (e) {
    debugPrint("엑셀 파싱 스레드 오류: $e");
    return null;
  }
}

/// ---------------------------------------------------------------------------
/// [인원 관리 전역 상태 제공자 (UserProvider)]
/// 애플리케이션의 비즈니스 로직과 데이터 상태를 관장하는 핵심 모듈입니다.
/// C++Builder의 DataModule 역할을 수행하며, UI 스레드에 데이터 변경을 통지합니다.
/// ---------------------------------------------------------------------------
class UserProvider extends ChangeNotifier {
  // 전역 pb 객체를 내부 변수로 매핑합니다.
  final PocketBase _pb = pb;

  // 데이터 대상 컬렉션 이름 (포켓베이스 기본 Auth 테이블)
  final String _collectionName = 'users';
  final String _configCollection = 'app_configs';
  final String _columnConfigKey = 'user_list_columns';

  // --- 내부 상태 변수 (DataSet 역할) ---
  List<UserModel> _list = [];                // 전체 인원 리스트
  List<String> _selectedColumns = [];        // UI에 표시할 선택된 컬럼들

  bool _isLoading = false;                   // 데이터 로딩 중 플래그
  bool _isSaving = false;                    // 서버 저장 중 플래그
  bool _isParsing = false;                   // 엑셀 파싱 중 플래그
  bool _isDisposed = false;                  // 객체 소멸 여부 확인
  bool _isInitialized = false;               // 초기화 완료 여부

  // --- 외부 노출용 Getter (Read-only) ---
  List<UserModel> get list => _list;
  List<String> get selectedColumns => _selectedColumns;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isParsing => _isParsing;

  UserProvider() {
    _initProvider();
  }

  /// 초기화 함수: 서버에서 설정값과 데이터를 순차적으로 로드하고 실시간 구독을 시작합니다.
  Future<void> _initProvider() async {
    if (_isInitialized) return;

    await fetchRemoteSettings(); // 1. 표시 컬럼 설정 로드
    await fetchData();           // 2. 실제 데이터 로드
    _subscribe();                // 3. 실시간 동기화 시작

    _isInitialized = true;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _safeUnsubscribe();
    super.dispose();
  }

  /// 포켓베이스 실시간 구독을 안전하게 해제합니다.
  Future<void> _safeUnsubscribe() async {
    try {
      await _pb.collection(_collectionName).unsubscribe('*');
    } catch (_) {}
  }

  /// ---------------------------------------------------------------------------
  /// [데이터 로드] - Query->Open()
  /// 서버에서 최신 인원 목록을 가져와 메모리 데이터셋을 갱신합니다.
  /// ---------------------------------------------------------------------------
  Future<void> fetchData() async {
    if (_isDisposed) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Created 일시 기준 내림차순으로 전체 목록을 가져옵니다.
      final records = await _pb.collection(_collectionName).getFullList(
        sort: '-created',
        expand: 'company_id', // 관계형 데이터인 회사 정보도 함께 가져옵니다.
      );

      if (_isDisposed) return;

      // 서버 레코드들을 UserModel 객체 리스트로 매핑합니다.
      _list = records.map((r) => UserModel.fromRecord(r)).toList();
      debugPrint("인원 데이터 로드 성공: ${_list.length}건");
    } catch (e) {
      debugPrint("데이터 로드 중 치명적 에러: $e");
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// ---------------------------------------------------------------------------
  /// [단건 통합 저장 처리] - 화면에서 1명씩 추가/수정 시
  /// 복잡했던 아이디(username) 생성 로직을 완전히 제거하고 이메일 중심으로 심플하게 재편!
  /// ---------------------------------------------------------------------------
  Future<bool> handleSave({
    required UserModel? p,
    required Map<String, dynamic> data,
    XFile? imageXFile,
  }) async {
    if (_isDisposed) return false;
    _isSaving = true;
    notifyListeners();

    try {
      // 1. 이미지 파일 처리 (아바타 업로드)
      List<http.MultipartFile> files = [];
      if (imageXFile != null) {
        final bytes = await imageXFile.readAsBytes();
        files.add(http.MultipartFile.fromBytes(
            'avatar',
            bytes,
            filename: imageXFile.name
        ));
      }

      // -----------------------------------------------------------------------
      // [데이터 가공 공통 규칙] 비밀번호 강제 동기화
      // -----------------------------------------------------------------------
      if (data.containsKey('password') && data['password'].toString().trim().isNotEmpty) {
        data['passwordConfirm'] = data['password'].toString().trim();
      }

      // 🔥 [핵심 방어 1] 포켓베이스 v0.23 이상에서는 일반 계정이 verified 값을 건드리면 400 에러 발생!
      // 따라서 페이로드에서 아예 제거해 버립니다.
      data.remove('verified');
      data['emailVisibility'] = true;

      // 🔥 [보안 권한 체크] 현재 접속 중인 계정이 시스템 최고 관리자(_superusers)인지 판별
      bool isAdmin = false;
      final authModel = _pb.authStore.model;
      if (authModel is RecordModel && authModel.collectionName == '_superusers') {
        isAdmin = true;
      } else if (authModel is AdminModel) {
        isAdmin = true; // 구버전 호환용
      }

      RecordModel record;

      if (p == null) {
        // [INSERT] 신규 인원 등록 (이메일 기반)
        if (!data.containsKey('password') || data['password'].toString().trim().isEmpty) {
          data['password'] = '12345678';
          data['passwordConfirm'] = '12345678';
        }

        record = await _pb.collection(_collectionName).create(body: data, files: files);
        _list.insert(0, UserModel.fromRecord(record));

      } else {
        // [UPDATE] 기존 인원 정보 수정
        if (data.containsKey('password') && data['password'].toString().trim().isEmpty) {
          data.remove('password');
          data.remove('passwordConfirm');
        }

        // 🔥 [핵심 방어 2] 최고 관리자가 아닌 일반 계정(앱 내 수퍼바이저 포함)일 경우의 필터링
        // 일반 사용자는 PocketBase 정책상 남의 이메일과 비밀번호를 절대 직접 바꿀 수 없습니다.
        // 이것들을 전송하려 들면 oldPassword 누락 및 value_mismatch 에러가 터지므로 전송에서 제외합니다!
        if (!isAdmin) {
          data.remove('email');
          if (data.containsKey('password')) {
            data.remove('password');
            data.remove('passwordConfirm');
            debugPrint('⚠️ 일반 권한이므로 비밀번호 및 이메일 변경은 업데이트 항목에서 안전하게 제외되었습니다.');
          }
        }

        record = await _pb.collection(_collectionName).update(p.id, body: data, files: files);

        int index = _list.indexWhere((item) => item.id == p.id);
        if (index != -1) {
          _list[index] = UserModel.fromRecord(record);
        }
      }

      notifyListeners();
      return true;
    } catch (e) {
      // 🚨 [핵심 디버깅] 포켓베이스가 저장을 거부한 "진짜 이유"를 낱낱이 출력합니다.
      if (e is ClientException) {
        debugPrint("\n===================================================");
        debugPrint("❌ PocketBase DB 저장 거부 (ClientException) ❌");
        debugPrint("상태 코드: ${e.statusCode}");
        debugPrint("응답 내용: ${e.response}");
        debugPrint("===================================================\n");
      } else {
        debugPrint("❌ 저장 중 알 수 없는 에러 발생: $e");
      }
      return false; // 저장이 실패했음을 UI에 알림
    } finally {
      if (!_isDisposed) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  /// ---------------------------------------------------------------------------
  /// [엑셀 일괄 임포트] - 이메일 중심 로직으로 변경
  /// ---------------------------------------------------------------------------
  Future<int> batchImportFromExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null) return 0;

      _isParsing = true;
      notifyListeners();

      Uint8List bytes;
      if (kIsWeb) {
        bytes = result.files.single.bytes!;
      } else {
        bytes = await File(result.files.single.path!).readAsBytes();
      }

      final parsedData = await compute(_parseExcelIsolate, bytes);

      if (parsedData == null || parsedData['details'] == null) {
        _isParsing = false;
        notifyListeners();
        return 0;
      }

      List<Map<String, dynamic>> rows = List<Map<String, dynamic>>.from(parsedData['details']);
      int successCount = 0;

      _isParsing = false;
      _isSaving = true;
      notifyListeners();

      for (var row in rows) {
        try {
          String name = _getExcelValue(row, ['성명', '이름', 'Name', 'name']);
          if (name.isEmpty) continue;

          String code = _getExcelValue(row, ['사원번호', '사번', '코드', 'Code', 'code']).trim();
          if (code.isEmpty) {
            code = "T-${DateTime.now().millisecondsSinceEpoch % 100000}";
          }

          // 🔥 엑셀 데이터에서 '이메일' 항목을 가장 먼저 찾습니다.
          String email = _getExcelValue(row, ['이메일', 'e-mail', 'email', '메일']);
          if (email.isEmpty) {
            // 이메일이 없다면 사번을 기반으로 가상의 이메일을 자동 부여합니다.
            String safePrefix = code.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.-]'), '');
            email = '$safePrefix@plug4rfid.local';
          }

          final body = {
            // username 항목은 아예 전송하지 않습니다. (포켓베이스가 알아서 랜덤 생성합니다)
            'email': email,
            'password': '12345678',
            'passwordConfirm': '12345678',
            // 'verified': true, // 🔥 삭제 완료! (에러 원인 제거)
            'emailVisibility': true,
            'name': name,
            'code': code,
            'department': _getExcelValue(row, ['담당부서', '부서', '소속', 'Dept']),
            'tag_id': _getExcelValue(row, ['태그', 'EPC', 'RFID', 'tag_id']),
            'is_active': true,
            'role': 'Operator',
            'metadata': {
              'import_source': 'excel',
              'original_row_data': row
            }
          };

          await _pb.collection(_collectionName).create(body: body);
          successCount++;
        } catch (e) {
          debugPrint("개별 행 임포트 실패: $e");
        }
      }

      _isSaving = false;
      await fetchData();
      return successCount;
    } catch (e) {
      _isParsing = false;
      _isSaving = false;
      notifyListeners();
      return 0;
    }
  }

  /// 엑셀 데이터에서 여러 후보 키 중 일치하는 값을 찾아 반환합니다.
  String _getExcelValue(Map<String, dynamic> row, List<String> possibleKeys) {
    for (var key in possibleKeys) {
      if (row.containsKey(key) && row[key] != null) {
        return row[rowDataKey(row, key)].toString().trim();
      }
    }
    for (var entry in row.entries) {
      if (possibleKeys.any((pk) => pk.toLowerCase() == entry.key.toLowerCase())) {
        return entry.value.toString().trim();
      }
    }
    return "";
  }

  String rowDataKey(Map<String, dynamic> row, String target) {
    return row.keys.firstWhere((k) => k == target, orElse: () => target);
  }

  /// ---------------------------------------------------------------------------
  /// [데이터 삭제 및 관리]
  /// ---------------------------------------------------------------------------
  Future<bool> deletePerson(String id) async {
    try {
      await _pb.collection(_collectionName).delete(id);
      _list.removeWhere((p) => p.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("삭제 처리 실패: $e");
      return false;
    }
  }

  Future<bool> resetAllPersons() async {
    if (_isDisposed) return false;
    _isSaving = true;
    notifyListeners();

    try {
      final records = await _pb.collection(_collectionName).getFullList(fields: 'id');
      if (records.isNotEmpty) {
        await Future.wait(records.map((r) => _pb.collection(_collectionName).delete(r.id)));
      }

      try {
        final config = await _pb.collection(_configCollection).getFirstListItem('key = "$_columnConfigKey"');
        await _pb.collection(_configCollection).delete(config.id);
      } catch (_) {}

      _list = [];
      _selectedColumns = [];
      return true;
    } catch (e) {
      debugPrint("시스템 초기화 중 오류: $e");
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// ---------------------------------------------------------------------------
  /// [환경 설정 관리]
  /// ---------------------------------------------------------------------------
  Future<void> fetchRemoteSettings() async {
    try {
      final record = await _pb.collection(_configCollection).getFirstListItem('key = "$_columnConfigKey"');
      final dynamic val = record.data['value'];
      if (val is List) {
        _selectedColumns = val.map((e) => e.toString()).toList();
        notifyListeners();
      }
    } on ClientException catch (e) {
      if (e.statusCode == 404) {
        _selectedColumns = ['성명', '부서', '사번', '태그ID'];
        notifyListeners();
      }
    } catch (e) {
      debugPrint("설정 로드 실패: $e");
    }
  }

  Future<void> saveRemoteSettings(List<String> columns) async {
    try {
      _selectedColumns = List.from(columns);
      notifyListeners();

      RecordModel? existing;
      try {
        existing = await _pb.collection(_configCollection).getFirstListItem('key = "$_columnConfigKey"');
      } catch (_) {}

      final body = {'key': _columnConfigKey, 'value': _selectedColumns};

      if (existing != null) {
        await _pb.collection(_configCollection).update(existing.id, body: body);
      } else {
        await _pb.collection(_configCollection).create(body: body);
      }
    } catch (e) {
      debugPrint("설정 저장 실패: $e");
    }
  }

  /// ---------------------------------------------------------------------------
  /// [실시간 서버 동기화] - LiveQuery
  /// ---------------------------------------------------------------------------
  void _subscribe() {
    _pb.collection(_collectionName).subscribe('*', (e) {
      if (_isDisposed || _isSaving) return;
      if (e.record == null) return;

      if (e.action == 'create') {
        if (!_list.any((p) => p.id == e.record!.id)) {
          _list.insert(0, UserModel.fromRecord(e.record!));
        }
      } else if (e.action == 'update') {
        int idx = _list.indexWhere((p) => p.id == e.record!.id);
        if (idx != -1) {
          _list[idx] = UserModel.fromRecord(e.record!);
        }
      } else if (e.action == 'delete') {
        _list.removeWhere((p) => p.id == e.record!.id);
      }
      notifyListeners();
    });
  }
}