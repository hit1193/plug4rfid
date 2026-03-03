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

/// [UI 설정 객체] 상위 페이지에서 이 객체를 통해 페이지의 스타일을 제어할 수 있습니다.
class ProductUiConfig {
  final TextStyle hintStyle;
  final TextStyle labelStyle;
  final Color inputFillColor;
  final Color inputFocusColor;
  final Color inputBorderColor;
  final double buttonElevation;
  final Color surfaceColor;
  final double outlineWidth;

  const ProductUiConfig({
    this.hintStyle = AppTheme.inputHintStyle,
    this.labelStyle = AppTheme.inputLabelStyle,
    this.inputFillColor = AppTheme.inputFillColor,
    this.inputFocusColor = AppTheme.inputFocusColor,
    this.inputBorderColor = AppTheme.inputBorderColor,
    this.buttonElevation = AppTheme.buttonElevation,
    this.surfaceColor = AppTheme.surface,
    this.outlineWidth = AppTheme.outlineWidth,
  });
}

class ProductPage extends StatefulWidget {
  final String searchQuery;
  final bool isMobile;
  final String baseUrl;
  final ProductUiConfig uiConfig;

  const ProductPage({
    super.key,
    required this.searchQuery,
    required this.isMobile,
    required this.baseUrl,
    this.uiConfig = const ProductUiConfig(),
  });

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  final TextEditingController _searchController = TextEditingController();
  String _currentQuery = "";
  String _groupByMode = 'item';
  String? _selectedGroupKey;

  final String _sortCriteria = 'name';
  bool _hideExcluded = true;

  static const double _colImgSize = 65.0;
  static const double _colActionWidth = 160.0;

