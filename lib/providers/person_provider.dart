import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:pocketbase/pocketbase.dart';

import '../models/persons.dart';
import '../services/pb_service.dart';

/// Isolate에서 실행될 최상위 엑셀 파싱 함수 (UI 프리징 방지)
Map<String, dynamic>? _parseExcelIsolate(Uint8List bytes) {
  try {
    var excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return null;
    String sheetName = excel.tables.keys.first;
    var table = excel.tables[sheetName]!;
    if (table.maxRows < 1) return null;

    List<String> headers = table.rows.first.map((cell) => (cell?.value?.toString() ?? "").trim()).toList();
    List<Map<String, dynamic>> rows = [];
    for (int i = 1; i < table.maxRows; i++) {
      Map<String, dynamic> rowData = {};
      for (int j = 0; j < headers.length; j++) {
        if (j < table.rows[i].length) {
          rowData[headers[j]] = table.rows[i][j]?.value?.toString() ?? "";
        }
      }
      if (rowData.values.any((v) => v.toString().isNotEmpty)) rows.add(rowData);
    }
    return {"data_count": rows.length, "details": rows};
  } catch (e) {
    debugPrint("Isolate Parsing Error: $e");
    return null;
  }
}

class PersonProvider extends ChangeNotifier {
  final String _collectionName = 'persons';
  final String _configCollection = 'app_configs';
  final String _columnConfigKey = 'person_list_columns';

  List<Person> _list = [];
  List<String> _selectedColumns = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isParsing = false;
  bool _isDisposed = false;
  bool _isInitialized = false;

  List<Person> get list => _list;
  List<String> get selectedColumns => _selectedColumns;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isParsing => _isParsing;

  PersonProvider() {
    _initProvider();
  }

  /// 초기화: 설정 로드 후 데이터 로드 및 구독 시작
  Future<void> _initProvider() async {
    if (_isInitialized) return;
    await fetchRemoteSettings();
    await fetchData();
    _subscribe();
    _isInitialized = true;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _safeUnsubscribe();
    super.dispose();
  }

  /// 실시간 구독 해제
  Future<void> _safeUnsubscribe() async {
    try {
      await PBService.pb.collection(_collectionName).unsubscribe('*');
      await PBService.pb.collection(_configCollection).unsubscribe('*');
    } catch (_) {}
  }

  /// [설정] 서버에서 컬럼 설정 로드
  Future<void> fetchRemoteSettings() async {
    try {
      final record = await PBService.pb.collection(_configCollection).getFirstListItem(
        'key = "$_columnConfigKey"',
      );

      final dynamic val = record.data['value'];
      if (val is List) {
        _selectedColumns = val.map((e) => e.toString()).toList();
        notifyListeners();
      }
    } on ClientException catch (e) {
      if (e.statusCode == 404) {
        debugPrint("ℹ️ 서버에 저장된 설정이 없습니다. 기본 설정을 사용합니다.");
      } else {
        // e.message 대신 e.toString() 또는 e.response['message'] 사용
        debugPrint("❌ 설정 로드 중 통신 오류: ${e.toString()}");
      }
    } catch (e) {
      debugPrint("⚠️ 예상치 못한 설정 로드 실패: $e");
    }
  }

  /// [설정] 서버에 컬럼 설정 저장
  Future<void> saveRemoteSettings(List<String> columns) async {
    try {
      _selectedColumns = List.from(columns);
      notifyListeners();

      RecordModel? existing;
      try {
        existing = await PBService.pb.collection(_configCollection).getFirstListItem('key = "$_columnConfigKey"');
      } catch (_) {}

      final body = {'key': _columnConfigKey, 'value': _selectedColumns};

      if (existing != null) {
        await PBService.pb.collection(_configCollection).update(existing.id, body: body);
      } else {
        await PBService.pb.collection(_configCollection).create(body: body);
      }
    } catch (e) {
      debugPrint("설정 저장 실패: $e");
    }
  }

