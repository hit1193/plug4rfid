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

  // --- 한글 초성 추출 로직 ---
  String _getChosung(String text) {
    const chosungList = [
      'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'
    ];
    String result = "";
    for (int i = 0; i < text.length; i++) {
      int code = text.codeUnitAt(i) - 0xAC00;
      if (code >= 0 && code <= 11172) {
        result += chosungList[code ~/ 588];
      } else {
        result += text[i];
      }
    }
    return result;
  }

  // --- 스마트 검색 매칭 로직 ---
  bool _isMatch(String target, String query) {
    final t = target.toLowerCase();
    final q = query.toLowerCase();
    if (t.contains(q)) {
      return true;
    }
    final RegExp chosungRegExp = RegExp(r'^[ㄱ-ㅎ\s]+$');
    if (chosungRegExp.hasMatch(q)) {
      return _getChosung(t).contains(q);
    }
    return false;
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
      case 'S/N': return p.serialNumber ?? "-";
      default: return p.metadata[key]?.toString() ?? "-";
    }
  }

  Map<String, dynamic> _calculateMetrics(List<ProductModel> allItems) {
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0; int todayOut = 0; int currentStock = 0;

    const inStatus = {'구매입고', '회수/반납', '수기입고'};
    const excludeStock = {'판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'};

    for (final item in allItems) {
      final lastDate = item.updated ?? item.created ?? "";
      if (lastDate.startsWith(todayStr)) {
        if (inStatus.contains(item.status)) { todayIn++; }
        if (excludeStock.contains(item.status)) { todayOut++; }
      }
      if (!excludeStock.contains(item.status)) { currentStock++; }
    }
    return {'prev': currentStock - todayIn + todayOut, 'in': todayIn, 'out': todayOut, 'stock': currentStock};
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
        if (found != null && mounted) {
          _showForm(context, provider, found);
        } else if (mounted) {
          _showForm(context, provider, null, initialTag: tag);
        }
      });
    }

    final filtered = provider.items.where((p) {
      final q = _currentQuery.trim();
      if (q.isEmpty) {
        return true;
      }
      return _isMatch(p.name, q) || _isMatch(p.location ?? "", q) || _isMatch(p.category ?? "", q);
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
                const Divider(indent: 0, endIndent: 0),
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
                const SizedBox(height: 20),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: Colors.white,
      child: LayoutBuilder(builder: (ctx, constraints) {
        bool isWide = constraints.maxWidth > 850;
        if (isWide) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1600),
              child: Row(
                children: [
                  Expanded(child: _buildStatTile("전일 재고", m['prev'], Icons.history, Colors.blueGrey)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatTile("금일 입고", m['in'], Icons.add_chart, Colors.green)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatTile("금일 출고", m['out'], Icons.trending_down, Colors.orange)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatTile("현재 실재고", m['stock'], Icons.inventory, AppTheme.primary, isMain: true)),
                ],
              ),
            ),
          );
        } else {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildStatTile("전일 재고", m['prev'], Icons.history, Colors.blueGrey)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatTile("금일 입고", m['in'], Icons.add_chart, Colors.green)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildStatTile("금일 출고", m['out'], Icons.trending_down, Colors.orange)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatTile("현재 실재고", m['stock'], Icons.inventory, AppTheme.primary, isMain: true)),
                ],
              ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 2),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7), fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                Text('$val', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: card) : card;
  }

  Widget _buildSplitLayout(ProductProvider provider, Map<String, List<ProductModel>> groupedMap, List<String> groupKeys, List<ProductModel> filtered) {
    return Row(
      children: [
        Container(
          width: 420,
          color: Colors.white,
          child: Column(
            children: [
              _buildHeader(provider, filtered),
              _buildFilterBar(),
              Expanded(
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
            ],
          ),
        ),
        const VerticalDivider(),
        Expanded(
          child: Container(
            color: widget.uiConfig.surfaceColor,
            padding: const EdgeInsets.only(left: 12),
            child: _selectedGroupKey == null
                ? _buildEmptyState("상세 분석을 위해 집계 내역을 선택하십시오.")
                : _buildDetailView(provider, _selectedGroupKey!, groupedMap[_selectedGroupKey] ?? [], key: ValueKey('detail_$_selectedGroupKey')),
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 50),
            itemCount: groupKeys.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, idx) {
              final key = groupKeys[idx];
              return _buildGroupTile(provider, key, groupedMap[key]!, false, true);
            },
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
              Expanded(
                child: Wrap(
                  spacing: 4, runSpacing: 4,
                  alignment: WrapAlignment.start,
                  children: [
                    _buildActionIcon(Icons.refresh, "새로고침", () { provider.fetchData(); }),
                    _buildActionIcon(FontAwesomeIcons.fileArrowUp, "엑셀 임포트", () async {
                      final res = await provider.batchImportFromExcel();
                      if (res['total']! > 0) {
                        _showInfoDialog("임포트 완료", "성공: ${res['success']} / 전체: ${res['total']}");
                      }
                    }, color: Colors.indigo),
                    _buildActionIcon(FontAwesomeIcons.fileArrowDown, "엑셀 출력", () { _exportToExcel(context, filtered); }, color: Colors.green),
                    _buildActionIcon(Icons.settings_outlined, "표시 설정", () { _showColumnSelectionDialog(provider); }),
                    _buildActionIcon(Icons.delete_sweep_outlined, "초기화", () { _showResetDialog(provider); }, color: AppTheme.danger),
                  ],
                ),
              ),
              _buildActionIcon(Icons.add_box, "신규 등록", () { _showForm(context, provider, null); }, color: AppTheme.primary, isLarge: true),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (v) { setState(() { _currentQuery = v; }); },
            decoration: InputDecoration(
              hintText: '품명, 위치, 분류 또는 초성 검색...',
              hintStyle: widget.uiConfig.hintStyle,
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Color(0xFFE9ECEF), width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
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
        child: Container(width: 44, height: 44, alignment: Alignment.center, child: Icon(icon, color: color ?? Colors.black54, size: isLarge ? 30 : 20)),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          style: SegmentedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), visualDensity: VisualDensity.comfortable),
          segments: const [
            ButtonSegment(value: 'item', label: Text('품명별', style: TextStyle(fontWeight: FontWeight.bold))),
            ButtonSegment(value: 'location', label: Text('위치별', style: TextStyle(fontWeight: FontWeight.bold))),
            ButtonSegment(value: 'category', label: Text('분류별', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          selected: {_groupByMode},
          showSelectedIcon: true,
          onSelectionChanged: (Set<String> v) { setState(() { _groupByMode = v.first; _selectedGroupKey = null; }); },
        ),
      ),
    );
  }

  Widget _buildDetailView(ProductProvider provider, String groupName, List<ProductModel> items, {Key? key}) {
    const exclude = {'판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'};
    final display = _hideExcluded ? items.where((p) => !exclude.contains(p.status)).toList() : items;
    final cols = provider.selectedColumns;

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
              FilterChip(label: const Text('보유 자산만 보기', style: TextStyle(fontSize: 12)), selected: _hideExcluded, onSelected: (v) { setState(() { _hideExcluded = v; }); }),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 70),
            itemCount: display.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, idx) {
              final p = display[idx];
              Color sCol = p.status == '정상' ? AppTheme.success : (exclude.contains(p.status) ? Colors.grey : Colors.orange);
              return InkWell(
                onTap: () { _showForm(context, provider, p); },
                child: Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.cardRadius), border: Border.all(color: sCol, width: AppTheme.outlineWidth), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))]),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _buildThumbnail(p, size: _colImgSize),
                        const SizedBox(width: 16),
                        Expanded(child: Wrap(spacing: 20, runSpacing: 8, children: cols.map((c) => SizedBox(width: 130, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c, style: const TextStyle(fontSize: 10, color: Colors.black26, fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text(_getDisplayValue(p, c), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87), overflow: TextOverflow.ellipsis)]))).toList())),
                        SizedBox(width: _colActionWidth, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [_buildCircleAction(Icons.login, AppTheme.success, "입고", () { _processAssetAccess(provider, p, '수기입고'); }), const SizedBox(width: 8), _buildCircleAction(Icons.logout, AppTheme.warning, "출고", () { _processAssetAccess(provider, p, '수기출고'); }), const SizedBox(width: 8), _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () { _confirmIndividualDelete(context, provider, p); })])),
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

  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, bool isMobile) {
    final healthRatio = items.isEmpty ? 0.0 : items.where((i) => i.status == '정상').length / items.length;
    Color hCol = healthRatio == 1.0 ? AppTheme.success : (healthRatio > 0.4 ? Colors.orange : AppTheme.danger);
    return InkWell(
      onTap: () { isMobile ? _showMobileGroupDetail(provider, title, items) : setState(() { _selectedGroupKey = title; }); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(AppTheme.cardRadius), border: Border.all(color: isSelected ? AppTheme.primary : hCol.withValues(alpha: 0.6), width: AppTheme.outlineWidth), boxShadow: isSelected ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 10)] : null),
        child: Row(
          children: [
            _buildThumbnail(items.first, size: 48),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: hCol.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: hCol.withValues(alpha: 0.2))), child: Text('${items.length}', style: TextStyle(color: hCol, fontWeight: FontWeight.w900, fontSize: 13))),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.delete_sweep_rounded, color: AppTheme.danger, size: 22), tooltip: "일괄 삭제", onPressed: () { _confirmGroupDelete(context, provider, title, items); }),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(ProductModel p, {double size = 44}) {
    final url = p.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(width: size, height: size, decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(10)), clipBehavior: Clip.antiAlias, child: url != null ? Image.network("$url?t=${p.updated}", fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 18, color: Colors.black12)) : const Icon(Icons.inventory_2_outlined, color: Colors.black12, size: 22));
  }

  Widget _buildFlatButton({required String text, required VoidCallback onPressed, Color? bgColor, Color? textColor}) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onPressed, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14), decoration: BoxDecoration(color: bgColor ?? AppTheme.primary, borderRadius: BorderRadius.circular(8)), child: Text(text, style: TextStyle(color: textColor ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 14)))));
  }

  // [복구] 원형 액션 버튼 빌더
  Widget _buildCircleAction(IconData icon, Color color, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  // [복구] 엑셀 출력 메서드
  Future<void> _exportToExcel(BuildContext context, List<ProductModel> list) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['Inventory'];
      sheet.appendRow([
        excel_pkg.TextCellValue('품명'),
        excel_pkg.TextCellValue('태그ID'),
        excel_pkg.TextCellValue('위치'),
        excel_pkg.TextCellValue('상태')
      ]);

      for (final i in list) {
        sheet.appendRow([
          excel_pkg.TextCellValue(i.name),
          excel_pkg.TextCellValue(i.tagId),
          excel_pkg.TextCellValue(i.location ?? ""),
          excel_pkg.TextCellValue(i.status)
        ]);
      }

      final path = await FilePicker.platform.saveFile(
          fileName: 'Inventory_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx']
      );

      if (path != null) {
        final file = File(path);
        await file.writeAsBytes(excel.encode()!);
        messenger.showSnackBar(const SnackBar(content: Text('✅ 엑셀 저장 성공')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ 엑셀 저장 실패: $e')));
    }
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
    String selStatus = p?.status ?? "정상";
    XFile? file; Uint8List? preview;
    final Map<String, TextEditingController> metaC = {};
    if (p != null) {
      p.metadata.forEach((k, v) { if (!_excludedSystemKeys.contains(k)) { metaC[k] = TextEditingController(text: v?.toString() ?? ""); } });
    } else {
      for (var k in provider.items.expand((i) => i.metadata.keys).toSet()) { if (!_excludedSystemKeys.contains(k)) { metaC[k] = TextEditingController(); } }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (dialogCtx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(p == null ? "신규 자산 마스터 등록" : "상세 제원 정보 수정", style: const TextStyle(fontWeight: FontWeight.bold)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        actionsAlignment: MainAxisAlignment.center,
        content: SizedBox(width: MediaQuery.of(ctx).size.width > 850 ? 800 : 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(onTap: () async { final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70); if (img != null) { final b = await img.readAsBytes(); setS(() { file = img; preview = b; }); } }, child: Container(width: 140, height: 140, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black12)), clipBehavior: Clip.antiAlias, child: preview != null ? Image.memory(preview!, fit: BoxFit.cover) : (p?.getImageUrl(widget.baseUrl) != null ? Image.network("${p!.getImageUrl(widget.baseUrl)}?t=${p.updated}", fit: BoxFit.cover) : const Icon(Icons.camera_alt, size: 40, color: Colors.grey)))),
          const SizedBox(height: 24),
          _buildSectionHeader(Icons.star, "기본 제원 정보", Colors.blue),
          const SizedBox(height: 20),
          Wrap(spacing: 16, runSpacing: 16, children: [
            SizedBox(width: 370, child: _buildStyledField("품명", nameC)),
            SizedBox(width: 370, child: _buildStyledField("태그ID", tagC, hint: "RFID EPC")),
            SizedBox(width: 370, child: _buildStyledField("위치", locC)),
            SizedBox(width: 370, child: _buildStyledField("분류", catC)),
            SizedBox(width: 370, child: _buildStyledField("규격", specC)),
            SizedBox(width: 370, child: _buildStyledField("안전재고", safeC, keyboardType: TextInputType.number)),
            SizedBox(width: 370, child: _buildStyledField("S/N", snC)),
            SizedBox(width: 370, child: _buildStyledDropdown("현재 상태", selStatus, ProductProvider.allStatus, (v) { if (v != null) { setS(() { selStatus = v; }); } })),
          ]),
          if (metaC.isNotEmpty) ...[const SizedBox(height: 32), _buildSectionHeader(Icons.table_view, "추가 메타데이터", Colors.green), Wrap(spacing: 16, runSpacing: 16, children: metaC.entries.map((e) => SizedBox(width: 370, child: _buildStyledField(e.key, e.value))).toList())],
          if (p == null) ...[const SizedBox(height: 32), _buildSectionHeader(Icons.copy_all, "벌크 생성 설정", Colors.orange), SizedBox(width: 370, child: _buildStyledField("등록 수량", qtyC, keyboardType: TextInputType.number))],
        ]))),
        actions: [
          _buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () { Navigator.pop(dialogCtx); }),
          const SizedBox(width: 12),
          _buildFlatButton(text: "데이터 저장", onPressed: () async {
            if (nameC.text.trim().isEmpty) { return; }
            final nav = Navigator.of(dialogCtx);
            final int loop = int.tryParse(qtyC.text.trim()) ?? 1;
            final meta = Map<String, dynamic>.from(p?.metadata ?? {}); metaC.forEach((k, v) => meta[k] = v.text.trim());
            bool ok = true;
            if (p == null) { for (int i = 0; i < loop; i++) { String tid = tagC.text.trim(); if (loop > 1 && tid.isNotEmpty) { tid = "${tid}_${i + 1}"; } final res = await provider.handleSave(p: null, data: {'name': nameC.text.trim(), 'tag_id': tid, 'location': locC.text.trim(), 'category': catC.text.trim(), 'spec': specC.text.trim(), 'serial_number': snC.text.trim(), 'status': selStatus, 'safety_stock': int.tryParse(safeC.text.trim()) ?? 5, 'metadata': meta}, imageXFile: file); if (!res) { ok = false; } } }
            else { ok = await provider.handleSave(p: p, data: {'name': nameC.text.trim(), 'tag_id': tagC.text.trim(), 'location': locC.text.trim(), 'category': catC.text.trim(), 'spec': specC.text.trim(), 'serial_number': snC.text.trim(), 'status': selStatus, 'safety_stock': int.tryParse(safeC.text.trim()) ?? 5, 'metadata': meta}, imageXFile: file); }
            if (ok) { nav.pop(); }
          }),
        ],
      )),
    );
  }

  // [성능 개선] 표시 항목 설정 다이얼로그
  void _showColumnSelectionDialog(ProductProvider provider) {
    final base = ['품명', '태그ID', '위치', '상태', '규격', '분류', 'S/N'];

    // [최적화] 전수조사 대신 Set을 이용한 빠른 추출
    final Set<String> metaKeySet = {};
    final sampleCount = provider.items.length > 200 ? 200 : provider.items.length;
    for (int i = 0; i < sampleCount; i++) {
      metaKeySet.addAll(provider.items[i].metadata.keys);
    }

    final metaKeys = metaKeySet.where((k) => !_excludedSystemKeys.contains(k)).toList()..sort();
    final all = [...base, ...metaKeys];
    List<String> temp = List.from(provider.selectedColumns);

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setS) => AlertDialog(
          title: const Text("표시 항목 설정", style: TextStyle(fontWeight: FontWeight.bold)),
          actionsAlignment: MainAxisAlignment.center,
          content: SizedBox(
              width: 350,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: all.map((k) => CheckboxListTile(
                          title: Text(k),
                          value: temp.contains(k),
                          onChanged: (v) {
                            setS(() {
                              if (v!) {
                                if (temp.length < 5) { temp.add(k); }
                              } else {
                                if (temp.length > 1) { temp.remove(k); }
                              }
                            });
                          }
                      )).toList()
                  )
              )
          ),
          actions: [
            _buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () { Navigator.pop(ctx); }),
            const SizedBox(width: 8),
            _buildFlatButton(text: "적용", onPressed: () async {
              final nav = Navigator.of(ctx);
              await provider.saveRemoteSettings(temp);
              nav.pop();
            }),
          ],
        ))
    );
  }

  void _confirmGroupDelete(BuildContext ctx, ProductProvider provider, String name, List<ProductModel> items) {
    showDialog(context: ctx, builder: (c) => AlertDialog(
      title: const Text("그룹 일괄 삭제", style: TextStyle(fontWeight: FontWeight.bold)),
      content: Text("[$name] 그룹의 모든 자산(${items.length}개)을 삭제하시겠습니까?"),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        _buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () { Navigator.pop(c); }),
        const SizedBox(width: 8),
        _buildFlatButton(text: "일괄 삭제", bgColor: AppTheme.danger, onPressed: () async { final nav = Navigator.of(c); await provider.deleteMultipleProducts(items.map((e) => e.id).toList()); setState(() { _selectedGroupKey = null; }); nav.pop(); }),
      ],
    ));
  }

  void _showResetDialog(ProductProvider provider) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("전체 초기화", style: TextStyle(fontWeight: FontWeight.bold)),
      content: const Text("모든 정보를 삭제하고 설정을 리셋하시겠습니까?"),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        _buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () { Navigator.pop(ctx); }),
        const SizedBox(width: 8),
        _buildFlatButton(text: "삭제", bgColor: AppTheme.danger, onPressed: () async { final nav = Navigator.of(ctx); await provider.resetAllProducts(); setState(() { _selectedGroupKey = null; }); nav.pop(); }),
      ],
    ));
  }

  void _confirmIndividualDelete(BuildContext ctx, ProductProvider provider, ProductModel p) {
    showDialog(context: ctx, builder: (c) => AlertDialog(
      title: const Text("삭제 확인", style: TextStyle(fontWeight: FontWeight.bold)),
      content: Text("[${p.name}] 자산을 삭제하시겠습니까?"),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        _buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () { Navigator.pop(c); }),
        const SizedBox(width: 8),
        _buildFlatButton(text: "삭제", bgColor: AppTheme.danger, onPressed: () async { final nav = Navigator.of(c); await provider.deleteMultipleProducts([p.id]); nav.pop(); }),
      ],
    ));
  }

  void _showInfoDialog(String title, String msg) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Text(msg),
      actionsAlignment: MainAxisAlignment.center,
      actions: [_buildFlatButton(text: "확인", onPressed: () { Navigator.pop(ctx); })],
    ));
  }

  void _showMobileGroupDetail(ProductProvider provider, String group, List<ProductModel> items) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => Container(decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))), height: MediaQuery.of(context).size.height * 0.85, child: _buildDetailView(provider, group, items)));
  }

  Widget _buildSectionHeader(IconData icon, String title, Color color) {
    return Column(children: [Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 8), Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 13))]), const Divider()]);
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.touch_app_outlined, size: 80, color: Colors.grey[300]), const SizedBox(height: 16), Text(msg, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))]));
  }

  Widget _buildStyledField(String label, TextEditingController ctrl, {TextInputType keyboardType = TextInputType.text, String? hint}) {
    return StatefulBuilder(builder: (context, setStateField) => Focus(onFocusChange: (hasFocus) => setStateField(() {}), child: Builder(builder: (ctx) {
      final bool hasFocus = Focus.of(ctx).hasFocus;
      return TextField(controller: ctrl, keyboardType: keyboardType, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), decoration: InputDecoration(labelText: label, labelStyle: widget.uiConfig.labelStyle, hintText: hint, hintStyle: widget.uiConfig.hintStyle, filled: true, fillColor: hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: hasFocus ? AppTheme.primary : widget.uiConfig.inputBorderColor)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.uiConfig.inputBorderColor)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)));
    })));
  }

  Widget _buildStyledDropdown(String label, String initial, List<String> items, ValueChanged<String?> onChanged) {
    return StatefulBuilder(builder: (context, setStateField) => Focus(onFocusChange: (hasFocus) => setStateField(() {}), child: Builder(builder: (ctx) {
      final bool hasFocus = Focus.of(ctx).hasFocus;
      return DropdownButtonFormField<String>(initialValue: initial, items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)))).toList(), onChanged: onChanged, decoration: InputDecoration(labelText: label, labelStyle: widget.uiConfig.labelStyle, filled: true, fillColor: hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: hasFocus ? AppTheme.primary : widget.uiConfig.inputBorderColor)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.uiConfig.inputBorderColor)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)));
    })));
  }

  Widget _buildGlobalLoadingOverlay(ProductProvider provider) {
    return Container(color: Colors.black26, child: Center(child: Card(child: Padding(padding: const EdgeInsets.all(40), child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 20), Text(provider.isParsing ? "분석 중..." : "저장 중...", style: const TextStyle(fontWeight: FontWeight.bold))])))));
  }

  Map<String, List<ProductModel>> _getGroupedData(List<ProductModel> items) {
    final Map<String, List<ProductModel>> grouped = {};
    for (final item in items) {
      String key = _groupByMode == 'item' ? item.name : (_groupByMode == 'location' ? (item.location ?? "미지정") : (item.category ?? "미정"));
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
  void dispose() { _locC.dispose(); _reasonC.dispose(); _handlerC.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isIn = widget.type == '수기입고';
    final items = isIn ? ['구매입고', '회수/반납', '수기입고'] : ['판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'];
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [Icon(isIn ? Icons.login : Icons.logout, color: isIn ? AppTheme.success : AppTheme.warning), const SizedBox(width: 10), Text('${widget.type} 처리', style: const TextStyle(fontWeight: FontWeight.bold))]),
      actionsAlignment: MainAxisAlignment.center,
      content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("품목: ${widget.product.name}", style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        _buildStyledDropdown("유형", _selS, items, (v) { if (v != null) { setState(() { _selS = v; }); } }),
        const SizedBox(height: 16),
        _buildStyledField("위치", _locC),
        const SizedBox(height: 16),
        _buildStyledField("담당자", _handlerC),
        const SizedBox(height: 16),
        _buildStyledField("비고", _reasonC)
      ]))),
      actions: [
        _buildFlatButton(text: "취소", bgColor: Colors.transparent, textColor: Colors.black54, onPressed: () { Navigator.pop(context); }),
        const SizedBox(width: 12),
        _buildFlatButton(text: "확인", onPressed: () { Navigator.pop(context, {'status': _selS, 'location': _locC.text.trim(), 'handler': _handlerC.text.trim(), 'reason': _reasonC.text.trim()}); }),
      ],
    );
  }

  Widget _buildFlatButton({required String text, required VoidCallback onPressed, Color? bgColor, Color? textColor}) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onPressed, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14), decoration: BoxDecoration(color: bgColor ?? AppTheme.primary, borderRadius: BorderRadius.circular(8)), child: Text(text, style: TextStyle(color: textColor ?? Colors.white, fontWeight: FontWeight.bold, fontSize: 14)))));
  }

  Widget _buildStyledField(String label, TextEditingController ctrl) {
    return StatefulBuilder(builder: (context, setStateField) => Focus(onFocusChange: (hasFocus) => setStateField(() {}), child: Builder(builder: (ctx) {
      final bool hasFocus = Focus.of(ctx).hasFocus;
      return TextField(controller: ctrl, decoration: InputDecoration(labelText: label, labelStyle: widget.uiConfig.labelStyle, filled: true, fillColor: hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: hasFocus ? AppTheme.primary : widget.uiConfig.inputBorderColor)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.uiConfig.inputBorderColor)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)));
    })));
  }

  Widget _buildStyledDropdown(String label, String initial, List<String> items, ValueChanged<String?> onChanged) {
    return StatefulBuilder(builder: (context, setStateField) => Focus(onFocusChange: (hasFocus) => setStateField(() {}), child: Builder(builder: (ctx) {
      final bool hasFocus = Focus.of(ctx).hasFocus;
      return DropdownButtonFormField<String>(initialValue: initial, items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)))).toList(), onChanged: onChanged, decoration: InputDecoration(labelText: label, labelStyle: widget.uiConfig.labelStyle, filled: true, fillColor: hasFocus ? widget.uiConfig.inputFocusColor : widget.uiConfig.inputFillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: hasFocus ? AppTheme.primary : widget.uiConfig.inputBorderColor)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.uiConfig.inputBorderColor)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)));
    })));
  }
}