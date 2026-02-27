import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';

import '../models/products.dart';
import '../providers/product_provider.dart';

/// 디자인 상수
const String _fontPretendard = 'Pretendard';
const Color _primaryColor = Color(0xFF6366F1);
const Color _surfaceColor = Color(0xFFF8FAFC);
const Color _borderColor = Color(0xFF475569);

class ProductPage extends StatefulWidget {
  final String searchQuery;
  final bool isMobile;
  final String baseUrl;

  const ProductPage({
    super.key,
    required this.searchQuery,
    required this.isMobile,
    required this.baseUrl,
  });

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  final TextEditingController _searchController = TextEditingController();
  String _currentQuery = "";
  String _groupByMode = 'item';
  String? _selectedGroupKey;

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

  Map<String, List<ProductModel>> _getGroupedData(List<ProductModel> items) {
    final Map<String, List<ProductModel>> grouped = {};
    for (var item in items) {
      String key = "";
      if (_groupByMode == 'item') {
        key = item.name;
      } else if (_groupByMode == 'location') {
        key = item.location ?? "위치 미지정";
      } else {
        key = item.category ?? "분류 미지정";
      }
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(item);
    }
    return grouped;
  }

  void _checkRfidStatus(ProductProvider provider) {
    if (provider.lastScannedTag.isNotEmpty) {
      final tag = provider.lastScannedTag;
      provider.clearLastScannedTag();

      final found = provider.findProductByTag(tag);
      if (found != null) {
        setState(() => _selectedGroupKey = _getGroupKeyOf(found));
        _showForm(context, provider, found);
      } else {
        _showForm(context, provider, null, initialTag: tag);
      }
    }
  }

  String _getGroupKeyOf(ProductModel p) {
    if (_groupByMode == 'item') return p.name;
    if (_groupByMode == 'location') return p.location ?? "위치 미지정";
    return p.category ?? "분류 미지정";
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRfidStatus(provider));

    final filteredRaw = provider.items.where((p) {
      final query = _currentQuery.toLowerCase();
      return p.name.toLowerCase().contains(query) || p.tagId.toLowerCase().contains(query);
    }).toList();

    final groupedMap = _getGroupedData(filteredRaw);
    final groupKeys = groupedMap.keys.toList()..sort();

