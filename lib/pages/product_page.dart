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

  // Lint 해결: 정렬 기능이 고정이므로 final 선언
  final String _sortCriteria = 'name';
  bool _hideExcluded = true;

  // 레이아웃 고정 상수
  static const double _colImgSize = 54.0;
  static const double _colActionWidth = 140.0;

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

  // --- 비즈니스 로직 헬퍼 ---

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
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0;
    int todayOut = 0;
    int currentStock = 0;

    const inStatus = {'구매입고', '회수/반납', '수기입고'};
    const excludeStock = {'판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'};

    for (final item in allItems) {
      final lastDate = item.updated ?? item.created ?? "";
      final isToday = lastDate.startsWith(todayStr);

      if (isToday) {
        if (inStatus.contains(item.status)) todayIn++;
        if (excludeStock.contains(item.status)) todayOut++;
      }
      if (!excludeStock.contains(item.status)) {
        currentStock++;
      }
    }
    int prevStock = currentStock - todayIn + todayOut;

    return {
      'prev': prevStock,
      'in': todayIn,
      'out': todayOut,
      'stock': currentStock
    };
  }

  Future<void> _processAssetAccess(ProductProvider provider, ProductModel p, String type) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _ManualInoutDialog(type: type, product: p),
    );

    if (!context.mounted || result == null) return;

    final success = await provider.handleSave(
      p: p,
      data: {
        'status': result['status'] ?? type,
        'location': result['location'] ?? "미지정",
        'metadata': {
          ...p.metadata,
          'last_manual_reason': result['reason'],
          'last_handler': result['handler'],
          'last_processed_at': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
        }
      },
    );

    if (!context.mounted) return;
    if (success) {
      messenger.showSnackBar(SnackBar(
        content: Text('[${p.name}] ${result['status']} 완료'),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 1),
      ));
    }
  }

  // --- UI 빌더 메서드 ---

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
                child: RepaintBoundary(
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
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Container(
            color: AppTheme.surface,
            child: RepaintBoundary(
              child: _selectedGroupKey == null
                  ? _buildEmptyState("목록에서 그룹을 선택하세요.")
                  : _buildDetailView(provider, _selectedGroupKey!, groupedMap[_selectedGroupKey] ?? [],
                  key: ValueKey('detail_$_selectedGroupKey')),
            ),
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
          child: RepaintBoundary(
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
          _buildStatCard("전일 재고", m['prev'], Colors.blueGrey),
          _buildStatCard("오늘 입고", m['in'], Colors.blue),
          _buildStatCard("오늘 출고", m['out'], Colors.orange),
          _buildStatCard("당일 재고", m['stock'], AppTheme.primary, isMain: true),
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

  /// [수정 보존] 제목 제거, 아이콘 좌측 정렬, 모든 아이콘에 Tooltip(힌트 풍선) 적용
  Widget _buildHeader(ProductProvider provider, List<ProductModel> filtered) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                  onPressed: () => provider.fetchData(),
                  tooltip: "새로고침",
                  icon: const Icon(Icons.refresh, size: 20)
              ),
              const SizedBox(width: 4),
              IconButton(
                  onPressed: () async {
                    final res = await provider.batchImportFromExcel();
                    if (!context.mounted) return;
                    if (res['total']! > 0) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("엑셀 업로드 결과"),
                          content: Text("성공: ${res['success']} / 전체: ${res['total']}"),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))],
                        ),
                      );
                    }
                  },
                  tooltip: "엑셀 대량 임포트",
                  icon: const FaIcon(FontAwesomeIcons.fileArrowUp, color: Colors.indigo, size: 18)
              ),
              const SizedBox(width: 4),
              IconButton(
                  onPressed: () => _showColumnSelectionDialog(provider),
                  tooltip: "표시 항목 설정",
                  icon: const Icon(Icons.settings_outlined, size: 20)
              ),
              const SizedBox(width: 4),
              IconButton(
                  onPressed: () => _exportToExcel(context, filtered),
                  tooltip: "엑셀 파일 내보내기",
                  icon: const FaIcon(FontAwesomeIcons.fileArrowDown, color: Colors.green, size: 18)
              ),
              const SizedBox(width: 4),
              IconButton(
                  onPressed: () => _showResetDialog(provider),
                  tooltip: "모든 데이터 초기화",
                  icon: const Icon(Icons.delete_sweep_outlined, color: AppTheme.danger)
              ),
              const SizedBox(width: 4),
              IconButton(
                  onPressed: () => _showForm(context, provider, null),
                  tooltip: "신규 데이터 등록",
                  icon: const Icon(Icons.add_circle, color: AppTheme.primary, size: 26)
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (v) { setState(() => _currentQuery = v); },
            decoration: InputDecoration(
              hintText: '검색어 입력...',
              hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.2), fontSize: 14),
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

  /// [수정 보존] 세그먼트 버튼 높이 축소
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'item', label: Text('품명별', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                ButtonSegment(value: 'location', label: Text('위치별', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                ButtonSegment(value: 'category', label: Text('분류별', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
              ],
              selected: {_groupByMode},
              showSelectedIcon: false,
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _groupByMode = newSelection.first;
                  _selectedGroupKey = null;
                });
              },
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                visualDensity: VisualDensity.standard,
                backgroundColor: Colors.white,
                selectedBackgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                selectedForegroundColor: AppTheme.primary,
                side: BorderSide(color: AppTheme.border.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailView(ProductProvider provider, String groupName, List<ProductModel> items, {Key? key}) {
    const excludeStatus = {'판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'};
    final displayItems = _hideExcluded ? items.where((p) => !excludeStatus.contains(p.status)).toList() : items;
    final dynamicColumns = provider.selectedColumns;

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
                label: const Text('출고제외 보기', style: TextStyle(fontSize: 11)),
                selected: _hideExcluded,
                onSelected: (v) { setState(() => _hideExcluded = v); },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            cacheExtent: 1000,
            itemCount: displayItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, idx) {
              final p = displayItems[idx];
              return InkWell(
                onTap: () => _showForm(context, provider, p),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border.withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))
                    ],
                  ),
                  child: Row(
                    children: [
                      _buildThumbnail(p, size: _colImgSize),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Wrap(
                          spacing: 20,
                          runSpacing: 10,
                          children: dynamicColumns.map((col) {
                            final val = _getDisplayValue(p, col);
                            return SizedBox(
                              width: 125,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(col, style: TextStyle(fontSize: 10, color: Colors.black.withValues(alpha: 0.38), fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  if (col == '품명') ...[
                                    Text(p.status, style: TextStyle(fontSize: 10, color: p.status == '정상' ? AppTheme.success : AppTheme.warning, fontWeight: FontWeight.bold))
                                  ]
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      SizedBox(
                        width: _colActionWidth,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(padding: EdgeInsets.zero, icon: const Icon(Icons.login, color: AppTheme.success, size: 20), tooltip: "수기입고", onPressed: () => _processAssetAccess(provider, p, '수기입고')),
                            IconButton(padding: EdgeInsets.zero, icon: const Icon(Icons.logout, color: AppTheme.warning, size: 20), tooltip: "수기출고", onPressed: () => _processAssetAccess(provider, p, '수기출고')),
                            IconButton(padding: EdgeInsets.zero, icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20), tooltip: "자산 개별 삭제", onPressed: () => _confirmIndividualDelete(context, provider, p)),
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

  /// [수정 보존] 집계 리스트 삭제 아이콘 매핑
  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, bool isMobile) {
    final first = items.first;
    const exclude = {'판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'};
    final tagCount = items.where((i) => !exclude.contains(i.status)).length;

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
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border.withValues(alpha: 0.3)),
              ),
              child: Text(
                  '$tagCount',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: isSelected ? Colors.white : AppTheme.primary
                  )
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: AppTheme.danger, size: 20),
              tooltip: "이 그룹 전체 삭제",
              onPressed: () => _confirmGroupDelete(context, provider, title, items),
            ),
          ],
        ),
      ),
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
          ? Image.network(
        "$url?t=${p.updated}",
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 16),
      )
          : Icon(Icons.inventory_2_outlined, color: Colors.grey.withValues(alpha: 0.3), size: 20),
    );
  }

  // --- 편집 폼 및 설정 로직 ---

  Future<void> _showForm(BuildContext context, ProductProvider provider, ProductModel? p, {String? initialTag}) async {
    final nameC = TextEditingController(text: p?.name ?? "");
    final tagC = TextEditingController(text: initialTag ?? p?.tagId ?? "");
    final locC = TextEditingController(text: p?.location ?? "");
    final catC = TextEditingController(text: p?.category ?? "");
    final specC = TextEditingController(text: p?.spec ?? "");
    final snC = TextEditingController(text: p?.serialNumber ?? "");
    final safeC = TextEditingController(text: p?.safetyStock.toString() ?? "5");
    final qtyC = TextEditingController(text: "1");

    String selectedStatus = p?.status ?? "정상";
    XFile? file; Uint8List? preview;

    final Map<String, TextEditingController> metaControllers = {};
    if (p != null) {
      p.metadata.forEach((key, value) {
        if (!['origin_key_map', 'history', 'last_location_info'].contains(key)) {
          metaControllers[key] = TextEditingController(text: value?.toString() ?? "");
        }
      });
    } else {
      final Set<String> discoveredKeys = {};
      for (var item in provider.items) {
        item.metadata.forEach((k, v) {
          if (!['origin_key_map', 'history', 'last_location_info'].contains(k)) discoveredKeys.add(k);
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
        final screenWidth = MediaQuery.of(dialogCtx).size.width;
        const double fieldWidth = 370.0;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(p == null ? "자산 신규 등록" : "상세 정보 수정", style: const TextStyle(fontWeight: FontWeight.bold)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          content: SizedBox(
            width: screenWidth > 850 ? 800 : screenWidth * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
                      if (!dialogCtx.mounted || img == null) return;
                      final b = await img.readAsBytes();
                      setS(() { file = img; preview = b; });
                    },
                    child: Container(
                      width: 140, height: 140,
                      decoration: BoxDecoration(color: AppTheme.headerBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border.withValues(alpha: 0.3))),
                      clipBehavior: Clip.antiAlias,
                      child: preview != null
                          ? Image.memory(preview!, fit: BoxFit.cover)
                          : (p?.getImageUrl(widget.baseUrl) != null
                          ? Image.network("${p!.getImageUrl(widget.baseUrl)}?t=${p.updated}", fit: BoxFit.cover, gaplessPlayback: true)
                          : const Icon(Icons.camera_alt, size: 40, color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (p == null) ...[
                    _buildSectionHeader(Icons.copy_all, "대량 등록 설정", Colors.orange),
                    Wrap(
                      children: [
                        SizedBox(width: fieldWidth, child: _buildStyledField("등록 개수 (단위: EA)", qtyC, keyboardType: TextInputType.number)),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildSectionHeader(Icons.star, "마스터 데이터", Colors.blue),
                  Wrap(
                    spacing: 16,
                    runSpacing: 0,
                    alignment: WrapAlignment.start,
                    children: [
                      SizedBox(width: fieldWidth, child: _buildStyledField("품명", nameC)),
                      SizedBox(width: fieldWidth, child: _buildStyledField("태그ID (EPC)", tagC, hint: "RFID EPC 고유값")),
                      SizedBox(width: fieldWidth, child: _buildStyledField("위치", locC)),
                      SizedBox(width: fieldWidth, child: _buildStyledField("분류", catC)),
                      SizedBox(width: fieldWidth, child: _buildStyledField("규격", specC)),
                      SizedBox(width: fieldWidth, child: _buildStyledField("안전재고", safeC, keyboardType: TextInputType.number)),
                      SizedBox(width: fieldWidth, child: _buildStyledField("S/N (시리얼)", snC)),
                      SizedBox(width: fieldWidth, child: _buildStyledDropdown("현재 상태", selectedStatus, (v) {
                        if (v != null) setS(() => selectedStatus = v);
                      })),
                    ],
                  ),
                  if (metaControllers.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    _buildSectionHeader(Icons.table_view, "사용자 추가 항목 (Excel 등)", Colors.green),
                    Wrap(
                      spacing: 16,
                      runSpacing: 0,
                      alignment: WrapAlignment.start,
                      children: metaControllers.entries.map((e) => SizedBox(width: fieldWidth, child: _buildStyledField(e.key, e.value))).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text("취소")),
            ElevatedButton(
              onPressed: () async {
                if (nameC.text.trim().isEmpty) return;

                final int loopCount = int.tryParse(qtyC.text.trim()) ?? 1;
                final updatedMeta = Map<String, dynamic>.from(p?.metadata ?? {});
                metaControllers.forEach((k, v) => updatedMeta[k] = v.text.trim());

                bool allSuccess = true;
                if (p == null) {
                  for (int i = 0; i < loopCount; i++) {
                    String finalTag = tagC.text.trim();
                    if (loopCount > 1 && finalTag.isNotEmpty) {
                      finalTag = "${finalTag}_${i + 1}";
                    }
                    final data = {
                      'name': nameC.text.trim(), 'tag_id': finalTag,
                      'location': locC.text.trim(), 'category': catC.text.trim(),
                      'spec': specC.text.trim(), 'serial_number': snC.text.trim(),
                      'status': selectedStatus, 'safety_stock': int.tryParse(safeC.text.trim()) ?? 5,
                      'metadata': updatedMeta,
                    };
                    final res = await provider.handleSave(p: null, data: data, imageXFile: file);
                    if (!res) allSuccess = false;
                  }
                } else {
                  final data = {
                    'name': nameC.text.trim(), 'tag_id': tagC.text.trim(),
                    'location': locC.text.trim(), 'category': catC.text.trim(),
                    'spec': specC.text.trim(), 'serial_number': snC.text.trim(),
                    'status': selectedStatus, 'safety_stock': int.tryParse(safeC.text.trim()) ?? 5,
                    'metadata': updatedMeta,
                  };
                  allSuccess = await provider.handleSave(p: p, data: data, imageXFile: file);
                }
                if (!dialogCtx.mounted) return;
                if (allSuccess) Navigator.pop(dialogCtx);
              },
              child: const Text("저장하기"),
            ),
          ],
        );
      }),
    );
  }

  void _showColumnSelectionDialog(ProductProvider provider) {
    final availableKeys = ['품명', '태그ID', '위치', '상태', '규격', '분류', '제조사', 'S/N'];
    final Set<String> metaKeys = {};
    for (var item in provider.items) {
      item.metadata.forEach((k, v) {
        if (!['origin_key_map', 'history', 'last_location_info'].contains(k)) metaKeys.add(k);
      });
    }
    final fullKeys = [...availableKeys, ...metaKeys.toList()..sort()];
    List<String> tempSelection = List.from(provider.selectedColumns);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setS) => AlertDialog(
        title: const Text("표시 항목 설정 (최대 5개)"),
        content: SizedBox(width: 350, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: fullKeys.map((key) => CheckboxListTile(title: Text(key, style: const TextStyle(fontSize: 13)), value: tempSelection.contains(key), onChanged: (val) {
          setS(() { if (val == true) { if (tempSelection.length < 5) tempSelection.add(key); } else { if (tempSelection.length > 1) tempSelection.remove(key); } });
        })).toList()))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          ElevatedButton(onPressed: () async {
            await provider.saveRemoteSettings(tempSelection);
            if (!context.mounted) return;
            Navigator.pop(ctx);
          }, child: const Text("적용"))
        ],
      )),
    );
  }

  // --- 보조 UI 메서드 ---

  Future<void> _exportToExcel(BuildContext context, List<ProductModel> list) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['물품_리스트'];
      sheet.appendRow([excel_pkg.TextCellValue('품명'), excel_pkg.TextCellValue('태그ID'), excel_pkg.TextCellValue('위치'), excel_pkg.TextCellValue('상태')]);
      for (final i in list) {
        sheet.appendRow([excel_pkg.TextCellValue(i.name), excel_pkg.TextCellValue(i.tagId), excel_pkg.TextCellValue(i.location ?? ""), excel_pkg.TextCellValue(i.status)]);
      }
      final path = await FilePicker.platform.saveFile(fileName: 'Inventory_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx']);
      if (!context.mounted || path == null) return;
      await File(path).writeAsBytes(excel.encode()!);
      messenger.showSnackBar(const SnackBar(content: Text('✅ 엑셀 파일 저장 완료')));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('❌ 저장 실패: $e')));
    }
  }

  void _showResetDialog(ProductProvider provider) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("전체 초기화"), content: const Text("모든 정보를 삭제하시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), ElevatedButton(onPressed: () async { await provider.resetAllProducts(); if (!ctx.mounted) return; Navigator.pop(ctx); }, child: const Text("삭제"))]));
  }

  void _confirmIndividualDelete(BuildContext context, ProductProvider provider, ProductModel p) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("삭제 확인"), content: Text("[${p.name}] 자산을 삭제하시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), ElevatedButton(onPressed: () async { await provider.deleteProduct(p.id); if (!ctx.mounted) return; Navigator.pop(ctx); }, child: const Text("삭제"))]));
  }

  /// [수정] 그룹 일괄 삭제 확인 다이얼로그 - 삭제 후 선택 해제 로직 추가
  void _confirmGroupDelete(BuildContext context, ProductProvider provider, String groupName, List<ProductModel> items) {
    final List<String> ids = items.map((e) => e.id).toList();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: const Text("그룹 일괄 삭제"),
            content: Text("[$groupName] 그룹의 모든 자산(${items.length}개)을 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                  onPressed: () async {
                    await provider.deleteMultipleProducts(ids);
                    if (!ctx.mounted) return;

                    // [핵심] 일괄 삭제 후 우측 상세 뷰 초기화 (선택 취소)
                    setState(() {
                      _selectedGroupKey = null;
                    });

                    Navigator.pop(ctx);
                  },
                  child: const Text("일괄 삭제")
              )
            ]
        )
    );
  }

  void _showMobileGroupDetail(ProductProvider provider, String groupName, List<ProductModel> items) {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => SizedBox(height: MediaQuery.of(context).size.height * 0.8, child: _buildDetailView(provider, groupName, items)));
  }

  Widget _buildEmptyState(String msg) => Center(child: Text(msg, style: const TextStyle(color: Colors.grey)));
  Widget _buildSectionHeader(IconData icon, String title, Color color) => Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(children: [Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 8), Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color))]), const Divider()]));

  Widget _buildStyledField(String label, TextEditingController ctrl, {TextInputType keyboardType = TextInputType.text, String? hint}) => Padding(padding: const EdgeInsets.only(bottom: 16), child: TextField(controller: ctrl, keyboardType: keyboardType, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: InputDecoration(labelText: label, hintText: hint, labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.26), fontSize: 13, fontWeight: FontWeight.bold), floatingLabelBehavior: FloatingLabelBehavior.always, border: OutlineInputBorder(borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.fromLTRB(12, 22, 12, 10))));
  Widget _buildStyledDropdown(String label, String initial, ValueChanged<String?> onChanged) => Padding(padding: const EdgeInsets.only(bottom: 16), child: DropdownButtonFormField<String>(initialValue: initial, items: const ['정상', '수리필요', '폐기'].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)))).toList(), onChanged: onChanged, decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.26), fontSize: 13, fontWeight: FontWeight.bold), floatingLabelBehavior: FloatingLabelBehavior.always, border: OutlineInputBorder(borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.fromLTRB(12, 11, 12, 11))));
  Widget _buildGlobalLoadingOverlay(ProductProvider provider) {
    String msg = provider.isParsing ? "데이터 분석 중..." : "저장 중...";
    return Container(color: Colors.black.withValues(alpha: 0.26), child: Center(child: Card(elevation: 8, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24), child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 20), Text(msg, style: const TextStyle(fontWeight: FontWeight.bold))])))));
  }

  Map<String, List<ProductModel>> _getGroupedData(List<ProductModel> items) {
    final Map<String, List<ProductModel>> grouped = {};
    for (final item in items) {
      String key = _groupByMode == 'item' ? item.name : (_groupByMode == 'location' ? (item.location ?? "미지정") : (item.category ?? "미지정"));
      grouped.putIfAbsent(key, () => []).add(item);
    }
    return grouped;
  }
}

