import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:pocketbase/pocketbase.dart';

import '../models/product_model.dart';
// [중요 수정] 기존의 개별 PBService 대신, DataModule 역할을 하는 전역 클라이언트를 임포트합니다.
import '../core/pocketbase_client.dart';

/// ---------------------------------------------------------------------------
/// [엑셀 파싱 Isolate 함수]
/// 메인 스레드(UI)가 멈추는 것을 방지하기 위해 백그라운드(Isolate)에서 실행됩니다.
/// 엑셀 파일의 바이트 데이터를 받아 분석한 뒤, 각 행을 Map 형태로 변환하여 반환합니다.
/// C++Builder의 별도 Worker Thread 작업과 동일한 개념입니다.
/// ---------------------------------------------------------------------------
Map<String, dynamic>? _parseProductExcel(Uint8List bytes) {
  try {
    // 1. 바이트 데이터로부터 엑셀 객체 생성
    var excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return null;

    // 2. 첫 번째 시트를 선택하여 데이터 추출
    String sheetName = excel.tables.keys.first;
    var table = excel.tables[sheetName]!;

    // 데이터가 헤더(1줄)조차 없다면 처리할 수 없으므로 종료
    if (table.maxRows < 1) return null;

    // 3. 첫 번째 행을 헤더(컬럼명)로 사용
    List<String> headers = table.rows.first.map((cell) {
      return (cell?.value?.toString() ?? "").trim();
    }).toList();

    List<Map<String, dynamic>> rows = [];

    // 4. 두 번째 행부터 실제 데이터로 읽어들이기
    for (int i = 1; i < table.maxRows; i++) {
      Map<String, dynamic> rowData = {};

      for (int j = 0; j < headers.length; j++) {
        // 셀에 데이터가 존재하는 경우에만 Map에 담기
        if (j < table.rows[i].length) {
          rowData[headers[j]] = table.rows[i][j]?.value?.toString() ?? "";
        }
      }

      // 행에 비어있지 않은 유효한 값이 하나라도 있다면 목록에 추가
      if (rowData.values.any((value) => value.toString().isNotEmpty)) {
        rows.add(rowData);
      }
    }

    // 총 데이터 개수와 상세 데이터를 반환
    return {
      "count": rows.length,
      "details": rows
    };
  } catch (error) {
    // 엑셀 파싱 중 오류가 발생하면 null을 반환하여 앱이 죽지 않도록 보호
    return null;
  }
}

/// ---------------------------------------------------------------------------
/// [ProductProvider 클래스]
/// 제품(Product)과 관련된 모든 상태(State)와 비즈니스 로직을 관리하는 Provider입니다.
/// 화면(UI)에서는 이 Provider를 바라보며 데이터가 변경될 때마다 화면을 갱신합니다.
/// ---------------------------------------------------------------------------
class ProductProvider extends ChangeNotifier {
  // [중요 수정] 전역 pb 객체를 내부 변수로 매핑합니다.
  // 이제 main.dart에서 획득한 '최고 관리자(Superuser) 권한'이 탑재된
  // 신분증(토큰)을 그대로 이 프로바이더에서도 공유하여 사용하게 됩니다! (403 에러 원천 차단)
  final PocketBase _pb = pb;

  // PocketBase 컬렉션 이름 정의
  final String _collectionName = 'products';
  final String _configCollection = 'app_configs';
  final String _columnConfigKey = 'product_list_columns';

  // 내부 상태 변수들
  List<ProductModel> _items = [];
  List<String> _selectedColumns = ['품명', '태그ID', '위치', '상태'];

  bool _isLoading = false;     // 데이터를 불러오는 중인지 여부
  bool _isSaving = false;      // 데이터를 저장/삭제 중인지 여부
  bool _isParsing = false;     // 엑셀을 분석 중인지 여부
  bool _isDisposed = false;    // Provider가 소멸되었는지 여부
  bool _isInitialized = false; // 초기화가 완료되었는지 여부

  // UI에서 접근할 수 있는 Getter 메서드들
  List<ProductModel> get items => _items;
  List<String> get selectedColumns => _selectedColumns;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isParsing => _isParsing;

  // 물품의 상태값 기준 목록 (고정값)
  static const List<String> allStatus = [
    '정상', '구매입고', '회수/반납', '수기입고', '판매출고',
    '수리출고', '대여출고', '폐기', '분실', '수기출고'
  ];

  /// 생성자: 객체가 생성될 때 초기화 함수를 자동으로 호출합니다.
  ProductProvider() {
    _initProvider();
  }