    return Scaffold(
      backgroundColor: Colors.white,
      body: DefaultTextStyle(
        style: const TextStyle(fontFamily: _fontPretendard, color: Colors.black),
        child: Column(
          children: [
            if (provider.isParsing || provider.isSaving)
              const LinearProgressIndicator(minHeight: 3, backgroundColor: Colors.transparent, color: _primaryColor),
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth > 950 && !widget.isMobile) {
                  return _buildSplitLayout(provider, groupedMap, groupKeys, filteredRaw);
                }
                return _buildMobileLayout(provider, groupedMap, groupKeys);
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys, List<ProductModel> filtered) {
    final selectedItems = _selectedGroupKey != null ? groupedMap[_selectedGroupKey] : null;

    return Row(
      children: [
        SizedBox(
          width: 480,
          child: Column(
            children: [
              _buildHeader(provider, filtered, isSplit: true),
              _buildGroupByToggle(),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: groupKeys.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    final key = groupKeys[idx];
                    final items = groupedMap[key]!;
                    return _buildGroupTile(provider, key, items, _selectedGroupKey == key, () => setState(() => _selectedGroupKey = key));
                  },
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),
        Expanded(
          child: Container(
            color: _surfaceColor,
            child: (_selectedGroupKey == null || selectedItems == null)
                ? _buildEmptyState("상세 정보를 확인하려면 목록에서 그룹을 선택하세요")
                : _buildGroupDetailList(provider, _selectedGroupKey!, selectedItems),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys) {
    return Column(
      children: [
        _buildHeader(provider, provider.items, isSplit: false),
        _buildGroupByToggle(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: groupKeys.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, idx) {
              final key = groupKeys[idx];
              final items = groupedMap[key]!;
              return _buildGroupTile(provider, key, items, false, () => _showMobileGroupDetail(provider, key, items));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGroupByToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          _toggleBtn('item', '품목별'),
          const SizedBox(width: 8),
          _toggleBtn('location', '위치별'),
          const SizedBox(width: 8),
          _toggleBtn('category', '분류별'),
        ],
      ),
    );
  }

  Widget _toggleBtn(String mode, String label) {
    final isSelected = _groupByMode == mode;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontFamily: _fontPretendard, fontSize: 12)),
      selected: isSelected,
      onSelected: (val) { if (val) setState(() { _groupByMode = mode; _selectedGroupKey = null; }); },
      selectedColor: _primaryColor,
      backgroundColor: _surfaceColor,
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
    );
  }

  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, VoidCallback onTap) {
    final firstItem = items.first;
    final totalQty = items.fold<int>(0, (sum, item) => sum + item.quantity);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? _primaryColor.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? _primaryColor : const Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _buildThumbnail(firstItem, size: 40),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(firstItem.spec ?? "-", style: TextStyle(fontFamily: _fontPretendard, fontSize: 11, color: Colors.grey.shade500), maxLines: 1),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(firstItem.category ?? "-", style: const TextStyle(fontFamily: _fontPretendard, fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
                    Text(firstItem.location ?? "-", style: TextStyle(fontFamily: _fontPretendard, fontSize: 11, color: Colors.blueGrey.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Text('$totalQty', style: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.w900, fontSize: 13, color: _primaryColor)),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.redAccent),
                onPressed: () => _confirmBatchDelete(context, provider, items),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupDetailList(ProductProvider provider, String groupName, List<ProductModel> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Text('$groupName - 세부 내역', style: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.w900, fontSize: 18)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (ctx, idx) {
              final p = items[idx];
              List<Widget> metaWidgets = [];
              p.metadata.forEach((k, v) {
                if (v.toString().isNotEmpty) {
                  metaWidgets.add(
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('$k: $v', style: const TextStyle(fontFamily: _fontPretendard, fontSize: 11, color: Colors.indigo, fontWeight: FontWeight.w500)),
                      )
                  );
                }
              });

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
                child: ListTile(
                  onTap: () => _showForm(context, provider, p),
                  leading: _buildThumbnail(p, size: 44),
                  title: Row(
                    children: [
                      Text(p.name, style: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 8),
                      _buildStatusBadge(p.status),
                    ],
                  ),
                  subtitle: Wrap(children: metaWidgets.isEmpty ? [const Text("추가 정보 없음", style: TextStyle(fontFamily: _fontPretendard, fontSize: 11))] : metaWidgets),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey[300]!)),
                        child: Text(p.tagId, style: TextStyle(fontFamily: _fontPretendard, color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                        onPressed: () => _confirmIndividualDelete(context, provider, p),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color c = status == '정상' ? Colors.green : (status == '수리필요' ? Colors.orange : Colors.red);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(status, style: TextStyle(fontFamily: _fontPretendard, color: c, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }

  Widget _buildThumbnail(ProductModel p, {double size = 50}) {
    final url = p.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined))
          : Icon(Icons.camera_alt_outlined, color: Colors.grey.withValues(alpha: 0.5), size: size * 0.5),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.inventory_2_outlined, size: 64, color: Color(0xFFE2E8F0)),
      const SizedBox(height: 16),
      Text(msg, style: TextStyle(fontFamily: _fontPretendard, color: Colors.grey.withValues(alpha: 0.8))),
    ]));
  }

  Widget _buildHeader(ProductProvider provider, List<ProductModel> filtered, {required bool isSplit}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // [해결] 타이틀을 Expanded로 감싸고 폰트 적용하여 Overflow 방지
              const Expanded(
                child: Text('자산 통합 관리',
                  style: TextStyle(fontFamily: _fontPretendard, fontSize: 22, fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                children: [
                  IconButton(onPressed: () => provider.fetchData(), icon: const Icon(Icons.refresh, color: _primaryColor)),
                  IconButton(onPressed: () => provider.batchImportFromExcel(), icon: const FaIcon(FontAwesomeIcons.fileArrowUp, size: 18, color: Colors.indigo)),
                  IconButton(onPressed: () => _exportToExcel(context, filtered), icon: const FaIcon(FontAwesomeIcons.fileArrowDown, size: 18, color: Colors.green)),
                  IconButton(onPressed: () => _showResetDialog(provider), icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent)),
                  IconButton(onPressed: () => _showForm(context, provider, null), icon: const Icon(Icons.add_circle, color: _primaryColor, size: 30)),
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _currentQuery = v),
            decoration: InputDecoration(
              hintText: '검색...',
              hintStyle: const TextStyle(fontFamily: _fontPretendard),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: _surfaceColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showForm(BuildContext context, ProductProvider provider, ProductModel? p, {String? initialTag}) async {
    final nav = Navigator.of(context);
    final nameC = TextEditingController(text: p?.name ?? "");
    final tagC = TextEditingController(text: initialTag ?? p?.tagId ?? "");
    final locC = TextEditingController(text: p?.location ?? "");
    final specC = TextEditingController(text: p?.spec ?? "");
    final catC = TextEditingController(text: p?.category ?? "");
    final remC = TextEditingController(text: p?.remarks ?? "");
    final qtyC = TextEditingController(text: "1");

    String selectedStatus = p?.status ?? "정상";

    final Map<String, TextEditingController> dynamicControllers = {};
    if (p != null) {
      // [해결] 린트 에러: metadata null 체크 간소화
      p.metadata.forEach((key, value) {
        if (!['name', 'tag_id', 'location', 'spec', 'category', 'remarks', 'quantity', 'status'].contains(key)) {
          dynamicControllers[key] = TextEditingController(text: value.toString());
        }
      });
    }

    XFile? file;
    Uint8List? preview;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (dialogCtx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(p == null ? '신규 등록' : '정보 수정', style: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Padding(
              // [해결] 우측 테두리가 지워지는 현상을 방지하기 위해 여백 추가
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(child: _buildFormImagePicker(p, preview, (f, b) => setS(() { file = f; preview = b; }))),
                  const SizedBox(height: 24),
                  _ProductField(label: '품명 (필수)', controller: nameC, maxLines: 1),
                  _ProductField(label: 'RFID TAG ID', controller: tagC, maxLines: 1),
                  Row(children: [
                    Expanded(child: _ProductField(label: '분류', controller: catC, maxLines: 1)),
                    const SizedBox(width: 10),
                    Expanded(child: _ProductField(label: '위치', controller: locC, maxLines: 1))
                  ]),
                  Row(children: [
                    Expanded(child: _ProductField(label: '규격 / 모델명', controller: specC, maxLines: 1)),
                    const SizedBox(width: 10),
                    Expanded(child: _ProductField(label: '생성 수량', controller: qtyC, maxLines: 1, keyboardType: TextInputType.number))
                  ]),
                  Row(children: [
                    // [해결] 상태 콤보박스 - 폰트 적용 및 Deprecated value 경고 해결
                    Expanded(child: _ProductSelectField(
                      label: '상태',
                      initialValue: selectedStatus,
                      items: const ['정상', '수리필요', '폐기', '분실'],
                      onChanged: (v) { if (v != null) selectedStatus = v; },
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ProductField(label: '비고', controller: remC, maxLines: 1))
                  ]),

                  if (dynamicControllers.isNotEmpty) ...[
                    const Divider(height: 40),
                    const Center(child: Text("추가 속성 (가변 항목)", style: TextStyle(fontFamily: _fontPretendard, fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor))),
                    const SizedBox(height: 16),
                    ...(() {
                      final keys = dynamicControllers.keys.toList();
                      final List<Widget> rows = [];
                      for (int i = 0; i < keys.length; i += 2) {
                        rows.add(Row(children: [
                          Expanded(child: _ProductField(label: keys[i], controller: dynamicControllers[keys[i]]!, maxLines: 1)),
                          const SizedBox(width: 10),
                          Expanded(child: (i + 1 < keys.length) ? _ProductField(label: keys[i + 1], controller: dynamicControllers[keys[i + 1]]!, maxLines: 1) : const SizedBox()),
                        ]));
                      }
                      return rows;
                    })(),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text("취소", style: TextStyle(fontFamily: _fontPretendard))),
          ElevatedButton(
              onPressed: provider.isSaving ? null : () async {
                if (nameC.text.isEmpty) return;
                final int count = int.tryParse(qtyC.text) ?? 1;
                final data = {
                  'name': nameC.text.trim(),
                  'tag_id': tagC.text.trim(),
                  'location': locC.text.trim(),
                  'spec': specC.text.trim(),
                  'category': catC.text.trim(),
                  'remarks': remC.text.trim(),
                  'quantity': 1,
                  'status': selectedStatus,
                  'metadata': dynamicControllers.map((k, v) => MapEntry(k, v.text.trim())),
                };
                bool overallSuccess = true;
                if (p == null) {
                  for (int i = 0; i < count; i++) {
                    final success = await provider.handleSave(p: null, data: data, imageXFile: file);
                    if (!success) overallSuccess = false;
                  }
                } else {
                  overallSuccess = await provider.handleSave(p: p, data: data, imageXFile: file);
                }
                if (overallSuccess && dialogCtx.mounted) nav.pop();
              },
              child: Text(provider.isSaving ? "저장 중..." : "저장", style: const TextStyle(fontFamily: _fontPretendard))
          )
        ],
      )),
    );
  }

  Widget _buildFormImagePicker(ProductModel? p, Uint8List? preview, Function(XFile, Uint8List) onPicked) {
    return GestureDetector(
      onTap: () async {
        final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
        if (img != null) {
          final bytes = await img.readAsBytes();
          onPicked(img, bytes);
        }
      },
      child: Container(
        width: 120, height: 120,
        decoration: BoxDecoration(color: _surfaceColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: preview != null ? Image.memory(preview, fit: BoxFit.contain) : _buildThumbnail(p ?? ProductModel(name: '', tagId: ''), size: 120),
      ),
    );
  }

  void _confirmIndividualDelete(BuildContext context, ProductProvider provider, ProductModel p) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('삭제 확인', style: TextStyle(fontFamily: _fontPretendard)),
      content: Text('${p.name} 물품을 삭제하시겠습니까?', style: const TextStyle(fontFamily: _fontPretendard)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(fontFamily: _fontPretendard))),
        ElevatedButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              await provider.deleteProduct(p.id);
              if (ctx.mounted) nav.pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제', style: TextStyle(fontFamily: _fontPretendard))
        ),
      ],
    ));
  }

  void _confirmBatchDelete(BuildContext context, ProductProvider provider, List<ProductModel> items) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('그룹 삭제', style: TextStyle(fontFamily: _fontPretendard)),
      content: Text('해당 그룹의 모든 자산(${items.length}개)을 삭제하시겠습니까?', style: const TextStyle(fontFamily: _fontPretendard)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(fontFamily: _fontPretendard))),
        ElevatedButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              for (var i in items) { await provider.deleteProduct(i.id); }
              if (ctx.mounted) {
                setState(() { _selectedGroupKey = null; });
                nav.pop();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('그룹 삭제', style: TextStyle(fontFamily: _fontPretendard))
        ),
      ],
    ));
  }

  void _showResetDialog(ProductProvider provider) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('전체 초기화', style: TextStyle(fontFamily: _fontPretendard, color: Colors.red, fontWeight: FontWeight.bold)),
      content: const Text('서버의 모든 물품 데이터를 삭제합니다.', style: TextStyle(fontFamily: _fontPretendard)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(fontFamily: _fontPretendard))),
        ElevatedButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              await provider.resetAllProducts();
              if (ctx.mounted) nav.pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('전체 삭제', style: TextStyle(fontFamily: _fontPretendard))
        )
      ],
    ));
  }

  Future<void> _exportToExcel(BuildContext context, List<ProductModel> list) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['물품리스트'];
      excel.rename('Sheet1', '물품리스트');
      sheet.appendRow([excel_pkg.TextCellValue('품명'), excel_pkg.TextCellValue('태그ID'), excel_pkg.TextCellValue('분류'), excel_pkg.TextCellValue('위치'), excel_pkg.TextCellValue('규격'), excel_pkg.TextCellValue('비고')]);
      for (var item in list) {
        sheet.appendRow([excel_pkg.TextCellValue(item.name), excel_pkg.TextCellValue(item.tagId), excel_pkg.TextCellValue(item.category ?? ""), excel_pkg.TextCellValue(item.location ?? ""), excel_pkg.TextCellValue(item.spec ?? ""), excel_pkg.TextCellValue(item.remarks ?? "")]);
      }
      final String? path = await FilePicker.platform.saveFile(fileName: '물품관리_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx']);
      if (path != null) {
        await File(path).writeAsBytes(excel.encode()!);
        messenger.showSnackBar(const SnackBar(content: Text('엑셀 파일이 저장되었습니다.', style: TextStyle(fontFamily: _fontPretendard))));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('저장 실패: $e', style: const TextStyle(fontFamily: _fontPretendard))));
    }
  }

  void _showMobileGroupDetail(ProductProvider provider, String groupName, List<ProductModel> items) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: _buildGroupDetailList(provider, groupName, items),
    ));
  }
}

