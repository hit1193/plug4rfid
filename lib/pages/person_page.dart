import 'package:flutter/material.dart';
import '../models/persons.dart';
import '../utils/hangul_utils.dart';
import '../services/pb_service.dart';

/// 인원 관리 페이지 (ProductPage 스타일로 디자인 통일 버전)
class PersonPage extends StatefulWidget {
  final String searchQuery;
  final String filter;
  final bool isMobile;
  final String baseUrl;
  final Function(Person)? onEdit;

  const PersonPage({
    super.key,
    required this.searchQuery,
    required this.filter,
    required this.isMobile,
    required this.baseUrl,
    this.onEdit,
  });

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  static const String _fontFamily = 'Pretendard';
  List<Person> _list = [];
  bool _isLoading = false;
  bool _isSaving = false;
  final String _collectionName = 'persons';

  // 검색 및 필터 상태 관리 (ProductPage와 동일한 구조)
  final TextEditingController _searchController = TextEditingController();
  String _currentSearchQuery = "";
  late String _currentFilter;

  @override
  void initState() {
    super.initState();
    _currentFilter = widget.filter;
    _currentSearchQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
    _fetchData();
    _subscribe();
  }

  @override
  void didUpdateWidget(PersonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter) {
      setState(() => _currentFilter = widget.filter);
    }
  }

  /// 데이터 로드
  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final records = await PBService.pb.collection(_collectionName).getFullList(sort: '-created');
      if (!mounted) return;
      setState(() {
        _list = records.map((r) => Person.fromRecord(r)).toList();
      });
    } catch (e) {
      debugPrint("데이터 로드 에러: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 실시간 구독
  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) {
      if (mounted) _fetchData();
    });
  }

  @override
  void dispose() {
    PBService.pb.collection(_collectionName).unsubscribe('*');
    _searchController.dispose();
    super.dispose();
  }

  /// 저장 로직 (Async Gap 완전 대응)
  Future<void> _handleSave({
    required Person? p,
    required Map<String, dynamic> data,
  }) async {
    setState(() => _isSaving = true);
    try {
      if (p == null) {
        await PBService.pb.collection(_collectionName).create(body: data);
      } else {
        await PBService.pb.collection(_collectionName).update(p.id, body: data);
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      if (widget.onEdit != null && p != null) widget.onEdit!(p);
    } catch (e) {
      debugPrint("저장 에러: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. 필터링 로직
    List<Person> filtered = _list;
    if (_currentFilter == '정상 등록') {
      filtered = _list.where((p) => p.tagId.isNotEmpty).toList();
    } else if (_currentFilter == '미등록') {
      filtered = _list.where((p) => p.tagId.isEmpty).toList();
    }

    // 2. 통합 검색 로직 (초성 검색 지원)
    if (_currentSearchQuery.isNotEmpty) {
      filtered = filtered.where((p) {
        return HangulUtils.matches(_currentSearchQuery, p.name) ||
            p.code.toLowerCase().contains(_currentSearchQuery.toLowerCase()) ||
            p.tagId.toLowerCase().contains(_currentSearchQuery.toLowerCase());
      }).toList();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildSearchBar(),
          _buildCustomFilterToggle(),
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
                    if (!widget.isMobile) _buildAggregatedHeader(),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
                          : filtered.isEmpty
                          ? const Center(child: Text("데이터가 없습니다.", style: TextStyle(fontFamily: _fontFamily)))
                          : _buildListView(filtered),
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
        elevation: 4,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  /// [ProductPage 스타일] 검색바
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 15, 26, 5),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: _fontFamily),
        onChanged: (val) => setState(() => _currentSearchQuery = val),
        decoration: InputDecoration(
          labelText: '인원 통합 검색',
          labelStyle: const TextStyle(fontSize: 16, color: Colors.black87, fontFamily: _fontFamily, fontWeight: FontWeight.w600),
          prefixIcon: const Icon(Icons.search, size: 28, color: Colors.indigo),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2))
          ),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.indigo, width: 2.0)
          ),
        ),
      ),
    );
  }

  /// [ProductPage 스타일] 커스텀 토글 바
  Widget _buildCustomFilterToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.indigo.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            _buildToggleItem('전체 인원', '전체', Icons.groups_outlined),
            _buildToggleItem('정상 등록', '정상 등록', Icons.how_to_reg_outlined),
            _buildToggleItem('태그 미등록', '미등록', Icons.person_off_outlined),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleItem(String label, String mode, IconData icon) {
    bool isSelected = _currentFilter == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentFilter = mode),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.indigo.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))]
                : [],
          ),
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

  /// [ProductPage 스타일] 웅장한 헤더
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
          const SizedBox(width: 50, child: Text('사진', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo))),
          const SizedBox(width: 15),
          Expanded(flex: 2, child: Text('성명', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo))),
          Expanded(flex: 2, child: Text('사번 / 관리번호', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo))),
          Expanded(flex: 3, child: Text('RFID 태그 ID', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo))),
          const SizedBox(width: 90, child: Text('상태', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo))),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  /// 메인 목록 뷰
  Widget _buildListView(List<Person> list) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: list.length,
      separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.withValues(alpha: 0.1)),
      itemBuilder: (context, index) {
        final item = list[index];
        return widget.isMobile ? _buildMobileCard(item) : _buildDesktopItem(item, index);
      },
    );
  }

  /// [ProductPage 스타일] 조밀한 목록 아이템
  Widget _buildDesktopItem(Person item, int index) {
    return InkWell(
      onTap: () => _showForm(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            SizedBox(width: 50, child: Text('${index + 1}', style: const TextStyle(fontSize: 14, color: Colors.grey))),
            _buildAvatar(item, size: 40),
            const SizedBox(width: 15),
            Expanded(flex: 2, child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87))),
            Expanded(flex: 2, child: Text(item.code, style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 14))),
            Expanded(
                flex: 3,
                child: Text(
                    item.tagId.isEmpty ? '미할당' : item.tagId,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: item.tagId.isEmpty ? Colors.grey : Colors.indigo,
                      fontSize: 14,
                      fontWeight: item.tagId.isEmpty ? FontWeight.normal : FontWeight.bold,
                    )
                )
            ),
            SizedBox(width: 90, child: Center(child: _buildStatusBadge(item.tagId.isNotEmpty))),
            const SizedBox(width: 40, child: Icon(Icons.edit_note, color: Colors.blueGrey, size: 24)),
          ],
        ),
      ),
    );
  }

  /// 모바일 카드 뷰
  Widget _buildMobileCard(Person item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1)))),
      child: Row(
        children: [
          _buildAvatar(item, size: 50),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text("사번: ${item.code}", style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
                Text("RFID: ${item.tagId.isEmpty ? '미등록' : item.tagId}",
                    style: TextStyle(fontSize: 13, color: item.tagId.isEmpty ? Colors.orange : Colors.indigo)),
              ],
            ),
          ),
          _buildStatusBadge(item.tagId.isNotEmpty, mini: true),
        ],
      ),
    );
  }

  /// 상태 배지
  Widget _buildStatusBadge(bool isRegistered, {bool mini = false}) {
    final color = isRegistered ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        isRegistered ? "정상" : "미등록",
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// 아바타 위젯
  Widget _buildAvatar(Person item, {double size = 40}) {
    final url = item.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: url != null
          ? Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => Icon(Icons.person, color: Colors.grey, size: size * 0.6),
      )
          : Icon(Icons.person, color: Colors.grey, size: size * 0.6),
    );
  }

  /// 폼 팝업
  void _showForm(Person? p) {
    final nameC = TextEditingController(text: p?.name ?? "");
    final codeC = TextEditingController(text: p?.code ?? "");
    final tagC = TextEditingController(text: p?.tagId ?? "");
    const lS = TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.black45, fontFamily: _fontFamily);

    showDialog(
      context: context,
      barrierDismissible: !_isSaving,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(p == null ? '신규 인원 등록' : '인원 정보 수정', style: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField(nameC, '성명 (필수)', Icons.person_outline, lS),
              const SizedBox(height: 12),
              _buildField(codeC, '사번 / 관리번호', Icons.badge_outlined, lS),
              const SizedBox(height: 12),
              _buildField(tagC, 'RFID EPC (Tag ID)', Icons.nfc_outlined, lS),
              if (_isSaving) const Padding(padding: EdgeInsets.only(top: 15), child: LinearProgressIndicator()),
            ],
          ),
        ),
        actions: [
          if (p != null)
            TextButton(
              onPressed: _isSaving ? null : () { Navigator.of(ctx).pop(); _confirmDelete(p); },
              child: const Text('삭제', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _isSaving ? null : () {
              if (nameC.text.trim().isEmpty) return;
              final data = {
                'name': nameC.text.trim(),
                'code': codeC.text.trim(),
                'tag_id': tagC.text.trim()
              };
              _handleSave(p: p, data: data);
            },
            child: Text(_isSaving ? '저장 중...' : '저장'),
          ),
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, TextStyle lS) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: _fontFamily),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: lS,
        prefixIcon: Icon(icon, size: 20),
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }

  /// 삭제 확인 (Async Gap 대응)
  void _confirmDelete(Person p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('[${p.name}] 인원 정보를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              try {
                await PBService.pb.collection(_collectionName).delete(p.id);
                if (!mounted) return;
                Navigator.of(context).pop();
              } catch (e) {
                debugPrint("삭제 에러: $e");
              }
            },
            child: const Text('삭제 확정', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}