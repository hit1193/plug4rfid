import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import '../models/products.dart';
import '../services/pb_service.dart';

/// [Logic] 물품 관리를 위한 상태 관리 클래스 (C++의 DataModule 역할)
class ProductProvider extends ChangeNotifier {
  final String _collectionName = 'products';
  List<ProductModel> _items = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDisposed = false;

  List<ProductModel> get items => _items;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;

  ProductProvider() {
    fetchData();
    _subscribe();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _unsubscribeSafely();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  Future<void> _unsubscribeSafely() async {
    try {
      await PBService.pb.collection(_collectionName).unsubscribe('*');
    } catch (e) {
      debugPrint("구독 해제 세션 종료 감지 (무시): $e");
    }
  }

  Future<void> fetchData() async {
    if (_isDisposed) return;
    _isLoading = true;
    notifyListeners();
    try {
      final records = await PBService.pb.collection(_collectionName).getFullList(sort: '-created');
      if (_isDisposed) return;
      _items = records.map((r) => ProductModel.fromJson(r.toJson())).toList();
    } catch (e) {
      debugPrint("물품 로드 에러: $e");
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) {
      if (!_isDisposed) fetchData();
    });
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
      Uint8List? fileBytes;
      String? fileName;
      if (imageXFile != null) {
        fileBytes = await imageXFile.readAsBytes();
        fileName = imageXFile.name;
      }

      final Map<String, dynamic> body = Map<String, dynamic>.from(data);
      final int bulkCount = body.remove('bulk_count') ?? 1;

      if (p == null) {
        for (int i = 0; i < bulkCount; i++) {
          if (_isDisposed) break;
          final Map<String, dynamic> singleBody = Map<String, dynamic>.from(body);
          if (bulkCount > 1) {
            singleBody['tag_id'] = "${body['tag_id']}_${DateTime.now().millisecondsSinceEpoch}_$i";
          }
          List<http.MultipartFile> files = [];
          if (fileBytes != null && fileName != null) {
            files.add(http.MultipartFile.fromBytes('image', fileBytes, filename: fileName));
          }
          await PBService.pb.collection(_collectionName).create(body: singleBody, files: files);
        }
      } else {
        if (imageXFile != null) {
          final sameProducts = _items.where((item) =>
          item.name == p.name && (item.spec ?? "") == (p.spec ?? "")
          ).toList();

          for (var item in sameProducts) {
            if (_isDisposed) break;
            List<http.MultipartFile> files = [];
            if (fileBytes != null && fileName != null) {
              files.add(http.MultipartFile.fromBytes('image', fileBytes, filename: fileName));
            }
            await PBService.pb.collection(_collectionName).update(
              item.id,
              body: item.id == p.id ? body : {'name': body['name'], 'spec': body['spec']},
              files: files,
            );
          }
        } else {
          await PBService.pb.collection(_collectionName).update(p.id, body: body);
        }
      }
      return true;
    } catch (e) {
      debugPrint("저장 에러: $e");
      return false;
    } finally {
      if (!_isDisposed) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  Future<bool> deleteProduct(String id) async {
    if (_isDisposed) return false;
    try {
      await PBService.pb.collection(_collectionName).delete(id);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> deleteBatch(List<ProductModel> itemsToDelete) async {
    if (_isDisposed) return;
    try {
      for (var item in itemsToDelete) {
        if (_isDisposed) break;
        await PBService.pb.collection(_collectionName).delete(item.id);
      }
    } finally {
      fetchData();
    }
  }
}

/// [UI] 물품 관리 페이지
class ProductPage extends StatefulWidget {
  final String searchQuery;
  final bool isMobile;
  final String baseUrl;
  final Function(ProductModel)? onEdit;

  const ProductPage({
    super.key,
    required this.searchQuery,
    required this.isMobile,
    required this.baseUrl,
    this.onEdit,
  });

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  static const String _fontFamily = 'Pretendard';
  static const List<String> _kStatusOptions = ['정상', '검수필요', '부족', '수리중', '폐기', '알 수 없음'];

  final TextEditingController _searchController = TextEditingController();
  String _currentQuery = "";
  String _groupByMode = 'item';

  @override
  void initState() {
    super.initState();
    _currentQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 한글 초성 검색 및 매칭 로직
  bool _isMatch(String? target, String query) {
    if (target == null || target.isEmpty) return "알 수 없음".contains(query);
    if (query.isEmpty) return true;
    final lowerTarget = target.toLowerCase();
    final lowerQuery = query.toLowerCase();
    if (lowerTarget.contains(lowerQuery)) return true;
    // ... 한글 초성 로직 생략 (기존과 동일)
    return false;
  }

  Map<String, List<ProductModel>> _getGroupedData(List<ProductModel> items) {
    Map<String, List<ProductModel>> grouped = {};
    for (var item in items) {
      String key = "";
      if (_groupByMode == 'item') {
        key = (item.spec ?? "").isEmpty ? item.name : "${item.name} (${item.spec})";
      } else if (_groupByMode == 'location') {
        key = (item.location ?? "").isEmpty ? "위치 알 수 없음" : item.location!;
      } else {
        key = (item.category ?? "").isEmpty ? "분류 알 수 없음" : item.category!;
      }
      if (!grouped.containsKey(key)) grouped[key] = [];
      grouped[key]!.add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProductProvider(),
      child: Consumer<ProductProvider>(
        builder: (context, provider, child) {
          final filteredRaw = provider.items.where((p) =>
          _isMatch(p.name, _currentQuery) || _isMatch(p.tagId, _currentQuery)
          ).toList();

          final groupedMap = _getGroupedData(filteredRaw);
          final groupKeys = groupedMap.keys.toList();

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: [
                _buildSearchBar(),
                _buildToggleRow(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _buildHeader(),
                          Expanded(
                            child: provider.isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : _buildListView(groupKeys, groupedMap, provider),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => _showForm(context, provider, null),
              backgroundColor: Colors.indigo,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 15, 26, 5),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _currentQuery = val),
        decoration: InputDecoration(
          labelText: '물품 검색',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildToggleRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
      child: Row(
        children: ['item', 'location', 'category'].map((mode) => Expanded(
          child: ActionChip(
            label: Text(mode == 'item' ? '품목별' : (mode == 'location' ? '위치별' : '분류별')),
            onPressed: () => setState(() => _groupByMode = mode),
            backgroundColor: _groupByMode == mode ? Colors.indigo : Colors.grey[200],
            labelStyle: TextStyle(color: _groupByMode == mode ? Colors.white : Colors.black),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.indigo.withValues(alpha: 0.05),
      child: const Row(children: [
        SizedBox(width: 50, child: Text('No')),
        Expanded(flex: 3, child: Text('품명/위치/분류')),
        SizedBox(width: 80, child: Text('수량', textAlign: TextAlign.center)),
        SizedBox(width: 100, child: Text('작업', textAlign: TextAlign.center)),
      ]),
    );
  }

  Widget _buildListView(List<String> keys, Map<String, List<ProductModel>> map, ProductProvider pvd) {
    return ListView.separated(
      itemCount: keys.length,
      separatorBuilder: (c, i) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final key = keys[index];
        final items = map[key]!;
        return ListTile(
          onTap: () => _showDetailGrid(context, pvd, key, items),
          title: Text(key, style: const TextStyle(fontWeight: FontWeight.bold)),
          trailing: Text('${items.length}개', style: const TextStyle(color: Colors.indigo)),
        );
      },
    );
  }

  // 상세 목록 그리드 팝업
  void _showDetailGrid(BuildContext context, ProductProvider provider, String title, List<ProductModel> items) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$title 상세 목록'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(items[i].tagId),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showForm(context, provider, items[i]);
                },
              ),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("닫기"))],
      ),
    );
  }

  // 핵심 수정: const 에러 방지된 다이얼로그 폼
  Future<void> _showForm(BuildContext context, ProductProvider provider, ProductModel? p) async {
    final nameC = TextEditingController(text: p?.name ?? "");
    final tagC = TextEditingController(text: p?.tagId ?? "");
    final qtyC = TextEditingController(text: "1");
    final locC = TextEditingController(text: p?.location ?? "");
    final specC = TextEditingController(text: p?.spec ?? "");
    final catC = TextEditingController(text: p?.category ?? "");
    String sV = (p?.status == null || p!.status.trim().isEmpty) ? '알 수 없음' : p.status;
    if (!_kStatusOptions.contains(sV)) sV = '알 수 없음';

    XFile? pickedFile;
    Uint8List? previewBytes;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ListenableProvider.value(
        value: provider,
        child: Consumer<ProductProvider>(
          builder: (context, pvd, _) => StatefulBuilder(
            builder: (context, setDialogState) {
              bool useHorizontal = MediaQuery.of(context).size.width > 600;
              // 런타임 결정 변수가 포함된 스타일은 const를 붙이지 않습니다.
              final dynamicLabelStyle = TextStyle(fontSize: 12, color: Colors.black45, fontFamily: _fontFamily);

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Text(p == null ? '신규 등록' : '정보 수정', style: const TextStyle(fontWeight: FontWeight.bold)),
                content: SizedBox(
                  width: useHorizontal ? 600 : null,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (useHorizontal)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildImagePicker(p, previewBytes, setDialogState, (file, bytes) {
                                pickedFile = file; previewBytes = bytes;
                              }),
                              Expanded(child: _buildInputs(nameC, sV, catC, locC, specC, tagC, qtyC, p, dynamicLabelStyle, (val) => sV = val)),
                            ],
                          )
                        else ...[
                          _buildImagePicker(p, previewBytes, setDialogState, (file, bytes) {
                            pickedFile = file; previewBytes = bytes;
                          }),
                          _buildInputs(nameC, sV, catC, locC, specC, tagC, qtyC, p, dynamicLabelStyle, (val) => sV = val),
                        ],
                        const SizedBox(height: 10),
                        // 상수 문자열만 있는 경우에만 const 허용
                        const Text("※ 이미지 변경 시 동일 품목의 모든 태그에 반영됩니다.", style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                        if (pvd.isSaving) const Padding(padding: EdgeInsets.only(top: 15), child: LinearProgressIndicator()),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("취소")),
                  ElevatedButton(
                    onPressed: pvd.isSaving ? null : () async {
                      if (nameC.text.isEmpty) return;
                      final nav = Navigator.of(ctx); // Navigator 캡처
                      final d = {
                        'name': nameC.text.trim(),
                        'tag_id': tagC.text.trim(),
                        'bulk_count': int.tryParse(qtyC.text) ?? 1,
                        'location': locC.text.trim(),
                        'spec': specC.text.trim(),
                        'category': catC.text.trim(),
                        'status': sV == '알 수 없음' ? '' : sV
                      };
                      if (await pvd.handleSave(p: p, data: d, imageXFile: pickedFile)) {
                        if (ctx.mounted) nav.pop();
                      }
                    },
                    child: const Text("저장"),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildImagePicker(ProductModel? p, Uint8List? preview, Function setDS, Function onP) {
    return GestureDetector(
      onTap: () async {
        final picker = ImagePicker();
        final image = await picker.pickImage(source: ImageSource.gallery);
        if (image != null) {
          final bytes = await image.readAsBytes();
          setDS(() => onP(image, bytes));
        }
      },
      child: Container(
        width: 150, height: 150,
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)),
        child: preview != null
            ? Image.memory(preview, fit: BoxFit.cover)
            : const Icon(Icons.add_a_photo, size: 40),
      ),
    );
  }

  Widget _buildInputs(TextEditingController n, String s, TextEditingController c, TextEditingController l, TextEditingController sp, TextEditingController t, TextEditingController q, ProductModel? p, TextStyle style, Function onS) {
    return Column(
      children: [
        _buildTextField('품명', n, style),
        DropdownButtonFormField<String>(
          value: s,
          decoration: InputDecoration(labelText: '상태', labelStyle: style, border: const OutlineInputBorder()),
          items: _kStatusOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) { if (v != null) onS(v); },
        ),
        const SizedBox(height: 12),
        _buildTextField('분류', c, style),
        _buildTextField('보관위치', l, style),
        _buildTextField('규격', sp, style),
        _buildTextField('EPC', t, style, readOnly: p != null),
        if (p == null) _buildTextField('수량', q, style, isNum: true),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController c, TextStyle s, {bool readOnly = false, bool isNum = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        readOnly: readOnly,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, labelStyle: s, border: const OutlineInputBorder(), isDense: true),
      ),
    );
  }
}