class _ProductField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType keyboardType;

  const _ProductField({
    required this.label,
    required this.controller,
    required this.maxLines,
    this.keyboardType = TextInputType.text,
  });

  @override
  State<_ProductField> createState() => _ProductFieldState();
}

class _ProductFieldState extends State<_ProductField> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        style: const TextStyle(fontFamily: _fontPretendard, fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: widget.label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: const TextStyle(fontFamily: _fontPretendard, color: _primaryColor, fontSize: 13, fontWeight: FontWeight.normal),
          isDense: true,
          filled: true,
          fillColor: _focusNode.hasFocus ? Colors.white : Colors.grey[200],
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _borderColor, width: 1.0)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primaryColor, width: 2.0)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _borderColor)),
        ),
      ),
    );
  }
}

class _ProductSelectField extends StatelessWidget {
  final String label;
  final String initialValue;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _ProductSelectField({
    required this.label,
    required this.initialValue,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: initialValue,
        // [해결] 드롭다운 메뉴 아이템에도 프리텐다드 및 굵기 적용
        items: items.map((e) => DropdownMenuItem(
            value: e,
            child: Text(e, style: const TextStyle(fontFamily: _fontPretendard, fontSize: 14, fontWeight: FontWeight.bold))
        )).toList(),
        onChanged: onChanged,
        style: const TextStyle(fontFamily: _fontPretendard, color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: const TextStyle(fontFamily: _fontPretendard, color: _primaryColor, fontSize: 13, fontWeight: FontWeight.normal),
          isDense: true,
          filled: true,
          fillColor: Colors.grey[200],
          // [해결] 텍스트필드와 완벽히 동일한 높이(vertical 15 효과)를 갖도록 패딩 조정
          contentPadding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _borderColor, width: 1.0)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _borderColor)),
        ),
      ),
    );
  }
}