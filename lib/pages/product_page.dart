import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/products.dart';
import '../providers/product_provider.dart';

/// 디자인 시스템 상수 (기존 값 유지)
const String _fontPretendard = 'Pretendard';
const Color _primaryColor = Color(0xFF6366F1);
const Color _surfaceColor = Color(0xFFF8FAFC);
const Color _borderColor = Color(0xFF94A3B8);
const Color _headerBgColor = Color(0xFFF1F5F9);
const Color _dangerColor = Color(0xFFEF4444);

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

  // --- 비즈니스 집계 로직 (RFID 1:1 방식 적용) ---
  Map<String, dynamic> _calculateMetrics(List<ProductModel> allItems) {
    final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0;
    int todayOut = 0;
    int currentStock = 0;
    int shortageCount = 0;

    const inStatus = {'구매입고', '회수/반납'};
    const outStatus = {'판매출고', '수리출고', '대여출고'};
    const excludeStock = {'판매출고', '수리출고', '대여출고', '폐기', '분실'};

    final Map<String, int> stockByGroup = {};
    final Map<String, int> safetyByGroup = {};

    for (var item in allItems) {
      final lastActionDate = item.updated ?? item.created ?? "";
      final isToday = lastActionDate.startsWith(today);

      if (inStatus.contains(item.status) && isToday) {
        todayIn += 1;
      }
      if (outStatus.contains(item.status) && isToday) {
        todayOut += 1;
      }

      if (!excludeStock.contains(item.status)) {
        currentStock += 1;
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

    return {
      'in': todayIn,
      'out': todayOut,
      'stock': currentStock,
      'short': shortageCount
    };
  }

  void _sortItems(List<ProductModel> items) {
    if (_sortCriteria == 'name') {
      items.sort((a, b) => a.name.compareTo(b.name));
    } else {
      items.sort((a, b) => a.status.compareTo(b.status));
    }
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
        _showForm(context, provider, found, initialTag: found == null ? tag : null);
      });
    }

    final filtered = provider.items.where((p) {
      final q = _currentQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) || p.tagId.toLowerCase().contains(q);
    }).toList();
    _sortItems(filtered);

    final metrics = _calculateMetrics(provider.items);
    final groupedMap = _getGroupedData(filtered);
    final groupKeys = groupedMap.keys.toList()..sort();

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: _fontPretendard),
        primaryTextTheme: Theme.of(context).primaryTextTheme.apply(fontFamily: _fontPretendard),
      ),
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.white,
            body: Column(
              children: [
                _buildDashboard(metrics),
                const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

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
          ),
          if (provider.isParsing || provider.isSaving || provider.isLoading)
            _buildGlobalLoadingOverlay(provider),
        ],
      ),
    );
  }

  Widget _buildGlobalLoadingOverlay(ProductProvider provider) {
    String msg = "잠시만 기다려 주세요...";
    if (provider.isParsing) msg = "엑셀 파일을 분석하여 서버에 저장 중입니다...";
    if (provider.isSaving) msg = "데이터를 서버에 전송 중입니다...";
    if (provider.isLoading) msg = "최신 정보를 불러오는 중입니다...";

    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: _primaryColor),
                const SizedBox(height: 24),
                Text(msg, style: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold, fontSize: 15)),
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
          width: 420,
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
        const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
        Expanded(
          child: Container(
            color: _surfaceColor,
            child: _selectedGroupKey == null
                ? _buildEmptyState("목록에서 그룹을 선택하여 상세 현황을 확인하세요.")
                : _buildDetailView(provider, _selectedGroupKey!, groupedMap[_selectedGroupKey] ?? []),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: groupKeys.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, idx) {
              final key = groupKeys[idx];
              final items = groupedMap[key]!;
              return _buildGroupTile(provider, key, items, false, true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDashboard(Map<String, dynamic> m) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: Colors.white,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.start,
        children: [
          _buildStatCard("당일 입고/회수", m['in'], Colors.blue),
          _buildStatCard("당일 판매/반출", m['out'], Colors.orange),
          _buildStatCard("현재고 합계", m['stock'], _primaryColor, isMain: true),
          _buildStatCard("안전재고 부족", m['short'], _dangerColor, isAlert: m['short'] > 0),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, int val, Color color, {bool isMain = false, bool isAlert = false}) {
    return Container(
      width: 165,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAlert ? color.withValues(alpha: 0.1) : (isMain ? color.withValues(alpha: 0.05) : _surfaceColor),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isAlert ? color : (isMain ? color : const Color(0xFFE2E8F0)), width: (isMain || isAlert) ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontFamily: _fontPretendard, fontSize: 13, fontWeight: FontWeight.w600, color: isAlert ? color : Colors.blueGrey[700])),
          const SizedBox(height: 4),
          Text('${NumberFormat('#,###').format(val)}개', style: TextStyle(fontFamily: _fontPretendard, fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _toggleChip('item', '품목별'),
                  const SizedBox(width: 8),
                  _toggleChip('location', '위치별'),
                  const SizedBox(width: 8),
                  _toggleChip('category', '분류별'),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: "정렬",
            icon: const Icon(Icons.sort, size: 20, color: Colors.blueGrey),
            onSelected: (v) => setState(() => _sortCriteria = v),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'name', child: Text("이름순 정렬", style: TextStyle(fontFamily: _fontPretendard, fontSize: 13))),
              const PopupMenuItem(value: 'status', child: Text("상태순 정렬", style: TextStyle(fontFamily: _fontPretendard, fontSize: 13))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggleChip(String mode, String label) {
    final isSel = _groupByMode == mode;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontFamily: _fontPretendard, fontSize: 12)),
      selected: isSel,
      onSelected: (v) {
        if (v) {
          setState(() { _groupByMode = mode; _selectedGroupKey = null; });
        }
      },
      selectedColor: _primaryColor,
      labelStyle: TextStyle(fontFamily: _fontPretendard, color: isSel ? Colors.white : Colors.black87),
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
    );
  }

  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, bool isMobile) {
    final first = items.first;
    const exclude = {'판매출고', '수리출고', '대여출고', '폐기', '분실'};

    final tagCount = items.where((item) => !exclude.contains(item.status)).length;
    final bool isShort = _groupByMode == 'item' && tagCount < first.safetyStock;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? _primaryColor.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? _primaryColor : const Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        onTap: () {
          if (isMobile) {
            _showMobileGroupDetail(provider, title, items);
          } else {
            setState(() => _selectedGroupKey = title);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _buildThumbnail(first, size: 44),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold, fontSize: 13, color: isShort ? _dangerColor : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(first.spec ?? "-", style: const TextStyle(fontFamily: _fontPretendard, fontSize: 10, color: Colors.grey), maxLines: 1),
                  ],
                ),
              ),
              if (!isMobile) ...[
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(first.category ?? "-", style: const TextStyle(fontFamily: _fontPretendard, fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600), maxLines: 1),
                      Text(first.location ?? "-", style: const TextStyle(fontFamily: _fontPretendard, fontSize: 10, color: Colors.blueGrey), maxLines: 1),
                    ],
                  ),
                ),
              ],
              Container(
                width: 70,
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isShort ? _dangerColor.withValues(alpha: 0.1) : _surfaceColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isShort ? _dangerColor : const Color(0xFFCBD5E1)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('현재고', style: TextStyle(fontFamily: _fontPretendard, fontSize: 9, color: isShort ? _dangerColor : Colors.blueGrey, fontWeight: FontWeight.bold)),
                      Text('$tagCount', style: TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.w900, fontSize: 14, color: isShort ? _dangerColor : _primaryColor)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.redAccent),
                onPressed: () => _confirmBatchDelete(context, provider, items),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailView(ProductProvider provider, String groupName, List<ProductModel> items) {
    final cols = provider.selectedColumns;
    const exclude = {'판매출고', '수리출고', '대여출고', '폐기', '분실'};

    final displayItems = _hideExcluded ? items.where((p) => !exclude.contains(p.status)).toList() : items;
    final currentStock = displayItems.where((p) => !exclude.contains(p.status)).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text('$groupName - 상세 내역', style: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.w900, fontSize: 18), overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 16),
                    FilterChip(
                      label: const Text('출고/폐기 숨기기', style: TextStyle(fontFamily: _fontPretendard, fontSize: 12)),
                      selected: _hideExcluded,
                      onSelected: (v) => setState(() => _hideExcluded = v),
                      selectedColor: _primaryColor.withValues(alpha: 0.1),
                      checkmarkColor: _primaryColor,
                    ),
                  ],
                ),
              ),
              RichText(
                textAlign: TextAlign.right,
                text: TextSpan(
                  style: const TextStyle(fontFamily: _fontPretendard, fontSize: 12, color: Colors.grey),
                  children: [
                    const TextSpan(text: '현재고 태그: '),
                    TextSpan(text: '$currentStock개', style: const TextStyle(color: _primaryColor, fontWeight: FontWeight.w900, fontSize: 14)),
                    TextSpan(text: '  (전체 등록: ${items.length}행)'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(color: _headerBgColor, borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
          child: Row(
            children: [
              const SizedBox(width: 44, child: Text('사진', style: TextStyle(fontFamily: _fontPretendard, fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54))),
              const SizedBox(width: 12),
              for (var c in cols)
                Expanded(flex: 2, child: Text(c, style: const TextStyle(fontFamily: _fontPretendard, fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54), overflow: TextOverflow.ellipsis)),
              const Expanded(flex: 3, child: Text('TAG ID', style: TextStyle(fontFamily: _fontPretendard, fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54))),
              const SizedBox(width: 70, child: Text('상태', style: TextStyle(fontFamily: _fontPretendard, fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54))),
              const SizedBox(width: 40, child: Text('관리', textAlign: TextAlign.center, style: TextStyle(fontFamily: _fontPretendard, fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: displayItems.length,
            itemBuilder: (ctx, idx) {
              final p = displayItems[idx];
              final bool isExcluded = exclude.contains(p.status);

              return Container(
                decoration: BoxDecoration(
                    color: isExcluded ? Colors.grey.shade50 : Colors.white,
                    border: const Border(bottom: BorderSide(color: _headerBgColor))
                ),
                child: Opacity(
                  opacity: isExcluded ? 0.5 : 1.0,
                  child: InkWell(
                    onTap: () => _showForm(context, provider, p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          _buildThumbnail(p, size: 44),
                          const SizedBox(width: 12),
                          for (var c in cols)
                            Expanded(flex: 2, child: Text(p.getValue(c), style: const TextStyle(fontFamily: _fontPretendard, fontSize: 13), overflow: TextOverflow.ellipsis)),
                          Expanded(flex: 3, child: Text(p.tagId, style: TextStyle(fontFamily: _fontPretendard, color: Colors.grey[700], fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5), overflow: TextOverflow.ellipsis)),
                          SizedBox(width: 70, child: _buildStatusBadge(p.status)),
                          SizedBox(
                              width: 40,
                              child: IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                  onPressed: () => _confirmIndividualDelete(context, provider, p)
                              )
                          ),
                        ],
                      ),
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

  Widget _buildStatusBadge(String status) {
    Color c;
    switch (status) {
      case '구매입고': c = Colors.blue; break;
      case '회수/반납': c = Colors.teal; break;
      case '판매출고': c = Colors.orange; break;
      case '수리출고': c = Colors.deepOrange; break;
      case '대여출고': c = Colors.purple; break;
      case '수리필요': c = Colors.amber; break;
      case '폐기': c = Colors.red; break;
      case '분실': c = Colors.grey; break;
      default: c = Colors.green;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(status, style: TextStyle(fontFamily: _fontPretendard, color: c, fontWeight: FontWeight.bold, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
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
          : Icon(Icons.camera_alt_outlined, color: Colors.grey.withValues(alpha: 0.3), size: size * 0.5),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.inventory_2_outlined, size: 64, color: Color(0xFFE2E8F0)),
      const SizedBox(height: 16),
      Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontFamily: _fontPretendard, color: Colors.grey)),
    ]));
  }

  Widget _buildHeader(ProductProvider provider, List<ProductModel> filtered) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('자산 통합 관리', style: TextStyle(fontFamily: _fontPretendard, fontSize: 20, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(onPressed: () => provider.fetchData(), icon: const Icon(Icons.refresh, color: _primaryColor)),
                    IconButton(
                        onPressed: () async {
                          final res = await provider.batchImportFromExcel();
                          if (!mounted) return;
                          if (res['total']! > 0) {
                            if (!context.mounted) return;
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("엑셀 임포트 결과", style: TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold)),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("전체 엑셀 행: ${res['total']}행", style: const TextStyle(fontFamily: _fontPretendard)),
                                    Text("생성된 태그: ${res['success']}개", style: const TextStyle(fontFamily: _fontPretendard, color: Colors.green, fontWeight: FontWeight.bold)),
                                    Text("실패: ${res['failed']}건", style: const TextStyle(fontFamily: _fontPretendard, color: Colors.red)),
                                    if (res['failed']! > 0)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 8.0),
                                        child: Text("※ 데이터 저장 중 오류가 발생한 항목입니다.", style: TextStyle(fontFamily: _fontPretendard, fontSize: 12, color: Colors.grey)),
                                      ),
                                  ],
                                ),
                                actions: [
                                  ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인", style: TextStyle(fontFamily: _fontPretendard)))
                                ],
                              ),
                            );
                          } else {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('임포트가 취소되었거나, 유효한 데이터가 없습니다.', style: TextStyle(fontFamily: _fontPretendard)))
                            );
                          }
                        },
                        icon: const FaIcon(FontAwesomeIcons.fileArrowUp, size: 16, color: Colors.indigo)
                    ),
                    IconButton(onPressed: () => _exportToExcel(context, filtered), icon: const FaIcon(FontAwesomeIcons.fileArrowDown, size: 16, color: Colors.green)),
                    IconButton(onPressed: () => _showColumnSelectionDialog(provider), icon: const Icon(Icons.settings_suggest_outlined, color: Colors.indigo)),
                    IconButton(onPressed: () => _showResetDialog(provider), icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent)),
                    IconButton(onPressed: () => _showForm(context, provider, null), icon: const Icon(Icons.add_circle, color: _primaryColor, size: 28)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _currentQuery = v),
            style: const TextStyle(fontFamily: _fontPretendard),
            decoration: InputDecoration(
              hintText: '자산명 또는 태그 ID 검색...',
              hintStyle: const TextStyle(fontFamily: _fontPretendard, color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: _surfaceColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _borderColor)),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _extractAvailableMetaKeys(List<ProductModel> items) {
    final Set<String> keySet = {'품명', '규격', '제조사', '위치', 'S/N', '분류', '단위', '비고'};
    for (var item in items) {
      item.metadata.forEach((k, v) {
        if (k != 'origin_key_map' && k != 'history') {
          keySet.add(k);
        }
      });
    }
    return keySet.toList()..sort();
  }

  void _showColumnSelectionDialog(ProductProvider provider) {
    final List<String> availableKeys = _extractAvailableMetaKeys(provider.items);
    final List<String> temp = List.from(provider.selectedColumns);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setDlgState) => AlertDialog(
        title: const Text("표시 항목 설정", style: TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("상세 리스트에 표시할 항목을 최대 5개 선택하세요.", style: TextStyle(fontFamily: _fontPretendard, fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: availableKeys.map((key) => CheckboxListTile(
                      title: Text(key, style: const TextStyle(fontFamily: _fontPretendard, fontSize: 14)),
                      value: temp.contains(key),
                      activeColor: _primaryColor,
                      dense: true,
                      onChanged: (v) => setDlgState(() {
                        if (v == true) {
                          if (temp.length < 5) temp.add(key);
                        } else {
                          temp.remove(key);
                        }
                      }),
                    )).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소", style: TextStyle(fontFamily: _fontPretendard))),
          ElevatedButton(onPressed: () { provider.saveRemoteSettings(temp); Navigator.pop(ctx); }, child: const Text("적용", style: TextStyle(fontFamily: _fontPretendard))),
        ],
      )),
    );
  }

  Future<void> _showForm(BuildContext context, ProductProvider provider, ProductModel? p, {String? initialTag}) async {
    final nameC = TextEditingController(text: p?.name ?? "");
    final tagC = TextEditingController(text: initialTag ?? p?.tagId ?? "");
    final locC = TextEditingController(text: p?.location ?? "");
    final specC = TextEditingController(text: p?.spec ?? "");
    final catC = TextEditingController(text: p?.category ?? "");
    final remC = TextEditingController(text: p?.remarks ?? "");
    final snC = TextEditingController(text: p?.serialNumber ?? "");
    final mfgC = TextEditingController(text: p?.manufacturer ?? "");
    final unitC = TextEditingController(text: p?.unit ?? "ea");
    final safeC = TextEditingController(text: p?.safetyStock.toString() ?? "5");

    final qtyGenerateC = TextEditingController(text: "1");

    String selectedStatus = p?.status ?? "구매입고";
    XFile? file;
    Uint8List? preview;

    final Map<String, TextEditingController> dynamicControllers = {};
    if (p != null) {
      p.metadata.forEach((key, value) {
        if (!['origin_key_map', 'history'].contains(key)) {
          dynamicControllers[key] = TextEditingController(text: value.toString());
        }
      });
    }

    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (dialogCtx, setS) {
        final nav = Navigator.of(dialogCtx);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(p == null ? '자산 신규 등록 (태그 발행)' : '정보 및 프로세스 변경', style: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 750,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(child: _buildFormImagePicker(p, preview, (f, b) => setS(() { file = f; preview = b; }))),
                  const SizedBox(height: 32),

                  const Row(
                    children: [
                      Icon(Icons.layers, color: _primaryColor, size: 20),
                      SizedBox(width: 8),
                      Text("기본 항목", style: TextStyle(fontFamily: _fontPretendard, fontSize: 16, fontWeight: FontWeight.w900, color: _primaryColor)),
                    ],
                  ),
                  const Divider(thickness: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 12),

                  if (p == null) ...[
                    Row(children: [
                      Expanded(child: _ProductField(label: '발행할 태그 수량 (예: 10개 한 번에 등록)', controller: qtyGenerateC, maxLines: 1, keyboardType: TextInputType.number)),
                      const SizedBox(width: 16),
                      const Expanded(child: SizedBox()),
                    ]),
                  ],

                  Row(children: [
                    Expanded(child: _ProductField(label: '품명 (필수)', controller: nameC, maxLines: 1)),
                    const SizedBox(width: 16),
                    Expanded(child: _ProductField(label: p == null ? '기본 태그 ID (지정하지 않으면 자동생성)' : 'RFID TAG ID', controller: tagC, maxLines: 1)),
                  ]),
                  Row(children: [
                    Expanded(child: _ProductField(label: '제조사', controller: mfgC, maxLines: 1)),
                    const SizedBox(width: 16),
                    Expanded(child: _ProductField(label: '시리얼 번호(S/N)', controller: snC, maxLines: 1))
                  ]),
                  Row(children: [
                    Expanded(child: _ProductField(label: '분류', controller: catC, maxLines: 1)),
                    const SizedBox(width: 16),
                    Expanded(child: _ProductField(label: '보관 위치', controller: locC, maxLines: 1))
                  ]),
                  Row(children: [
                    Expanded(child: _ProductField(label: '규격 / 모델명', controller: specC, maxLines: 1)),
                    const SizedBox(width: 16),
                    Expanded(child: _ProductField(label: '단위', controller: unitC, maxLines: 1)),
                  ]),
                  Row(children: [
                    Expanded(child: _ProductField(label: '안전재고수량 (그룹 기준)', controller: safeC, maxLines: 1, keyboardType: TextInputType.number)),
                    const SizedBox(width: 16),
                    Expanded(child: _ProductSelectField(
                      label: '비즈니스 상태 (프로세스)',
                      initialValue: selectedStatus,
                      items: const ['정상', '구매입고', '회수/반납', '판매출고', '수리출고', '대여출고', '수리필요', '폐기', '분실'],
                      onChanged: (v) { if (v != null) selectedStatus = v; },
                    )),
                  ]),
                  Row(children: [
                    Expanded(child: _ProductField(label: '비고 / 사유', controller: remC, maxLines: 1)),
                    const SizedBox(width: 16),
                    const Expanded(child: SizedBox()),
                  ]),

                  if (dynamicControllers.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Icon(Icons.table_view, color: Colors.green, size: 20),
                        SizedBox(width: 8),
                        Text("엑셀 항목", style: TextStyle(fontFamily: _fontPretendard, fontSize: 16, fontWeight: FontWeight.w900, color: Colors.green)),
                      ],
                    ),
                    const Divider(thickness: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 12),

                    for (int i = 0; i < dynamicControllers.length; i += 2)
                      Row(children: [
                        Expanded(child: _ProductField(label: dynamicControllers.keys.elementAt(i), controller: dynamicControllers.values.elementAt(i), maxLines: 1)),
                        const SizedBox(width: 16),
                        Expanded(child: (i + 1 < dynamicControllers.length)
                            ? _ProductField(label: dynamicControllers.keys.elementAt(i + 1), controller: dynamicControllers.values.elementAt(i + 1), maxLines: 1)
                            : const SizedBox()),
                      ]),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: isProcessing ? null : () => nav.pop(),
                child: const Text("취소", style: TextStyle(fontFamily: _fontPretendard))
            ),
            ElevatedButton(
              onPressed: isProcessing ? null : () async {
                if (nameC.text.isEmpty) return;
                setS(() => isProcessing = true);

                final updatedMeta = Map<String, dynamic>.from(p?.metadata ?? {});

                dynamicControllers.forEach((k, v) => updatedMeta[k] = v.text.trim());

                if (p != null && p.status != selectedStatus) {
                  List<dynamic> history = updatedMeta['history'] is List ? List.from(updatedMeta['history']) : [];
                  history.add({'at': DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()), 'from': p.status, 'to': selectedStatus, 'note': remC.text.trim()});
                  if (history.length > 10) history = history.sublist(history.length - 10);
                  updatedMeta['history'] = history;
                }

                final data = {
                  'name': nameC.text.trim(),
                  'location': locC.text.trim(),
                  'spec': specC.text.trim(),
                  'category': catC.text.trim(),
                  'remarks': remC.text.trim(),
                  'quantity': 1,
                  'safety_stock': int.tryParse(safeC.text) ?? 5,
                  'unit': unitC.text.trim(),
                  'serial_number': snC.text.trim(),
                  'manufacturer': mfgC.text.trim(),
                  'status': selectedStatus,
                  'metadata': updatedMeta,
                };

                bool success = true;
                try {
                  if (p == null) {
                    int genCount = int.tryParse(qtyGenerateC.text) ?? 1;
                    for (int i = 0; i < genCount; i++) {
                      final itemData = Map<String, dynamic>.from(data);
                      if (genCount == 1 && tagC.text.isNotEmpty) {
                        itemData['tag_id'] = tagC.text.trim();
                      } else {
                        itemData['tag_id'] = "TEMP-${DateTime.now().millisecondsSinceEpoch}-$i";
                      }
                      final res = await provider.handleSave(p: null, data: itemData, imageXFile: file);
                      if (!res) success = false;
                    }
                  } else {
                    data['tag_id'] = tagC.text.trim();
                    success = await provider.handleSave(p: p, data: data, imageXFile: file);

                    if (success && file != null) {
                      final sameItems = provider.items.where((item) => item.name == p.name && item.id != p.id).toList();
                      for (var target in sameItems) {
                        await provider.handleSave(p: target, data: {}, imageXFile: file);
                      }
                    }
                  }
                } catch (e) {
                  success = false;
                }

                if (dialogCtx.mounted) {
                  setS(() => isProcessing = false);
                  if (success) {
                    nav.pop();
                  } else {
                    if (!dialogCtx.mounted) return;
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(const SnackBar(content: Text('❌ 저장에 실패했습니다. 서버 연결을 확인하세요.', style: TextStyle(fontFamily: _fontPretendard))));
                  }
                }
              },
              child: Text(isProcessing ? "처리 중..." : "저장", style: const TextStyle(fontFamily: _fontPretendard)),
            )
          ],
        );
      }),
    );
  }

  /// [수정됨] 카메라 촬영 및 갤러리 선택 기능 통합 이미지 피커
  Widget _buildFormImagePicker(ProductModel? p, Uint8List? preview, Function(XFile, Uint8List) onPicked) {
    final picker = ImagePicker();

    // 이미지 획득 내부 함수
    Future<void> pickImage(ImageSource source) async {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      try {
        // [안정성 확보] 플랫폼 가드: 웹 환경이거나 델리게이트가 없는 환경 방어
        if (source == ImageSource.camera && kIsWeb) {
          throw Exception("현재 웹 브라우저 환경에서는 카메라를 직접 호출할 수 없습니다.");
        }

        final img = await picker.pickImage(
          source: source,
          imageQuality: 70, // 용량 최적화
          maxWidth: 1024,   // 해상도 제한
        );

        if (!mounted) return;
        if (img != null) {
          final bytes = await img.readAsBytes();
          onPicked(img, bytes);
        }
      } catch (e) {
        if (!mounted) return;
        String errMsg = e.toString();
        // 델리게이트 오류를 한국어로 순화하여 안내
        if (errMsg.contains('cameraDelegate')) {
          errMsg = "카메라를 실행할 수 없습니다. 기기에 카메라가 없거나 권한 설정이 필요합니다.";
        } else if (errMsg.contains('Exception:')) {
          errMsg = errMsg.replaceFirst("Exception: ", "");
        }

        scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('⚠️ 오류: $errMsg', style: const TextStyle(fontFamily: _fontPretendard)),
              backgroundColor: _dangerColor,
            )
        );
      }
    }

    return GestureDetector(
      onTap: () {
        // 하단 선택 시트 노출
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (ctx) {
            return SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.camera_alt, color: _primaryColor),
                    title: const Text('카메라로 촬영', style: TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(ctx);
                      pickImage(ImageSource.camera);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library, color: Colors.green),
                    title: const Text('갤러리에서 선택', style: TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(ctx);
                      pickImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
      child: Stack(
        children: [
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5)
            ),
            clipBehavior: Clip.antiAlias,
            child: preview != null
                ? Image.memory(preview, fit: BoxFit.cover)
                : _buildThumbnail(p ?? ProductModel(name: '', tagId: ''), size: 120),
          ),
          // 우측 하단 카메라 배지 (사용자 유도 UI)
          Positioned(
            bottom: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmIndividualDelete(BuildContext context, ProductProvider provider, ProductModel p) {
    final nav = Navigator.of(context);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('삭제 확인', style: TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold)),
      content: Text('[${p.tagId}] ${p.name} 자산을 삭제하시겠습니까?', style: const TextStyle(fontFamily: _fontPretendard)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(fontFamily: _fontPretendard))),
        ElevatedButton(
          onPressed: () async {
            final success = await provider.deleteProduct(p.id);
            if (success && ctx.mounted) {
              nav.pop();
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('삭제', style: TextStyle(fontFamily: _fontPretendard)),
        ),
      ],
    ));
  }

  void _confirmBatchDelete(BuildContext context, ProductProvider provider, List<ProductModel> items) {
    final nav = Navigator.of(context);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('그룹 일괄 삭제', style: TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold)),
      content: Text('해당 그룹의 모든 자산(${items.length}개)을 삭제하시겠습니까?', style: const TextStyle(fontFamily: _fontPretendard)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(fontFamily: _fontPretendard))),
        ElevatedButton(
          onPressed: () async {
            for (final i in items) {
              await provider.deleteProduct(i.id);
            }
            if (ctx.mounted) {
              setState(() => _selectedGroupKey = null);
              nav.pop();
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('전체 삭제', style: TextStyle(fontFamily: _fontPretendard)),
        ),
      ],
    ));
  }

  void _showResetDialog(ProductProvider provider) {
    final nav = Navigator.of(context);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('DB 전체 초기화', style: TextStyle(fontFamily: _fontPretendard, color: Colors.red, fontWeight: FontWeight.bold)),
      content: const Text('서버에 등록된 모든 물품 데이터를 삭제합니다. 계속하시겠습니까?', style: TextStyle(fontFamily: _fontPretendard)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(fontFamily: _fontPretendard))),
        ElevatedButton(
          onPressed: () async {
            await provider.resetAllProducts();
            if (ctx.mounted) {
              nav.pop();
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('전체 삭제', style: TextStyle(fontFamily: _fontPretendard)),
        ),
      ],
    ));
  }

  Future<void> _exportToExcel(BuildContext context, List<ProductModel> list) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['물품리스트'];
      excel.rename('Sheet1', '물품리스트');
      sheet.appendRow([excel_pkg.TextCellValue('품명'), excel_pkg.TextCellValue('제조사'), excel_pkg.TextCellValue('규격'), excel_pkg.TextCellValue('S/N'), excel_pkg.TextCellValue('태그ID'), excel_pkg.TextCellValue('상태'), excel_pkg.TextCellValue('위치'), excel_pkg.TextCellValue('비고')]);
      for (final i in list) {
        sheet.appendRow([excel_pkg.TextCellValue(i.name), excel_pkg.TextCellValue(i.manufacturer ?? ""), excel_pkg.TextCellValue(i.spec ?? ""), excel_pkg.TextCellValue(i.serialNumber ?? ""), excel_pkg.TextCellValue(i.tagId), excel_pkg.TextCellValue(i.status), excel_pkg.TextCellValue(i.location ?? ""), excel_pkg.TextCellValue(i.remarks ?? "")]);
      }
      final path = await FilePicker.platform.saveFile(fileName: 'Asset_Inventory_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx']);
      if (path != null) {
        await File(path).writeAsBytes(excel.encode()!);
        messenger.showSnackBar(const SnackBar(content: Text('✅ 엑셀 파일이 성공적으로 저장되었습니다.', style: TextStyle(fontFamily: _fontPretendard))));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ 저장 실패: $e', style: const TextStyle(fontFamily: _fontPretendard))));
    }
  }

  void _showMobileGroupDetail(ProductProvider provider, String groupName, List<ProductModel> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: _buildDetailView(provider, groupName, items),
      ),
    );
  }
}