class _ManualInoutDialog extends StatefulWidget {
  final String type; final ProductModel product;
  const _ManualInoutDialog({required this.type, required this.product});
  @override
  State<_ManualInoutDialog> createState() => _ManualInoutDialogState();
}

class _ManualInoutDialogState extends State<_ManualInoutDialog> {
  late TextEditingController _locC, _reasonC, _handlerC;
  late String _selectedStatus;

  @override
  void initState() {
    super.initState();
    _locC = TextEditingController(text: widget.product.location ?? "창고A");
    _reasonC = TextEditingController();
    _handlerC = TextEditingController();
    _selectedStatus = widget.type == '수기입고' ? '구매입고' : '판매출고';
  }

  @override
  void dispose() {
    _locC.dispose();
    _reasonC.dispose();
    _handlerC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isIn = widget.type == '수기입고';
    final List<String> statusItems = isIn
        ? ['구매입고', '회수/반납', '수기입고']
        : ['판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'];

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(isIn ? Icons.login : Icons.logout, color: isIn ? AppTheme.success : AppTheme.warning),
          const SizedBox(width: 8),
          Text('${widget.type} 처리', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("대상 품목: [${widget.product.name}]", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
              const SizedBox(height: 24),
              _buildStyledDropdown("처리 사유 유형", _selectedStatus, statusItems, (v) {
                if (v != null) setState(() => _selectedStatus = v);
              }),
              _buildStyledField("이동 장소", _locC, hint: "창고 번호 또는 구역명"),
              _buildStyledField("업무 담당자", _handlerC, hint: "담당자 성함"),
              _buildStyledField("상세 사유/비고", _reasonC, hint: "특이사항 기록"),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
        ElevatedButton(
            onPressed: () => Navigator.pop(context, {
              'status': _selectedStatus,
              'location': _locC.text.trim(),
              'handler': _handlerC.text.trim(),
              'reason': _reasonC.text.trim()
            }),
            child: const Text("확인 완료")
        ),
      ],
    );
  }

  Widget _buildStyledField(String label, TextEditingController ctrl, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.26), fontSize: 13, fontWeight: FontWeight.bold),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: OutlineInputBorder(borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.fromLTRB(12, 22, 12, 10),
        ),
      ),
    );
  }

  Widget _buildStyledDropdown(String label, String initial, List<String> items, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: initial,
        items: items.map((e) => DropdownMenuItem(
            value: e,
            child: Text(e, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))
        )).toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.26), fontSize: 13, fontWeight: FontWeight.bold),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: OutlineInputBorder(borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        ),
      ),
    );
  }
}