  static const Set<String> _excludedSystemKeys = {
    'excel_row',
    'import_date',
    'import_data',
    'is_auto_tag',
    'is_auto_atg',
    'excel_row_internal',
    'import_date_internal',
    'is_auto_tag_internal',
    'origin_key_map',
    'history',
    'last_location_info'
  };

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
      case '품명':
        return p.name;
      case '태그ID':
        return p.tagId;
      case '위치':
        return p.location ?? "-";
      case '상태':
        return p.status;
      case '규격':
        return p.spec ?? "-";
      case '분류':
        return p.category ?? "-";
      case 'S/N':
        return p.serialNumber ?? "-";
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
      if (lastDate.startsWith(todayStr)) {
        if (inStatus.contains(item.status)) {
          todayIn++;
        }
        if (excludeStock.contains(item.status)) {
          todayOut++;
        }
      }
      if (!excludeStock.contains(item.status)) {
        currentStock++;
      }
    }
    return {
      'prev': currentStock - todayIn + todayOut,
      'in': todayIn,
      'out': todayOut,
      'stock': currentStock
    };
  }

  Future<void> _processAssetAccess(ProductProvider provider, ProductModel p, String type) async {
    final messenger = ScaffoldMessenger.of(context);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _ManualInoutDialog(type: type, product: p, uiConfig: widget.uiConfig),
    );

    if (result == null) {
      return;
    }

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

    if (success) {
      messenger.showSnackBar(SnackBar(
        content: Text('[${p.name}] ${result['status']} 완료'),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 1),
      ));
    }
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
      data: AppTheme.lightTheme.copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: AppTheme.fontPretendard),
      ),
      child: Scaffold(
        backgroundColor: widget.uiConfig.surfaceColor,
        body: Stack(
          children: [
            Column(
              children: [
                _buildDashboard(metrics),
                const Divider(),
                if (provider.isLoading) ...[
                  const LinearProgressIndicator(minHeight: 2, color: AppTheme.primary)
                ],
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
            if (provider.isParsing || provider.isSaving) ...[
              _buildGlobalLoadingOverlay(provider)
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(Map<String, dynamic> m) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: LayoutBuilder(builder: (ctx, constraints) {
        bool isWide = constraints.maxWidth > 700;
        if (isWide) {
          return Row(
            children: [
              _buildStatTile("전일 재고", m['prev'], Icons.history, Colors.blueGrey),
              const SizedBox(width: 10),
              _buildStatTile("금일 입고", m['in'], Icons.add_chart, Colors.blue),
              const SizedBox(width: 10),
              _buildStatTile("금일 출고", m['out'], Icons.trending_down, Colors.orange),
              const SizedBox(width: 10),
              _buildStatTile("현재 실재고", m['stock'], Icons.inventory, AppTheme.primary, isMain: true),
            ],
          );
        } else {
          return Column(
            children: [
              Row(
                children: [
                  _buildStatTile("입고", m['in'], Icons.add_chart, Colors.blue),
                  const SizedBox(width: 8),
                  _buildStatTile("출고", m['out'], Icons.trending_down, Colors.orange),
                ],
              ),
              const SizedBox(height: 8),
              _buildStatTile("현재 실재고", m['stock'], Icons.inventory, AppTheme.primary, isMain: true, fullWidth: true),
            ],
          );
        }
      }),
    );
  }

  Widget _buildStatTile(String label, int val, IconData icon, Color color, {bool isMain = false, bool fullWidth = false}) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isMain ? color : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isMain ? color : color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isMain ? Colors.white : color, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: isMain ? Colors.white70 : Colors.black45, fontWeight: FontWeight.bold)),
              Text('$val', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isMain ? Colors.white : Colors.black87)),
            ],
          ),
        ],
      ),
    );
    if (fullWidth) {
      return SizedBox(width: double.infinity, child: card);
    } else {
      return Expanded(child: card);
    }
  }

  Widget _buildSplitLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys, List<ProductModel> filtered) {
    return Row(
      children: [
        Container(
          width: 380,
          color: Colors.white,
          child: Column(
            children: [
              _buildHeader(provider, filtered),
              _buildFilterBar(),
              Expanded(
                child: RepaintBoundary(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    itemCount: groupKeys.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
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
        const VerticalDivider(),
        Expanded(
          child: Container(
            color: widget.uiConfig.surfaceColor,
            child: RepaintBoundary(
              child: _selectedGroupKey == null
                  ? _buildEmptyState("상세 분석을 위해 집계 내역을 선택하십시오.")
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 60),
              itemCount: groupKeys.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
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

  Widget _buildHeader(ProductProvider provider, List<ProductModel> filtered) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              _buildActionIcon(Icons.refresh, "새로고침", () {
                provider.fetchData();
              }),
              const SizedBox(width: 4),
              _buildActionIcon(FontAwesomeIcons.fileArrowUp, "엑셀 임포트", () async {
                final res = await provider.batchImportFromExcel();
                if (res['total']! > 0) {
                  _showInfoDialog("임포트 완료", "성공: ${res['success']} / 전체: ${res['total']}");
                }
              }, color: Colors.indigo),
              const SizedBox(width: 4),
              _buildActionIcon(Icons.settings_outlined, "표시 설정", () {
                _showColumnSelectionDialog(provider);
              }),
              const SizedBox(width: 4),
              _buildActionIcon(FontAwesomeIcons.fileArrowDown, "엑셀 출력", () {
                _exportToExcel(context, filtered);
              }, color: Colors.green),
              const SizedBox(width: 4),
              _buildActionIcon(Icons.delete_sweep_outlined, "초기화", () {
                _showResetDialog(provider);
              }, color: AppTheme.danger),
              const Spacer(),
              _buildActionIcon(Icons.add_circle, "신규 등록", () {
                _showForm(context, provider, null);
              }, color: AppTheme.primary, isLarge: true),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (v) {
              setState(() {
                _currentQuery = v;
              });
            },
            decoration: InputDecoration(
              hintText: '품명 또는 태그ID 검색...',
              hintStyle: widget.uiConfig.hintStyle,
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: const Color(0xFFF1F3F5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, String tip, VoidCallback onTap, {Color? color, bool isLarge = false}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(icon, color: color ?? Colors.black54, size: isLarge ? 30 : 20),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'item', label: Text('품명별', style: TextStyle(fontWeight: FontWeight.bold))),
            ButtonSegment(value: 'location', label: Text('위치별', style: TextStyle(fontWeight: FontWeight.bold))),
            ButtonSegment(value: 'category', label: Text('분류별', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          selected: {_groupByMode},
          showSelectedIcon: true,
          onSelectionChanged: (Set<String> newSelection) {
            setState(() {
              _groupByMode = newSelection.first;
              _selectedGroupKey = null;
            });
          },
        ),
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
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Container(width: 4, height: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(groupName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const Spacer(),
              FilterChip(
                label: const Text('보유 자산만 보기', style: TextStyle(fontSize: 12)),
                selected: _hideExcluded,
                onSelected: (v) {
                  setState(() {
                    _hideExcluded = v;
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            cacheExtent: 1000,
            itemCount: displayItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, idx) {
              final p = displayItems[idx];
              Color statusColor = p.status == '정상' ? AppTheme.success : (excludeStatus.contains(p.status) ? Colors.grey : Colors.orange);

              return InkWell(
                onTap: () {
                  _showForm(context, provider, p);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    border: Border.all(color: statusColor, width: AppTheme.outlineWidth),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _buildThumbnail(p, size: _colImgSize),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Wrap(
                            spacing: 20,
                            runSpacing: 8,
                            alignment: WrapAlignment.start,
                            children: dynamicColumns.map((col) {
                              return SizedBox(
                                width: 130,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(col, style: const TextStyle(fontSize: 10, color: Colors.black26, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(_getDisplayValue(p, col), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87), overflow: TextOverflow.ellipsis),
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
                              _buildCircleAction(Icons.login, AppTheme.success, "입고", () {
                                _processAssetAccess(provider, p, '수기입고');
                              }),
                              const SizedBox(width: 8),
                              _buildCircleAction(Icons.logout, AppTheme.warning, "출고", () {
                                _processAssetAccess(provider, p, '수기출고');
                              }),
                              const SizedBox(width: 8),
                              _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () {
                                _confirmIndividualDelete(context, provider, p);
                              }),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCircleAction(IconData icon, Color color, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, bool isMobile) {
    const exclude = {'판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'};
    final total = items.length;
    final inStock = items.where((i) => !exclude.contains(i.status)).length;
    final normalCount = items.where((i) => i.status == '정상').length;
    final healthRatio = total > 0 ? normalCount / total : 0.0;

    return InkWell(
      onTap: () {
        if (isMobile) {
          _showMobileGroupDetail(provider, title, items);
        } else {
          setState(() {
            _selectedGroupKey = title;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? AppTheme.primary : Colors.transparent, width: 2),
          boxShadow: isSelected ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 10)] : null,
        ),
        child: Column(
          children: [
            Row(
              children: [
                _buildThumbnail(items.first, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('현재고: $inStock / 전체: $total', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded, color: AppTheme.danger, size: 22),
                  tooltip: "일괄 삭제",
                  onPressed: () {
                    _confirmGroupDelete(context, provider, title, items);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: healthRatio,
                minHeight: 4,
                backgroundColor: Colors.black.withValues(alpha: 0.05),
                color: healthRatio > 0.8 ? AppTheme.success : (healthRatio > 0.4 ? Colors.orange : Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(ProductModel p, {double size = 44}) {
    final url = p.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network("$url?t=${p.updated}", fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) {
        return const Icon(Icons.broken_image, size: 18, color: Colors.black12);
      })
          : const Icon(Icons.inventory_2_outlined, color: Colors.black12, size: 22),
    );
  }

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
    XFile? file;
    Uint8List? preview;
    final Map<String, TextEditingController> metaControllers = {};

    if (p != null) {
      p.metadata.forEach((key, value) {
        if (!_excludedSystemKeys.contains(key)) {
          metaControllers[key] = TextEditingController(text: value?.toString() ?? "");
        }
      });
    } else {
      final keys = provider.items.expand((i) => i.metadata.keys).toSet();
      for (final key in keys) {
        if (!_excludedSystemKeys.contains(key)) {
          metaControllers[key] = TextEditingController();
        }
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (dialogCtx, setS) {
        final sw = MediaQuery.of(dialogCtx).size.width;
        const double fw = 370.0;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(p == null ? "신규 자산 마스터 등록" : "상세 제원 정보 수정", style: const TextStyle(fontWeight: FontWeight.bold)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          content: SizedBox(
            width: sw > 850 ? 800 : sw * 0.95,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
                      if (img != null) {
                        final b = await img.readAsBytes();
                        setS(() {
                          file = img;
                          preview = b;
                        });
                      }
                    },
                    child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black12)),
                        clipBehavior: Clip.antiAlias,
                        child: preview != null
                            ? Image.memory(preview!, fit: BoxFit.cover)
                            : (p?.getImageUrl(widget.baseUrl) != null ? Image.network("${p!.getImageUrl(widget.baseUrl)}?t=${p.updated}", fit: BoxFit.cover, gaplessPlayback: true) : const Icon(Icons.camera_alt, size: 40, color: Colors.grey))),
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader(Icons.star, "기본 제원 정보", Colors.blue),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.start,
                    children: [
                      SizedBox(width: fw, child: _buildStyledField("품명", nameC)),
                      SizedBox(width: fw, child: _buildStyledField("태그ID", tagC, hint: "RFID EPC")),
                      SizedBox(width: fw, child: _buildStyledField("위치", locC)),
                      SizedBox(width: fw, child: _buildStyledField("분류", catC)),
                      SizedBox(width: fw, child: _buildStyledField("규격", specC)),
                      SizedBox(width: fw, child: _buildStyledField("안전재고", safeC, keyboardType: TextInputType.number)),
                      SizedBox(width: fw, child: _buildStyledField("S/N", snC)),
                      SizedBox(
                          width: fw,
                          child: _buildStyledDropdown("현재 상태", selectedStatus, ProductProvider.allStatus, (v) {
                            if (v != null) {
                              setS(() {
                                selectedStatus = v;
                              });
                            }
                          })),
                    ],
                  ),

                  if (metaControllers.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    _buildSectionHeader(Icons.table_view, "추가 메타데이터 (Excel)", Colors.green),
                    const SizedBox(height: 20),
                    Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.start,
                        children: metaControllers.entries.map((e) {
                          return SizedBox(width: fw, child: _buildStyledField(e.key, e.value));
                        }).toList()),
                  ],

                  if (p == null) ...[
                    const SizedBox(height: 32),
                    _buildSectionHeader(Icons.copy_all, "벌크(대량) 생성 설정", Colors.orange),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.start,
                      children: [
                        SizedBox(width: fw, child: _buildStyledField("등록 수량 (단위: EA)", qtyC, keyboardType: TextInputType.number)),
                        Container(
                          width: fw,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.1)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 20, color: Colors.orange),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "설정한 수량만큼 동일 제원의 자산이 일괄 등록됩니다.",
                                  style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
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
            TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                },
                style: Theme.of(context).textButtonTheme.style,
                child: const Text("취소")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                elevation: widget.uiConfig.buttonElevation,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
              onPressed: () async {
                if (nameC.text.trim().isEmpty) {
                  return;
                }

                final navigator = Navigator.of(dialogCtx);
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
                    final data = {'name': nameC.text.trim(), 'tag_id': finalTag, 'location': locC.text.trim(), 'category': catC.text.trim(), 'spec': specC.text.trim(), 'serial_number': snC.text.trim(), 'status': selectedStatus, 'safety_stock': int.tryParse(safeC.text.trim()) ?? 5, 'metadata': updatedMeta};
                    final res = await provider.handleSave(p: null, data: data, imageXFile: file);
                    if (!res) {
                      allSuccess = false;
                    }
                  }
                } else {
                  final data = {'name': nameC.text.trim(), 'tag_id': tagC.text.trim(), 'location': locC.text.trim(), 'category': catC.text.trim(), 'spec': specC.text.trim(), 'serial_number': snC.text.trim(), 'status': selectedStatus, 'safety_stock': int.tryParse(safeC.text.trim()) ?? 5, 'metadata': updatedMeta};
                  allSuccess = await provider.handleSave(p: p, data: data, imageXFile: file);
                }

                if (allSuccess) {
                  navigator.pop();
                }
              },
              child: const Text("데이터 저장"),
            ),
          ],
        );
      }),
    );
  }

  void _showColumnSelectionDialog(ProductProvider provider) {
    final base = ['품명', '태그ID', '위치', '상태', '규격', '분류', 'S/N'];
    final metaKeys = provider.items.expand((i) => i.metadata.keys).toSet();
    final filteredMeta = metaKeys.where((k) => !_excludedSystemKeys.contains(k)).toList()..sort();

    final all = [...base, ...filteredMeta];
    List<String> temp = List.from(provider.selectedColumns);

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (context, setS) => AlertDialog(
                title: const Text("표시 항목 설정"),
                content: SizedBox(
                    width: 350,
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: all.map((key) {
                              return CheckboxListTile(
                                  title: Text(key),
                                  value: temp.contains(key),
                                  onChanged: (val) {
                                    setS(() {
                                      if (val!) {
                                        if (temp.length < 5) {
                                          temp.add(key);
                                        }
                                      } else if (temp.length > 1) {
                                        temp.remove(key);
                                      }
                                    });
                                  });
                            }).toList()))),
                actions: [
                  TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                      },
                      style: Theme.of(context).textButtonTheme.style,
                      child: const Text("취소")),
                  ElevatedButton(
                      onPressed: () async {
                        final navigator = Navigator.of(ctx);
                        await provider.saveRemoteSettings(temp);
                        navigator.pop();
                      },
                      child: const Text("적용"))
                ])));
  }

  Future<void> _exportToExcel(BuildContext context, List<ProductModel> list) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['Inventory'];
      sheet.appendRow([excel_pkg.TextCellValue('품명'), excel_pkg.TextCellValue('태그ID'), excel_pkg.TextCellValue('위치'), excel_pkg.TextCellValue('상태')]);
      for (final i in list) {
        sheet.appendRow([excel_pkg.TextCellValue(i.name), excel_pkg.TextCellValue(i.tagId), excel_pkg.TextCellValue(i.location ?? ""), excel_pkg.TextCellValue(i.status)]);
      }
      final path = await FilePicker.platform.saveFile(fileName: 'Inventory_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx']);
      if (path != null) {
        await File(path).writeAsBytes(excel.encode()!);
        messenger.showSnackBar(const SnackBar(content: Text('✅ 엑셀 저장 성공')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ 엑셀 저장 실패: $e')));
    }
  }

  void _confirmGroupDelete(BuildContext context, ProductProvider provider, String groupName, List<ProductModel> items) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: const Text("그룹 일괄 삭제"),
            content: Text("[$groupName] 그룹의 모든 자산(${items.length}개)을 삭제하시겠습니까?"),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  style: Theme.of(context).textButtonTheme.style,
                  child: const Text("취소")),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, elevation: 0),
                  onPressed: () async {
                    final navigator = Navigator.of(ctx);
                    await provider.deleteMultipleProducts(items.map((e) => e.id).toList());
                    setState(() {
                      _selectedGroupKey = null;
                    });
                    navigator.pop();
                  },
                  child: const Text("일괄 삭제"))
            ]));
  }

  void _showResetDialog(ProductProvider provider) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(title: const Text("전체 초기화"), content: const Text("모든 정보를 삭제하고 설정을 리셋하시겠습니까?"), actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              style: Theme.of(context).textButtonTheme.style,
              child: const Text("취소")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, elevation: 0),
              onPressed: () async {
                final navigator = Navigator.of(ctx);
                await provider.resetAllProducts();
                setState(() {
                  _selectedGroupKey = null;
                });
                navigator.pop();
              },
              child: const Text("삭제"))
        ]));
  }

  void _confirmIndividualDelete(BuildContext context, ProductProvider provider, ProductModel p) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(title: const Text("삭제 확인"), content: Text("[${p.name}] 자산을 삭제하시겠습니까?"), actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              style: Theme.of(context).textButtonTheme.style,
              child: const Text("취소")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(elevation: 0),
              onPressed: () async {
                final navigator = Navigator.of(ctx);
                await provider.deleteMultipleProducts([p.id]);
                navigator.pop();
              },
              child: const Text("삭제"))
        ]));
  }

  void _showMobileGroupDetail(ProductProvider provider, String groupName, List<ProductModel> items) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))), height: MediaQuery.of(context).size.height * 0.85, child: _buildDetailView(provider, groupName, items)));
  }

  void _showInfoDialog(String title, String msg) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(msg),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  style: Theme.of(context).textButtonTheme.style,
                  child: const Text("확인"))
            ]));
  }

  Widget _buildEmptyState(String msg) {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.touch_app_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(msg, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
        ]));
  }

  Widget _buildSectionHeader(IconData icon, String title, Color color) {
    return Column(children: [
      Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 8), Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 13))]),
      const Divider(),
    ]);
  }

  Widget _buildStyledField(String label, TextEditingController ctrl, {TextInputType keyboardType = TextInputType.text, String? hint}) {
    return StatefulBuilder(builder: (context, setStateField) {
      return Focus(
        onFocusChange: (hasFocus) {
          setStateField(() {});
        },
        child: Builder(builder: (ctx) {
          final bool hasFocus = Focus.of(ctx).hasFocus;
          return TextField(
            controller: ctrl,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              hintStyle: widget.uiConfig.hintStyle,
              labelStyle: widget.uiConfig.labelStyle,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              filled: true,
              fillColor: hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: hasFocus ? AppTheme.primary : widget.uiConfig.inputBorderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.uiConfig.inputBorderColor),
              ),
              contentPadding: const EdgeInsets.fromLTRB(12, 22, 12, 10),
            ),
          );
        }),
      );
    });
  }

  Widget _buildStyledDropdown(String label, String initial, List<String> items, ValueChanged<String?> onChanged) {
    return StatefulBuilder(
        builder: (context, setStateField) {
          return Focus(
            onFocusChange: (hasFocus) {
              setStateField(() {});
            },
            child: Builder(
                builder: (ctx) {
                  final bool hasFocus = Focus.of(ctx).hasFocus;
                  return DropdownButtonFormField<String>(
                    initialValue: initial,
                    items: items.map((e) {
                      return DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)));
                    }).toList(),
                    onChanged: onChanged,
                    decoration: InputDecoration(
                        labelText: label,
                        labelStyle: widget.uiConfig.labelStyle,
                        filled: true,
                        // [핵심] 텍스트 필드와 동일하게 포커스 시 배경색 변경
                        fillColor: hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: hasFocus ? AppTheme.primary : widget.uiConfig.inputBorderColor)
                        ),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: widget.uiConfig.inputBorderColor)
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
                    ),
                  );
                }
            ),
          );
        }
    );
  }

  Widget _buildGlobalLoadingOverlay(ProductProvider provider) {
    return Container(
        color: Colors.black26,
        child: Center(
            child: Card(
                child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      Text(provider.isParsing ? "분석 중..." : "저장 중...", style: const TextStyle(fontWeight: FontWeight.bold))
                    ])))));
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
  final String type;
  final ProductModel product;
  final ProductUiConfig uiConfig;
  const _ManualInoutDialog({required this.type, required this.product, required this.uiConfig});
  @override
  State<_ManualInoutDialog> createState() => _ManualInoutDialogState();
}