  /// [데이터] 전체 리스트 로드
  Future<void> fetchData() async {
    if (_isDisposed) return;
    _isLoading = true;
    notifyListeners();
    try {
      final records = await PBService.pb.collection(_collectionName).getFullList(
        sort: '-created',
        expand: 'company_id',
      );
      if (_isDisposed) return;
      _list = records.map((r) => Person.fromRecord(r)).toList();
    } catch (e) {
      debugPrint("데이터 로드 에러: $e");
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// [엑셀 임포트] 컬럼이 달라도 metadata/original_row_data에 모두 보존함
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

          String code = _getExcelValue(row, ['사번', '코드', 'Code', 'code']);
          if (code.isEmpty) code = "T-${DateTime.now().millisecondsSinceEpoch % 100000}";

          final body = {
            'name': name,
            'code': code,
            'department': _getExcelValue(row, ['부서', '소속', 'Dept']),
            'tag_id': _getExcelValue(row, ['태그', 'EPC', 'RFID', 'tag_id']),
            'is_active': true,
            'role': 'Operator',
            'metadata': {
              'import_source': 'excel',
              'original_row_data': row
            }
          };

          await PBService.pb.collection(_collectionName).create(body: body);
          successCount++;
        } catch (e) {
          debugPrint("행 임포트 실패: $e");
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

  String _getExcelValue(Map<String, dynamic> row, List<String> possibleKeys) {
    for (var key in possibleKeys) {
      if (row.containsKey(key) && row[key] != null) {
        return row[key].toString().trim();
      }
    }
    return "";
  }

  /// [시스템 초기화] 인원 데이터와 컬럼 설정값을 모두 삭제 (Factory Reset)
  Future<bool> resetAllPersons() async {
    if (_isDisposed) return false;

    _isSaving = true;
    notifyListeners();

    try {
      final records = await PBService.pb.collection(_collectionName).getFullList(fields: 'id');
      if (records.isNotEmpty) {
        await Future.wait(
            records.map((r) => PBService.pb.collection(_collectionName).delete(r.id))
        );
      }

      try {
        final configRecord = await PBService.pb.collection(_configCollection).getFirstListItem(
          'key = "$_columnConfigKey"',
        );
        await PBService.pb.collection(_configCollection).delete(configRecord.id);
      } catch (e) {
        debugPrint("설정값 초기화 건너뜀 (이미 없거나 오류): $e");
      }

      _list = [];
      _selectedColumns = [];

      _isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("전체 초기화 오류: $e");
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  /// [저장/수정] 단일 레코드 저장 및 이미지 업로드 처리
  Future<bool> handleSave({
    required Person? p,
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

      RecordModel record;
      if (p == null) {
        record = await PBService.pb.collection(_collectionName).create(body: data, files: files);
        _list.insert(0, Person.fromRecord(record));
      } else {
        record = await PBService.pb.collection(_collectionName).update(p.id, body: data, files: files);
        int index = _list.indexWhere((item) => item.id == p.id);
        if (index != -1) _list[index] = Person.fromRecord(record);
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("저장 에러: $e");
      return false;
    } finally {
      if (!_isDisposed) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  /// [삭제] 단일 레코드 삭제
  Future<bool> deletePerson(String id) async {
    try {
      await PBService.pb.collection(_collectionName).delete(id);
      _list.removeWhere((p) => p.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("삭제 실패: $e");
      return false;
    }
  }

  /// [실시간 구독] 서버의 데이터 변경을 실시간으로 감시하여 반영
  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) {
      if (_isDisposed || _isSaving) return;
      if (e.record == null) return;

      if (e.action == 'create') {
        if (!_list.any((p) => p.id == e.record!.id)) {
          _list.insert(0, Person.fromRecord(e.record!));
        }
      } else if (e.action == 'update') {
        int idx = _list.indexWhere((p) => p.id == e.record!.id);
        if (idx != -1) {
          _list[idx] = Person.fromRecord(e.record!);
        }
      } else if (e.action == 'delete') {
        _list.removeWhere((p) => p.id == e.record!.id);
      }
      notifyListeners();
    });
  }
}