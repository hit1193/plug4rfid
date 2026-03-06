import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

import '../models/device_model.dart';
import '../providers/device_provider.dart'; // 통신 로직 전담 DataModule
import '../services/device_protocols.dart';

/// [UI] 장치 관리 페이지 (VCL의 TForm 역할)
class DevicePage extends StatefulWidget {
  final String searchQuery;
  final bool isMobile;
  final String baseUrl;

  const DevicePage({
    super.key,
    required this.searchQuery,
    required this.isMobile,
    required this.baseUrl,
  });

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final TextEditingController _searchController = TextEditingController();
  final String _fontPretendard = 'Pretendard';
  String _currentQuery = "";

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

  IconData _getDeviceIcon(String model) {
    if (model.contains('PRINTER')) return FontAwesomeIcons.print;
    if (model.contains('SCANNER')) return FontAwesomeIcons.barcode;
    return FontAwesomeIcons.rss;
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DeviceProvider>(context);
    final bool isWide = MediaQuery.of(context).size.width > 900;

    final filtered = provider.list.where((d) {
      final q = _currentQuery.toLowerCase();
      return d.name.toLowerCase().contains(q) ||
          d.ipAddress.contains(q) ||
          d.model.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
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
                    _buildHeader(isWide),
                    Expanded(
                      child: provider.isLoading
                          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
                          : _buildListView(filtered, provider, isWide),
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
        child: const Icon(Icons.router, color: Colors.white),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 15, 26, 5),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _currentQuery = val),
        style: TextStyle(fontFamily: _fontPretendard, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: '장치 통합 검색 (이름, IP, 모델)',
          labelStyle: const TextStyle(fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.indigo),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildHeader(bool isWide) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      color: Colors.indigo.withValues(alpha: 0.05),
      child: Row(children: [
        const SizedBox(width: 45, child: Text('아이콘', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        const SizedBox(width: 150, child: Text('장치 명칭', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        if (isWide) const Expanded(child: Text('통신 정보 (IP Address : Port)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        const SizedBox(width: 120, child: Text('통신 제어', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        const SizedBox(width: 80, child: Text('상태', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        const SizedBox(width: 50, child: Text('관리', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
      ]),
    );
  }

  Widget _buildListView(List<DeviceModel> list, DeviceProvider provider, bool isWide) {
    if (list.isEmpty) return const Center(child: Text("등록된 장치가 없습니다."));

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (ctx, idx) => const Divider(height: 1, color: Color(0xFFF5F5F5)),
      itemBuilder: (context, index) {
        final item = list[index];
        bool isOnline = item.status == 'Online';

        return InkWell(
          onDoubleTap: () => _showForm(context, provider, item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                SizedBox(width: 45, child: FaIcon(_getDeviceIcon(item.model), size: 18, color: isOnline ? Colors.indigo : Colors.grey)),
                SizedBox(
                  width: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, overflow: TextOverflow.ellipsis)),
                      Text(item.model, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
                if (isWide)
                  Expanded(child: Text("${item.ipAddress} : ${item.port}", style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.blueGrey))),

                SizedBox(
                  width: 120,
                  child: Center(
                    child: isOnline
                        ? OutlinedButton(
                      onPressed: () => provider.disconnectDevice(item.id),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red, minimumSize: const Size(80, 32), padding: EdgeInsets.zero),
                      child: const Text("연결해제", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                        : ElevatedButton(
                      onPressed: () => provider.connectDevice(item),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, minimumSize: const Size(80, 32), padding: EdgeInsets.zero),
                      child: const Text("장치연결", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),

                SizedBox(
                  width: 80,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isOnline ? Colors.green : Colors.red).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: (isOnline ? Colors.green : Colors.red).withValues(alpha: 0.3)),
                      ),
                      child: Text(item.status, style: TextStyle(color: isOnline ? Colors.green[700] : Colors.red[700], fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),

                SizedBox(
                  width: 50,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    onPressed: () => _confirmDelete(context, provider, item),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// [기능] 장치 등록/수정 다이얼로그 (Async Gap 방어 적용)
  Future<void> _showForm(BuildContext context, DeviceProvider provider, DeviceModel? d) async {
    final nameC = TextEditingController(text: d?.name ?? "");
    final ipC = TextEditingController(text: d?.ipAddress ?? "");
    final portC = TextEditingController(text: (d?.port ?? 8080).toString());
    final clientIdC = TextEditingController(text: d?.clientId ?? "");

    final List<String> modelOptions = SupportedDeviceModels.list;
    String modelV = modelOptions.contains(d?.model) ? d!.model : modelOptions.first;
    bool activeV = d?.isActive ?? true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ListenableProvider.value(
        value: provider,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            bool isWide = MediaQuery.of(context).size.width > 750;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(d == null ? '신규 장치 등록' : '장치 설정 수정', style: const TextStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: isWide ? 680 : null,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildImagePicker(context, d, null, (file, bytes) {}),
                            const SizedBox(width: 25),
                            Expanded(child: _buildFormFields(nameC, ipC, portC, clientIdC, modelV, activeV, (m, a) {
                              setDialogState(() { if (m != null) modelV = m; if (a != null) activeV = a; });
                            })),
                          ],
                        )
                      else ...[
                        _buildImagePicker(context, d, null, (file, bytes) { }),
                        const SizedBox(height: 20),
                        _buildFormFields(nameC, ipC, portC, clientIdC, modelV, activeV, (m, a) {
                          setDialogState(() { if (m != null) modelV = m; if (a != null) activeV = a; });
                        }),
                      ],
                      if (provider.isSaving) const LinearProgressIndicator(color: Colors.indigo),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소", style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  onPressed: provider.isSaving ? null : () async {
                    if (nameC.text.isEmpty) return;

                    // 1. 비동기 작업 전 Navigator를 미리 캡처하거나 context가 살아있는지 확인해야 합니다.
                    final nav = Navigator.of(ctx);

                    final data = {
                      'name': nameC.text.trim(),
                      'model': modelV,
                      'ip_address': ipC.text.trim(),
                      'port': int.tryParse(portC.text.trim()) ?? 8080,
                      'client_id': clientIdC.text.trim(),
                      'is_active': activeV,
                    };

                    // 비동기 작업 (Async Gap 발생 지점)
                    bool success = await provider.handleSave(d: d, data: data);

                    // 2. [핵심] await 이후에 context가 살아있는지 확인합니다.
                    if (success && ctx.mounted) {
                      nav.pop();
                    }
                  },
                  child: Text(d == null ? "등록하기" : "수정완료"),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildImagePicker(BuildContext context, DeviceModel? d, Uint8List? preview, Function(XFile, Uint8List) onP) {
    final imgUrl = d?.getImageUrl(widget.baseUrl, thumb: '200x200');
    return Container(
      width: 150, height: 150,
      decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.indigo.withValues(alpha: 0.2))
      ),
      child: imgUrl != null
          ? ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network(imgUrl, fit: BoxFit.cover))
          : const Icon(Icons.add_a_photo_outlined, size: 50, color: Colors.indigo),
    );
  }

  Widget _buildFormFields(TextEditingController n, TextEditingController i, TextEditingController p, TextEditingController c, String mV, bool aV, Function(String?, bool?) onC) {
    return Column(
      children: [
        _buildField("장치 관리 명칭", n, icon: Icons.label_outline),
        Row(children: [Expanded(child: _buildField("IP", i, icon: Icons.lan)), const SizedBox(width: 10), SizedBox(width: 100, child: _buildField("Port", p, isNumber: true))]),
        _buildField("Client ID (Host Serial)", c, icon: Icons.fingerprint),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: mV,
          decoration: const InputDecoration(labelText: '제조사/모델 프로토콜', border: OutlineInputBorder(), isDense: true),
          items: SupportedDeviceModels.labels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => onC(v, null),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            const Text("장치 활성화 상태", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const Spacer(),
            Switch(value: aV, activeColor: Colors.indigo, onChanged: (v) => onC(null, v)),
          ],
        ),
      ],
    );
  }

  Widget _buildField(String label, TextEditingController c, {bool isNumber = false, IconData? icon}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  /// [기능] 장치 삭제 (Async Gap 방어 적용)
  void _confirmDelete(BuildContext context, DeviceProvider provider, DeviceModel d) {
    showDialog(context: context, builder: (c) {
      return AlertDialog(
        title: const Text("장치 삭제", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
        content: Text("[${d.name}] 장치를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              // 1. Navigator를 미리 확보합니다.
              final nav = Navigator.of(c);

              // 비동기 삭제 작업
              bool result = await provider.deleteDevice(d.id);

              // 2. 작업 후 context(c)가 살아있는지 확인 후 닫습니다.
              if (result && c.mounted) {
                nav.pop();
              }
            },
            child: const Text("삭제 실행"),
          ),
        ],
      );
    });
  }
}