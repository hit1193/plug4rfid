import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/products.dart';
import '../services/pb_service.dart';

class ProductProvider extends ChangeNotifier {
  final String _collectionName = 'products';
  final String _prefKey = "selected_columns_v1";

  List<ProductModel> _items = [];
  List<String> _selectedColumns = ['품명', '태그ID', '위치', '상태'];

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isParsing = false;
  bool _isDisposed = false;

  List<ProductModel> get items => _items;
  List<String> get selectedColumns => _selectedColumns;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isParsing => _isParsing;

  String _lastScannedTag = "";
  String get lastScannedTag => _lastScannedTag;

  ProductProvider() {
    _initProvider();
  }

  Future<void> _initProvider() async {
    await _loadSettings();
    await fetchData();
    _subscribe();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _unsubscribe();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? saved = prefs.getStringList(_prefKey);
      if (saved != null && saved.isNotEmpty) {
        _selectedColumns = saved;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("⚠️ 설정 로드 실패: $e");
    }
  }

  Future<void> saveRemoteSettings(List<String> newColumns) async {
    _selectedColumns = List.from(newColumns);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, _selectedColumns);
    } catch (e) {
      debugPrint("⚠️ 설정 저장 실패: $e");
    }
  }

  Future<void> fetchData() async {
    if (_isDisposed) return;
    _isLoading = true;
    notifyListeners();
    try {
      final records = await PBService.pb.collection(_collectionName).getFullList(sort: '-created');
      _items = records.map((r) => ProductModel.fromJson(r.toJson())).toList();
    } catch (e) {
      debugPrint("❌ 데이터 로드 에러: $e");
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void _subscribe() {
    try {
      PBService.pb.collection(_collectionName).subscribe('*', (e) {
        fetchData();
      });
    } catch (e) {
      debugPrint("❌ 실시간 구독 실패: $e");
    }
  }

  Future<void> _unsubscribe() async {
    try {
      await PBService.pb.collection(_collectionName).unsubscribe('*');
    } catch (e) {
      debugPrint("❌ 구독 해제 에러: $e");
    }
  }

  void setLastScannedTag(String tag) {
    _lastScannedTag = tag;
    notifyListeners();
  }

  void clearLastScannedTag() {
    _lastScannedTag = "";
    notifyListeners();
  }

  ProductModel? findProductByTag(String tag) {
    try {
      return _items.firstWhere((p) => p.tagId.trim().toLowerCase() == tag.trim().toLowerCase());
    } catch (_) {
      return null;
    }
  }

  Future<bool> handleSave({required ProductModel? p, required Map<String, dynamic> data, XFile? imageXFile}) async {
    if (_isDisposed) return false;
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
      await fetchData();
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

  Future<bool> deleteProduct(String id) async {
    try {
      await PBService.pb.collection(_collectionName).delete(id);
      await fetchData();
      return true;
    } catch (e) { return false; }
  }

  /// [핵심 추가] 여러 개의 ID를 순차적으로 삭제하는 일괄 삭제 메서드
  Future<void> deleteMultipleProducts(List<String> ids) async {
    if (_isDisposed || ids.isEmpty) return;
    _isLoading = true;
    notifyListeners();
    try {
      // PocketBase는 단일 트랜잭션 벌크 삭제를 기본 제공하지 않으므로 루프로 처리
      // C++의 for(int i=0; i<ids.length; i++)와 동일한 로직
      for (var id in ids) {
        await PBService.pb.collection(_collectionName).delete(id);
      }
      await fetchData();
    } catch (e) {
      debugPrint("❌ 일괄 삭제 중 에러: $e");
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> resetAllProducts() async {
    _isLoading = true;
    notifyListeners();
    try {
      for (var item in _items) {
        await PBService.pb.collection(_collectionName).delete(item.id);
      }
      await fetchData();
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<Map<String, int>> batchImportFromExcel() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
    if (result == null) return {'total': 0, 'success': 0, 'failed': 0};
    _isParsing = true;
    notifyListeners();
    int success = 0; int total = 0;
    try {
      final bytes = File(result.files.single.path!).readAsBytesSync();
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);
      for (var table in decoder.tables.keys) {
        final sheet = decoder.tables[table]!;
        if (sheet.maxRows < 2) continue;
        for (int i = 1; i < sheet.maxRows; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty || row.every((e) => e == null)) continue;
          total++;
          final Map<String, dynamic> data = {
            'name': row[0]?.toString() ?? "Unnamed",
            'tag_id': row.length > 4 ? row[4]?.toString() ?? "" : "T-${DateTime.now().millisecond}-$i",
            'status': '정상',
            'metadata': { 'import_date': DateTime.now().toIso8601String() }
          };
          await PBService.pb.collection(_collectionName).create(body: data);
          success++;
        }
      }
    } catch (e) {
      debugPrint("❌ 엑셀 임포트 오류: $e");
    } finally {
      _isParsing = false;
      await fetchData();
    }
    return {'total': total, 'success': success, 'failed': total - success};
  }
}