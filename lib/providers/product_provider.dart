import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:intl/intl.dart';

import '../models/products.dart';
import '../services/pb_service.dart';

/// 자산(Product) 데이터의 상태 관리 및 비즈니스 로직을 담당하는 클래스
class ProductProvider extends ChangeNotifier {
  final String _collectionName = 'products';
  List<ProductModel> _items = [];
  List<String> _selectedColumns = ['규격', '제조사', '위치', 'S/N'];

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isParsing = false;
  bool _isDisposed = false;

  // 원본 엑셀의 헤더(컬럼명들) 정보를 보관
  List<String> _errorHeaders = [];
  // 실패한 행의 원본 데이터 전체와 에러 메시지를 보관 (C++의 TList<Record> 구조)
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
    fetchData();
    _subscribe();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _unsubscribe();
    super.dispose();
  }

  void setParsing(bool val) {
    _isParsing = val;
    notifyListeners();
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
    notifyListeners();
    try {
      final records = await PBService.pb.collection(_collectionName).getFullList(sort: '-created');
      _items = records.map((r) => ProductModel.fromJson(r.toJson())).toList();
    } catch (e) {
      debugPrint("❌ 데이터 로드 에러: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
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

  Future<void> saveRemoteSettings(List<String> newColumns) async {
    _selectedColumns = List.from(newColumns);
    notifyListeners();
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
      return _items.firstWhere((p) {
        return p.tagId.trim().toLowerCase() == tag.trim().toLowerCase();
      });
    } catch (_) {
      return null;
    }
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
      if (data.containsKey('metadata') && data['metadata'].containsKey('origin_key_map')) {
        final Map<String, dynamic> metadata = Map<String, dynamic>.from(data['metadata']);
        final Map<String, dynamic> originMap = metadata['origin_key_map'];

        originMap.forEach((excelHeader, dbField) {
          if (data.containsKey(dbField)) {
            metadata[excelHeader] = data[dbField];
          }
        });
        data['metadata'] = metadata;
      }

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

      fetchData();
      return true;
    } catch (e) {
      debugPrint("❌ 폼 저장 에러: $e");
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
        await PBService.pb.collection(_collectionName).delete(item.id);
      }
      await fetchData();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 엑셀 일괄 임포트 로직 (에러 원본 보존 기능 강화)
  Future<Map<String, int>> batchImportFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result == null) {
      return {'total': 0, 'success': 0, 'failed': 0};
    }

    _isParsing = true;
    _lastErrors = [];
    _errorHeaders = [];
    notifyListeners();

    int success = 0;
    int failed = 0;
    int total = 0;

    try {
      final bytes = File(result.files.single.path!).readAsBytesSync();
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);

      final mapDef = {
        'name': ['관리대상의명칭', '명칭', '품명', '제품명', 'name'],
        'tag_id': ['태그번호', '태그', 'rfid', 'epc', 'tag'],
        'loc': ['보관(사용)위치', '보관위치', '위치', 'location'],
        'cat': ['분류키워드', '자산구분', '분류', 'category'],
        'qty': ['수량', 'quantity', 'qty'],
        'memo': ['참고사항', '비고', 'remarks', 'memo'],
        'spec': ['부품번호', '규격', '모델', 'spec'],
        'mfg': ['제조사', '제조처', '메이커', 'brand'],
        'sn': ['시리얼', 's/n', 'sn', 'serial'],
        'unit': ['단위', 'unit'],
        'safe': ['안전재고', '기준재고', 'safety'],
      };

      for (var table in decoder.tables.keys) {
        final sheet = decoder.tables[table]!;
        if (sheet.maxRows < 2) {
          continue;
        }

        // [중요] 엑셀의 첫 번째 줄(헤더)을 그대로 복사하여 보관합니다.
        final rawHeaders = sheet.rows[0].map((e) {
          return e?.toString().trim() ?? "";
        }).toList();
        _errorHeaders = List<String>.from(rawHeaders);

        final headers = rawHeaders.map((e) {
          return e.toLowerCase().replaceAll(' ', '');
        }).toList();

        int findIdx(List<String> keys) {
          return headers.indexWhere((h) {
            return keys.any((k) => h.contains(k.toLowerCase()));
          });
        }

        int nIdx = findIdx(mapDef['name']!);
        int tIdx = findIdx(mapDef['tag_id']!);
        int lIdx = findIdx(mapDef['loc']!);
        int cIdx = findIdx(mapDef['cat']!);
        int qIdx = findIdx(mapDef['qty']!);
        int mIdx = findIdx(mapDef['memo']!);
        int sIdx = findIdx(mapDef['spec']!);
        int mfIdx = findIdx(mapDef['mfg']!);
        int snIdx = findIdx(mapDef['sn']!);
        int uIdx = findIdx(mapDef['unit']!);
        int sfIdx = findIdx(mapDef['safe']!);

        for (int i = 1; i < sheet.maxRows; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty || row.every((e) => e == null)) {
            continue;
          }

          total++;

          String val(int idx) {
            return (idx != -1 && row.length > idx) ? row[idx]?.toString().trim() ?? "" : "";
          }

          String tag = val(tIdx);
          if (tag.isEmpty) {
            tag = "TEMP-${DateTime.now().millisecondsSinceEpoch}-$i";
          }

          final Map<String, String> originKeyMap = {};
          if (nIdx != -1) { originKeyMap[rawHeaders[nIdx]] = 'name'; }
          if (sIdx != -1) { originKeyMap[rawHeaders[sIdx]] = 'spec'; }
          if (lIdx != -1) { originKeyMap[rawHeaders[lIdx]] = 'location'; }
          if (mfIdx != -1) { originKeyMap[rawHeaders[mfIdx]] = 'manufacturer'; }
          if (snIdx != -1) { originKeyMap[rawHeaders[snIdx]] = 'serial_number'; }

          final Map<String, dynamic> metadataMap = {};
          for (int c = 0; c < row.length; c++) {
            if (c < rawHeaders.length) {
              metadataMap[rawHeaders[c]] = row[c]?.toString() ?? "";
            }
          }
          metadataMap['origin_key_map'] = originKeyMap;

          final data = {
            'name': val(nIdx).isEmpty ? "Unnamed" : val(nIdx),
            'tag_id': tag,
            'location': val(lIdx),
            'category': val(cIdx).isNotEmpty ? val(cIdx) : val(findIdx(['자산구분'])),
            'spec': val(sIdx),
            'remarks': val(mIdx),
            'manufacturer': val(mfIdx),
            'serial_number': val(snIdx),
            'unit': val(uIdx).isEmpty ? "ea" : val(uIdx),
            'quantity': int.tryParse(val(qIdx)) ?? 1, // 수량 누락 시 1로 자동 보정
            'safety_stock': int.tryParse(val(sfIdx)) ?? 5,
            'status': '정상',
            'metadata': metadataMap,
          };

          try {
            if (tag.startsWith("TEMP-")) {
              await PBService.pb.collection(_collectionName).create(body: data);
            } else {
              final existing = findProductByTag(tag);
              if (existing != null) {
                await PBService.pb.collection(_collectionName).update(existing.id, body: data);
              } else {
                await PBService.pb.collection(_collectionName).create(body: data);
              }
            }
            success++;
          } catch (e) {
            failed++;
            // [해결] 실패한 행의 모든 데이터를 원본 리스트(row) 그대로 보관합니다.
            _lastErrors.add({
              'originalRow': row.map((cell) => cell?.toString() ?? "").toList(),
              'errorMsg': e.toString(),
            });
            debugPrint("❌ DB 오류 (${i + 1}행): $e");
          }
        }
      }
    } catch (e) {
      debugPrint("❌ 엑셀 파싱 치명적 오류: $e");
    } finally {
      _isParsing = false;
      fetchData();
    }
    return {'total': total, 'success': success, 'failed': failed};
  }
}