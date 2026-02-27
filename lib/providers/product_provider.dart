import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../models/products.dart';
import '../services/pb_service.dart';

class ProductProvider extends ChangeNotifier {
  final String _collectionName = 'products';
  List<ProductModel> _items = [];
  final List<String> _selectedColumns = ['category', 'location', 'spec', 'remarks'];

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isParsing = false;
  bool _isDisposed = false;

  bool _hasError = false;
  String _errorMessage = "";
  String _lastScannedTag = "";

  List<ProductModel> get items => _items;
  List<String> get selectedColumns => _selectedColumns;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isParsing => _isParsing;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  String get lastScannedTag => _lastScannedTag;

  ProductProvider() {
    fetchData();
    _subscribe();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _unsubscribe();
    super.dispose();
  }

  Future<void> _unsubscribe() async {
    try {
      await PBService.pb.collection(_collectionName).unsubscribe('*');
    } catch (e) {
      debugPrint("❌ 구독 해제 에러: $e");
    }
  }

  Future<void> fetchData() async {
    if (_isDisposed) {
      return;
    }

    _isLoading = true;
    _hasError = false;
    _errorMessage = "";
    notifyListeners();

    try {
      debugPrint("📡 데이터 로딩 시작... (Collection: $_collectionName)");
      final records = await PBService.pb.collection(_collectionName).getFullList(
        sort: '-created',
      );
      _items = records.map((r) => ProductModel.fromJson(r.toJson())).toList();
      debugPrint("✅ 데이터 로드 성공: ${_items.length}건");
    } catch (e) {
      _hasError = true;
      if (e is ClientException) {
        _errorMessage = "서버 에러 (${e.statusCode}): ${e.response['message'] ?? e.toString()}";
      } else {
        _errorMessage = "연결 에러: $e";
      }
      debugPrint("❌ 물품 로드 에러 상세: $_errorMessage");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _subscribe() {
    try {
      PBService.pb.collection(_collectionName).subscribe('*', (e) {
        debugPrint("🔔 실시간 업데이트 감지: ${e.action}");
        fetchData();
      });
    } catch (e) {
      debugPrint("❌ 실시간 구독 실패: $e");
    }
  }

  Future<void> refresh() async {
    await fetchData();
  }

  void setLastScannedTag(String tag) {
    _lastScannedTag = tag;
    notifyListeners();
  }

  void clearLastScannedTag() => _lastScannedTag = "";

  ProductModel? findProductByTag(String tag) {
    try {
      return _items.firstWhere((p) => p.tagId == tag);
    } catch (_) {
      return null;
    }
  }

  void updateColumns(List<String> cols) {
    _selectedColumns.clear();
    _selectedColumns.addAll(cols);
    notifyListeners();
  }

  Future<bool> handleSave({
    required ProductModel? p,
    required Map<String, dynamic> data,
    XFile? imageXFile,
  }) async {
    if (_isDisposed) {
      return false;
    }
    _isSaving = true;
    notifyListeners();
    try {
      Uint8List? fileBytes;
      if (imageXFile != null) {
        fileBytes = await imageXFile.readAsBytes();
      }

      List<http.MultipartFile> files = [];
      if (fileBytes != null) {
        files.add(http.MultipartFile.fromBytes('image', fileBytes, filename: imageXFile!.name));
      }

      if (p == null) {
        await PBService.pb.collection(_collectionName).create(body: data, files: files);
      } else {
        await PBService.pb.collection(_collectionName).update(p.id, body: data, files: files);
      }
      return true;
    } catch (e) {
      debugPrint("❌ 저장 실패 상세: $e");
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> deleteProduct(String id) async {
    try {
      await PBService.pb.collection(_collectionName).delete(id);
      fetchData();
      return true;
    } catch (e) {
      debugPrint("❌ 삭제 실패: $e");
      return false;
    }
  }

  Future<void> resetAllProducts() async {
    if (_isDisposed) {
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      debugPrint("🧹 모든 제품 삭제 시작...");
      for (var item in _items) {
        if (_isDisposed) {
          break;
        }
        await PBService.pb.collection(_collectionName).delete(item.id);
      }
      await fetchData();
    } catch (e) {
      debugPrint("❌ 초기화 실패: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, int>> batchImportFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result == null) {
      return {'total': 0, 'success': 0, 'failed': 0};
    }

    _isParsing = true;
    notifyListeners();

    int successCount = 0;
    int failedCount = 0;
    int totalRows = 0;

    try {
      final bytes = File(result.files.single.path!).readAsBytesSync();
      final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);

      final nameKeys = ['명칭', '이름', '품명', '성명', '제품명', 'name'];
      final tagKeys = ['태그', 'tag', 'rfid', 'epc', '번호'];
      final memoKeys = ['참고', '메모', '비고', 'memo', 'remarks'];
      final locKeys = ['위치', '보관', '사용위치', 'location'];
      final catKeys = ['분류', '키워드', '카테고리', 'category'];
      final specKeys = ['규격', '모델', 'spec'];

      for (var table in decoder.tables.keys) {
        final sheet = decoder.tables[table]!;
        if (sheet.maxRows < 2) {
          continue;
        }

        final List<String> rawHeaders = sheet.rows[0].map((e) => e?.toString().trim() ?? "").toList();
        final List<String> headers = rawHeaders.map((e) => e.toLowerCase()).toList();
        debugPrint("📂 분석 시트: $table, 헤더: $rawHeaders");

        int nameIdx = -1, tagIdx = -1, memoIdx = -1, locIdx = -1, catIdx = -1, specIdx = -1;

        for (int i = 0; i < headers.length; i++) {
          String h = headers[i];
          if (nameKeys.any((k) => h.contains(k))) { nameIdx = i; }
          if (tagKeys.any((k) => h.contains(k))) { tagIdx = i; }
          if (memoKeys.any((k) => h.contains(k))) { memoIdx = i; }
          if (locKeys.any((k) => h.contains(k))) { locIdx = i; }
          if (catKeys.any((k) => h.contains(k))) { catIdx = i; }
          if (specKeys.any((k) => h.contains(k))) { specIdx = i; }
        }

        debugPrint("🎯 매칭 결과 - 이름:$nameIdx, 태그:$tagIdx, 위치:$locIdx, 분류:$catIdx");

        if (tagIdx == -1) {
          debugPrint("⚠️ 태그ID(RFID) 컬럼을 찾지 못해 이 시트는 건너뜁니다.");
          continue;
        }

        for (int i = 1; i < sheet.maxRows; i++) {
          if (_isDisposed) {
            break;
          }
          final row = sheet.rows[i];
          if (row.isEmpty || row.every((element) => element == null)) {
            continue;
          }

          totalRows++;

          final String tagVal = tagIdx != -1 && row.length > tagIdx ? row[tagIdx]?.toString().trim() ?? "" : "";

          if (tagVal.isEmpty) {
            failedCount++;
            continue;
          }

          final String nameVal = nameIdx != -1 && row.length > nameIdx ? row[nameIdx]?.toString() ?? "" : "";
          final String memoVal = memoIdx != -1 && row.length > memoIdx ? row[memoIdx]?.toString() ?? "" : "";
          final String locVal = locIdx != -1 && row.length > locIdx ? row[locIdx]?.toString() ?? "" : "";
          final String catVal = catIdx != -1 && row.length > catIdx ? row[catIdx]?.toString() ?? "" : "";
          final String specVal = specIdx != -1 && row.length > specIdx ? row[specIdx]?.toString() ?? "" : "";

          final existing = findProductByTag(tagVal);

          final Map<String, dynamic> metadataMap = {};
          final usedIndices = [nameIdx, tagIdx, memoIdx, locIdx, catIdx, specIdx];
          for (int c = 0; c < row.length; c++) {
            if (!usedIndices.contains(c) && c < rawHeaders.length) {
              metadataMap[rawHeaders[c]] = row[c]?.toString() ?? "";
            }
          }

          final data = {
            'name': nameVal.isNotEmpty ? nameVal : "Unnamed",
            'tag_id': tagVal,
            'category': catVal,
            'location': locVal,
            'spec': specVal,
            'remarks': memoVal,
            'quantity': 1,
            'status': '정상',
            'metadata': metadataMap,
          };

          try {
            if (existing != null) {
              await PBService.pb.collection(_collectionName).update(existing.id, body: data);
            } else {
              await PBService.pb.collection(_collectionName).create(body: data);
            }
            successCount++;
          } catch (e) {
            debugPrint("❌ 저장 실패 ($tagVal): $e");
            failedCount++;
          }
        }
      }
    } catch (e) {
      debugPrint("❌ 엑셀 파싱 에러: $e");
    } finally {
      _isParsing = false;
      fetchData();
    }

    return {'total': totalRows, 'success': successCount, 'failed': failedCount};
  }
}