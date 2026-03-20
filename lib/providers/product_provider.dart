import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:pocketbase/pocketbase.dart';

import '../models/product_model.dart';
import '../core/pocketbase_client.dart';

/// ---------------------------------------------------------------------------
/// [엑셀 파싱 전용 백그라운드 워커 (Isolate)]
/// 메인 UI 스레드의 프리징을 방지하기 위해 엑셀 데이터를 독립된 메모리 공간에서 분석합니다.
/// ---------------------------------------------------------------------------
Map<String, dynamic>? _parseProductExcel(Uint8List bytes) {
  try {
    var excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      return null;
    }

    String sheetName = excel.tables.keys.first;
    var table = excel.tables[sheetName]!;
    if (table.maxRows < 1) {
      return null;
    }

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
/// [물품 관리 전역 상태 제공자 (ProductProvider)]
/// 애플리케이션의 비즈니스 로직과 데이터 상태를 관장하는 핵심 모듈입니다.
/// ---------------------------------------------------------------------------
class ProductProvider extends ChangeNotifier {
  final PocketBase _pb = pb;

  final String _collectionName = 'products';
  final String _configCollection = 'app_configs';
  final String _columnConfigKey = 'product_list_columns';

  List<ProductModel> _items = [];
  List<String> _selectedColumns = [];

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isParsing = false;
  bool _isDisposed = false;
  bool _isInitialized = false;

  List<ProductModel> get items => _items;
  List<String> get selectedColumns => _selectedColumns;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isParsing => _isParsing;

  ProductProvider() {
    _initProvider();
  }

  Future<void> _initProvider() async {
    if (_isInitialized) {
      return;
    }

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

  Future<void> _safeUnsubscribe() async {
    try {
      await _pb.collection(_collectionName).unsubscribe('*');
    } catch (_) {}
  }

  Future<void> fetchData() async {
    if (_isDisposed) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final records = await _pb.collection(_collectionName).getFullList(
        sort: '-created',
      );

      if (_isDisposed) {
        return;
      }

      _items = records.map((r) => ProductModel.fromRecord(r)).toList();
      debugPrint("물품 데이터 로드 성공: ${_items.length}건");
    } catch (e) {
      debugPrint("물품 데이터 로드 중 에러: $e");
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> handleSave({
    required ProductModel? product,
    required Map<String, dynamic> data,
    XFile? imageXFile,
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
        files.add(http.MultipartFile.fromBytes(
            'image', // Product에서는 avatar대신 image 사용
            bytes,
            filename: imageXFile.name
        ));
      }

      RecordModel record;

      if (product == null) {
        record = await _pb.collection(_collectionName).create(body: data, files: files);
        _items.insert(0, ProductModel.fromRecord(record));
      } else {
        record = await _pb.collection(_collectionName).update(product.id, body: data, files: files);
        int index = _items.indexWhere((item) => item.id == product.id);
        if (index != -1) {
          _items[index] = ProductModel.fromRecord(record);
        }
      }

      notifyListeners();
      return true;

    } catch (e) {
      if (e is ClientException) {
        debugPrint("\n===================================================");
        debugPrint("❌ Product DB 저장 거부 (ClientException) ❌");
        debugPrint("상태 코드: ${e.statusCode}");
        debugPrint("응답 내용: ${e.response}");
        debugPrint("===================================================\n");
      } else {
        debugPrint("❌ 물품 저장 중 알 수 없는 에러 발생: $e");
      }
      return false;
    } finally {
      if (!_isDisposed) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  Future<int> batchImportFromExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null) {
        return 0;
      }

      _isParsing = true;
      notifyListeners();

      Uint8List bytes;
      if (kIsWeb) {
        bytes = result.files.single.bytes!;
      } else {
        bytes = await File(result.files.single.path!).readAsBytes();
      }

      final parsedData = await compute(_parseProductExcel, bytes);

      if (parsedData == null || parsedData['details'] == null) {
        _isParsing = false;
        notifyListeners();
        return 0;
      }

      List<Map<String, dynamic>> rows = List<Map<String, dynamic>>.from(parsedData['details']);
      int successCount = 0;
      int errorCount = 0;

      _isParsing = false;
      _isSaving = true;
      notifyListeners();

      for (var row in rows) {
        try {
          String name = _getExcelValue(row, ['품명', '이름', 'Name', '제품명', '자산명']);
          String tagId = _getExcelValue(row, ['태그ID', 'RFID', 'UID', 'tag_id']);
          String tagEpc = _getExcelValue(row, ['EPC', '태그EPC', 'tag_epc']);
          String location = _getExcelValue(row, ['위치', '로케이션', '보관장소']);
          String category = _getExcelValue(row, ['분류', '카테고리']);
          String status = _getExcelValue(row, ['상태', 'status']);

          if (location.isEmpty) {
            location = "미지정";
          }
          if (category.isEmpty) {
            category = "미지정";
          }
          if (status.isEmpty) {
            status = "보유중";
          }

          if (name.isNotEmpty) {
            final body = {
              'name': name,
              'tag_id': tagId,
              'tag_epc': tagEpc,
              'location': location,
              'category': category,
              'status': status,
              'is_active': true,
              'metadata': {
                'import_source': 'excel',
                'original_row_data': row
              }
            };
            await _pb.collection(_collectionName).create(body: body);
            successCount++;
          } else {
            // [형식 오류 데이터] - 누락된 건을 버리지 않고 '형식에 맞지 않는 건'으로 저장
            final errorBody = {
              'name': '형식에 맞지 않는 건',
              'tag_id': tagId,
              'tag_epc': tagEpc,
              'location': location,
              'status': '수기입고', // 비정상 상태임을 알 수 있도록 임의의 상태 지정
              'metadata': {
                'import_source': 'excel_error',
                'error_reason': '품명(또는 제품명) 항목 누락',
                'original_row_data': row
              }
            };
            await _pb.collection(_collectionName).create(body: errorBody);
            errorCount++;
          }
        } catch (error) {
          if (kDebugMode) {
            print('엑셀 단일 행 저장 실패: $error');
          }
          errorCount++;
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

  Future<bool> deleteMultipleProducts(List<String> ids) async {
    if (_isDisposed) {
      return false;
    }

    try {
      await Future.wait(ids.map((id) => _pb.collection(_collectionName).delete(id)));

      _items.removeWhere((p) => ids.contains(p.id));
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("물품 다중 삭제 실패: $e");
      return false;
    }
  }

  Future<bool> resetAllProducts() async {
    if (_isDisposed) {
      return false;
    }

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

      _items = [];
      _selectedColumns = [];
      return true;
    } catch (e) {
      debugPrint("물품 데이터 초기화 오류: $e");
      return false;
    } finally {
      if (!_isDisposed) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

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
        _selectedColumns = ['품명', '태그ID', 'EPC', '위치', '상태', '규격', '분류', 'S/N']; // EPC 추가
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

  void _subscribe() {
    _pb.collection(_collectionName).subscribe('*', (e) {
      if (_isDisposed || _isSaving) {
        return;
      }

      if (e.record == null) {
        return;
      }

      if (e.action == 'create') {
        if (!_items.any((p) => p.id == e.record!.id)) {
          _items.insert(0, ProductModel.fromRecord(e.record!));
        }
      } else if (e.action == 'update') {
        int idx = _items.indexWhere((p) => p.id == e.record!.id);
        if (idx != -1) {
          _items[idx] = ProductModel.fromRecord(e.record!);
        }
      } else if (e.action == 'delete') {
        _items.removeWhere((p) => p.id == e.record!.id);
      }

      notifyListeners();
    });
  }
}