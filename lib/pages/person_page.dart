import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/persons.dart';
import '../utils/hangul_utils.dart';
import '../services/pb_service.dart';

/// 전역적으로 사용할 폰트 패밀리 정의
const String _fontPretendard = 'Pretendard';

/// [Logic] 인원 관리를 위한 상태 관리 클래스
class PersonProvider extends ChangeNotifier {
  final String _collectionName = 'persons';
  List<Person> _list = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDisposed = false;

  List<Person> get list => _list;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;

  PersonProvider() {
    fetchData();
    _subscribe();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _safeUnsubscribe();
    super.dispose();
  }

  Future<void> _safeUnsubscribe() async {
    try {
      await PBService.pb.collection(_collectionName).unsubscribe('*');
    } catch (e) {
      debugPrint("구독 해제 중 세션 종료 감지 (정상): $e");
    }
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  Future<void> fetchData() async {
    if (_isDisposed) return;
    _isLoading = true;
    notifyListeners();
    try {
      final records = await PBService.pb.collection(_collectionName).getFullList(
        sort: '-created',
        expand: 'company_id',
      );
      if (_isDisposed) return;
      _list = records.map((r) => Person.fromRecord(r)).toList();
    } catch (e) {
      debugPrint("데이터 로드 에러: $e");
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) {
      if (!_isDisposed) fetchData();
    });
  }