  /// ---------------------------------------------------------------------------
  /// [초기화 및 실시간 구독 설정]
  /// 서버 설정값과 초기 데이터를 불러온 후, 실시간 데이터 변경 감지를 시작합니다.
  /// ---------------------------------------------------------------------------
  Future<void> _initProvider() async {
    if (_isInitialized) return;

    await fetchRemoteSettings();
    await fetchData();
    _subscribe(); // 서버의 데이터 변경을 실시간으로 감지

    _isInitialized = true;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _safeUnsubscribe(); // 앱 종료 또는 화면 이동 시 실시간 구독 해제
    super.dispose();
  }

  /// 서버 실시간 구독 안전하게 해제
  Future<void> _safeUnsubscribe() async {
    try {
      await _pb.collection(_collectionName).unsubscribe('*');
    } catch (error) {
      // 구독 해제 중 발생하는 오류는 무시 (앱 동작에 영향 없음)
    }
  }

  /// ---------------------------------------------------------------------------
  /// [서버 데이터 실시간 감지 (Subscribe)]
  /// 누군가 데이터를 추가, 수정, 삭제하면 자동으로 감지하여 목록을 새로고침합니다.
  /// ---------------------------------------------------------------------------
  void _subscribe() {
    _pb.collection(_collectionName).subscribe('*', (event) {
      // 내가 직접 저장 중이거나 이미 종료된 화면이라면 무시
      if (_isDisposed || _isSaving) return;

      // 변경 이벤트가 발생하면 데이터를 다시 불러옴
      fetchData();
    });
  }