class _ProductField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType keyboardType;
  const _ProductField({required this.label, required this.controller, required this.maxLines, this.keyboardType = TextInputType.text});
  @override
  State<_ProductField> createState() => _ProductFieldState();
}

class _ProductFieldState extends State<_ProductField> {
  late FocusNode _focusNode;
  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }
  @override
  void dispose() { _focusNode.dispose(); super.dispose(); }
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
          labelStyle: const TextStyle(fontFamily: _fontPretendard, color: _primaryColor, fontSize: 13),
          isDense: true,
          filled: true,
          fillColor: _focusNode.hasFocus ? Colors.white : Colors.grey[100],
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _borderColor, width: 1.2)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primaryColor, width: 2.0)),
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
  const _ProductSelectField({required this.label, required this.initialValue, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: initialValue,
        items: [
          for (final e in items)
            DropdownMenuItem(
              value: e,
              child: Text(e, style: const TextStyle(fontFamily: _fontPretendard, fontSize: 14, fontWeight: FontWeight.bold)),
            )
        ],
        onChanged: onChanged,
        style: const TextStyle(fontFamily: _fontPretendard, color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: const TextStyle(fontFamily: _fontPretendard, color: _primaryColor, fontSize: 13),
          isDense: true,
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _borderColor, width: 1.2)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _borderColor)),
        ),
      ),
    );
  }
}