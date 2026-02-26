import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../models/products.dart';
import '../services/pb_service.dart';

class ProductProvider extends ChangeNotifier {
  final String _collectionName = 'products';
  List<ProductModel> _items = [];

  // [수정] 참조 변경이 필요 없으므로 final로 선언
  final List<String> _selectedColumns = ['category', 'location', 'spec', 'remarks'];

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isParsing = false;
  bool _isDisposed = false;
  String _lastScannedTag = "";

  List<ProductModel> get items => _items;
  List<String> get selectedColumns => _selectedColumns;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isParsing => _isParsing;
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
      debugPrint("구독 해제 에러: $e");
    }
  }

  Future<void> fetchData() async {
    if (_isDisposed) {
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      final records = await PBService.pb.collection(_collectionName).getFullList(sort: '-created');
      _items = records.map((r) => ProductModel.fromJson(r.toJson())).toList();
    } catch (e) {
      debugPrint("물품 로드 에러: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) => fetchData());
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

  // [수정] final 리스트이므로 내부 값을 비우고 새로 채우는 방식 채택
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
      debugPrint("저장 실패: $e");
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
      return false;
    }
  }

  Future<void> resetAllProducts() async {
    _isLoading = true;
    notifyListeners();
    try {
      for (var item in _items) {
        if (_isDisposed) {
          break;
        }
        await PBService.pb.collection(_collectionName).delete(item.id);
      }
      fetchData();
    } catch (e) {
      debugPrint("초기화 실패: $e");
    }
  }

  Future<Map<String, int>> batchImportFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx']
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

      final nameKeys = ['이름', '품명', '성명', '제품명', 'name'];
      final tagKeys = ['태그ID', 'TAGID', 'EPC', 'tag_id'];
      final memoKeys = ['참고사항', '메모', '비고', 'memo', 'remarks'];
      final locKeys = ['위치', '보관위치', 'location'];
      final catKeys = ['분류', '카테고리', 'category'];
      final specKeys = ['규격', '모델명', 'spec'];

      for (var table in decoder.tables.keys) {
        final sheet = decoder.tables[table]!;
        if (sheet.maxRows < 2) {
          continue;
        }

        final List<String> headers = sheet.rows[0].map((e) => e?.toString().trim() ?? "").toList();

        int nameIdx = -1, tagIdx = -1, memoIdx = -1, locIdx = -1, catIdx = -1, specIdx = -1;

        for (int i = 0; i < headers.length; i++) {
          String h = headers[i].toLowerCase();
          if (nameKeys.any((k) => h.contains(k.toLowerCase()))) {
            nameIdx = i;
          } else if (tagKeys.any((k) => h.contains(k.toLowerCase()))) {
            tagIdx = i;
          } else if (memoKeys.any((k) => h.contains(k.toLowerCase()))) {
            memoIdx = i;
          } else if (locKeys.any((k) => h.contains(k.toLowerCase()))) {
            locIdx = i;
          } else if (catKeys.any((k) => h.contains(k.toLowerCase()))) {
            catIdx = i;
          } else if (specKeys.any((k) => h.contains(k.toLowerCase()))) {
            specIdx = i;
          }
        }

        totalRows += (sheet.maxRows - 1);

        for (int i = 1; i < sheet.maxRows; i++) {
          if (_isDisposed) {
            break;
          }
          final row = sheet.rows[i];
          if (row.isEmpty) {
            continue;
          }

          final String nameVal = nameIdx != -1 && row.length > nameIdx ? row[nameIdx]?.toString() ?? "" : "";
          final String tagVal = tagIdx != -1 && row.length > tagIdx ? row[tagIdx]?.toString().trim() ?? "" : "";
          final String memoVal = memoIdx != -1 && row.length > memoIdx ? row[memoIdx]?.toString() ?? "" : "";
          final String locVal = locIdx != -1 && row.length > locIdx ? row[locIdx]?.toString() ?? "" : "";
          final String catVal = catIdx != -1 && row.length > catIdx ? row[catIdx]?.toString() ?? "" : "";
          final String specVal = specIdx != -1 && row.length > specIdx ? row[specIdx]?.toString() ?? "" : "";

          if (tagVal.isEmpty) {
            failedCount++;
            continue;
          }

          final existing = findProductByTag(tagVal);

          final Map<String, dynamic> metadataMap = {};
          final usedIndices = [nameIdx, tagIdx, memoIdx, locIdx, catIdx, specIdx];
          for (int c = 0; c < row.length; c++) {
            if (!usedIndices.contains(c) && c < headers.length) {
              metadataMap[headers[c]] = row[c]?.toString() ?? "";
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
            failedCount++;
          }
        }
      }
    } catch (e) {
      debugPrint("엑셀 파싱 에러: $e");
    } finally {
      _isParsing = false;
      fetchData();
    }

    return {'total': totalRows, 'success': successCount, 'failed': failedCount};
  }
}