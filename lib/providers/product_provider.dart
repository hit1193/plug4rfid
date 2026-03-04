import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:pocketbase/pocketbase.dart';

import '../models/products.dart';
import '../services/pb_service.dart';

/// 엑셀 파싱 Isolate 함수
Map<String, dynamic>? _parseProductExcel(Uint8List bytes) {
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
    return {"count": rows.length, "details": rows};
  } catch (e) {
    return null;
  }
}

class ProductProvider extends ChangeNotifier {
  final String _collectionName = 'products';
  final String _configCollection = 'app_configs';
  final String _columnConfigKey = 'product_list_columns';

  List<ProductModel> _items = [];
  List<String> _selectedColumns = ['품명', '태그ID', '위치', '상태'];
  bool _isLoading = false, _isSaving = false, _isParsing = false, _isDisposed = false, _isInitialized = false;

  List<ProductModel> get items => _items;
  List<String> get selectedColumns => _selectedColumns;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isParsing => _isParsing;

  static const List<String> allStatus = ['정상', '구매입고', '회수/반납', '수기입고', '판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'];

  ProductProvider() {
    _initProvider();
  }

  Future<void> _initProvider() async {
    if (_isInitialized) return;
    await fetchRemoteSettings();
    await fetchData();
    _subscribe(); // [핵심] 실시간 구독 시작
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
      await PBService.pb.collection(_collectionName).unsubscribe('*');
    } catch (_) {}
  }

  // 실시간 구독 설정
  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) {
      if (_isDisposed || _isSaving) return;
      // 서버에서 데이터 변경 이벤트(create, update, delete) 발생 시 실행
      fetchData();
    });
  }

  Future<void> fetchData() async {
    if (_isDisposed) return;
    _isLoading = true;
    notifyListeners();
    try {
      final records = await PBService.pb.collection(_collectionName).getFullList(sort: '-updated');
      if (_isDisposed) return;
      _items = records.map((r) => ProductModel.fromJson({...r.data, 'id': r.id, 'created': r.created, 'updated': r.updated})).toList();
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> fetchRemoteSettings() async {
    try {
      final record = await PBService.pb.collection(_configCollection).getFirstListItem('key = "$_columnConfigKey"');
      final dynamic val = record.data['value'];
      if (val is List) {
        _selectedColumns = val.map((e) => e.toString()).toList();
        notifyListeners();
      }
    } catch (_) {}
  }

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
    } catch (_) {}
  }

  Future<bool> handleSave({required ProductModel? p, required Map<String, dynamic> data, XFile? imageXFile}) async {
    _isSaving = true;
    notifyListeners();
    try {
      List<http.MultipartFile> files = [];
      if (imageXFile != null) {
        final bytes = await imageXFile.readAsBytes();
        files.add(http.MultipartFile.fromBytes('image', bytes, filename: imageXFile.name));
      }
      if (p == null) {
        await PBService.pb.collection(_collectionName).create(body: data, files: files);
      } else {
        await PBService.pb.collection(_collectionName).update(p.id, body: data, files: files);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      _isSaving = false;
      // 구독 로직이 fetchData를 호출하겠지만, 즉각적인 반응을 위해 여기서도 호출 가능
      await fetchData();
    }
  }

  Future<void> deleteMultipleProducts(List<String> ids) async {
    _isSaving = true;
    notifyListeners();
    try {
      for (var id in ids) {
        await PBService.pb.collection(_collectionName).delete(id);
      }
    } finally {
      _isSaving = false;
      await fetchData();
    }
  }

  Future<void> resetAllProducts() async {
    _isSaving = true;
    notifyListeners();
    try {
      final records = await PBService.pb.collection(_collectionName).getFullList(fields: 'id');
      for (var r in records) {
        await PBService.pb.collection(_collectionName).delete(r.id);
      }
      _items = [];
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<Map<String, int>> batchImportFromExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
      if (result == null) return {'success': 0, 'total': 0};

      _isParsing = true;
      notifyListeners();

      Uint8List bytes = kIsWeb ? result.files.single.bytes! : await File(result.files.single.path!).readAsBytes();
      final parsed = await compute(_parseProductExcel, bytes);

      _isParsing = false;
      if (parsed == null) {
        notifyListeners();
        return {'success': 0, 'total': 0};
      }

      _isSaving = true;
      notifyListeners();

      List<Map<String, dynamic>> rows = List<Map<String, dynamic>>.from(parsed['details']);
      int success = 0;

      for (var row in rows) {
        try {
          final body = {
            'name': row['품명'] ?? row['제품명'] ?? '이름없음',
            'tag_id': row['태그ID'] ?? row['RFID'] ?? '',
            'location': row['위치'] ?? '미지정',
            'status': '정상',
            'metadata': {'import_source': 'excel', 'original_row_data': row}
          };
          await PBService.pb.collection(_collectionName).create(body: body);
          success++;
        } catch (_) {}
      }

      _isSaving = false;
      await fetchData();
      return {'success': success, 'total': rows.length};
    } catch (_) {
      _isParsing = false;
      _isSaving = false;
      notifyListeners();
      return {'success': 0, 'total': 0};
    }
  }
}