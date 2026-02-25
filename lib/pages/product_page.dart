import 'package:flutter/material.dart';
import 'dart:math';
import '../models/products.dart';
import '../services/pb_service.dart';

/// 물품 관리 페이지 (커스텀 세그먼트 컨트롤 및 레이아웃 최적화 버전)
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

  List<ProductModel> _allList = [];
  bool _isLoading = false;
  bool _isSaving = false;
  final String _collectionName = 'products';

  String _groupByMode = 'item';

  final TextEditingController _searchController = TextEditingController();
  String _currentQuery = "";

  @override
  void initState() {
    super.initState();
    _currentQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
    _fetchData();
    _subscribe();
  }

  /// 데이터 집계 로직
  Map<String, List<ProductModel>> _getGroupedData(List<ProductModel> items) {
    Map<String, List<ProductModel>> grouped = {};
    for (var item in items) {
      String key = "";
      String cleanName = item.name.trim().isEmpty ? "품명 알 수 없음" : item.name.trim();
      String cleanSpec = (item.spec ?? "").trim();
      String cleanLoc = (item.location ?? "").trim().isEmpty ? "위치 알 수 없음" : item.location!.trim();
      String cleanCat = (item.category ?? "").trim().isEmpty ? "분류 알 수 없음" : item.category!.trim();

      if (_groupByMode == 'item') {
        key = cleanSpec.isEmpty ? cleanName : "$cleanName ($cleanSpec)";
      } else if (_groupByMode == 'location') {
        key = cleanLoc;
      } else {
        key = cleanCat;
      }

      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(item);
    }
    return grouped;
  }

  bool _isMatch(String? target, String query) {
    if (target == null || target.isEmpty) {
      return "알 수 없음".contains(query) || "모름".contains(query);
    }
    if (query.isEmpty) {
      return true;
    }
    final lowerTarget = target.toLowerCase();
    final lowerQuery = query.toLowerCase();
    if (lowerTarget.contains(lowerQuery)) {
      return true;
    }

    const chosungList = ['ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'];
    String chosungTarget = "";
    for (int i = 0; i < lowerTarget.length; i++) {
      int code = lowerTarget.codeUnitAt(i);
      if (code >= 0xAC00 && code <= 0xD7A3) {
        int index = (code - 0xAC00) ~/ 28 ~/ 21;
        chosungTarget += chosungList[index];
      } else {
        chosungTarget += lowerTarget[i];
      }
    }
    return chosungTarget.contains(lowerQuery);
  }

  @override
  void dispose() {
    PBService.pb.collection(_collectionName).unsubscribe('*');
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    if (!mounted) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      final records = await PBService.pb.collection(_collectionName).getFullList(sort: '-created');
      if (!mounted) {
        return;
      }
      setState(() {
        _allList = records.map((r) => ProductModel.fromJson(r.toJson())).toList();
      });
    } catch (e) {
      debugPrint("Load Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) {
      if (mounted) {
        _fetchData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredRaw = _allList.where((p) {
      return _isMatch(p.name, _currentQuery) ||
          _isMatch(p.tagId, _currentQuery) ||
          _isMatch(p.location, _currentQuery) ||
          _isMatch(p.category, _currentQuery) ||
          _isMatch(p.status, _currentQuery);
    }).toList();

    final groupedMap = _getGroupedData(filteredRaw);
    final groupKeys = groupedMap.keys.toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildSearchBar(),
          _buildCustomAggregationToggle(), // 커스텀으로 변경된 집계 전환 바
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 10, 26, 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildAggregatedHeader(),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
                          : groupKeys.isEmpty
                          ? const Center(child: Text("데이터가 없습니다.", style: TextStyle(fontFamily: _fontFamily)))
                          : _buildGroupedListView(groupKeys, groupedMap),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(null),
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  /// [핵심 수정] SegmentedButton 대신 직접 구현한 커스텀 토글 위젯
  /// 높이와 정렬을 완벽하게 제어할 수 있습니다.
  Widget _buildCustomAggregationToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      child: Container(
        height: 60, // 시원하게 키운 높이
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.indigo.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            _buildToggleItem('품목별 집계', 'item', Icons.inventory_2_outlined),
            _buildToggleItem('위치별 집계', 'location', Icons.location_on_outlined),
            _buildToggleItem('분류별 집계', 'category', Icons.category_outlined),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleItem(String label, String mode, IconData icon) {
    bool isSelected = _groupByMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _groupByMode = mode),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.indigo.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))]
                : [],
          ),
          // 핵심: Center 위젯으로 수직/수평 정중앙 정렬 보장
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: isSelected ? Colors.white : Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: _fontFamily,
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 15, 26, 5),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: _fontFamily),
        onChanged: (val) => setState(() => _currentQuery = val),
        decoration: InputDecoration(
          labelText: '물품 통합 검색',
          labelStyle: const TextStyle(fontSize: 16, color: Colors.black87, fontFamily: _fontFamily, fontWeight: FontWeight.w600),
          prefixIcon: const Icon(Icons.search, size: 28, color: Colors.indigo),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.indigo, width: 2.0)),
        ),
      ),
    );
  }

  /// 웅장한 헤더 (높이 확보)
  Widget _buildAggregatedHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.12),
        border: Border(bottom: BorderSide(color: Colors.indigo.withValues(alpha: 0.2), width: 2)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 50, child: Text('No', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo))),
          Expanded(flex: 3, child: Text(_groupByMode == 'item' ? '품명(규격)' : (_groupByMode == 'location' ? '보관 위치' : '분류'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo))),
          const Expanded(flex: 2, child: Text('상태 요약', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo))),
          const Expanded(flex: 1, child: Text('수량', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo))),
          const SizedBox(width: 120, child: Text('작업', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo))),
        ],
      ),
    );
  }

  /// 조밀한 목록
  Widget _buildGroupedListView(List<String> keys, Map<String, List<ProductModel>> groupedMap) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: keys.length,
      separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.withValues(alpha: 0.1)),
      itemBuilder: (context, index) {
        final key = keys[index];
        final groupItems = groupedMap[key]!;

        return InkWell(
          onTap: () => _showDetailGridDialog(key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 50, child: Text('${index + 1}', style: const TextStyle(fontSize: 14, color: Colors.grey))),
                Expanded(flex: 3, child: Text(key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Center(child: _buildStatusSummary(groupItems))),
                Expanded(flex: 1, child: Text('${groupItems.length}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 15))),
                SizedBox(
                  width: 120,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.list_alt, color: Colors.blueGrey, size: 24), onPressed: () => _showDetailGridDialog(key)),
                      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 24), onPressed: () => _confirmDeleteGroup(key, groupItems)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusSummary(List<ProductModel> items) {
    int normal = items.where((i) => i.status == '정상').length;
    int fault = items.length - normal;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fault == 0)
            _buildStatusBadge('전체정상', Colors.green)
          else if (fault > 0 && normal > 0) ...[
            _buildStatusBadge('정상 $normal', Colors.green),
            const SizedBox(width: 4),
            _buildStatusBadge('이상 $fault', Colors.red),
          ] else
            _buildStatusBadge('전체이상 $fault', Colors.red),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
  );

  void _showDetailGridDialog(String groupKey) {
    final ScrollController detailGridController = ScrollController();
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredData = _allList.where((p) => _isMatch(p.name, _currentQuery) || _isMatch(p.tagId, _currentQuery) || _isMatch(p.location, _currentQuery) || _isMatch(p.category, _currentQuery) || _isMatch(p.status, _currentQuery)).toList();
            final grouped = _getGroupedData(filteredData);
            final items = grouped[groupKey] ?? [];

            if (items.isEmpty && !_isLoading && context.mounted) {
              Future.delayed(Duration.zero, () {
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              });
            }

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.inventory_2, color: Colors.indigo),
                  const SizedBox(width: 10),
                  Expanded(child: Text('$groupKey 상세 정보', style: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold, fontSize: 20), overflow: TextOverflow.ellipsis)),
                  Text("총 ${items.length}개", style: const TextStyle(fontSize: 16, color: Colors.indigo, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                height: 650,
                child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                        decoration: BoxDecoration(color: Colors.grey[200]),
                        child: const Row(
                          children: [
                            SizedBox(width: 45, child: Text('No', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                            Expanded(flex: 3, child: Text('RFID EPC (Tag ID)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                            Expanded(flex: 1, child: Text('상태', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                            Expanded(flex: 2, child: Text('보관 위치', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                            Expanded(flex: 2, child: Text('분류', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                            SizedBox(width: 100, child: Text('작업', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: detailGridController,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: detailGridController,
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              String dS = (item.status.trim().isEmpty) ? "알 수 없음" : item.status;
                              String dL = (item.location ?? "").trim().isEmpty ? "위치 알 수 없음" : item.location!;
                              String dC = (item.category ?? "").trim().isEmpty ? "분류 알 수 없음" : item.category!;
                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[100]!))),
                                child: Row(
                                  children: [
                                    SizedBox(width: 45, child: Text('${index + 1}', style: const TextStyle(fontSize: 13, color: Colors.grey))),
                                    Expanded(flex: 3, child: Text(item.tagId, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo), overflow: TextOverflow.ellipsis)),
                                    Expanded(flex: 1, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: _buildStatusBadge(dS, dS == '정상' ? Colors.green : (dS == '알 수 없음' ? Colors.grey : Colors.orange))))),
                                    Expanded(flex: 2, child: Text(dL, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                                    Expanded(flex: 2, child: Text(dC, style: const TextStyle(fontSize: 14, color: Colors.blueGrey), overflow: TextOverflow.ellipsis)),
                                    SizedBox(width: 100, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_note, color: Colors.blue, size: 24), onPressed: () async {
                                        final n = Navigator.of(context);
                                        await _showForm(item);
                                        if (n.context.mounted) {
                                          setDialogState(() {});
                                        }
                                      }),
                                      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 24), onPressed: () async {
                                        final n = Navigator.of(context);
                                        if (await _confirmDelete(item) && n.context.mounted) {
                                          setDialogState(() {});
                                        }
                                      }),
                                    ])),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [TextButton(onPressed: () => context.mounted ? Navigator.of(context).pop() : null, child: const Text("닫기", style: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold, fontSize: 16)))],
            );
          }
      ),
    );
  }

  Future<void> _showForm(ProductModel? p) async {
    if (!mounted) {
      return;
    }
    final nameC = TextEditingController(text: p?.name ?? "");
    final tagC = TextEditingController(text: p?.tagId ?? "");
    final qtyC = TextEditingController(text: "1");
    final locC = TextEditingController(text: p?.location ?? "");
    final specC = TextEditingController(text: p?.spec ?? "");
    final catC = TextEditingController(text: p?.category ?? "");
    String sV = (p?.status == null || p!.status.trim().isEmpty) ? '알 수 없음' : p.status;
    if (!_kStatusOptions.contains(sV)) {
      sV = _kStatusOptions.last;
    }
    const lS = TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.black45, fontFamily: _fontFamily);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(p == null ? '신규 물품 등록' : '개별 태그 정보 수정', style: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInputGroup('품명 (필수)', nameC, lS),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: DropdownButtonFormField<String>(
                value: sV, isDense: true, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87, fontFamily: _fontFamily),
                decoration: InputDecoration(labelText: '상태', labelStyle: lS, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                items: _kStatusOptions.map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, fontFamily: _fontFamily)))).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() => sV = v);
                  }
                },
              )),
              _buildInputGroup('분류', catC, lS), _buildInputGroup('보관 위치', locC, lS), _buildInputGroup('규격/상세', specC, lS),
              _buildInputGroup('RFID EPC', tagC, lS, isReadOnly: p != null),

              if (p == null)
                _buildInputGroup('등록 수량 (낱개 생성)', qtyC, lS, isNumber: true),

              if (_isSaving)
                const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () {
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          }, child: const Text("취소", style: TextStyle(fontFamily: _fontFamily))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white), onPressed: _isSaving ? null : () async {
            if (nameC.text.isEmpty) {
              return;
            }
            final n = Navigator.of(context);
            setDialogState(() => _isSaving = true);
            final sS = sV == '알 수 없음' ? '' : sV;
            final d = {'name': nameC.text.trim(), 'tag_id': tagC.text.trim(), 'bulk_count': int.tryParse(qtyC.text) ?? 1, 'location': locC.text.trim(), 'spec': specC.text.trim(), 'category': catC.text.trim(), 'status': sS};
            await _saveProduct(p: p, data: d, navigator: n);
            if (context.mounted) {
              setDialogState(() => _isSaving = false);
            }
          }, child: const Text("저장", style: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold))),
        ],
      )),
    );
  }

  Widget _buildInputGroup(String label, TextEditingController c, TextStyle lS, {bool isReadOnly = false, bool isNumber = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextField(controller: c, readOnly: isReadOnly, keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: _fontFamily, fontSize: 14),
      decoration: InputDecoration(labelText: label, labelStyle: lS, border: const OutlineInputBorder(), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
    ),
  );

  void _confirmDeleteGroup(String gK, List<ProductModel> items) {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('그룹 일괄 삭제', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
        content: Text('[$gK] 그룹의 태그 ${items.length}개를 모두 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () {
            if (dCtx.mounted) {
              Navigator.of(dCtx).pop();
            }
          }, child: const Text('취소')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () async {
            final n = Navigator.of(dCtx);
            if (n.context.mounted) {
              n.pop();
            }
            await _deleteBatch(items);
          }, child: const Text('모두 삭제', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Future<void> _deleteBatch(List<ProductModel> items) async {
    if (!mounted) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      for (var item in items) {
        await PBService.pb.collection(_collectionName).delete(item.id);
      }
      if (mounted) {
        await _fetchData();
      }
    } catch (e) {
      debugPrint("Delete Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProduct({required ProductModel? p, required Map<String, dynamic> data, required NavigatorState navigator}) async {
    try {
      if (p == null) {
        final int count = data['bulk_count'] ?? 1;
        for (int i = 0; i < count; i++) {
          await PBService.pb.collection(_collectionName).create(body: {'name': data['name'], 'tag_id': count > 1 ? "${data['tag_id']}_${DateTime.now().millisecondsSinceEpoch}_$i" : data['tag_id'], 'quantity': 1, 'location': data['location'], 'spec': data['spec'], 'category': data['category'], 'status': data['status']});
        }
      } else {
        await PBService.pb.collection(_collectionName).update(p.id, body: data);
      }
      if (navigator.context.mounted) {
        navigator.pop();
        if (mounted) {
          await _fetchData();
        }
      }
    } catch (e) {
      debugPrint("Save Error: $e");
    }
  }

  Future<bool> _confirmDelete(ProductModel p) async {
    if (!mounted) {
      return false;
    }
    bool deleted = false;
    await showDialog(context: context, builder: (dCtx) => AlertDialog(
      title: const Text('삭제 확인', style: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold)),
      content: Text('태그 [${p.tagId}] 항목을 삭제하시겠습니까?'),
      actions: [
        TextButton(onPressed: () {
          if (dCtx.mounted) {
            Navigator.of(dCtx).pop();
          }
        }, child: const Text('취소')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () async {
          final n = Navigator.of(dCtx);
          try {
            await PBService.pb.collection(_collectionName).delete(p.id);
            deleted = true;
            if (n.context.mounted) {
              n.pop();
              if (mounted) {
                await _fetchData();
              }
            }
          } catch (e) {
            debugPrint("Delete Fail");
          }
        }, child: const Text('삭제', style: TextStyle(color: Colors.white))),
      ],
    ));
    return deleted;
  }
}