import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
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

  bool _isExcelImporting = false;
  bool _isBatchProcessing = false;

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

  // --- 비즈니스 집계 및 처리 로직 ---

  Map<String, dynamic> _calculateMetrics(List<ProductModel> allItems) {
    final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0;
    int todayOut = 0;
    int currentStock = 0;
    int shortageCount = 0;

    const inStatus = {'구매입고', '회수/반납', '수기입고'};
    const outStatus = {'판매출고', '수리출고', '대여출고', '수기출고'};
    const excludeStock = {'판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'};

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

    return {'in': todayIn, 'out': todayOut, 'stock': currentStock, 'short': shortageCount};
  }

  Future<void> _processAssetAccessWithLocation(ProductProvider provider, ProductModel p, String type) async {
    final messenger = ScaffoldMessenger.of(context);
    final Map<String, String>? location = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _LocationSelectionDialog(
        type: type,
        existingItems: provider.items,
      ),
    );

    if (!mounted || location == null) {
      return;
    }

    final String now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final String building = location['building']?.trim() ?? "미지정";
    final String gate = location['gate']?.trim() ?? "미지정";

    final updatedMeta = Map<String, dynamic>.from(p.metadata);
    List<dynamic> history = updatedMeta['history'] is List ? List.from(updatedMeta['history']) : [];

    history.add({
      'at': now,
      'from': p.status,
      'to': type,
      'note': '수기처리: $building($gate)',
      'location': building,
      'gate': gate,
    });

    if (history.length > 20) {
      history = history.sublist(history.length - 20);
    }

    updatedMeta['history'] = history;
    updatedMeta['last_location_info'] = {
      'building': building,
      'gate': gate,
      'full_name': "$building - $gate"
    };

    final data = {
      'status': type,
      'metadata': updatedMeta,
      'location': building,
    };

    final success = await provider.handleSave(p: p, data: data);

    if (!mounted) {
      return;
    }
    if (success) {
      messenger.showSnackBar(SnackBar(
        content: Text('[${p.name}] $building $gate $type 완료'),
        backgroundColor: type.contains('입고') ? AppTheme.success : AppTheme.warning,
        duration: const Duration(seconds: 1),
      ));
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

  Future<void> _showResetConfirmationDialog(ProductProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("데이터 및 설정 전체 초기화", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        content: const Text("서버의 모든 자산 정보와 가변 필드 설정이 영구 삭제됩니다.\n새로운 엑셀 로드를 위해 모든 상태를 초기화하시겠습니까?"),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(ctx, false); },
            child: const Text("취소"),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx, true); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("전체 초기화"),
          ),
        ],
      ),
    );

    if (!mounted || confirm != true) {
      return;
    }

    setState(() {
      _isBatchProcessing = true;
      _selectedGroupKey = null;
    });

    try {
      await provider.resetAllProducts();
      await provider.saveRemoteSettings([]);
      await provider.fetchData();

      if (mounted) {
        setState(() {
          _currentQuery = "";
          _searchController.clear();
        });
      }
    } catch (e) {
      debugPrint("초기화 중 오류 발생: $e");
    } finally {
      if (mounted) {
        setState(() { _isBatchProcessing = false; });
      }
    }

    if (!mounted) {
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('데이터와 필드 설정이 모두 초기화되었습니다.')));
  }

  // --- 에러 로그 생성 로직 (요청에 따라 실패 원인 기록 제거) ---

  Future<void> _generateErrorExcel(ProductProvider provider) async {
    final errors = provider.lastErrors;
    final originalHeaders = provider.errorHeaders;

    if (errors == null || errors.isEmpty || originalHeaders.isEmpty) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['ErrorLog'];
      excel.rename('Sheet1', 'ErrorLog');

      // 1. 헤더 생성: 업로드했던 엑셀의 모든 컬럼 그대로 복원 (실패원인 제외)
      sheet.appendRow(originalHeaders.map((h) => excel_pkg.TextCellValue(h)).toList());

      // 2. 데이터 생성: 각 실패 행의 원본 데이터 리스트 전체를 그대로 복원
      for (var e in errors) {
        final List<String> rowData = List<String>.from(e['originalRow']);

        // 데이터의 길이가 헤더와 맞지 않을 경우를 대비해 패딩 처리
        while (rowData.length < originalHeaders.length) {
          rowData.add("");
        }

        sheet.appendRow(rowData.map((v) => excel_pkg.TextCellValue(v)).toList());
      }

      final String fileName = 'LoadError_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
      final path = await FilePicker.platform.saveFile(
          dialogTitle: '실패한 원본 항목 저장',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx']
      );

      if (!mounted || path == null) {
        return;
      }

      final bytes = excel.encode();
      if (bytes != null) {
        await File(path).writeAsBytes(bytes);
        if (mounted) {
          messenger.showSnackBar(const SnackBar(content: Text('✅ 실패한 원본 데이터 로그가 저장되었습니다.')));
        }
      }
    } catch (e) {
      debugPrint("에러 엑셀 생성 오류: $e");
    }
  }

  // --- 메인 빌드 및 레이아웃 ---

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

    if (_sortCriteria == 'name') {
      filtered.sort((a, b) => a.name.compareTo(b.name));
    } else {
      filtered.sort((a, b) => a.status.compareTo(b.status));
    }

    final metrics = _calculateMetrics(provider.items);
    final groupedMap = _getGroupedData(filtered);
    final groupKeys = groupedMap.keys.toList()..sort();

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: AppTheme.fontPretendard),
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
          if (provider.isSaving || provider.isLoading || _isExcelImporting || _isBatchProcessing)
            _buildGlobalLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildDashboard(Map<String, dynamic> m) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: Colors.white,
      child: Wrap(
        spacing: 12, runSpacing: 12,
        children: [
          _buildStatCard("당일 입고", m['in'], Colors.blue),
          _buildStatCard("당일 출고", m['out'], Colors.orange),
          _buildStatCard("현재고 합계", m['stock'], AppTheme.primary, isMain: true),
          _buildStatCard("안전재고 부족", m['short'], AppTheme.danger, isAlert: m['short'] > 0),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, int val, Color color, {bool isMain = false, bool isAlert = false}) {
    return Container(
      width: 165,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAlert ? color.withValues(alpha: 0.1) : (isMain ? color.withValues(alpha: 0.05) : AppTheme.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isAlert ? color : (isMain ? color : const Color(0xFFE2E8F0)), width: (isMain || isAlert) ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isAlert ? color : Colors.blueGrey[700])),
          const SizedBox(height: 4),
          Text('${NumberFormat('#,###').format(val)}개', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        ],
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
            color: AppTheme.surface,
            child: _selectedGroupKey == null
                ? const Center(child: Text("상세 현황을 확인하려면 그룹을 선택하세요."))
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
              return _buildGroupTile(provider, key, groupedMap[key]!, false, true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ProductProvider provider, List<ProductModel> filtered) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Text('자산 통합 관리', style: AppTheme.headerStyle),
              const Spacer(),
              IconButton(
                onPressed: () { _showResetConfirmationDialog(provider); },
                tooltip: "전체 초기화",
                icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
              ),
              IconButton(
                onPressed: () { provider.fetchData(); },
                tooltip: "새로고침",
                icon: const Icon(Icons.refresh, color: AppTheme.primary),
              ),
              IconButton(
                  onPressed: () { _importFromExcel(context, provider); },
                  tooltip: "엑셀 업로드",
                  icon: const FaIcon(FontAwesomeIcons.fileArrowUp, color: Colors.blueAccent, size: 20)
              ),
              IconButton(
                  onPressed: () { _exportToExcel(context, filtered); },
                  tooltip: "엑셀 다운로드",
                  icon: const FaIcon(FontAwesomeIcons.fileArrowDown, color: Colors.green, size: 20)
              ),
              IconButton(
                  onPressed: () { _showColumnSelectionDialog(provider); },
                  tooltip: "컬럼 설정",
                  icon: const Icon(Icons.settings_suggest_outlined, color: Colors.indigo)
              ),
              IconButton(
                  onPressed: () { _showForm(context, provider, null); },
                  tooltip: "자산 추가",
                  icon: const Icon(Icons.add_circle, color: AppTheme.primary, size: 28)
              ),
            ],
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, _) {
                return TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _currentQuery = v),
                  decoration: InputDecoration(
                    hintText: '자산명 또는 태그 ID 검색...',
                    hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.3)),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: value.text.isNotEmpty
                        ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.clear, size: 20, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _currentQuery = "");
                        },
                      ),
                    )
                        : null,
                    filled: true,
                    fillColor: AppTheme.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                );
              }
          ),
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
          IconButton(
            icon: const Icon(Icons.sort, size: 20, color: Colors.blueGrey),
            onPressed: () {
              setState(() => _sortCriteria = _sortCriteria == 'name' ? 'status' : 'name');
            },
          ),
        ],
      ),
    );
  }

  Widget _toggleChip(String mode, String label) {
    final isSel = _groupByMode == mode;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSel,
      onSelected: (bool selected) {
        if (selected) {
          setState(() { _groupByMode = mode; _selectedGroupKey = null; });
        }
      },
      selectedColor: AppTheme.primary,
      backgroundColor: const Color(0xFFF1F5F9),
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
    );
  }

  Widget _buildGroupTile(ProductProvider provider, String title, List<ProductModel> items, bool isSelected, bool isMobile) {
    final first = items.first;
    const exclude = {'판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'};
    final tagCount = items.where((item) => !exclude.contains(item.status)).length;
    final bool isShort = _groupByMode == 'item' && tagCount < first.safetyStock;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primary.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0)),
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
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isShort ? AppTheme.danger : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(first.spec ?? "-", style: const TextStyle(fontSize: 10, color: Colors.grey), maxLines: 1),
                  ],
                ),
              ),
              Container(
                width: 70,
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isShort ? AppTheme.danger.withValues(alpha: 0.1) : AppTheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isShort ? AppTheme.danger : const Color(0xFFCBD5E1)),
                  ),
                  child: Text('$tagCount', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: isShort ? AppTheme.danger : AppTheme.primary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailView(ProductProvider provider, String groupName, List<ProductModel> items) {
    const exclude = {'판매출고', '수리출고', '대여출고', '폐기', '분실', '수기출고'};
    final cols = provider.selectedColumns;
    final displayItems = _hideExcluded ? items.where((p) => !exclude.contains(p.status)).toList() : items;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(groupName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const Spacer(),
              FilterChip(
                label: const Text('출고/폐종 숨기기', style: TextStyle(fontSize: 12)),
                selected: _hideExcluded,
                onSelected: (v) {
                  setState(() => _hideExcluded = v);
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(color: AppTheme.headerBg, borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
          child: Row(
            children: [
              const SizedBox(width: 44, child: Text('사진', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
              const SizedBox(width: 12),
              for (var c in cols)
                Expanded(flex: 2, child: Text(c, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
              const Expanded(flex: 3, child: Text('TAG ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
              const SizedBox(width: 100, child: Text('관리', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: displayItems.length,
            itemBuilder: (ctx, idx) {
              final p = displayItems[idx];
              final bool isOut = exclude.contains(p.status);
              return Container(
                decoration: BoxDecoration(
                    color: isOut ? Colors.grey.shade50 : Colors.white,
                    border: const Border(bottom: BorderSide(color: AppTheme.headerBg))
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: _buildThumbnail(p, size: 44),
                  title: Row(
                    children: [
                      for (var c in cols)
                        Expanded(flex: 2, child: Text(p.getValue(c), style: const TextStyle(fontSize: 13))),
                      Expanded(flex: 3, child: Text(p.tagId, style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w600))),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.login, color: AppTheme.success, size: 20), onPressed: () { _processAssetAccessWithLocation(provider, p, '수기입고'); }),
                      const SizedBox(width: 12),
                      IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.logout, color: AppTheme.warning, size: 20), onPressed: () { _processAssetAccessWithLocation(provider, p, '수기출고'); }),
                      const SizedBox(width: 12),
                      IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20), onPressed: () { _confirmIndividualDelete(context, provider, p); }),
                    ],
                  ),
                  onTap: () {
                    _showForm(context, provider, p);
                  },
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))
          : Icon(Icons.camera_alt_outlined, color: Colors.grey.withValues(alpha: 0.3)),
    );
  }

  Future<void> _showForm(BuildContext context, ProductProvider provider, ProductModel? p, {String? initialTag}) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final nameC = TextEditingController(text: p?.name ?? "");
    final tagC = TextEditingController(text: initialTag ?? p?.tagId ?? "");
    final mfgC = TextEditingController(text: p?.manufacturer ?? "");
    final snC = TextEditingController(text: p?.serialNumber ?? "");
    final specC = TextEditingController(text: p?.spec ?? "");
    final unitC = TextEditingController(text: p?.unit ?? "ea");
    final catC = TextEditingController(text: p?.category ?? "");
    final locC = TextEditingController(text: p?.location ?? "");
    final safeC = TextEditingController(text: p?.safetyStock.toString() ?? "5");
    final qtyC = TextEditingController(text: p?.quantity.toString() ?? "1");
    final remC = TextEditingController(text: p?.remarks ?? "");

    String selectedStatus = p?.status ?? "구매입고";
    XFile? file;
    Uint8List? preview;

    final Map<String, TextEditingController> metaControllers = {};
    const sysKeys = {'origin_key_map', 'history', 'last_location_info'};
    final Map<String, dynamic> originMap = p?.metadata['origin_key_map'] ?? {};

    if (p != null) {
      p.metadata.forEach((key, value) {
        if (!sysKeys.contains(key)) {
          metaControllers[key] = TextEditingController(text: value?.toString() ?? "");
        }
      });
    }

    void setupSync(TextEditingController master, String metaKey) {
      if (metaControllers.containsKey(metaKey)) {
        final slave = metaControllers[metaKey]!;
        bool isLock = false;

        master.addListener(() {
          if (isLock) { return; }
          isLock = true;
          if (slave.text != master.text) {
            slave.text = master.text;
          }
          isLock = false;
        });

        slave.addListener(() {
          if (isLock) { return; }
          isLock = true;
          if (master.text != slave.text) {
            master.text = slave.text;
          }
          isLock = false;
        });
      }
    }

    originMap.forEach((excelHeader, dbField) {
      if (dbField == 'name') { setupSync(nameC, excelHeader); }
      else if (dbField == 'tag_id') { setupSync(tagC, excelHeader); }
      else if (dbField == 'manufacturer') { setupSync(mfgC, excelHeader); }
      else if (dbField == 'serial_number') { setupSync(snC, excelHeader); }
      else if (dbField == 'category') { setupSync(catC, excelHeader); }
      else if (dbField == 'location') { setupSync(locC, excelHeader); }
      else if (dbField == 'spec') { setupSync(specC, excelHeader); }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (dialogCtx, setS) {

        Future<void> handlePhotoSelection() async {
          final source = await showModalBottomSheet<String>(
            context: dialogCtx,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (ctx) => SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.camera_alt, color: AppTheme.primary),
                    title: const Text('카메라로 촬영', style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () { Navigator.pop(ctx, 'camera'); },
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library, color: Colors.green),
                    title: const Text('갤러리/파일에서 선택', style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () { Navigator.pop(ctx, 'gallery'); },
                  ),
                ],
              ),
            ),
          );

          if (!dialogCtx.mounted || source == null) {
            return;
          }

          if (source == 'camera') {
            if (Platform.isWindows) {
              try {
                final cameras = await availableCameras();
                if (cameras.isEmpty) {
                  throw Exception("인식된 카메라 장치가 없습니다.");
                }
                if (!dialogCtx.mounted) {
                  return;
                }
                final XFile? result = await showDialog<XFile>(
                  context: dialogCtx,
                  builder: (ctx) => _CameraCaptureDialog(cameras: cameras),
                );
                if (!dialogCtx.mounted || result == null) {
                  return;
                }
                final bytes = await result.readAsBytes();
                setS(() { file = result; preview = bytes; });
              } catch (e) { messenger.showSnackBar(SnackBar(content: Text('카메라 오류: $e'))); }
            } else {
              final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
              if (!dialogCtx.mounted || img == null) {
                return;
              }
              final bytes = await img.readAsBytes();
              setS(() { file = img; preview = bytes; });
            }
          } else {
            final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
            if (!dialogCtx.mounted || img == null) {
              return;
            }
            final bytes = await img.readAsBytes();
            setS(() { file = img; preview = bytes; });
          }
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(p == null ? '자산 신규 등록' : '자산 정보 상세 편집', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 850,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: handlePhotoSelection,
                      child: Stack(
                        children: [
                          Container(
                            width: 120, height: 120,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppTheme.border, width: 1.5)
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: preview != null
                                  ? Image.memory(preview!, fit: BoxFit.contain)
                                  : (p != null ? _buildThumbnail(p, size: 120) : const Icon(Icons.camera_alt, size: 40, color: Colors.grey)),
                            ),
                          ),
                          Positioned(bottom: 6, right: 6, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 14))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(children: [
                    const Icon(Icons.inventory_2_outlined, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text("마스터 필드 정보", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.primary)),
                  ]),
                  const Divider(thickness: 1),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _ProductField(label: '품명', controller: nameC, hint: "자산 명칭")),
                    const SizedBox(width: 12),
                    Expanded(child: _ProductField(label: 'RFID TAG ID', controller: tagC, hint: "태그 ID")),
                  ]),
                  Row(children: [
                    Expanded(child: _ProductField(label: '제조사', controller: mfgC)),
                    const SizedBox(width: 12),
                    Expanded(child: _ProductField(label: '시리얼 번호(S/N)', controller: snC)),
                  ]),
                  Row(children: [
                    Expanded(child: _ProductField(label: '분류', controller: catC)),
                    const SizedBox(width: 12),
                    Expanded(child: _ProductField(label: '보관 위치', controller: locC)),
                  ]),
                  Row(children: [
                    Expanded(child: _ProductField(label: '규격/모델명', controller: specC)),
                    const SizedBox(width: 12),
                    Expanded(child: _ProductField(label: '단위', controller: unitC)),
                  ]),
                  Row(children: [
                    Expanded(child: _ProductField(label: '현재 수량', controller: qtyC, keyboardType: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(child: _ProductField(label: '안전재고', controller: safeC, keyboardType: TextInputType.number)),
                  ]),
                  _ProductSelectField(
                      label: '상태',
                      value: selectedStatus,
                      items: const ['구매입고', '회수/반납', '수기입고', '정상', '수리필요', '분실', '폐기'],
                      onChanged: (v) { if (v != null) { selectedStatus = v; } }
                  ),
                  _ProductField(label: '비고', controller: remC),

                  if (metaControllers.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Row(children: [
                      const Icon(Icons.table_view_outlined, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Text("추가 메타데이터 정보 (엑셀 항목)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.green)),
                      const SizedBox(width: 8),
                      const Text("(마스터 필드와 실시간 연동)", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                    const Divider(thickness: 1, color: Colors.green),
                    const SizedBox(height: 12),
                    for (int i = 0; i < metaControllers.length; i += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 0),
                        child: Row(children: [
                          Expanded(child: _ProductField(
                            label: metaControllers.keys.elementAt(i),
                            controller: metaControllers.values.elementAt(i),
                            isMeta: true,
                          )),
                          const SizedBox(width: 12),
                          if (i + 1 < metaControllers.length)
                            Expanded(child: _ProductField(
                              label: metaControllers.keys.elementAt(i + 1),
                              controller: metaControllers.values.elementAt(i + 1),
                              isMeta: true,
                            ))
                          else
                            const Expanded(child: SizedBox()),
                        ]),
                      ),
                  ]
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text("취소")),
            ElevatedButton(
              onPressed: () async {
                if (nameC.text.isEmpty) {
                  return;
                }

                final updatedMeta = Map<String, dynamic>.from(p?.metadata ?? {});
                metaControllers.forEach((k, v) => updatedMeta[k] = v.text.trim());

                int finalQty = int.tryParse(qtyC.text) ?? 1;
                if (finalQty < 1) {
                  finalQty = 1;
                }

                final data = {
                  'name': nameC.text.trim(),
                  'tag_id': tagC.text.trim(),
                  'manufacturer': mfgC.text.trim(),
                  'serial_number': snC.text.trim(),
                  'category': catC.text.trim(),
                  'location': locC.text.trim(),
                  'spec': specC.text.trim(),
                  'unit': unitC.text.trim(),
                  'quantity': finalQty,
                  'safety_stock': int.tryParse(safeC.text) ?? 0,
                  'remarks': remC.text.trim(),
                  'status': selectedStatus,
                  'metadata': updatedMeta,
                };

                final success = await provider.handleSave(p: p, data: data, imageXFile: file);

                if (!mounted) {
                  return;
                }
                if (success) {
                  navigator.pop();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
              child: const Text("저장"),
            )
          ],
        );
      }),
    );
  }

  Widget _buildGlobalLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
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

  void _confirmIndividualDelete(BuildContext context, ProductProvider provider, ProductModel p) {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('삭제 확인'), content: Text('${p.name}을(를) 삭제하시겠습니까?'),
      actions: [
        TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text('취소')),
        ElevatedButton(
            onPressed: () async {
              final success = await provider.deleteProduct(p.id);
              if (!ctx.mounted) {
                return;
              }
              if (success) {
                nav.pop();
              } else {
                messenger.showSnackBar(const SnackBar(content: Text('삭제에 실패했습니다.')));
              }
            },
            child: const Text('삭제')
        ),
      ],
    ));
  }

  Future<void> _importFromExcel(BuildContext context, ProductProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isExcelImporting = true;
    });

    try {
      final res = await provider.batchImportFromExcel();

      if (!mounted) {
        return;
      }

      if (res['total'] == 0 && res['failed'] == 0 && res['success'] == 0) {
        return;
      }

      final int failedCount = res['failed'] ?? 0;
      String msg = '총 ${res['total']}행 처리 완료 (성공: ${res['success']}, 실패: $failedCount)';

      if (failedCount > 0) {
        msg += '\n⚠️ 실패한 원본 항목은 [로그 받기]를 눌러 확인하세요.';
      }

      messenger.showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 10),
        backgroundColor: failedCount == 0 ? AppTheme.success : AppTheme.warning,
        action: failedCount > 0
            ? SnackBarAction(
            label: '로그 받기',
            textColor: Colors.white,
            onPressed: () {
              _generateErrorExcel(provider);
            }
        )
            : null,
      ));

    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text('업로드 중 오류 발생: $e'),
            backgroundColor: AppTheme.danger
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExcelImporting = false;
        });
      }
    }
  }

  Future<void> _exportToExcel(BuildContext context, List<ProductModel> list) async {
    final messenger = ScaffoldMessenger.of(context);

    if (list.isEmpty) {
      return;
    }

    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['자산리스트'];
      excel.rename('Sheet1', '자산리스트');
      sheet.appendRow([excel_pkg.TextCellValue('태그ID'), excel_pkg.TextCellValue('품명'), excel_pkg.TextCellValue('위치'), excel_pkg.TextCellValue('분류'), excel_pkg.TextCellValue('상태')]);

      for (final i in list) {
        sheet.appendRow([excel_pkg.TextCellValue(i.tagId), excel_pkg.TextCellValue(i.name), excel_pkg.TextCellValue(i.location ?? ""), excel_pkg.TextCellValue(i.category ?? ""), excel_pkg.TextCellValue(i.status)]);
      }

      final path = await FilePicker.platform.saveFile(dialogTitle: '파일 저장 위치 선택', fileName: 'Asset_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx']);

      if (!mounted || path == null) {
        return;
      }

      final bytes = excel.encode();
      if (bytes != null) {
        await File(path).writeAsBytes(bytes);
        if (mounted) {
          messenger.showSnackBar(const SnackBar(content: Text('✅ 엑셀 파일이 저장되었습니다.')));
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('❌ 저장 실패: $e')));
      }
    }
  }

  void _showColumnSelectionDialog(ProductProvider provider) {
    final availableKeys = _extractAvailableMetaKeys(provider.items);
    final List<String> tempSelection = List.from(provider.selectedColumns);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setDlgState) => AlertDialog(
            title: const Text("표시 항목 설정"),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: availableKeys.map((key) => CheckboxListTile(
                        title: Text(key),
                        value: tempSelection.contains(key),
                        onChanged: (val) {
                          setDlgState(() {
                            if (val == true) {
                              if (tempSelection.length < 5) {
                                tempSelection.add(key);
                              }
                            } else {
                              tempSelection.remove(key);
                            }
                          });
                        }
                    )).toList()
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text("취소")),
              ElevatedButton(onPressed: () async {
                await provider.saveRemoteSettings(tempSelection);
                if (!context.mounted) {
                  return;
                }
                Navigator.pop(ctx);
              }, child: const Text("적용")),
            ],
          )
      ),
    );
  }

  List<String> _extractAvailableMetaKeys(List<ProductModel> items) {
    final Set<String> keySet = {};
    for (var item in items) {
      item.metadata.forEach((k, v) {
        if (!['origin_key_map', 'history', 'last_location_info'].contains(k)) {
          keySet.add(k);
        }
      });
    }
    return keySet.toList()..sort();
  }
}

