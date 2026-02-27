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

class ProductProvider extends ChangeNotifier {
  final String _collectionName = 'products';
  List<ProductModel> _items = [];
  List<String> _selectedColumns = ['규격', '제조사', '위치', 'S/N'];

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
    if (_isDisposed) return;
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
      PBService.pb.collection(_collectionName).subscribe('*', (e) => fetchData());
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

  void clearLastScannedTag() => _lastScannedTag = "";

  ProductModel? findProductByTag(String tag) {
    try {
      return _items.firstWhere((p) => p.tagId.trim().toLowerCase() == tag.trim().toLowerCase());
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
      fetchData();
      return true;
    } catch (e) {
      if (e is ClientException) {
        debugPrint("❌ 폼 저장 에러 (PB 거부): ${e.response}");
      } else {
        debugPrint("❌ 폼 저장 에러: $e");
      }
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
        if (sheet.maxRows < 2) continue;

        final rawHeaders = sheet.rows[0].map((e) => e?.toString().trim() ?? "").toList();
        final headers = rawHeaders.map((e) => e.toLowerCase().replaceAll(' ', '')).toList();

        int findIdx(List<String> keys) => headers.indexWhere((h) => keys.any((k) => h.contains(k.toLowerCase())));

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

        debugPrint("📌 매핑 결과 -> 품명: $nIdx, 태그: $tIdx, 위치: $lIdx, 분류: $cIdx, 수량: $qIdx, 참고: $mIdx, 부품번호: $sIdx");

        for (int i = 1; i < sheet.maxRows; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty || row.every((e) => e == null)) continue;

          total++;

          String val(int idx) => (idx != -1 && row.length > idx) ? row[idx]?.toString().trim() ?? "" : "";

          String tag = val(tIdx);

          // [핵심 변경점] 태그가 비어있으면 버리지 않고 임시(가상) 태그를 발급합니다.
          if (tag.isEmpty) {
            tag = "TEMP-${DateTime.now().millisecondsSinceEpoch}-$i";
            debugPrint("⚠️ [${i + 1}행] 태그가 없어 임시 태그($tag)를 발급하여 저장합니다.");
          }

          final Map<String, String> originKeyMap = {};
          if (nIdx != -1) originKeyMap['name'] = rawHeaders[nIdx];
          if (sIdx != -1) originKeyMap['spec'] = rawHeaders[sIdx];
          if (lIdx != -1) originKeyMap['location'] = rawHeaders[lIdx];
          if (mfIdx != -1) originKeyMap['manufacturer'] = rawHeaders[mfIdx];
          if (snIdx != -1) originKeyMap['serial_number'] = rawHeaders[snIdx];

          final Map<String, dynamic> metadataMap = {};
          final used = [nIdx, tIdx, lIdx, cIdx, qIdx, mIdx, sIdx, mfIdx, snIdx, uIdx, sfIdx];
          for (int c = 0; c < row.length; c++) {
            if (!used.contains(c) && c < rawHeaders.length) {
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
            'safety_stock': int.tryParse(val(sfIdx)) ?? 5,
            'quantity': int.tryParse(val(qIdx)) ?? 1,
            'status': '정상',
            'metadata': metadataMap,
          };

          try {
            // "TEMP-" 로 시작하는 임시 태그는 무조건 새로 Create 하도록 분기
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
            if (e is ClientException) {
              debugPrint("❌ DB 거부 (태그: $tag, ${i + 1}행): ${e.response}");
            } else {
              debugPrint("❌ 시스템 오류 (${i + 1}행): $e");
            }
          }
        }
      }
    } catch (e) {
      debugPrint("❌ 엑셀 파싱 중 치명적 오류: $e");
    } finally {
      _isParsing = false;
      fetchData();
    }
    return {'total': total, 'success': success, 'failed': failed};
  }
}