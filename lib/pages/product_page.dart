import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/products.dart';
import '../providers/product_provider.dart';
import '../theme/app_theme.dart';

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
  String _sortCriteria = 'name';
  bool _hideExcluded = true;

  // 레이아웃 상수
  static const double _rowHeight = 72.0;
  static const double _colImgWidth = 80.0;
  static const double _colActionWidth = 120.0;

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

  String _getDisplayValue(ProductModel p, String key) {
    switch (key) {
      case '품명': return p.name;
      case '태그ID': return p.tagId;
      case '위치': return p.location ?? "-";
      case '상태': return p.status;
      case '규격': return p.spec ?? "-";
      case '분류': return p.category ?? "-";
      case '제조사': return p.manufacturer ?? "-";
      case 'S/N': return p.serialNumber ?? "-";
      default:
        return p.metadata[key]?.toString() ?? "-";
    }
  }

  Map<String, dynamic> _calculateMetrics(List<ProductModel> allItems) {
    final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0;
    int todayOut = 0;
    int currentStock = 0;
    int shortageCount = 0;

    const inStatus = {'구매입고', '회수/반납', '수기입고'};
    const excludeStock = {'판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'};

    final Map<String, int> stockByGroup = {};
    final Map<String, int> safetyByGroup = {};

    for (final item in allItems) {
      final lastActionDate = item.updated ?? item.created ?? "";
      final isToday = lastActionDate.startsWith(today);

      if (inStatus.contains(item.status) && isToday) {
        todayIn++;
      }
      if (excludeStock.contains(item.status) && isToday) {
        todayOut++;
      }

      if (!excludeStock.contains(item.status)) {
        currentStock++;
        String key = "${item.name}|${item.spec ?? ''}";
        stockByGroup[key] = (stockByGroup[key] ?? 0) + 1;
        safetyByGroup[key] = item.safetyStock;
      }
    }

    stockByGroup.forEach((key, tagCount) {
      if (tagCount < (safetyByGroup[key] ?? 0)) {
        shortageCount++;
      }
    });

    return {'in': todayIn, 'out': todayOut, 'stock': currentStock, 'short': shortageCount};
  }

  Future<void> _processAssetAccess(ProductProvider provider, ProductModel p, String type) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _LocationSelectionDialog(type: type),
    );

    if (!mounted || result == null) {
      return;
    }

    final success = await provider.handleSave(
      p: p,
      data: {'status': type, 'location': result['building'] ?? "미지정"},
    );

    if (mounted && success) {
      messenger.showSnackBar(SnackBar(
        content: Text('[${p.name}] $type 완료'),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 1),
      ));
    }
  }

  Map<String, List<ProductModel>> _getGroupedData(List<ProductModel> items) {
    final Map<String, List<ProductModel>> grouped = {};
    for (final item in items) {
      String key = _groupByMode == 'item' ? item.name : (_groupByMode == 'location' ? (item.location ?? "미지정") : (item.category ?? "미지정"));
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();

    if (provider.lastScannedTag.isNotEmpty) {
      final tag = provider.lastScannedTag;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.clearLastScannedTag();
        final found = provider.findProductByTag(tag);
        if (mounted) {
          _showForm(context, provider, found, initialTag: found == null ? tag : null);
        }
      });
    }

    final filtered = provider.items.where((p) {
      final q = _currentQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) || p.tagId.toLowerCase().contains(q);
    }).toList();

    if (_sortCriteria == 'name') {
      filtered.sort((a, b) => a.name.compareTo(b.name));
    } else {
      filtered.sort((a, b) => a.status.compareTo(b.status));
    }

    final metrics = _calculateMetrics(provider.items);
    final groupedMap = _getGroupedData(filtered);
    final groupKeys = groupedMap.keys.toList()..sort();

    return Theme(
      data: Theme.of(context).copyWith(textTheme: Theme.of(context).textTheme.apply(fontFamily: AppTheme.fontPretendard)),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Column(
              children: [
                _buildDashboard(metrics),
                if (provider.isLoading)
                  const LinearProgressIndicator(minHeight: 2, color: AppTheme.primary),
                const Divider(height: 1),
                Expanded(
                  child: LayoutBuilder(builder: (ctx, constraints) {
                    if (constraints.maxWidth > 950 && !widget.isMobile) {
                      return _buildSplitLayout(provider, groupedMap, groupKeys, filtered);
                    }
                    return _buildMobileLayout(provider, groupedMap, groupKeys);
                  }),
                ),
              ],
            ),
            if (provider.isParsing || provider.isSaving)
              _buildGlobalLoadingOverlay(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalLoadingOverlay(ProductProvider provider) {
    String msg = provider.isParsing ? "데이터 분석 중..." : "저장 중...";
    return Container(
      color: Colors.black.withValues(alpha: 0.26),
      child: Center(
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSplitLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys, List<ProductModel> filtered) {
    return Row(
      children: [
        SizedBox(
          width: 400,
          child: Column(
            children: [
              _buildHeader(provider, filtered),
              _buildFilterBar(),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: groupKeys.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    final key = groupKeys[idx];
                    return _buildGroupTile(provider, key, groupedMap[key]!, _selectedGroupKey == key, false);
                  },
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Container(
            color: AppTheme.surface,
            child: _selectedGroupKey == null
                ? _buildEmptyState("목록에서 그룹을 선택하세요.")
                : _buildDetailView(provider, _selectedGroupKey!, groupedMap[_selectedGroupKey] ?? [],
                key: ValueKey('detail_$_selectedGroupKey')),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys) {
    return Column(
      children: [
        _buildHeader(provider, provider.items),
        _buildFilterBar(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: groupKeys.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, idx) {
              final key = groupKeys[idx];
              return _buildGroupTile(provider, key, groupedMap[key]!, false, true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDashboard(Map<String, dynamic> m) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _buildStatCard("오늘 입고", m['in'], Colors.blue),
          _buildStatCard("오늘 출고", m['out'], Colors.orange),
          _buildStatCard("현재고 합계", m['stock'], AppTheme.primary, isMain: true),
          _buildStatCard("안전부족", m['short'], AppTheme.danger, isAlert: m['short'] > 0),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, int val, Color color, {bool isMain = false, bool isAlert = false}) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAlert ? color.withValues(alpha: 0.1) : (isMain ? color.withValues(alpha: 0.05) : AppTheme.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isAlert ? color : (isMain ? color : AppTheme.border.withValues(alpha: 0.5))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isAlert ? color : Colors.black54)),
          Text('$val', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _buildHeader(ProductProvider provider, List<ProductModel> filtered) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Text('자산 통합 관리', style: AppTheme.headerStyle),
              const Spacer(),
              IconButton(onPressed: () { provider.fetchData(); }, tooltip: "새로고침", icon: const Icon(Icons.refresh, size: 20)),
              IconButton(
                  onPressed: () async {
                    final res = await provider.batchImportFromExcel();
                    if (res['total']! > 0 && mounted) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("엑셀 업로드 결과"),
                          content: Text("전체: ${res['total']}행\n성공: ${res['success']}개\n실패: ${res['failed']}개"),
                          actions: [TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text("확인"))],
                        ),
                      );
                    }
                  },
                  tooltip: "엑셀 업로드",
                  icon: const FaIcon(FontAwesomeIcons.fileArrowUp, color: Colors.indigo, size: 18)
              ),
              IconButton(onPressed: () { _showColumnSelectionDialog(provider); }, tooltip: "컬럼 설정", icon: const Icon(Icons.settings_outlined, size: 20)),
              IconButton(onPressed: () { _exportToExcel(context, filtered); }, tooltip: "엑셀 다운로드", icon: const FaIcon(FontAwesomeIcons.fileArrowDown, color: Colors.green, size: 18)),
              IconButton(onPressed: () { _showResetDialog(provider); }, tooltip: "전체 초기화", icon: const Icon(Icons.delete_sweep_outlined, color: AppTheme.danger)),
              IconButton(onPressed: () { _showForm(context, provider, null); }, tooltip: "신규 등록", icon: const Icon(Icons.add_circle, color: AppTheme.primary, size: 26)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (v) { setState(() => _currentQuery = v); },
            decoration: InputDecoration(
              hintText: '검색...',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: AppTheme.headerBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ...['item', 'location', 'category'].map((mode) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ChoiceChip(
              label: Text(mode == 'item' ? '품목별' : (mode == 'location' ? '위치별' : '분류별'), style: const TextStyle(fontSize: 11)),
              selected: _groupByMode == mode,
              onSelected: (s) {
                if (s) {
                  setState(() { _groupByMode = mode; _selectedGroupKey = null; });
                }
              },
            ),
          )),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.sort, size: 18),
            onPressed: () {
              setState(() => _sortCriteria = (_sortCriteria == 'name') ? 'status' : 'name');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, bool isMobile) {
    final first = items.first;
    const exclude = {'판매출고', '수리출고', '대여출고', '폐기', '분실'};
    final tagCount = items.where((i) => !exclude.contains(i.status)).length;
    final bool isShort = _groupByMode == 'item' && tagCount < first.safetyStock;

    return InkWell(
      onTap: () {
        if (isMobile) {
          _showMobileGroupDetail(provider, title, items);
        } else {
          setState(() => _selectedGroupKey = title);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            _buildThumbnail(first, size: 48),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isShort ? AppTheme.danger : Colors.black))),
            Text('$tagCount', style: TextStyle(fontWeight: FontWeight.w900, color: isShort ? AppTheme.danger : AppTheme.primary)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailView(ProductProvider provider, String groupName, List<ProductModel> items, {Key? key}) {
    const excludeStatus = {'판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'};
    final displayItems = _hideExcluded ? items.where((p) => !excludeStatus.contains(p.status)).toList() : items;
    final dynamicColumns = provider.selectedColumns.isEmpty ? ['품명', '태그ID', '위치'] : provider.selectedColumns;

    return Column(
      key: key,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(groupName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const Spacer(),
              FilterChip(
                label: const Text('출고제외', style: TextStyle(fontSize: 11)),
                selected: _hideExcluded,
                onSelected: (v) { setState(() => _hideExcluded = v); },
              ),
            ],
          ),
        ),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: AppTheme.headerBg,
          child: Row(
            children: [
              const SizedBox(width: _colImgWidth, child: Text('사진', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ...dynamicColumns.map((col) => Expanded(child: Text(col, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
              const SizedBox(width: _colActionWidth, child: Text('관리', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: displayItems.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, idx) {
              final p = displayItems[idx];
              return InkWell(
                onTap: () { _showForm(context, provider, p); },
                child: Container(
                  height: _rowHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(width: _colImgWidth, child: Center(child: _buildThumbnail(p, size: 54))),
                      ...dynamicColumns.map((col) {
                        final val = _getDisplayValue(p, col);
                        return Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (col == '품명')
                                Text(p.status, style: TextStyle(fontSize: 10, color: p.status == '정상' ? AppTheme.success : AppTheme.warning, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      }),
                      SizedBox(
                        width: _colActionWidth,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.login, color: AppTheme.success, size: 20), onPressed: () { _processAssetAccess(provider, p, '수기입고'); }),
                            IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.logout, color: AppTheme.warning, size: 20), onPressed: () { _processAssetAccess(provider, p, '수기출고'); }),
                            IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20), onPressed: () { _confirmIndividualDelete(context, provider, p); }),
                          ],
                        ),
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

  Widget _buildThumbnail(ProductModel p, {double size = 44}) {
    final url = p.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: AppTheme.headerBg, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network("$url?t=${p.updated}", fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 16))
          : Icon(Icons.inventory_2_outlined, color: Colors.grey.withValues(alpha: 0.3), size: 20),
    );
  }

  // --- 상세 편집 및 신규 등록 폼 ---
  Future<void> _showForm(BuildContext context, ProductProvider provider, ProductModel? p, {String? initialTag}) async {
    final nameC = TextEditingController(text: p?.name ?? "");
    final tagC = TextEditingController(text: initialTag ?? p?.tagId ?? "");
    final locC = TextEditingController(text: p?.location ?? "");
    final catC = TextEditingController(text: p?.category ?? "");
    final specC = TextEditingController(text: p?.spec ?? "");
    final mfgC = TextEditingController(text: p?.manufacturer ?? "");
    final snC = TextEditingController(text: p?.serialNumber ?? "");
    final safeC = TextEditingController(text: p?.safetyStock.toString() ?? "5");
    final qtyC = TextEditingController(text: "1");

    String selectedStatus = p?.status ?? "정상";
    XFile? file;
    Uint8List? preview;

    final Map<String, TextEditingController> metaControllers = {};

    if (p != null) {
      final Map<String, dynamic> originMap = p.metadata['origin_key_map'] ?? {};
      p.metadata.forEach((key, value) {
        if (!['origin_key_map', 'history', 'last_location_info'].contains(key)) {
          final ctrl = TextEditingController(text: value?.toString() ?? "");
          metaControllers[key] = ctrl;
          if (originMap.containsKey(key)) {
            final dbField = originMap[key];
            ctrl.addListener(() {
              final val = ctrl.text.trim();
              if (dbField == 'name') { nameC.text = val; }
              else if (dbField == 'location') { locC.text = val; }
              else if (dbField == 'spec') { specC.text = val; }
              else if (dbField == 'manufacturer') { mfgC.text = val; }
              else if (dbField == 'serial_number') { snC.text = val; }
            });
          }
        }
      });
    } else {
      final Set<String> discoveredKeys = {};
      for (var item in provider.items) {
        item.metadata.forEach((k, v) {
          if (!['origin_key_map', 'history', 'last_location_info'].contains(k)) {
            discoveredKeys.add(k);
          }
        });
      }
      for (var key in discoveredKeys) {
        metaControllers[key] = TextEditingController();
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (dialogCtx, setS) {
        const double fieldWidth = 370.0;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(p == null ? '자산 신규 등록' : '상세 정보 편집', style: const TextStyle(fontWeight: FontWeight.bold)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          content: SizedBox(
            width: 800,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
                      if (img != null) {
                        final b = await img.readAsBytes();
                        setS(() { file = img; preview = b; });
                      }
                    },
                    child: Stack(
                      children: [
                        Container(
                          width: 140, height: 140,
                          decoration: BoxDecoration(color: AppTheme.headerBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border.withValues(alpha: 0.3))),
                          clipBehavior: Clip.antiAlias,
                          child: preview != null
                              ? Image.memory(preview!, fit: BoxFit.cover)
                              : (p?.getImageUrl(widget.baseUrl) != null
                              ? Image.network("${p!.getImageUrl(widget.baseUrl)}?t=${p.updated}", fit: BoxFit.cover)
                              : const Icon(Icons.camera_alt, size: 40, color: Colors.grey)),
                        ),
                        Positioned(bottom: 8, right: 8, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle), child: const Icon(Icons.edit, color: Colors.white, size: 14))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (p == null) ...[
                    _buildSectionHeader(Icons.copy_all, "생성 수량 (동일 품목 일괄 등록)", Colors.orange),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start, // 마스터 정보와 정렬 일치 (좌측 정렬)
                      children: [
                        const SizedBox(width: 23), // 중앙 정렬된 Wrap과의 시작 위치 동기화 보정
                        SizedBox(
                          width: fieldWidth,
                          child: _buildStyledField(
                            "발행 수량",
                            qtyC,
                            keyboardType: TextInputType.number,
                            hint: "생성할 태그 개수",
                            onChanged: (v) => setS(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildSectionHeader(Icons.star, "마스터 정보", Colors.blue),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start, // 좌측 정렬로 수정
                    children: [
                      const SizedBox(width: 23), // 시작 위치 보정
                      SizedBox(width: fieldWidth, child: _buildStyledField("품명", nameC)),
                      const SizedBox(width: 12),
                      SizedBox(width: fieldWidth, child: _buildStyledField("태그ID", tagC, hint: "EPC 번호")),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start, // 좌측 정렬로 수정
                    children: [
                      const SizedBox(width: 23),
                      SizedBox(width: fieldWidth, child: _buildStyledField("위치", locC, hint: "창고/구역")),
                      const SizedBox(width: 12),
                      SizedBox(width: fieldWidth, child: _buildStyledField("분류", catC, hint: "카테고리")),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start, // 좌측 정렬로 수정
                    children: [
                      const SizedBox(width: 23),
                      SizedBox(width: fieldWidth, child: _buildStyledField("제조사", mfgC)),
                      const SizedBox(width: 12),
                      SizedBox(width: fieldWidth, child: _buildStyledField("시리얼번호", snC, hint: "S/N")),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start, // 좌측 정렬로 수정
                    children: [
                      const SizedBox(width: 23),
                      SizedBox(width: fieldWidth, child: _buildStyledField("안전재고", safeC, keyboardType: TextInputType.number, hint: "최저 유지 수량")),
                      const SizedBox(width: 12),
                      SizedBox(width: fieldWidth, child: _buildStyledDropdown("상태", selectedStatus, (v) { if (v != null) { setS(() => selectedStatus = v); } })),
                    ],
                  ),
                  if (metaControllers.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    _buildSectionHeader(Icons.table_view, "엑셀 추가 필드 (수정 시 마스터 자동 연동)", Colors.green),
                    Row(
                      children: [
                        const SizedBox(width: 23),
                        Expanded(
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 0,
                            alignment: WrapAlignment.start, // 홀수 시 이상하지 않게 좌측 정렬 적용
                            children: metaControllers.entries.map((e) => SizedBox(
                              width: fieldWidth,
                              child: _buildStyledField(e.key, e.value),
                            )).toList(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () { Navigator.pop(dialogCtx); }, child: const Text("취소")),
            ElevatedButton(
              onPressed: () async {
                if (nameC.text.trim().isEmpty) {
                  return;
                }
                final int loopCount = int.tryParse(qtyC.text.trim()) ?? 1;
                final updatedMeta = Map<String, dynamic>.from(p?.metadata ?? {});
                metaControllers.forEach((k, v) { updatedMeta[k] = v.text.trim(); });

                final baseData = {
                  'name': nameC.text.trim(), 'location': locC.text.trim(),
                  'category': catC.text.trim(), 'spec': specC.text.trim(), 'manufacturer': mfgC.text.trim(),
                  'serial_number': snC.text.trim(), 'safety_stock': int.tryParse(safeC.text.trim()) ?? 5,
                  'status': selectedStatus, 'metadata': updatedMeta,
                };

                bool success = true;
                if (p == null) {
                  for (int i = 0; i < loopCount; i++) {
                    final Map<String, dynamic> itemData = Map.from(baseData);
                    if (loopCount > 1 && tagC.text.isNotEmpty) {
                      itemData['tag_id'] = "${tagC.text.trim()}_${i + 1}";
                    } else {
                      itemData['tag_id'] = tagC.text.trim();
                    }
                    final res = await provider.handleSave(p: null, data: itemData, imageXFile: file);
                    if (!res) {
                      success = false;
                    }
                  }
                } else {
                  baseData['tag_id'] = tagC.text.trim();
                  success = await provider.handleSave(p: p, data: baseData, imageXFile: file);
                  if (success && file != null) {
                    final others = provider.items.where((i) => i.name == p.name && i.id != p.id).toList();
                    for (var item in others) {
                      await provider.handleSave(p: item, data: {'status': item.status}, imageXFile: file);
                    }
                  }
                }
                if (success && dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                }
              },
              child: Text(p == null ? "${qtyC.text}개 생성" : "저장"),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, Color color) {
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(children: [Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 8), Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color))]), const Divider()]));
  }

  Widget _buildStyledField(String label, TextEditingController ctrl, {TextInputType keyboardType = TextInputType.text, String? hint, ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label, hintText: hint,
          labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.38), fontSize: 13, fontWeight: FontWeight.bold),
          hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.38), fontSize: 13),
          floatingLabelBehavior: FloatingLabelBehavior.always, filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5), width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.fromLTRB(12, 22, 12, 10),
        ),
      ),
    );
  }

  Widget _buildStyledDropdown(String label, String initial, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: initial,
        items: const ['정상', '구매입고', '회수/반납', '판매출고', '수리출고', '대여출고', '수리필요', '분실', '폐기']
            .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)))).toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.38), fontSize: 13, fontWeight: FontWeight.bold),
          floatingLabelBehavior: FloatingLabelBehavior.always, filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        ),
      ),
    );
  }

  void _showColumnSelectionDialog(ProductProvider provider) {
    final availableKeys = ['품명', '태그ID', '위치', '상태', '규격', '분류', '제조사', 'S/N'];
    final Set<String> metaKeys = {};
    for (var item in provider.items) {
      item.metadata.forEach((k, v) {
        if (!['origin_key_map', 'history', 'last_location_info'].contains(k)) {
          metaKeys.add(k);
        }
      });
    }
    final fullKeys = [...availableKeys, ...metaKeys.toList()..sort()];
    List<String> tempSelection = List.from(provider.selectedColumns.isEmpty ? ['품명', '태그ID', '위치'] : provider.selectedColumns);
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setS) => AlertDialog(
            title: const Text("표시 항목 설정 (최대 5개)"),
            content: SizedBox(width: 300, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: fullKeys.map((key) => CheckboxListTile(title: Text(key, style: const TextStyle(fontSize: 13)), value: tempSelection.contains(key), onChanged: (val) {
              setS(() {
                if (val != null && val) {
                  if (tempSelection.length < 5) {
                    tempSelection.add(key);
                  }
                } else {
                  if (tempSelection.length > 1) {
                    tempSelection.remove(key);
                  }
                }
              });
            })).toList()))),
            actions: [
              TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text("취소")),
              ElevatedButton(onPressed: () async { await provider.saveRemoteSettings(tempSelection); if (context.mounted) { Navigator.pop(ctx); } }, child: const Text("적용"))
            ]
        ))
    );
  }

  Future<void> _exportToExcel(BuildContext context, List<ProductModel> list) async {
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['물품리스트'];
      excel.rename('Sheet1', '물품리스트');
      sheet.appendRow([excel_pkg.TextCellValue('품명'), excel_pkg.TextCellValue('제조사'), excel_pkg.TextCellValue('규격'), excel_pkg.TextCellValue('S/N'), excel_pkg.TextCellValue('태그ID'), excel_pkg.TextCellValue('상태'), excel_pkg.TextCellValue('위치')]);
      for (final i in list) {
        sheet.appendRow([excel_pkg.TextCellValue(i.name), excel_pkg.TextCellValue(i.manufacturer ?? ""), excel_pkg.TextCellValue(i.spec ?? ""), excel_pkg.TextCellValue(i.serialNumber ?? ""), excel_pkg.TextCellValue(i.tagId), excel_pkg.TextCellValue(i.status), excel_pkg.TextCellValue(i.location ?? "")]);
      }
      final path = await FilePicker.platform.saveFile(fileName: 'Inventory_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx']);
      if (path != null) {
        await File(path).writeAsBytes(excel.encode()!);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 엑셀 파일 저장 완료')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 저장 실패: $e')));
      }
    }
  }

  void _showResetDialog(ProductProvider provider) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: const Text('DB 전체 초기화', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
            content: const Text('모든 자산 데이터를 삭제하시겠습니까?'),
            actions: [
              TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text("취소")),
              ElevatedButton(onPressed: () async { await provider.resetAllProducts(); if (ctx.mounted) { Navigator.pop(ctx); } }, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white), child: const Text('전체 삭제'))
            ]
        )
    );
  }

  void _confirmIndividualDelete(BuildContext context, ProductProvider provider, ProductModel p) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: const Text('삭제 확인'),
            content: Text('${p.name} 자산을 삭제하시겠습니까?'),
            actions: [
              TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text('취소')),
              ElevatedButton(onPressed: () async { await provider.deleteProduct(p.id); if (ctx.mounted) { Navigator.pop(ctx); } }, child: const Text('삭제'))
            ]
        )
    );
  }

  void _showMobileGroupDetail(ProductProvider provider, String groupName, List<ProductModel> items) {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => SizedBox(height: MediaQuery.of(context).size.height * 0.8, child: _buildDetailView(provider, groupName, items)));
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Text(msg, style: const TextStyle(color: Colors.grey)));
  }
}

class _LocationSelectionDialog extends StatefulWidget {
  final String type;
  const _LocationSelectionDialog({required this.type});
  @override
  State<_LocationSelectionDialog> createState() => _LocationSelectionDialogState();
}

class _LocationSelectionDialogState extends State<_LocationSelectionDialog> {
  final TextEditingController _bC = TextEditingController(text: "본관A");
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
        title: Text('${widget.type} 위치'),
        content: TextField(controller: _bC, decoration: const InputDecoration(labelText: '건물/구역')),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); }, child: const Text("취소")),
          ElevatedButton(onPressed: () { Navigator.pop(context, {'building': _bC.text}); }, child: const Text("확인"))
        ]
    );
  }
}