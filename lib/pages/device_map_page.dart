import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/device_model.dart';
import '../providers/device_provider.dart';
import '../services/device_protocols.dart';

/// [UI] 장치 관제 상황판 (FA 현장 도면 기반)
/// C++Builder의 TForm 위에 TImage(도면)와 TPanel(장비마커)을 배치한 구조와 같습니다.
class DeviceMapPage extends StatefulWidget {
  final String baseUrl;
  const DeviceMapPage({super.key, required this.baseUrl});

  @override
  State<DeviceMapPage> createState() => _DeviceMapPageState();
}

class _DeviceMapPageState extends State<DeviceMapPage> {
  // 도면의 좌표 계산을 위한 Key (C++의 Canvas.Handle 역할)
  final GlobalKey _mapKey = GlobalKey();
  bool _isFullScreen = false;

  // 장치 모델별 아이콘 매핑
  IconData _getIcon(String model) {
    if (model.contains('PRINTER')) return FontAwesomeIcons.print;
    if (model.contains('SCANNER')) return FontAwesomeIcons.barcode;
    if (model == SupportedDeviceModels.ats200) return FontAwesomeIcons.mobileScreen;
    if (model == SupportedDeviceModels.m120) return FontAwesomeIcons.keyboard;
    return FontAwesomeIcons.rss;
  }

  @override
  Widget build(BuildContext context) {
    // TDataModule(DeviceProvider)로부터 실시간 데이터 구독
    final provider = Provider.of<DeviceProvider>(context);

    // 좌표가 설정된 장치와 설정되지 않은 장치 분류
    final unplacedDevices = provider.list.where((d) => d.posX == 0 && d.posY == 0).toList();
    final placedDevices = provider.list.where((d) => d.posX != 0 || d.posY != 0).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: Row(
        children: [
          // 1. 왼쪽 사이드바: 미배치 장치 리스트 (Drag Source)
          if (!_isFullScreen) _buildSidebar(unplacedDevices, provider),

          // 2. 메인 영역: 공장 도면 관제판
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: provider.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildMapArea(placedDevices, provider),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _isFullScreen
          ? FloatingActionButton(
        mini: true,
        backgroundColor: Colors.black.withValues(alpha: 0.5),
        onPressed: () => setState(() => _isFullScreen = false),
        child: const Icon(Icons.fullscreen_exit, color: Colors.white),
      )
          : null,
    );
  }

  /// 상단 헤더 (상태 요약 및 제어)
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers_outlined, color: Colors.indigo),
          const SizedBox(width: 10),
          const Text(
            "실시간 장치 관제 상황판",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Spacer(),
          IconButton(
            tooltip: "전체 화면",
            icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.indigo),
            onPressed: () => setState(() => _isFullScreen = !_isFullScreen),
          ),
        ],
      ),
    );
  }

  /// 미배치 장치 사이드바 (C++의 컴포넌트 팔레트와 같은 역할)
  Widget _buildSidebar(List<DeviceModel> devices, DeviceProvider provider) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text("미배치 장치", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
          ),
          Expanded(
            child: devices.isEmpty
                ? const Center(child: Text("모든 장치가 배치됨", style: TextStyle(color: Colors.grey, fontSize: 12)))
                : ListView.builder(
              itemCount: devices.length,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemBuilder: (context, index) {
                final d = devices[index];
                return Draggable<DeviceModel>(
                  data: d,
                  feedback: _buildDeviceMarker(d, isDragging: true),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFEEEEEE)),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: FaIcon(_getIcon(d.model), size: 14, color: Colors.indigo),
                      title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(d.ipAddress, style: const TextStyle(fontSize: 10)),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 메인 맵 영역 (InteractiveViewer로 줌/팬 지원)
  Widget _buildMapArea(List<DeviceModel> placed, DeviceProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double mapWidth = constraints.maxWidth;
        final double mapHeight = constraints.maxHeight;

        return DragTarget<DeviceModel>(
          onAcceptWithDetails: (details) {
            // 마우스/터치 좌표를 도면 내 비율(0.0~1.0)로 변환하여 저장
            final RenderBox box = _mapKey.currentContext!.findRenderObject() as RenderBox;
            final Offset localOffset = box.globalToLocal(details.offset);

            provider.handleSave(
                d: details.data,
                data: {
                  'pos_x': (localOffset.dx / mapWidth).clamp(0.0, 1.0),
                  'pos_y': (localOffset.dy / mapHeight).clamp(0.0, 1.0),
                }
            );
          },
          builder: (context, candidateData, rejectedData) {
            return InteractiveViewer(
              maxScale: 3.0,
              minScale: 0.5,
              child: Center(
                child: Container(
                  key: _mapKey,
                  width: mapWidth,
                  height: mapHeight,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    image: DecorationImage(
                      // [임시] 실제 공장 도면 이미지가 없을 경우를 대비한 샘플 이미지
                      image: NetworkImage("https://img.freepik.com/free-vector/factory-interior-isometric-composition_1284-24151.jpg"),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Stack(
                    children: placed.map((device) {
                      return Positioned(
                        left: device.posX * mapWidth - 23, // 마커 중심점 보정
                        top: device.posY * mapHeight - 23,
                        child: Draggable<DeviceModel>(
                          data: device,
                          feedback: _buildDeviceMarker(device, isDragging: true),
                          childWhenDragging: const SizedBox.shrink(),
                          child: GestureDetector(
                            onTap: () => _showDeviceDetails(context, device, provider),
                            child: _buildDeviceMarker(device),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 장치 마커 위젯 (Online/Offline 상태 시각화)
  Widget _buildDeviceMarker(DeviceModel d, {bool isDragging = false}) {
    bool isOnline = d.status == 'Online';

    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isOnline ? Colors.indigo : Colors.grey,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Center(
              child: FaIcon(_getIcon(d.model), color: Colors.white, size: 18),
            ),
          ),
          if (!isDragging) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                d.name,
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ]
        ],
      ),
    );
  }

  /// 장치 상세 정보 및 제어 팝업 (C++의 TForm.ShowModal 역할)
  void _showDeviceDetails(BuildContext context, DeviceModel d, DeviceProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            FaIcon(_getIcon(d.model), color: Colors.indigo, size: 20),
            const SizedBox(width: 10),
            Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow("모델", d.model),
            _buildInfoRow("IP 주소", d.ipAddress),
            _buildInfoRow("통신상태", d.status, isStatus: true),
            const Divider(),
            const Text("실시간 로그 (최근 5건)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Container(
              height: 100,
              width: double.maxFinite,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(5)),
              child: ListView(
                children: provider.getLogs(d.id).reversed.take(5).map((log) =>
                    Text(log, style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'))
                ).toList(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              provider.handleSave(d: d, data: {'pos_x': 0.0, 'pos_y': 0.0});
              Navigator.pop(context);
            },
            child: const Text("배치 취소", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("닫기"),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isStatus = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isStatus ? (value == 'Online' ? Colors.green : Colors.red) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}