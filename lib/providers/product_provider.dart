import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../models/products.dart';
import '../services/pb_service.dart';

/// 자산(Product) 데이터의 상태 관리 및 비즈니스 로직을 담당하는 클래스
class ProductProvider extends ChangeNotifier {
  final String _collectionName = 'products';
  final String _prefKey = "selected_columns_v1";

  List<ProductModel> _items = [];
  List<String> _selectedColumns = ['규격', '제조사', '위치', 'S/N'];

  bool _isLoading = false;
  bool _isSaving = false;

  // 아래 필드들은 런타임에 상태가 변경되므로 final을 사용할 수 없습니다.
  // _isParsing: 엑셀 분석 진행 상태를 UI에 전달하기 위한 플래그
  bool _isParsing = false;
  // _isDisposed: 비동기 작업 중 객체 파괴 여부를 확인하여 런타임 에러를 방지하는 가드
  bool _isDisposed = false;

  List<String> _errorHeaders = [];
  List<Map<String, dynamic>> _lastErrors = [];

  List<ProductModel> get items => _items;
  List<String> get selectedColumns => _selectedColumns;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isParsing => _isParsing;
  List<String> get errorHeaders => _errorHeaders;
  List<Map<String, dynamic>>? get lastErrors => _lastErrors.isEmpty ? null : _lastErrors;

  String _lastScannedTag = "";
  String get lastScannedTag => _lastScannedTag;

  ProductProvider() {
    _initProvider();
  }

  /// 초기화 시퀀스
  Future<void> _initProvider() async {
    await _loadSettings();
    await fetchData();
    _subscribe();
  }

  @override
  void dispose() {
    _isDisposed = true; // 객체 파기 시 상태 변경 (final 불가)
    _unsubscribe();
    super.dispose();
  }

  /// 로컬 저장소에서 사용자 설정 로드
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefKey);
      if (saved != null && saved.isNotEmpty) {
        _selectedColumns = saved;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("⚠️ 설정 로드 실패: $e");
    }
  }

  /// 설정 저장
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
      return _items.firstWhere(
              (p) => p.tagId.trim().toLowerCase() == tag.trim().toLowerCase()
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> handleSave({
    required ProductModel? p,
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

      if (p == null) {
        await PBService.pb.collection(_collectionName).create(body: data, files: files);
      } else {
        await PBService.pb.collection(_collectionName).update(p.id, body: data, files: files);
      }

      await fetchData();
      return true;
    } catch (e) {
      debugPrint("❌ 폼 저장 에러: $e");
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
    } catch (e) {
      return false;
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result == null) return {'total': 0, 'success': 0, 'failed': 0};

    _isParsing = true; // 파싱 시작 상태로 변경 (final 불가)
    _lastErrors = [];
    _errorHeaders = [];
    notifyListeners();

    int success = 0;
    int failed = 0;
    int total = 0;

    try {
      final bytes = File(result.files.single.path!).readAsBytesSync();
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);

      for (var table in decoder.tables.keys) {
        final sheet = decoder.tables[table]!;
        if (sheet.maxRows < 2) continue;

        final rawHeaders = sheet.rows[0].map((e) => e?.toString().trim() ?? "").toList();
        _errorHeaders = List<String>.from(rawHeaders);

        for (int i = 1; i < sheet.maxRows; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty || row.every((e) => e == null)) continue;

          total++;
          try {
            final Map<String, dynamic> data = {
              'name': row[0]?.toString() ?? "Unnamed",
              'tag_id': row.length > 4 ? row[4]?.toString() ?? "" : "T-${DateTime.now().millisecond}-$i",
              'status': '정상',
              'metadata': { 'import_date': DateTime.now().toIso8601String() }
            };

            await PBService.pb.collection(_collectionName).create(body: data);
            success++;
          } catch (e) {
            failed++;
            _lastErrors.add({
              'originalRow': row.map((cell) => cell?.toString() ?? "").toList(),
              'errorMsg': e.toString(),
            });
          }
        }
      }
    } catch (e) {
      debugPrint("❌ 엑셀 치명적 오류: $e");
    } finally {
      _isParsing = false; // 파싱 종료 상태로 복구 (final 불가)
      await fetchData();
    }
    return {'total': total, 'success': success, 'failed': failed};
  }
}