  Future<bool> handleSave({
    required Person? p,
    required Map<String, dynamic> data,
    XFile? imageXFile,
  }) async {
    if (_isDisposed) return false;
    _isSaving = true;
    notifyListeners();

    try {
      Uint8List? fileBytes;
      String? fileName;
      if (imageXFile != null) {
        fileBytes = await imageXFile.readAsBytes();
        fileName = imageXFile.name;
      }
      List<http.MultipartFile> files = [];
      if (fileBytes != null && fileName != null) {
        files.add(http.MultipartFile.fromBytes('image', fileBytes, filename: fileName));
      }

      if (p == null) {
        await PBService.pb.collection(_collectionName).create(body: data, files: files);
      } else {
        await PBService.pb.collection(_collectionName).update(p.id, body: data, files: files);
      }
      return true;
    } catch (e) {
      debugPrint("저장 에러: $e");
      return false;
    } finally {
      if (!_isDisposed) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  Future<bool> deletePerson(String id) async {
    if (_isDisposed) return false;
    try {
      await PBService.pb.collection(_collectionName).delete(id);
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// [UI Component] 사진 촬영 다이얼로그
class CameraCaptureDialog extends StatefulWidget {
  const CameraCaptureDialog({super.key});
  @override
  State<CameraCaptureDialog> createState() => _CameraCaptureDialogState();
}

class _CameraCaptureDialogState extends State<CameraCaptureDialog> {
  CameraController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final selected = cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );
        _controller = CameraController(selected, ResolutionPreset.medium, enableAudio: false);
        await _controller!.initialize();
        if (!mounted) return;
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint("카메라 초기화 에러: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("사진 촬영", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: _fontPretendard)),
      content: Container(
        width: 400, height: 300, color: Colors.black,
        child: _isInitialized
            ? AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: CameraPreview(_controller!))
            : const Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소", style: TextStyle(fontFamily: _fontPretendard))),
        ElevatedButton.icon(
          onPressed: _isInitialized ? () async {
            final nav = Navigator.of(context);
            final image = await _controller!.takePicture();
            if (context.mounted) nav.pop(image);
          } : null,
          icon: const Icon(Icons.camera),
          label: const Text("촬영하기", style: TextStyle(fontFamily: _fontPretendard)),
        ),
      ],
    );
  }
}

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
  final TextEditingController _searchController = TextEditingController();
  String _currentSearchQuery = "";
  late String _currentFilter;

  // 그리드 비율 및 높이 상수
  static const double _rowHeight = 56.0;
  static const double _colImgWidth = 60.0;
  static const int _flexName = 4;
  static const int _flexDept = 5;
  static const int _flexCode = 3;
  static const int _flexEpc = 6;
  static const double _colActionWidth = 80.0;

  @override
  void initState() {
    super.initState();
    _currentFilter = widget.filter;
    _currentSearchQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const defaultTextStyle = TextStyle(fontFamily: _fontPretendard);

    return ChangeNotifierProvider(
      create: (_) => PersonProvider(),
      child: Consumer<PersonProvider>(
        builder: (context, provider, child) {
          List<Person> filtered = provider.list.where((p) {
            bool matchesFilter = true;
            if (_currentFilter == '정상 등록') matchesFilter = p.tagId.isNotEmpty;
            if (_currentFilter == '미등록') matchesFilter = p.tagId.isEmpty;

            bool matchesSearch = HangulUtils.matches(_currentSearchQuery, p.name) ||
                p.code.toLowerCase().contains(_currentSearchQuery.toLowerCase()) ||
                p.department.toLowerCase().contains(_currentSearchQuery.toLowerCase()) ||
                (p.companyName?.toLowerCase().contains(_currentSearchQuery.toLowerCase()) ?? false) ||
                p.tagId.toLowerCase().contains(_currentSearchQuery.toLowerCase());
            return matchesFilter && matchesSearch;
          }).toList();

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: DefaultTextStyle(
              style: defaultTextStyle.copyWith(color: Colors.black),
              child: Column(
                children: [
                  _buildSearchBar(),
                  _buildFilterToggle(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.indigo.withValues(alpha: 0.3), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            )
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: LayoutBuilder(
                            builder: (context, constraints) {
                              bool showFullInfo = constraints.maxWidth > 700;
                              bool showMediumInfo = constraints.maxWidth > 450;

                              return Column(
                                children: [
                                  _buildHeader(showFullInfo, showMediumInfo),
                                  const Divider(height: 1, thickness: 1.2, color: Color(0xFFE0E0E0)),
                                  Expanded(
                                    child: provider.isLoading
                                        ? const Center(child: CircularProgressIndicator())
                                        : _buildListView(filtered, provider, showFullInfo, showMediumInfo),
                                  ),
                                ],
                              );
                            }
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => _showForm(context, provider, null),
              backgroundColor: Colors.indigo,
              child: const Icon(Icons.person_add, color: Colors.white),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 15, 26, 5),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontFamily: _fontPretendard),
        onChanged: (val) => setState(() => _currentSearchQuery = val),
        decoration: InputDecoration(
          labelText: '이름, 사번, 부서, 거래처 통합 검색',
          labelStyle: const TextStyle(fontFamily: _fontPretendard),
          prefixIcon: const Icon(Icons.search, color: Colors.indigo),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildFilterToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
      child: Row(
        children: ['전체', '정상 등록', '미등록'].map((m) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              label: Center(child: Text(m, style: const TextStyle(fontFamily: _fontPretendard))),
              onPressed: () => setState(() => _currentFilter = m),
              backgroundColor: _currentFilter == m ? Colors.indigo : Colors.white,
              labelStyle: TextStyle(
                fontFamily: _fontPretendard,
                color: _currentFilter == m ? Colors.white : Colors.black87,
                fontWeight: _currentFilter == m ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildHeader(bool showFull, bool showMedium) {
    const headerStyle = TextStyle(
        fontFamily: _fontPretendard,
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: Colors.black87
    );
    return Container(
      height: _rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: Colors.indigo.withValues(alpha: 0.07),
      child: Row(children: [
        const SizedBox(width: _colImgWidth, child: Text('사진', style: headerStyle)),
        const Expanded(flex: _flexName, child: Text('성명', style: headerStyle)),
        if (showMedium) const Expanded(flex: _flexDept, child: Text('부서 / 거래처', style: headerStyle)),
        if (showFull) const Expanded(flex: _flexCode, child: Text('사번', style: headerStyle)),
        if (showMedium) const Expanded(flex: _flexEpc, child: Text('RFID EPC (태그)', style: headerStyle)),
        const SizedBox(width: _colActionWidth, child: Text('관리', textAlign: TextAlign.center, style: headerStyle)),
      ]),
    );
  }

  Widget _buildListView(List<Person> list, PersonProvider provider, bool showFull, bool showMedium) {
    if (list.isEmpty) return const Center(child: Text("검색 결과가 없습니다.", style: TextStyle(fontFamily: _fontPretendard)));

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (ctx, idx) => const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
      itemBuilder: (context, index) {
        final item = list[index];
        return InkWell(
          onTap: () => _showForm(context, provider, item),
          child: Container(
            height: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SizedBox(width: _colImgWidth, child: Align(alignment: Alignment.centerLeft, child: _buildAvatar(item))),
                Expanded(
                    flex: _flexName,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            style: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!item.isActive) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.pause_circle_outline, size: 14, color: Colors.red),
                        ]
                      ],
                    )
                ),
                if (showMedium)
                  Expanded(
                      flex: _flexDept,
                      child: Text(
                        "${item.department} / ${item.companyName ?? '자사'}",
                        style: const TextStyle(fontFamily: _fontPretendard, fontSize: 13, color: Colors.black54),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                  ),
                if (showFull)
                  Expanded(
                    flex: _flexCode,
                    child: Text(
                      item.code,
                      style: const TextStyle(fontFamily: _fontPretendard, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (showMedium)
                  Expanded(
                      flex: _flexEpc,
                      child: Text(
                        item.tagId.isEmpty ? "미등록" : item.tagId,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: item.tagId.isEmpty ? Colors.grey : Colors.indigo,
                          fontWeight: item.tagId.isEmpty ? FontWeight.normal : FontWeight.bold,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      )
                  ),
                SizedBox(
                    width: _colActionWidth,
                    child: Center(
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                        onPressed: () => _confirmDelete(context, provider, item),
                      ),
                    )
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(Person item) {
    final url = item.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(
      width: 40, height: 40,
      padding: const EdgeInsets.all(5),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: url != null
          ? Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (c, e, s) => const Icon(Icons.camera_alt_outlined, size: 14, color: Colors.grey)
      )
          : const Icon(Icons.camera_alt_outlined, size: 14, color: Colors.grey),
    );
  }

  Future<void> _showForm(BuildContext context, PersonProvider provider, Person? p) async {
    final nameC = TextEditingController(text: p?.name ?? "");
    final codeC = TextEditingController(text: p?.code ?? "");
    final tagC = TextEditingController(text: p?.tagId ?? "");
    final deptC = TextEditingController(text: p?.department ?? "");
    final compIdC = TextEditingController(text: p?.companyId ?? "");
    final List<String> roleOptions = ['Admin', 'Operator', 'Viewer'];
    String currentRole = roleOptions.contains(p?.role) ? p!.role : "Operator";
    bool currentIsActive = p?.isActive ?? true;
    XFile? pickedFile;
    Uint8List? previewBytes;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ListenableProvider.value(
        value: provider,
        child: Consumer<PersonProvider>(
          builder: (context, pvd, _) => StatefulBuilder(
            builder: (context, setDialogState) {
              bool isWide = MediaQuery.of(context).size.width > 700;
              final dynamicLabelStyle = TextStyle(fontSize: 12, color: Colors.black45, fontFamily: _fontPretendard);

              void pickImageAction(ImageSource source) async {
                XFile? image;
                try {
                  if (!kIsWeb && Platform.isWindows && source == ImageSource.camera) {
                    image = await showDialog<XFile>(
                      context: context,
                      builder: (c) => const CameraCaptureDialog(),
                    );
                  } else {
                    final picker = ImagePicker();
                    image = await picker.pickImage(source: source, imageQuality: 70);
                  }

                  if (image != null && context.mounted) {
                    final bytes = await image.readAsBytes();
                    setDialogState(() {
                      pickedFile = image;
                      previewBytes = bytes;
                    });
                  }
                } catch (e) {
                  debugPrint("이미지 선택 에러: $e");
                }
              }

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Text(
                    p == null ? '신규 인원 등록' : '인원 정보 수정',
                    style: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold)
                ),
                content: SizedBox(
                  width: isWide ? 700 : null,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    showModalBottomSheet(
                                      context: context,
                                      builder: (b) => Wrap(children: [
                                        ListTile(leading: const Icon(Icons.camera_alt), title: const Text('카메라 촬영'), onTap: () { Navigator.pop(b); pickImageAction(ImageSource.camera); }),
                                        ListTile(leading: const Icon(Icons.photo), title: const Text('갤러리 선택'), onTap: () { Navigator.pop(b); pickImageAction(ImageSource.gallery); }),
                                      ]),
                                    );
                                  },
                                  child: Container(
                                    width: 150, height: 150,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                        color: Colors.grey[50],
                                        borderRadius: BorderRadius.circular(15),
                                        border: Border.all(color: Colors.indigo.withValues(alpha: 0.2))
                                    ),
                                    child: previewBytes != null
                                        ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(previewBytes!, fit: BoxFit.contain))
                                        : (p != null && (p.image?.isNotEmpty ?? false))
                                        ? ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(
                                        p.getImageUrl(widget.baseUrl, thumb: '200x200')!,
                                        fit: BoxFit.contain,
                                        errorBuilder: (c, e, s) => const Column( // 에러 시에도 카메라 아이콘 + 텍스트 표시
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.camera_alt_outlined, size: 40, color: Colors.grey),
                                            SizedBox(height: 8),
                                            Text("사진 등록", style: TextStyle(fontFamily: _fontPretendard, color: Colors.grey, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    )
                                        : const Column( // [수정 지점] 인원정보 편집창에도 카메라 아이콘 + "사진 등록" 텍스트 반영
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.camera_alt_outlined, size: 40, color: Colors.grey),
                                        SizedBox(height: 8),
                                        Text("사진 등록", style: TextStyle(fontFamily: _fontPretendard, color: Colors.grey, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  children: [
                                    const Text("활성 상태", style: TextStyle(fontFamily: _fontPretendard, fontSize: 13, fontWeight: FontWeight.bold)),
                                    Switch(
                                        value: currentIsActive,
                                        onChanged: (val) => setDialogState(() => currentIsActive = val)
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(width: 25),
                            Expanded(
                              child: Column(
                                children: [
                                  _buildField('성명 (필수)', nameC, dynamicLabelStyle),
                                  _buildField('부서 / 소속', deptC, dynamicLabelStyle),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _buildField('사번 / 코드', codeC, dynamicLabelStyle, noPadding: true),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: currentRole,
                                            style: const TextStyle(fontFamily: _fontPretendard, fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold),
                                            decoration: InputDecoration(
                                              labelText: '권한 설정',
                                              isDense: true,
                                              border: const OutlineInputBorder(),
                                              labelStyle: dynamicLabelStyle,
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                            ),
                                            items: roleOptions.map((r) => DropdownMenuItem(
                                                value: r,
                                                child: Text(r, style: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold, fontSize: 16))
                                            )).toList(),
                                            onChanged: (val) {
                                              if (val != null) setDialogState(() => currentRole = val);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _buildField('거래처 ID', compIdC, dynamicLabelStyle),
                                  _buildField('RFID EPC (태그)', tagC, dynamicLabelStyle),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (pvd.isSaving) const Padding(padding: EdgeInsets.only(top: 15), child: LinearProgressIndicator()),
                      ],
                    ),
                  ),
                ),
                actions: [
                  Row(
                    children: [
                      if (p != null)
                        TextButton(
                          onPressed: () => _confirmDelete(context, provider, p, onDeleted: () => Navigator.of(ctx).pop()),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text("인원 삭제", style: TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold)),
                        ),
                      const Spacer(),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("취소", style: TextStyle(fontFamily: _fontPretendard))
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: pvd.isSaving ? null : () async {
                          if (nameC.text.isEmpty) return;
                          final nav = Navigator.of(ctx);
                          final data = {
                            'name': nameC.text.trim(),
                            'code': codeC.text.trim(),
                            'tag_id': tagC.text.trim(),
                            'department': deptC.text.trim(),
                            'company_id': compIdC.text.isEmpty ? null : compIdC.text.trim(),
                            'role': currentRole,
                            'is_active': currentIsActive,
                          };
                          if (await pvd.handleSave(p: p, data: data, imageXFile: pickedFile)) {
                            if (ctx.mounted) nav.pop();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold)
                        ),
                        child: const Text("저장하기"),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController c, TextStyle labelStyle, {bool noPadding = false}) {
    final field = TextField(
        controller: c,
        style: const TextStyle(fontFamily: _fontPretendard, fontSize: 16, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          labelStyle: labelStyle,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        )
    );
    if (noPadding) return field;
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: field);
  }

  void _confirmDelete(BuildContext context, PersonProvider provider, Person p, {VoidCallback? onDeleted}) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("삭제 확인", style: TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold)),
      content: Text("${p.name}님을 시스템에서 삭제하시겠습니까?", style: const TextStyle(fontFamily: _fontPretendard)),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text("취소", style: TextStyle(fontFamily: _fontPretendard))),
        ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              final nav = Navigator.of(c);
              if (await provider.deletePerson(p.id)) {
                if (c.mounted) nav.pop();
                if (onDeleted != null) onDeleted();
              }
            }, child: const Text("삭제", style: TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold))),
      ],
    ));
  }
}