class _ProductField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType keyboardType;
  final bool isMeta;

  const _ProductField({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType = TextInputType.text,
    this.isMeta = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontSize: 13),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primary, width: 2.0)),
          filled: true,
          fillColor: isMeta ? Colors.green.withValues(alpha: 0.02) : Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
        ),
      ),
    );
  }
}

class _ProductSelectField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _ProductSelectField({required this.label, required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)))).toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontSize: 13),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.border, width: 1.0)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primary, width: 2.0)),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
        ),
      ),
    );
  }
}

class _CameraCaptureDialog extends StatefulWidget {
  final List<CameraDescription> cameras;
  const _CameraCaptureDialog({required this.cameras});
  @override
  State<_CameraCaptureDialog> createState() => _CameraCaptureDialogState();
}

class _CameraCaptureDialogState extends State<_CameraCaptureDialog> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.cameras.first, ResolutionPreset.medium, enableAudio: false);
    _initializeFuture = _controller!.initialize();
  }
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    return AlertDialog(
      title: const Text("웹캠 촬영 (Windows)"),
      content: Container(
        width: 480, height: 360,
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<void>(
          future: _initializeFuture,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.done) {
              return CameraPreview(_controller!);
            }
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () { nav.pop(); }, child: const Text("취소")),
        ElevatedButton(
          onPressed: () async {
            final img = await _controller!.takePicture();
            if (mounted) {
              nav.pop(img);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
          child: const Text("촬영"),
        ),
      ],
    );
  }
}

