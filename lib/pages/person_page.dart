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

  /// [수정] C++의 소멸자 처리와 같습니다.
  /// unsubscribe를 호출할 때 발생할 수 있는 내부 스트림 에러를 방어합니다.
  @override
  void dispose() {
    _isDisposed = true;
    _safeUnsubscribe(); // 비동기 에러 방지를 위한 별도 함수 호출
    super.dispose();
  }

  /// 안전한 구독 해제: 닫히는 과정에서 발생하는 이벤트를 무시하도록 try-catch 처리
  Future<void> _safeUnsubscribe() async {
    try {
      // 묻지도 따지지도 않고 해당 컬렉션의 모든 구독을 해제 시도
      await PBService.pb.collection(_collectionName).unsubscribe('*');
    } catch (e) {
      // 이미 스트림이 닫혔다는 에러(Bad state)가 나더라도 무시합니다.
      debugPrint("구독 해제 중 세션 종료 감지 (정상): $e");
    }
  }

  /// [수정] 객체가 파괴된 후 UI 갱신 명령을 내리는 것을 원천 차단
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
      if (_isDisposed) return; // 비동기 작업 후 객체 생존 여부 재확인
      _list = records.map((r) => Person.fromRecord(r)).toList();
    } catch (e) {
      debugPrint("데이터 로드 에러: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _subscribe() {
    PBService.pb.collection(_collectionName).subscribe('*', (e) {
      // [중요] 이벤트가 도착했을 때 이미 이 프로바이더가 죽었다면 데이터 갱신을 하지 않음
      if (!_isDisposed) {
        fetchData();
      }
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

      if (!_isDisposed) await fetchData();
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
      if (!_isDisposed) await fetchData();
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
            body: Column(
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
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          if (!widget.isMobile) _buildHeader(),
                          Expanded(
                            child: provider.isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : _buildListView(filtered, provider),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
        onChanged: (val) => setState(() => _currentSearchQuery = val),
        decoration: InputDecoration(
          labelText: '이름, 사번, 부서, 거래처 통합 검색',
          prefixIcon: const Icon(Icons.search, color: Colors.indigo),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
              label: Center(child: Text(m)),
              onPressed: () => setState(() => _currentFilter = m),
              backgroundColor: _currentFilter == m ? Colors.indigo : Colors.grey[100],
              labelStyle: TextStyle(color: _currentFilter == m ? Colors.white : Colors.black, fontSize: 13),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.indigo.withValues(alpha: 0.05),
      child: const Row(children: [
        SizedBox(width: 50, child: Text('사진', style: TextStyle(fontWeight: FontWeight.bold))),
        Expanded(flex: 2, child: Text('성명', style: TextStyle(fontWeight: FontWeight.bold))),
        Expanded(flex: 2, child: Text('부서/거래처', style: TextStyle(fontWeight: FontWeight.bold))),
        Expanded(flex: 2, child: Text('사번', style: TextStyle(fontWeight: FontWeight.bold))),
        Expanded(flex: 3, child: Text('RFID EPC', style: TextStyle(fontWeight: FontWeight.bold))),
        SizedBox(width: 50, child: Text('관리', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
      ]),
    );
  }

  Widget _buildListView(List<Person> list, PersonProvider provider) {
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (ctx, idx) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = list[index];
        return ListTile(
          onTap: () => _showForm(context, provider, item),
          leading: _buildAvatar(item),
          title: Row(
            children: [
              Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              if (!item.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(4)),
                  child: const Text('중단', style: TextStyle(color: Colors.red, fontSize: 10)),
                ),
            ],
          ),
          subtitle: Text("${item.department} | ${item.companyName ?? '자사'} | ${item.code}"),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _confirmDelete(context, provider, item),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(Person item) {
    final url = item.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(
      width: 40, height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
      child: url != null
          ? Image.network(url, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.person))
          : const Icon(Icons.person),
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
                    image = await picker.pickImage(source: source);
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
                title: Text(p == null ? '신규 인원 등록' : '인원 정보 수정', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                                    width: 160, height: 160,
                                    decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(15),
                                        border: Border.all(color: Colors.indigo.withValues(alpha: 0.2))
                                    ),
                                    child: previewBytes != null
                                        ? ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.memory(previewBytes!, fit: BoxFit.cover))
                                        : (p != null ? ClipRRect(borderRadius: BorderRadius.circular(15), child: _buildAvatar(p)) : const Icon(Icons.add_a_photo, size: 40, color: Colors.indigo)),
                                  ),
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  children: [
                                    const Text("활성 상태", style: TextStyle(fontSize: 13)),
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
                                  _buildField('성명 (필수)', nameC),
                                  _buildField('부서/소속', deptC),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: codeC,
                                            decoration: const InputDecoration(
                                              labelText: '사번/코드',
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                              labelStyle: TextStyle(fontSize: 14),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: currentRole,
                                            style: const TextStyle(fontSize: 13, color: Colors.black),
                                            decoration: const InputDecoration(
                                              labelText: '권한 설정',
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                              labelStyle: TextStyle(fontSize: 14),
                                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                            ),
                                            items: roleOptions.map((r) => DropdownMenuItem(
                                                value: r,
                                                child: Text(r, style: const TextStyle(fontSize: 13))
                                            )).toList(),
                                            onChanged: (val) {
                                              if (val != null) setDialogState(() => currentRole = val);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _buildField('거래처 ID', compIdC),
                                  _buildField('RFID EPC (태그)', tagC),
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
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
                  ElevatedButton(
                    onPressed: pvd.isSaving ? null : () async {
                      if (nameC.text.isEmpty) return;
                      final nav = Navigator.of(ctx);
                      final data = {
                        'name': nameC.text,
                        'code': codeC.text,
                        'tag_id': tagC.text,
                        'department': deptC.text,
                        'company_id': compIdC.text.isEmpty ? null : compIdC.text,
                        'role': currentRole,
                        'is_active': currentIsActive,
                      };
                      if (await pvd.handleSave(p: p, data: data, imageXFile: pickedFile)) {
                        if (ctx.mounted) nav.pop();
                      }
                    },
                    child: const Text("저장하기"),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController c) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          labelStyle: const TextStyle(fontSize: 14),
        )
    ),
  );

  void _confirmDelete(BuildContext context, PersonProvider provider, Person p) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("삭제 확인"),
      content: Text("${p.name}님을 시스템에서 삭제하시겠습니까?"),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text("취소")),
        ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              final nav = Navigator.of(c);
              if (await provider.deletePerson(p.id)) {
                if (c.mounted) nav.pop();
              }
            }, child: const Text("삭제")),
      ],
    ));
  }
}