class _ManualInoutDialogState extends State<_ManualInoutDialog> {
  late TextEditingController _locC, _reasonC, _handlerC;
  late String _selS;
  @override
  void initState() {
    super.initState();
    _locC = TextEditingController(text: widget.product.location ?? "창고A");
    _reasonC = TextEditingController();
    _handlerC = TextEditingController();
    _selS = widget.type == '수기입고' ? '구매입고' : '판매출고';
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
    final isIn = widget.type == '수기입고';
    final items = isIn ? ['구매입고', '회수/반납', '수기입고'] : ['판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'];
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [Icon(isIn ? Icons.login : Icons.logout, color: isIn ? AppTheme.success : AppTheme.warning), const SizedBox(width: 10), Text('${widget.type} 처리')]),
      content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text("품목: ${widget.product.name}", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                _buildStyledDropdown("유형", _selS, items, (v) {
                  if (v != null) {
                    setState(() {
                      _selS = v;
                    });
                  }
                }),
                const SizedBox(height: 16),
                _buildStyledField("위치", _locC),
                const SizedBox(height: 16),
                _buildStyledField("담당자", _handlerC),
                const SizedBox(height: 16),
                _buildStyledField("비고", _reasonC)
              ]))),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            style: Theme.of(context).textButtonTheme.style,
            child: const Text("취소")),
        ElevatedButton(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context, {'status': _selS, 'location': _locC.text.trim(), 'handler': _handlerC.text.trim(), 'reason': _reasonC.text.trim()});
            },
            child: const Text("확인"))
      ],
    );
  }

  Widget _buildStyledField(String label, TextEditingController ctrl) {
    return StatefulBuilder(builder: (context, setStateField) {
      return Focus(
        onFocusChange: (hasFocus) => setStateField(() {}),
        child: Builder(builder: (ctx) {
          final bool hasFocus = Focus.of(ctx).hasFocus;
          return TextField(
              controller: ctrl,
              decoration: InputDecoration(
                  labelText: label,
                  labelStyle: widget.uiConfig.labelStyle,
                  filled: true,
                  fillColor: hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: hasFocus ? AppTheme.primary : widget.uiConfig.inputBorderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.uiConfig.inputBorderColor)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
              )
          );
        }),
      );
    });
  }

  Widget _buildStyledDropdown(String label, String initial, List<String> items, ValueChanged<String?> onChanged) {
    return StatefulBuilder(
        builder: (context, setStateField) {
          return Focus(
            onFocusChange: (hasFocus) => setStateField(() {}),
            child: Builder(
                builder: (ctx) {
                  final bool hasFocus = Focus.of(ctx).hasFocus;
                  return DropdownButtonFormField<String>(
                      initialValue: initial,
                      items: items.map((e) {
                        return DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)));
                      }).toList(),
                      onChanged: onChanged,
                      decoration: InputDecoration(
                          labelText: label,
                          labelStyle: widget.uiConfig.labelStyle,
                          filled: true,
                          fillColor: hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: hasFocus ? AppTheme.primary : widget.uiConfig.inputBorderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.uiConfig.inputBorderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
                      )
                  );
                }
            ),
          );
        }
    );
  }
}