  /// ---------------------------------------------------------------------------
  /// [데이터 목록 불러오기]
  /// 서버에서 최근 수정된 순서대로 전체 제품 목록을 가져옵니다.
  /// ---------------------------------------------------------------------------
  Future<void> fetchData() async {
    if (_isDisposed) return;

    _isLoading = true;
    notifyListeners(); // 화면에 로딩 스피너 표시 지시

    try {
      // sort: '-updated' -> 최근 수정일 기준 내림차순 정렬
      final records = await _pb.collection(_collectionName).getFullList(sort: '-updated');

      if (_isDisposed) return;

      // 서버에서 받은 레코드를 ProductModel 객체 리스트로 변환
      _items = records.map((record) {
        return ProductModel.fromJson({
          ...record.data,
          'id': record.id,
          'created': record.created,
          'updated': record.updated
        });
      }).toList();

    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners(); // 화면에 데이터 갱신 지시
      }
    }
  }

  /// ---------------------------------------------------------------------------
  /// [원격 설정 가져오기]
  /// 서버에 저장된 사용자의 컬럼(리스트 표출 항목) 설정값을 불러옵니다.
  /// ---------------------------------------------------------------------------
  Future<void> fetchRemoteSettings() async {
    try {
      final record = await _pb.collection(_configCollection).getFirstListItem('key = "$_columnConfigKey"');
      final dynamic value = record.data['value'];

      if (value is List) {
        _selectedColumns = value.map((element) => element.toString()).toList();
        notifyListeners();
      }
    } catch (error) {
      // 설정값이 없거나 가져오기 실패 시 기본값 유지
    }
  }

  /// ---------------------------------------------------------------------------
  /// [원격 설정 저장하기]
  /// 사용자가 그리드/리스트에서 보길 원하는 컬럼 구성을 서버에 저장합니다.
  /// ---------------------------------------------------------------------------
  Future<void> saveRemoteSettings(List<String> columns) async {
    try {
      _selectedColumns = List.from(columns);
      notifyListeners();

      RecordModel? existingRecord;
      try {
        existingRecord = await _pb.collection(_configCollection).getFirstListItem('key = "$_columnConfigKey"');
      } catch (error) {
        // 기존 설정이 없으면 null 상태 유지
      }

      final requestBody = {
        'key': _columnConfigKey,
        'value': _selectedColumns
      };

      if (existingRecord != null) {
        // 기존 설정이 있으면 업데이트
        await _pb.collection(_configCollection).update(existingRecord.id, body: requestBody);
      } else {
        // 기존 설정이 없으면 새로 생성
        await _pb.collection(_configCollection).create(body: requestBody);
      }
    } catch (error) {
      // 저장 실패 처리
    }
  }

  /// ---------------------------------------------------------------------------
  /// [단일 제품 데이터 저장/수정]
  /// 이미지가 있는 경우 포함하여 서버에 데이터를 저장합니다.
  /// ---------------------------------------------------------------------------
  Future<bool> handleSave({required ProductModel? product, required Map<String, dynamic> data, XFile? imageXFile}) async {
    _isSaving = true;
    notifyListeners();

    try {
      List<http.MultipartFile> files = [];

      // 이미지가 첨부된 경우 MultipartFile 형식으로 변환하여 추가
      if (imageXFile != null) {
        final bytes = await imageXFile.readAsBytes();
        files.add(
            http.MultipartFile.fromBytes('image', bytes, filename: imageXFile.name)
        );
      }

      if (product == null) {
        // 신규 등록
        await _pb.collection(_collectionName).create(body: data, files: files);
      } else {
        // 기존 데이터 수정
        await _pb.collection(_collectionName).update(product.id, body: data, files: files);
      }
      return true;
    } catch (error) {
      return false;
    } finally {
      _isSaving = false;
      // 실시간 구독(Subscribe)이 작동하지만, 즉각적인 화면 반영을 위해 명시적으로 호출
      await fetchData();
    }
  }

  /// ---------------------------------------------------------------------------
  /// [다중 선택 제품 삭제]
  /// 체크박스로 선택된 여러 개의 제품을 일괄 삭제합니다.
  /// ---------------------------------------------------------------------------
  Future<void> deleteMultipleProducts(List<String> productIds) async {
    _isSaving = true;
    notifyListeners();

    try {
      for (var id in productIds) {
        await _pb.collection(_collectionName).delete(id);
      }
    } finally {
      _isSaving = false;
      await fetchData();
    }
  }

  /// ---------------------------------------------------------------------------
  /// [전체 데이터 초기화]
  /// 시스템 전체의 물품 데이터를 삭제합니다. (주의해서 사용)
  /// ---------------------------------------------------------------------------
  Future<void> resetAllProducts() async {
    _isSaving = true;
    notifyListeners();

    try {
      // 전체 목록의 ID만 먼저 가져옵니다. (트래픽 절약)
      final records = await _pb.collection(_collectionName).getFullList(fields: 'id');

      for (var record in records) {
        await _pb.collection(_collectionName).delete(record.id);
      }
      _items = []; // 로컬 리스트 비우기
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// ---------------------------------------------------------------------------
  /// [엑셀 데이터 일괄 가져오기 (핵심 개선 영역)]
  /// 선택된 엑셀 파일을 분석하여 서버에 연속으로 등록합니다.
  /// 일부 데이터가 형식이 맞지 않거나 서버 저장에 실패해도 멈추지 않고,
  /// 에러 건으로 분류하여 저장하므로 나중에 확인/수정이 가능합니다.
  /// ---------------------------------------------------------------------------
  Future<Map<String, int>> batchImportFromExcel() async {
    try {
      // 1. 엑셀 파일 선택창 띄우기 (.xlsx, .xls 확장자만 허용)
      FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['xlsx', 'xls']
      );

      if (result == null) return {'success': 0, 'error': 0, 'total': 0};

      _isParsing = true;
      notifyListeners();

      // 2. 파일 바이트 데이터 추출 (웹과 데스크탑/모바일 환경 구분)
      Uint8List bytes = kIsWeb
          ? result.files.single.bytes!
          : await File(result.files.single.path!).readAsBytes();

      // 3. 백그라운드 스레드(Isolate)에서 엑셀 파싱 실행
      final parsedData = await compute(_parseProductExcel, bytes);

      _isParsing = false;

      if (parsedData == null) {
        notifyListeners();
        return {'success': 0, 'error': 0, 'total': 0};
      }

      _isSaving = true;
      notifyListeners();

      // 파싱된 데이터 행 목록
      List<Map<String, dynamic>> rows = List<Map<String, dynamic>>.from(parsedData['details']);

      int successCount = 0;
      int errorCount = 0;

      // 4. 추출된 각 행(Row) 데이터를 서버에 하나씩 업로드
      for (var row in rows) {
        try {
          // 데이터 유연성 확보: 컬럼명이 약간 달라도 호환되도록 처리하고 앞뒤 공백 제거
          String name = (row['품명'] ?? row['제품명'] ?? '').toString().trim();
          String tagId = (row['태그ID'] ?? row['RFID'] ?? '').toString().trim();
          String location = (row['위치'] ?? '').toString().trim();

          if (location.isEmpty) {
            location = '미지정';
          }

          // 유효성 검증: 제품명은 필수값이라고 가정
          bool isFormatValid = name.isNotEmpty;

          if (isFormatValid) {
            // [정상 데이터]
            final body = {
              'name': name,
              'tag_id': tagId,
              'location': location,
              'status': '정상',
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
          // 서버 통신 에러 (예: 태그ID 유니크 제약조건 위반 등)
          // 반복문이 멈추지 않도록 catch 블록 안에서 카운트만 증가시킴
          if (kDebugMode) {
            print('엑셀 단일 행 저장 실패: $error'); // 프로덕션 환경에서는 출력되지 않도록 보호
          }
          errorCount++;
        }
      }

      _isSaving = false;
      await fetchData(); // 완료 후 화면 새로고침

      // 결과 리포트를 UI로 전달 (성공 건수, 실패 건수, 전체 건수)
      return {
        'success': successCount,
        'error': errorCount,
        'total': rows.length
      };

    } catch (error) {
      // 파일 읽기 자체에서 치명적 오류 발생 시 처리
      _isParsing = false;
      _isSaving = false;
      notifyListeners();
      return {'success': 0, 'error': 0, 'total': 0};
    }
  }
}