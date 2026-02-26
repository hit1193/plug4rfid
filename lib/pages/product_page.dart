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
const Color _borderColor = Color(0xFFE2E8F0);

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

  // 집계 모드: 'item'(품명), 'location'(위치), 'category'(분류)
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

  /// 데이터 그룹화 (Aggregation)
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
      if (!grouped.containsKey(key)) grouped[key] = [];
      grouped[key]!.add(item);
    }
    return grouped;
  }

  /// RFID 인식 시 자동 반응 로직
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
            // [개선] 진행바를 최상단에 배치하여 시인성 확보 (crHourGlass 효과)
            if (provider.isParsing || provider.isSaving)
              const LinearProgressIndicator(minHeight: 3, backgroundColor: Colors.transparent, color: _primaryColor),

            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth > 950 && !widget.isMobile) {
                  return _buildSplitLayout(provider, groupedMap, groupKeys);
                }
                return _buildMobileLayout(provider, groupedMap, groupKeys);
              }),
            ),
          ],
        ),
      ),
    );
  }

  // --- [레이아웃] 1. 데스크톱/태블릿 Split View ---
  Widget _buildSplitLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys) {
    final selectedItems = _selectedGroupKey != null ? groupedMap[_selectedGroupKey] : null;

    return Row(
      children: [
        SizedBox(
          width: 420,
          child: Column(
            children: [
              _buildHeader(provider, provider.items, isSplit: true),
              _buildGroupByToggle(),
              Expanded(
                child: RepaintBoundary(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: groupKeys.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, idx) {
                      final key = groupKeys[idx];
                      final items = groupedMap[key]!;
                      final isSelected = _selectedGroupKey == key;
                      return _buildGroupTile(provider, key, items, isSelected, () => setState(() => _selectedGroupKey = key));
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: _borderColor),
        Expanded(
          child: Container(
            color: _surfaceColor,
            child: RepaintBoundary(
              child: (_selectedGroupKey == null || selectedItems == null)
                  ? _buildEmptyState("상세 정보를 확인하려면 목록에서 그룹을 선택하세요")
                  : _buildGroupDetailList(provider, _selectedGroupKey!, selectedItems),
            ),
          ),
        ),
      ],
    );
  }

  // --- [레이아웃] 2. 모바일용 리스트 ---
  Widget _buildMobileLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys) {
    return Column(
      children: [
        _buildHeader(provider, provider.items, isSplit: false),
        _buildGroupByToggle(),
        Expanded(
          child: RepaintBoundary(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: groupKeys.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final key = groupKeys[idx];
                final items = groupedMap[key]!;
                return _buildGroupTile(provider, key, items, false, () {
                  _showMobileGroupDetail(provider, key, items);
                });
              },
            ),
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
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (val) { if (val) setState(() { _groupByMode = mode; _selectedGroupKey = null; }); },
      selectedColor: _primaryColor,
      backgroundColor: _surfaceColor,
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
    );
  }

  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, VoidCallback onTap) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? _primaryColor.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? _primaryColor : _borderColor),
      ),
      child: ListTile(
        onTap: onTap,
        leading: _buildThumbnail(items.first, size: 40),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('자산 수량: ${items.length}개', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.redAccent),
              onPressed: () => _confirmBatchDelete(context, provider, items),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
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
          child: Text('$groupName (${items.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (ctx, idx) {
              final p = items[idx];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _borderColor)),
                child: ListTile(
                  onTap: () => _showForm(context, provider, p),
                  leading: _buildThumbnail(p, size: 44),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('TAG: ${p.tagId}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildBadge(p.status),
                      const SizedBox(width: 8),
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

  Widget _buildThumbnail(ProductModel p, {double size = 50}) {
    final url = p.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: _borderColor)),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined))
          : Icon(Icons.camera_alt_outlined, color: Colors.grey.withValues(alpha: 0.5), size: size * 0.5),
    );
  }

  Widget _buildBadge(String status) {
    Color c = status == '정상' ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(status, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.inventory_2_outlined, size: 64, color: _borderColor),
      const SizedBox(height: 16),
      Text(msg, style: TextStyle(color: Colors.grey.withValues(alpha: 0.8))),
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
              const Text('자산 통합 관리', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              Row(
                children: [
                  _headerIcon(Icons.refresh, "새로고침", () => provider.fetchData(), color: _primaryColor),

                  // [핵심 수정] 업로드 로직에 즉각 피드백 및 에러 처리 추가
                  _headerIcon(FontAwesomeIcons.fileArrowUp, "엑셀 업로드", () async {
                    if (provider.isParsing) return; // 중복 클릭 방지

                    final messenger = ScaffoldMessenger.of(context);
                    // 시작 안내
                    messenger.showSnackBar(const SnackBar(content: Text('엑셀 파일을 선택해주세요...'), duration: Duration(seconds: 1)));

                    try {
                      final result = await provider.batchImportFromExcel();

                      if (!context.mounted) return;

                      if (result['total']! > 0) {
                        messenger.hideCurrentSnackBar();
                        messenger.showSnackBar(SnackBar(
                          content: Text('업로드 완료: 총 ${result['total']}건 중 ${result['success']}건 성공'),
                          backgroundColor: Colors.green,
                        ));
                      } else {
                        // 결과가 0인 경우 (취소했거나 파일이 비어있는 경우)
                        messenger.hideCurrentSnackBar();
                        messenger.showSnackBar(const SnackBar(content: Text('업로드할 데이터가 없거나 취소되었습니다.')));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        messenger.showSnackBar(SnackBar(content: Text('에러 발생: $e'), backgroundColor: Colors.red));
                      }
                    }
                  }, color: Colors.indigo),

                  _headerIcon(FontAwesomeIcons.fileArrowDown, "엑셀 다운로드", () => _exportToExcel(context, filtered), color: Colors.green),
                  _headerIcon(Icons.delete_sweep_outlined, "전체 초기화", () => _showResetDialog(provider), color: Colors.redAccent),
                  if (!isSplit) ...[const SizedBox(width: 8), _circleAction(Icons.add, () => _showForm(context, provider, null), color: _primaryColor)],
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _currentQuery = v),
              decoration: InputDecoration(
                hintText: '품명 또는 TAG ID 검색...',
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true,
                fillColor: _surfaceColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerIcon(IconData icon, String tip, VoidCallback onTap, {required Color color}) {
    return IconButton(onPressed: onTap, tooltip: tip, icon: FaIcon(icon, size: 18, color: color));
  }

  Widget _circleAction(IconData icon, VoidCallback onTap, {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(color: color?.withValues(alpha: 0.1) ?? _surfaceColor, shape: BoxShape.circle),
      child: IconButton(icon: Icon(icon, size: 20, color: color ?? Colors.blueGrey), onPressed: onTap),
    );
  }

  // --- 비동기 Context 안전하게 처리된 폼 ---
  Future<void> _showForm(BuildContext context, ProductProvider provider, ProductModel? p, {String? initialTag}) async {
    final nav = Navigator.of(context);

    final nameC = TextEditingController(text: p?.name ?? "");
    final tagC = TextEditingController(text: initialTag ?? p?.tagId ?? "");
    final locC = TextEditingController(text: p?.location ?? "");
    final specC = TextEditingController(text: p?.spec ?? "");
    final catC = TextEditingController(text: p?.category ?? "");
    final remC = TextEditingController(text: p?.remarks ?? "");

    final Map<String, TextEditingController> dynamicControllers = {};
    if (p != null) {
      p.metadata.forEach((key, value) {
        if (!['name', 'tag_id', 'location', 'spec', 'category', 'remarks'].contains(key)) {
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
        title: Text(p == null ? '신규 등록' : '정보 수정', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFormImagePicker(p, preview, (f, b) => setS(() { file = f; preview = b; })),
                const SizedBox(height: 24),
                _fld('품명 (필수)', nameC),
                _fld('RFID TAG ID', tagC),
                Row(children: [Expanded(child: _fld('분류', catC)), const SizedBox(width: 10), Expanded(child: _fld('위치', locC))]),
                _fld('규격 / 모델명', specC),

                if (dynamicControllers.isNotEmpty) ...[
                  const Divider(height: 32),
                  const Text("추가 속성 (가변 항목)", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    children: dynamicControllers.entries.map((e) => SizedBox(width: 240, child: _fld(e.key, e.value))).toList(),
                  ),
                ],
                _fld('비고', remC, maxLines: 2),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text("취소")),
          ElevatedButton(
              onPressed: provider.isSaving ? null : () async {
                if (nameC.text.isEmpty) return;
                final success = await provider.handleSave(p: p, data: {
                  'name': nameC.text.trim(), 'tag_id': tagC.text.trim(),
                  'location': locC.text.trim(), 'spec': specC.text.trim(),
                  'category': catC.text.trim(), 'remarks': remC.text.trim(),
                  'quantity': 1, 'status': '정상',
                  'metadata': dynamicControllers.map((k, v) => MapEntry(k, v.text.trim())),
                }, imageXFile: file);

                if (success && dialogCtx.mounted) {
                  nav.pop();
                }
              },
              child: Text(provider.isSaving ? "처리 중..." : "저장")
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
        decoration: BoxDecoration(color: _surfaceColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: _borderColor)),
        child: preview != null ? Image.memory(preview, fit: BoxFit.contain) : _buildThumbnail(p ?? ProductModel(name: '', tagId: ''), size: 120),
      ),
    );
  }

  Widget _fld(String l, TextEditingController c, {int maxLines = 1}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
          controller: c, maxLines: maxLines, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: l, labelStyle: const TextStyle(fontSize: 12, color: _primaryColor, fontWeight: FontWeight.normal),
            border: const OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white,
          )
      )
  );

  void _confirmIndividualDelete(BuildContext context, ProductProvider provider, ProductModel p) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('삭제 확인'), content: Text('${p.name} 물품을 삭제하시겠습니까?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
        ElevatedButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              await provider.deleteProduct(p.id);
              if (ctx.mounted) nav.pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제')
        ),
      ],
    ));
  }

  void _confirmBatchDelete(BuildContext context, ProductProvider provider, List<ProductModel> items) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('그룹 삭제'), content: Text('해당 그룹의 모든 자산(${items.length}개)을 삭제하시겠습니까?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
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
            child: const Text('그룹 삭제')
        ),
      ],
    ));
  }

  void _showResetDialog(ProductProvider provider) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('전체 초기화', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      content: const Text('서버의 모든 물품 데이터를 삭제합니다. 이 작업은 되돌릴 수 없습니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
        ElevatedButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              await provider.resetAllProducts();
              if (ctx.mounted) nav.pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('전체 삭제')
        )
      ],
    ));
  }

  void _showMobileGroupDetail(ProductProvider provider, String groupName, List<ProductModel> items) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: _buildGroupDetailList(provider, groupName, items),
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

      final String? path = await FilePicker.platform.saveFile(
          fileName: '물품관리_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx']
      );

      if (path != null) {
        await File(path).writeAsBytes(excel.encode()!);
        messenger.showSnackBar(const SnackBar(content: Text('엑셀 파일이 저장되었습니다.')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }
}