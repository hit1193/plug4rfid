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
    _safeUnsubscribe();
    super.dispose();
  }

  Future<void> _safeUnsubscribe() async {
    try {
      await PBService.pb.collection(_collectionName).unsubscribe('*');
    } catch (e) {
      debugPrint("구독 해제 세션 종료 감지: $e");
    }
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
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

  /// PocketBase의 quantity 필수 제약 조건 해결 및 벌크 등록 로직
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
        // 신규 등록: 벌크 생성
        for (int i = 0; i < bulkCount; i++) {
          if (_isDisposed) break;
          final Map<String, dynamic> singleBody = Map<String, dynamic>.from(body);

          if (bulkCount > 1) {
            singleBody['tag_id'] = "${body['tag_id']}_$i";
          }
          singleBody['quantity'] = 1;

          List<http.MultipartFile> files = [];
          if (fileBytes != null && fileName != null) {
            files.add(http.MultipartFile.fromBytes('image', fileBytes, filename: fileName));
          }
          await PBService.pb.collection(_collectionName).create(body: singleBody, files: files);
        }
      } else {
        // 수정 모드
        if (!body.containsKey('quantity')) {
          body['quantity'] = 1;
        }

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
              body: item.id == p.id ? body : {'name': body['name'], 'spec': body['spec'], 'quantity': 1},
              files: files,
            );
          }
        } else {
          await PBService.pb.collection(_collectionName).update(p.id, body: body);
        }
      }
      return true;
    } catch (e) {
      debugPrint("저장 에러 상세: $e");
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
    for (var item in itemsToDelete) {
      if (_isDisposed) break;
      await deleteProduct(item.id);
    }
    fetchData();
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

  // 그리드 상수
  static const double _rowHeight = 56.0;
  static const double _colImgWidth = 60.0;
  static const double _colQtyWidth = 100.0;
  static const double _colActionWidth = 100.0;

  static const double _detailColImgWidth = 50.0;
  static const double _detailColStatusWidth = 80.0;
  static const double _detailColActionWidth = 90.0;

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

  bool _isMatch(String? target, String query) {
    if (target == null || target.isEmpty) return "알 수 없음".contains(query);
    if (query.isEmpty) return true;
    return target.toLowerCase().contains(query.toLowerCase());
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

  String _getImageUrl(ProductModel p) {
    if (p.image == null || p.image!.isEmpty) return "";
    return "${widget.baseUrl}/api/files/products/${p.id}/${p.image}";
  }

  /// [수정] 썸네일 이미지 위젯: 이미지 없는 경우 기본 배경을 카메라 아이콘으로 통일
  Widget _buildThumbnail(ProductModel p) {
    final url = _getImageUrl(p);
    return Container(
      width: 40,
      height: 40,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? const Icon(Icons.camera_alt_outlined, size: 16, color: Colors.grey)
          : Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.error_outline, size: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const defaultTextStyle = TextStyle(fontFamily: _fontFamily);

    return ChangeNotifierProvider(
      create: (_) => ProductProvider(),
      child: Consumer<ProductProvider>(
        builder: (context, provider, child) {
          final filteredRaw = provider.items.where((p) =>
          _isMatch(p.name, _currentQuery) ||
              _isMatch(p.tagId, _currentQuery) ||
              _isMatch(p.location, _currentQuery)
          ).toList();

          final groupedMap = _getGroupedData(filteredRaw);
          final groupKeys = groupedMap.keys.toList();

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: DefaultTextStyle(
              style: defaultTextStyle.copyWith(color: Colors.black),
              child: Column(
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
                          border: Border.all(color: Colors.indigo.withValues(alpha: 0.3), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            )
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            _buildHeader(),
                            const Divider(height: 1, thickness: 1.2, color: Color(0xFFE0E0E0)),
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
        style: const TextStyle(fontFamily: _fontFamily),
        onChanged: (val) => setState(() => _currentQuery = val),
        decoration: InputDecoration(
          labelText: '물품 검색',
          labelStyle: const TextStyle(fontFamily: _fontFamily),
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildToggleRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
      child: Row(
        children: ['item', 'location', 'category'].map((mode) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              label: Center(
                  child: Text(
                    mode == 'item' ? '품목별' : (mode == 'location' ? '위치별' : '분류별'),
                    style: const TextStyle(fontFamily: _fontFamily),
                  )
              ),
              onPressed: () => setState(() => _groupByMode = mode),
              backgroundColor: _groupByMode == mode ? Colors.indigo : Colors.white,
              labelStyle: TextStyle(
                fontFamily: _fontFamily,
                color: _groupByMode == mode ? Colors.white : Colors.black87,
                fontWeight: _groupByMode == mode ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildHeader() {
    const headerStyle = TextStyle(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: Colors.black87
    );
    return Container(
      height: _rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: Colors.indigo.withValues(alpha: 0.07),
      child: const Row(children: [
        SizedBox(width: _colImgWidth, child: Text('이미지', style: headerStyle)),
        Expanded(child: Text('품명 / 정보', style: headerStyle)),
        SizedBox(width: _colQtyWidth, child: Text('보유수량', textAlign: TextAlign.center, style: headerStyle)),
        SizedBox(width: _colActionWidth, child: Text('작업', textAlign: TextAlign.center, style: headerStyle)),
      ]),
    );
  }

  Widget _buildListView(List<String> keys, Map<String, List<ProductModel>> map, ProductProvider pvd) {
    if (keys.isEmpty) return const Center(child: Text("검색 결과가 없습니다.", style: TextStyle(fontFamily: _fontFamily)));

    return ListView.separated(
      itemCount: keys.length,
      separatorBuilder: (c, i) => const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
      itemBuilder: (context, index) {
        final key = keys[index];
        final items = map[key]!;
        final representativeItem = items.first;

        return InkWell(
          onTap: () => _showDetailGrid(context, pvd, key),
          child: Container(
            height: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SizedBox(width: _colImgWidth, child: Align(alignment: Alignment.centerLeft, child: _buildThumbnail(representativeItem))),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(key, style: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                          _groupByMode == 'item' ? (representativeItem.category ?? "분류 없음") : "${items.length}개의 품목",
                          style: const TextStyle(fontFamily: _fontFamily, fontSize: 12, color: Colors.black54)
                      ),
                    ],
                  ),
                ),
                SizedBox(
                    width: _colQtyWidth,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                        child: Text(
                            '${items.length}',
                            style: const TextStyle(fontFamily: _fontFamily, color: Colors.indigo, fontWeight: FontWeight.bold)
                        ),
                      ),
                    )
                ),
                SizedBox(
                    width: _colActionWidth,
                    child: Center(
                      child: IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 22),
                        onPressed: () => _confirmBatchDelete(context, pvd, key, items),
                      ),
                    )
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDetailGrid(BuildContext context, ProductProvider provider, String groupKey) {
    showDialog(
      context: context,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: provider,
        child: Consumer<ProductProvider>(
            builder: (context, pvd, _) {
              final items = pvd.items.where((p) {
                if (_groupByMode == 'item') return ((p.spec ?? "").isEmpty ? p.name : "${p.name} (${p.spec})") == groupKey;
                if (_groupByMode == 'location') return (p.location ?? "위치 알 수 없음") == groupKey;
                return (p.category ?? "분류 알 수 없음") == groupKey;
              }).toList();

              const detailHeaderStyle = TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87);

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Text(groupKey, style: const TextStyle(fontFamily: _fontFamily, fontSize: 18, fontWeight: FontWeight.bold)),
                content: Container(
                  width: 650,
                  height: 500,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.indigo.withValues(alpha: 0.25), width: 1.2),
                    color: Colors.white,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Container(
                        height: _rowHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        color: Colors.grey[100],
                        child: const Row(
                          children: [
                            SizedBox(width: _detailColImgWidth, child: Text("이미지", style: detailHeaderStyle)),
                            SizedBox(width: 10),
                            Expanded(child: Text("태그 ID (EPC)", style: detailHeaderStyle)),
                            SizedBox(width: _detailColStatusWidth, child: Text("상태", textAlign: TextAlign.center, style: detailHeaderStyle)),
                            SizedBox(width: _detailColActionWidth, child: Text("작업", textAlign: TextAlign.center, style: detailHeaderStyle)),
                          ],
                        ),
                      ),
                      const Divider(height: 1, thickness: 1, color: Color(0xFFE0E0E0)),
                      Expanded(
                        child: ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (c, i) => const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
                          itemBuilder: (c, i) => InkWell(
                            onTap: () => _showForm(context, pvd, items[i]),
                            child: Container(
                              height: _rowHeight,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  SizedBox(width: _detailColImgWidth, child: Center(child: _buildThumbnail(items[i]))),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            items[i].tagId,
                                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w500),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis
                                        ),
                                        Text(
                                            items[i].name,
                                            style: const TextStyle(fontFamily: _fontFamily, fontSize: 11, color: Colors.grey),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: _detailColStatusWidth, child: Center(
                                    child: Text(
                                        _kStatusOptions[indexToStatus(items[i].status)],
                                        style: TextStyle(fontFamily: _fontFamily, color: _getStatusColor(items[i].status), fontSize: 12, fontWeight: FontWeight.bold)
                                    ),
                                  )),
                                  SizedBox(width: _detailColActionWidth, child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_note, size: 22, color: Colors.blueGrey),
                                        onPressed: () => _showForm(context, pvd, items[i]),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 22, color: Colors.redAccent),
                                        onPressed: () => _confirmDelete(context, pvd, items[i]),
                                      ),
                                    ],
                                  )),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("닫기", style: TextStyle(fontFamily: _fontFamily))
                  )
                ],
              );
            }
        ),
      ),
    );
  }

  int indexToStatus(String? s) => _kStatusOptions.contains(s) ? _kStatusOptions.indexOf(s!) : 5;

  Color _getStatusColor(String? status) {
    switch (status) {
      case '정상': return Colors.green;
      case '검수필요': return Colors.orange;
      case '부족': return Colors.red;
      case '수리중': return Colors.blue;
      case '폐기': return Colors.grey;
      default: return Colors.black54;
    }
  }

  Future<void> _confirmDelete(BuildContext context, ProductProvider pvd, ProductModel p) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("데이터 삭제", style: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold)),
        content: Text("태그 [${p.tagId}] 정보를 삭제하시겠습니까?", style: const TextStyle(fontFamily: _fontFamily)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소", style: TextStyle(fontFamily: _fontFamily))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text("삭제", style: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (result == true) await pvd.deleteProduct(p.id);
  }

  Future<void> _confirmBatchDelete(BuildContext context, ProductProvider pvd, String title, List<ProductModel> items) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("그룹 일괄 삭제", style: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold)),
        content: Text("[$title] 그룹의 모든 항목(${items.length}개)을 삭제하시겠습니까?", style: const TextStyle(fontFamily: _fontFamily)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소", style: TextStyle(fontFamily: _fontFamily))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text("전체 삭제", style: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (result == true) await pvd.deleteBatch(items);
  }

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
              final dynamicLabelStyle = TextStyle(fontSize: 12, color: Colors.black45, fontFamily: _fontFamily);

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Text(
                    p == null ? '신규 등록' : '정보 수정',
                    style: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold)
                ),
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
                              const SizedBox(width: 20),
                              Expanded(child: _buildInputs(nameC, sV, catC, locC, specC, tagC, qtyC, p, dynamicLabelStyle, (val) => sV = val)),
                            ],
                          )
                        else ...[
                          _buildImagePicker(p, previewBytes, setDialogState, (file, bytes) {
                            pickedFile = file; previewBytes = bytes;
                          }),
                          const SizedBox(height: 20),
                          _buildInputs(nameC, sV, catC, locC, specC, tagC, qtyC, p, dynamicLabelStyle, (val) => sV = val),
                        ],
                        const SizedBox(height: 15),
                        const Text(
                            "※ 이미지 변경 시 동일 품목(품명/규격 일치)의 모든 데이터에 반영됩니다.",
                            style: TextStyle(fontFamily: _fontFamily, fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w500)
                        ),
                        if (pvd.isSaving) const Padding(padding: EdgeInsets.only(top: 15), child: LinearProgressIndicator()),
                      ],
                    ),
                  ),
                ),
                actions: [
                  Row(
                    children: [
                      if (p != null)
                        TextButton(
                          onPressed: () async {
                            final result = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text("삭제 확인", style: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold)),
                                content: const Text("정말 삭제하시겠습니까?", style: TextStyle(fontFamily: _fontFamily)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("취소", style: TextStyle(fontFamily: _fontFamily))),
                                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("삭제", style: TextStyle(fontFamily: _fontFamily, color: Colors.red))),
                                ],
                              ),
                            );
                            if (result == true) {
                              if (await pvd.deleteProduct(p.id)) {
                                if (ctx.mounted) Navigator.of(ctx).pop();
                              }
                            }
                          },
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text("삭제", style: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold)),
                        ),
                      const Spacer(),
                      TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text("취소", style: TextStyle(fontFamily: _fontFamily))
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: pvd.isSaving ? null : () async {
                          if (nameC.text.isEmpty) return;
                          final nav = Navigator.of(ctx);
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
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold)
                        ),
                        child: const Text("저장"),
                      ),
                    ],
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
        final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
        if (image != null) {
          final bytes = await image.readAsBytes();
          setDS(() => onP(image, bytes));
        }
      },
      child: Container(
        width: 150, height: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey[300]!)
        ),
        child: preview != null
            ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(preview, fit: BoxFit.contain))
            : (p != null && p.image != null && p.image!.isNotEmpty)
            ? ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(_getImageUrl(p), fit: BoxFit.contain)
        )
            : const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, size: 30, color: Colors.grey),
            SizedBox(height: 8),
            Text("사진 등록", style: TextStyle(fontFamily: _fontFamily, color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputs(TextEditingController n, String s, TextEditingController c, TextEditingController l, TextEditingController sp, TextEditingController t, TextEditingController q, ProductModel? p, TextStyle style, Function onS) {
    return Column(
      children: [
        _buildTextField('품명', n, style),
        DropdownButtonFormField<String>(
          value: s,
          style: const TextStyle(fontFamily: _fontFamily, color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
          decoration: InputDecoration(
            labelText: '상태',
            labelStyle: style,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            isDense: true,
          ),
          items: _kStatusOptions.map((v) => DropdownMenuItem(
              value: v,
              child: Text(v, style: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold, fontSize: 16))
          )).toList(),
          onChanged: (v) { if (v != null) onS(v); },
        ),
        const SizedBox(height: 12),
        _buildTextField('분류', c, style),
        _buildTextField('보관위치', l, style),
        _buildTextField('규격', sp, style),
        _buildTextField('EPC (태그 ID)', t, style, readOnly: p != null),
        if (p == null) _buildTextField('초기 등록 수량', q, style, isNum: true),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController c, TextStyle s, {bool readOnly = false, bool isNum = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        readOnly: readOnly,
        style: const TextStyle(fontFamily: _fontFamily, fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: s.copyWith(fontFamily: _fontFamily),
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          fillColor: readOnly ? Colors.grey[50] : null,
          filled: readOnly,
        ),
      ),
    );
  }
}