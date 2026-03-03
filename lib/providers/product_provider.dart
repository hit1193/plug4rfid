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

class ProductProvider extends ChangeNotifier {
  final String _collectionName = 'products';
  final String _prefKey = "selected_columns_v1";

  List<ProductModel> _items = [];
  final List<String> _defaultColumns = ['품명', '태그ID', '위치', '상태'];
  List<String> _selectedColumns = ['품명', '태그ID', '위치', '상태'];

  List<Map<String, dynamic>> _failedRows = [];

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isParsing = false;
  bool _isDisposed = false;

  // --- FA 솔루션 비즈니스 로직: 입/출고 사유 정의 ---
  static const Map<String, List<String>> inventoryReasons = {
    '입고': ['구매입고', '회수/반납', '이동입고', '재고조정(입고)', '기타입고'],
    '출고': ['판매출고', '수리출고', '대여출고', '폐기', '분실', '재고조정(출고)', '기타출고'],
  };

  static List<String> get allStatus => [
    '정상',
    ...inventoryReasons['입고']!,
    ...inventoryReasons['출고']!,
  ];

  // Getters
  List<ProductModel> get items => _items;
  List<String> get selectedColumns => _selectedColumns;
  List<Map<String, dynamic>> get failedRows => _failedRows;
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

  // --- 설정 관리 (SharedPreferences) ---
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

  // --- 데이터 통신 (PocketBase) ---
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

  // --- RFID 처리 로직 ---
  void setLastScannedTag(String tag) {
    if (tag.isEmpty || tag == _lastScannedTag) return;
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

  // --- CRUD 비즈니스 로직 ---
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
      debugPrint("❌ 저장 실패: $e");
      return false;
    } finally {
      if (!_isDisposed) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  Future<void> deleteMultipleProducts(List<String> ids) async {
    if (_isDisposed || ids.isEmpty) return;
    _isLoading = true;
    notifyListeners();
    try {
      for (var id in ids) {
        await PBService.pb.collection(_collectionName).delete(id);
      }
      await fetchData();
    } catch (e) {
      debugPrint("❌ 일괄 삭제 오류: $e");
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// [유지] 데이터 및 로컬 설정(사용자 컬럼)까지 모두 초기화
  Future<void> resetAllProducts() async {
    _isLoading = true;
    notifyListeners();
    try {
      for (var item in _items) {
        await PBService.pb.collection(_collectionName).delete(item.id);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
      _selectedColumns = List.from(_defaultColumns);
      await fetchData();
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// [스마트 매핑 도우미] 헤더 이름으로 인덱스를 찾습니다.
  int _findIdx(List<dynamic> headers, List<String> keywords) {
    for (int i = 0; i < headers.length; i++) {
      String h = headers[i]?.toString().trim() ?? "";
      if (keywords.any((k) => h.contains(k))) return i;
    }
    return -1;
  }

  // --- [핵심 복구 및 확장] 스마트 헤더 매핑 + 동적 메타데이터 ---
  Future<Map<String, int>> batchImportFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return {'total': 0, 'success': 0, 'failed': 0};

    _isParsing = true;
    _failedRows.clear();
    notifyListeners();

    int success = 0;
    int total = 0;

    try {
      final bytes = result.files.single.bytes ?? File(result.files.single.path!).readAsBytesSync();
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);

      for (var table in decoder.tables.keys) {
        final sheet = decoder.tables[table]!;
        if (sheet.maxRows < 2) continue;

        // 헤더 행 분석
        final headerRow = sheet.rows[0];

        // [수정] "명칭" 키워드 추가하여 품명으로 매핑되도록 강화
        int nameIdx = _findIdx(headerRow, ['품명', '명칭', '이름', '제품', 'Name']);
        int tagIdx = _findIdx(headerRow, ['태그', 'RFID', 'Tag', 'EPC', 'ID']);
        int locIdx = _findIdx(headerRow, ['위치', '장소', '창고', 'Location']);
        int catIdx = _findIdx(headerRow, ['분류', '카테고리', '구분', 'Category']);
        int specIdx = _findIdx(headerRow, ['규격', '형식', 'Spec']);
        int manIdx = _findIdx(headerRow, ['제조사', 'Maker', 'Manufacturer']);
        int snIdx = _findIdx(headerRow, ['시리얼', 'SN', 'Serial']);

        for (int i = 1; i < sheet.maxRows; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty || (nameIdx != -1 && nameIdx < row.length && row[nameIdx] == null)) continue;

          total++;

          // 태그 ID 처리
          String tagId = (tagIdx != -1 && tagIdx < row.length && row[tagIdx] != null)
              ? row[tagIdx].toString().trim() : "";
          if (tagId.isEmpty) {
            tagId = "PENDING_${DateTime.now().millisecondsSinceEpoch}_$i";
          }

          // 데이터 매핑
          final Map<String, dynamic> data = {
            'name': nameIdx != -1 && nameIdx < row.length ? row[nameIdx]?.toString().trim() ?? "Unnamed" : "Unnamed",
            'tag_id': tagId,
            'location': locIdx != -1 && locIdx < row.length ? row[locIdx]?.toString().trim() ?? "미지정" : "미지정",
            'category': catIdx != -1 && catIdx < row.length ? row[catIdx]?.toString().trim() ?? "" : "",
            'spec': specIdx != -1 && specIdx < row.length ? row[specIdx]?.toString().trim() ?? "" : "",
            'manufacturer': manIdx != -1 && manIdx < row.length ? row[manIdx]?.toString().trim() ?? "" : "",
            'serial_number': snIdx != -1 && snIdx < row.length ? row[snIdx]?.toString().trim() ?? "" : "",
            'status': '정상',
          };

          // [수정] UI 노출 제외 필드를 제외하고 메타데이터 구성
          final Map<String, dynamic> metadata = {
            'import_date_internal': DateTime.now().toIso8601String(), // 내부 관리용 키 이름 변경
            'is_auto_tag_internal': tagId.startsWith("PENDING_"),
            'excel_row_internal': i + 1
          };

          for (int colIdx = 0; colIdx < row.length; colIdx++) {
            if (colIdx < headerRow.length && headerRow[colIdx] != null) {
              String headerName = headerRow[colIdx].toString().trim();

              // [핵심] 사용자가 요청한 제외 필드 필터링 (표시 방지)
              if (headerName == 'excel_row' ||
                  headerName == 'import_date' ||
                  headerName == 'is_auto_tag') {
                continue;
              }

              metadata[headerName] = row[colIdx]?.toString().trim() ?? "";
            }
          }
          data['metadata'] = metadata;

          try {
            await PBService.pb.collection(_collectionName).create(body: data);
            success++;
          } catch (e) {
            _failedRows.add({
              'row': i + 1,
              'name': data['name'],
              'error': e.toString(),
            });
            debugPrint("⚠️ 행 ${i + 1} 생성 실패: $e");
          }
        }
        break;
      }
    } catch (e) {
      debugPrint("❌ 엑셀 처리 치명적 오류: $e");
    } finally {
      _isParsing = false;
      await fetchData();
      notifyListeners();
    }
    return {'total': total, 'success': success, 'failed': _failedRows.length};
  }
}