class _LocationSelectionDialog extends StatefulWidget {
  final String type;
  final List<ProductModel> existingItems;
  const _LocationSelectionDialog({required this.type, required this.existingItems});
  @override
  State<_LocationSelectionDialog> createState() => _LocationSelectionDialogState();
}

class _LocationSelectionDialogState extends State<_LocationSelectionDialog> {
  late List<String> _buildings;
  late List<String> _gates;
  final TextEditingController _bC = TextEditingController();
  final TextEditingController _gC = TextEditingController();

  @override
  void initState() {
    super.initState();
    final Set<String> bs = {'메인창고', '출하장A', '보관실B'};
    final Set<String> gs = {'G1', 'G2', '정문'};
    for (var i in widget.existingItems) {
      final loc = i.metadata['last_location_info'];
      if (loc is Map) {
        if (loc['building'] != null) {
          bs.add(loc['building']);
        }
        if (loc['gate'] != null) {
          gs.add(loc['gate']);
        }
      }
    }
    _buildings = bs.toList()..sort();
    _gates = gs.toList()..sort();
    _bC.text = _buildings.first;
    _gC.text = _gates.first;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('${widget.type} 위치 선택', style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildComboField('건물/창고명', _bC, _buildings),
          const SizedBox(height: 20),
          _buildComboField('GATE/상세위치', _gC, _gates),
        ],
      ),
      actions: [
        TextButton(onPressed: () { Navigator.pop(context); }, child: const Text("취소")),
        ElevatedButton(
            onPressed: () { Navigator.pop(context, {'building': _bC.text, 'gate': _gC.text}); },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            child: const Text("확인")
        ),
      ],
    );
  }

  Widget _buildComboField(String label, TextEditingController ctrl, List<String> opts) {
    return Autocomplete<String>(
      optionsBuilder: (val) => val.text.isEmpty ? opts : opts.where((o) => o.contains(val.text)),
      onSelected: (sel) => ctrl.text = sel,
      fieldViewBuilder: (ctx, tC, fN, onS) {
        if (tC.text != ctrl.text && ctrl.text.isNotEmpty && tC.text.isEmpty) {
          tC.text = ctrl.text;
        }
        tC.addListener(() {
          if (tC.text != ctrl.text) {
            ctrl.text = tC.text;
          }
        });
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: tC,
          builder: (ctx, val, _) => TextField(
            controller: tC, focusNode: fN,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontSize: 13),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primary, width: 2.0)),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                if (val.text.isNotEmpty)
                  IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.clear, size: 18), onPressed: () { tC.clear(); ctrl.clear(); }),
                const Icon(Icons.arrow_drop_down),
                const SizedBox(width: 8),
              ]),
            ),
          ),
        );
      },
    );
  }
}