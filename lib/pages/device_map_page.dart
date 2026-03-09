import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/device_model.dart';
import '../providers/device_provider.dart';
import '../services/device_protocols.dart';
import '../theme/app_theme.dart'; // 중앙 집중형 테마 임포트

/// ---------------------------------------------------------------------------
/// [UI] 장치 관제 상황판 (SCADA & 플로팅 UI 기반)
/// 바탕 전체를 도면(Canvas)으로 쓰고 UI를 그 위에 투명하게 띄우는(Overlay)
/// 가장 현대적인 플로팅(Floating) 아키텍처로 설계되었습니다.
/// ---------------------------------------------------------------------------
class DeviceMapPage extends StatefulWidget {
  /// 서버와 통신하기 위한 기본 URL 주소입니다.
  final String baseUrl;

  /// 생성자입니다.
  const DeviceMapPage({super.key, required this.baseUrl});

  @override
  State<DeviceMapPage> createState() {
    return _DeviceMapPageState();
  }
}

class _DeviceMapPageState extends State<DeviceMapPage> {
  // 도면의 내부 좌표(Local Coordinate) 계산을 위한 Key 입니다.
  // 위젯의 크기와 위치 정보를 가져올 때 사용합니다.
  final GlobalKey _mapKey = GlobalKey();

  // -------------------------------------------------------------------------
  // [상태 제어 변수]
  // -------------------------------------------------------------------------
  // 진정한 전체화면 여부 (헤더와 사이드바를 모두 숨깁니다)
  bool _isFullScreen = false;
  // 사이드바(미배치 장치 리스트 뷰) 열림/닫힘 상태
  bool _isSidebarOpen = true;

  /// 장치 모델(프로토콜) 문자열을 분석하여 직관적인 아이콘을 반환합니다.
  /// 블록 스타일을 적용하여 조건별로 명확하게 보이도록 작성했습니다.
  IconData _getIcon(String model) {
    if (model.contains('PRINTER')) {
      return FontAwesomeIcons.print;
    }
    if (model.contains('SCANNER') || model.contains('RS232')) {
      return FontAwesomeIcons.barcode;
    }
    if (model == SupportedDeviceModels.ats200) {
      return FontAwesomeIcons.mobileScreen;
    }
    if (model == SupportedDeviceModels.m120) {
      return FontAwesomeIcons.keyboard;
    }
    // 기본 아이콘 (기타 통신 장비)
    return FontAwesomeIcons.rss;
  }

  @override
  Widget build(BuildContext context) {
    // 전역 상태 관리자인 Provider로부터 장치 목록 데이터를 가져옵니다.
    final DeviceProvider provider = context.watch<DeviceProvider>();
    // 중앙 집중형 테마 설정을 가져옵니다.
    final ThemeData theme = Theme.of(context);

    // 좌표가 0,0 인 장치는 '미배치 장치'로, 그 외는 '도면 배치 장치'로 분리합니다.
    final List<DeviceModel> unplacedDevices = provider.list.where((device) {
      return device.posX == 0 && device.posY == 0;
    }).toList();

    final List<DeviceModel> placedDevices = provider.list.where((device) {
      return device.posX != 0 || device.posY != 0;
    }).toList();

    return Scaffold(
      // 도면 바깥쪽 빈 공간의 배경색 (미니멀하고 깔끔한 회색톤)
      backgroundColor: const Color(0xFFE5E7EB),

      // -----------------------------------------------------------------------
      // [핵심 레이아웃] Stack 위젯
      // Z-Index 개념을 사용하여 맨 바닥에 도면을 100% 크기로 깔고,
      // 그 위(Layer)에 헤더와 사이드바를 애니메이션과 함께 띄웁니다!
      // -----------------------------------------------------------------------
      body: Stack(
        children: [
          // 1층 (Layer 0): 도면 영역 (항상 화면 100%를 차지함)
          Positioned.fill(
            child: provider.isLoading
                ? Center(
              child: CircularProgressIndicator(color: theme.colorScheme.primary),
            )
                : _buildMapArea(placedDevices, provider, theme),
          ),

          // 2층 (Layer 1): 상단 플로팅 헤더
          // 전체화면 모드일 때는 위(top: -100)로 밀어서 부드럽게 숨깁니다.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutBack,
            top: _isFullScreen ? -100 : 20,
            left: 20,
            right: 20,
            child: _buildFloatingHeader(theme),
          ),

          // 3층 (Layer 2): 좌측 플로팅 사이드바 (미배치 리스트)
          // 전체화면이거나 사이드바를 접었을 때 좌측(left: -350)으로 밀어서 쏙 숨깁니다.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutBack,
            top: _isFullScreen ? -1000 : 100, // 헤더 아래에 위치
            bottom: _isFullScreen ? -1000 : 20,
            left: (_isSidebarOpen && !_isFullScreen) ? 20 : -350,
            child: _buildFloatingSidebar(unplacedDevices, provider, theme),
          ),

          // 4층 (Layer 3): 사이드바 열기/닫기 토글 버튼
          // 사이드바 패널의 바로 우측에 딱 붙어서 같이 움직이도록 설계했습니다.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutBack,
            top: _isFullScreen ? -100 : 100,
            left: (_isSidebarOpen && !_isFullScreen) ? 335 : 20,
            child: _buildSidebarToggleBtn(theme),
          ),

          // 5층 (Layer 4): 전체화면 종료 버튼 (전체화면 모드일 때만 우측 하단에 스르륵 나타남)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutBack,
            bottom: _isFullScreen ? 30 : -100,
            right: 30,
            child: FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  _isFullScreen = false;
                });
              },
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              elevation: 8,
              icon: const Icon(Icons.fullscreen_exit),
              label: const Text(
                "기본 화면 복귀",
                style: TextStyle(
                  fontFamily: AppTheme.fontPretendard,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [플로팅 헤더 패널] 공중에 떠 있는 둥근 카드(Card) 형태의 헤더
  /// ---------------------------------------------------------------------------
  Widget _buildFloatingHeader(ThemeData theme) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: theme.cardTheme.color?.withValues(alpha: 0.95), // 반투명 느낌 적용
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.layers_outlined, color: theme.colorScheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Text(
            "실시간 장치 관제 상황판",
            style: TextStyle(
                fontFamily: AppTheme.fontPretendard,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: AppTheme.dataColor(theme.brightness == Brightness.dark)
            ),
          ),
          const Spacer(),
          // 진정한 전체화면(Map Only) 실행 버튼
          Tooltip(
            message: "도면 100% 전체화면",
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isFullScreen = true;
                  _isSidebarOpen = false; // 전체화면 진입 시 사이드바도 같이 숨김
                });
              },
              icon: const Icon(Icons.fullscreen, size: 20),
              label: const Text(
                "도면 확장",
                style: TextStyle(
                  fontFamily: AppTheme.fontPretendard,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [플로팅 토글 버튼] 리스트뷰가 거슬릴 때 넣고 뺄 수 있는 손잡이
  /// ---------------------------------------------------------------------------
  Widget _buildSidebarToggleBtn(ThemeData theme) {
    return Tooltip(
      message: _isSidebarOpen ? "리스트 숨기기" : "미배치 장치 보기",
      child: InkWell(
        onTap: () {
          setState(() {
            _isSidebarOpen = !_isSidebarOpen;
          });
        },
        child: Container(
          width: 40,
          height: 50,
          decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(2, 2),
                )
              ],
              border: Border.all(color: theme.dividerTheme.color ?? Colors.grey.shade300)
          ),
          child: Icon(
            _isSidebarOpen ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            color: theme.colorScheme.primary,
            size: 28,
          ),
        ),
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [플로팅 사이드바] 도면 위를 침범하지 않고 둥둥 떠 있는 서랍장
  /// ---------------------------------------------------------------------------
  Widget _buildFloatingSidebar(List<DeviceModel> devices, DeviceProvider provider, ThemeData theme) {
    return Container(
      width: 300, // 사이드바 고정 넓이
      decoration: BoxDecoration(
        color: theme.cardTheme.color?.withValues(alpha: 0.95), // 도면이 살짝 비치는 고급스러운 효과
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 15,
            offset: const Offset(4, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 20, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    const Text(
                        "미배치 장치",
                        style: TextStyle(
                          fontFamily: AppTheme.fontPretendard,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          color: Colors.blueGrey,
                        )
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.danger,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "${devices.length}",
                        style: const TextStyle(
                          fontFamily: AppTheme.fontPretendard,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                    "장치를 드래그하여 배경 도면에 배치하세요.",
                    style: TextStyle(
                      fontFamily: AppTheme.fontPretendard,
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    )
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerTheme.color),
          Expanded(
            child: devices.isEmpty
                ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, size: 50, color: AppTheme.success.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    const Text(
                      "모든 장치가 도면에\n배치되었습니다.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        height: 1.5,
                      ),
                    )
                  ],
                )
            )
                : ListView.separated(
              itemCount: devices.length,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              // 가독성을 위해 화살표 함수 대신 블록 스타일 사용
              separatorBuilder: (BuildContext context, int index) {
                return const SizedBox(height: 10);
              },
              itemBuilder: (BuildContext context, int index) {
                final DeviceModel d = devices[index];

                return Draggable<DeviceModel>(
                  data: d,
                  feedback: Opacity(
                      opacity: 0.8,
                      child: _buildDeviceMarker(d, isDragging: true)
                  ),
                  childWhenDragging: Opacity(
                      opacity: 0.3,
                      child: _buildSidebarItem(d, theme)
                  ),
                  child: _buildSidebarItem(d, theme),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 사이드바 내부에 그려질 개별 장치 카드 아이템
  Widget _buildSidebarItem(DeviceModel d, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey.shade300, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle
            ),
            child: FaIcon(_getIcon(d.model), size: 16, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.name,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  d.ipAddress.isEmpty ? 'IP 미설정' : '${d.ipAddress}:${d.port}',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.drag_indicator, color: Colors.black26, size: 20),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// 메인 맵 영역 (도면 및 마커 렌더링)
  /// [최적화 적용] Positioned.fill 내부에서 화면 100%를 무조건 차지합니다.
  /// ---------------------------------------------------------------------------
  Widget _buildMapArea(List<DeviceModel> placed, DeviceProvider provider, ThemeData theme) {
    return InteractiveViewer(
      maxScale: 4.0,
      minScale: 0.3,
      // 화면 밖으로 마음껏 패닝(Panning) 할 수 있도록 여백을 아주 크게 줍니다.
      boundaryMargin: EdgeInsets.all(MediaQuery.of(context).size.width),
      constrained: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double mapWidth = constraints.maxWidth;
          final double mapHeight = constraints.maxHeight;

          return DragTarget<DeviceModel>(
            onAcceptWithDetails: (DragTargetDetails<DeviceModel> details) {
              final RenderBox box = _mapKey.currentContext!.findRenderObject() as RenderBox;
              final Offset localOffset = box.globalToLocal(details.offset) + const Offset(23, 23);

              // 장치가 놓인 위치(좌표)를 비율 단위로 계산하여 저장합니다.
              provider.handleSave(
                  d: details.data,
                  data: {
                    'pos_x': (localOffset.dx / mapWidth).clamp(0.0, 1.0),
                    'pos_y': (localOffset.dy / mapHeight).clamp(0.0, 1.0),
                  }
              );
            },
            builder: (BuildContext context, List<DeviceModel?> candidateData, List<dynamic> rejectedData) {
              return Container(
                key: _mapKey,
                width: mapWidth,
                height: mapHeight,
                decoration: const BoxDecoration(
                  color: Colors.white, // 도면 배경색
                  image: DecorationImage(
                    image: NetworkImage("https://img.freepik.com/free-vector/factory-interior-isometric-composition_1284-24151.jpg"),
                    fit: BoxFit.contain,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: placed.map((DeviceModel device) {
                    return Positioned(
                      left: (device.posX * mapWidth) - 23,
                      top: (device.posY * mapHeight) - 23,
                      child: Draggable<DeviceModel>(
                        data: device,
                        feedback: _buildDeviceMarker(device, isDragging: true),
                        childWhenDragging: const SizedBox.shrink(),
                        child: GestureDetector(
                          onTap: () {
                            _showDeviceDetails(context, device, provider, theme);
                          },
                          child: _buildDeviceMarker(device),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// 장치 마커 위젯 (통신 상태에 따른 시각적 피드백 제공)
  /// ---------------------------------------------------------------------------
  Widget _buildDeviceMarker(DeviceModel d, {bool isDragging = false}) {
    final bool isOnline = d.status.toLowerCase() == 'online';
    final Color markerColor = isOnline ? AppTheme.success : AppTheme.danger;

    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: markerColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: isDragging ? markerColor.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.3),
                  blurRadius: isDragging ? 15 : 6,
                  spreadRadius: isDragging ? 2 : 0,
                  offset: isDragging ? const Offset(0, 10) : const Offset(0, 3),
                )
              ],
            ),
            child: Center(
              child: FaIcon(_getIcon(d.model), color: Colors.white, size: 20),
            ),
          ),
          if (!isDragging) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
              ),
              child: Text(
                d.name,
                style: const TextStyle(
                  fontFamily: AppTheme.fontPretendard,
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [과감한 미니멀 UI 적용] 장치 상세 정보 및 실시간 로그 팝업창
  /// 어수선했던 7컬럼 구조와 큰 요약 박스를 완전히 제거하고,
  /// 좁은 공간에서도 핵심만 보이도록 리스트 형태로 압축했습니다.
  /// ---------------------------------------------------------------------------
  void _showDeviceDetails(BuildContext context, DeviceModel d, DeviceProvider provider, ThemeData theme) {
    final bool isOnline = d.status.toLowerCase() == 'online';
    final Color statusColor = isOnline ? AppTheme.success : AppTheme.danger;

    // [로컬 변수 이름 규칙 준수 및 정밀 파싱]
    Map<String, String> parseLog(String rawLog) {
      String time = "-";
      String type = "MSG";
      String ant = "-";
      String epc = "-";
      String tid = "-";
      String rssi = "-";
      String rawString = rawLog;

      try {
        final timeRegex = RegExp(r'^\[(\d{2}:\d{2}:\d{2})\]\s*');
        final timeMatch = timeRegex.firstMatch(rawLog);

        if (timeMatch != null) {
          time = timeMatch.group(1) ?? "-";
          rawString = rawLog.substring(timeMatch.end);
        }

        if (rawString.startsWith('🎯 [태그 인식]')) {
          type = 'TAG';
          String dataPart = rawString.replaceFirst('🎯 [태그 인식]', '').trim();
          List<String> parts = dataPart.split('|');

          for (var part in parts) {
            part = part.trim();
            if (part.startsWith('EPC:')) {
              epc = part.substring(4).trim();
            } else if (part.startsWith('Ant:')) {
              ant = part.substring(4).trim();
            } else if (part.startsWith('RSSI:')) {
              rssi = part.substring(5).trim();
            } else if (part.startsWith('TID:')) {
              tid = part.substring(4).trim();
            }
          }
          rawString = "";
        } else if (rawString.startsWith('<<< [SYS]')) {
          type = 'SYS';
          rawString = rawString.replaceFirst('<<< [SYS]', '').trim();
        } else if (rawString.startsWith('★★★ [방향 판별 완료]')) {
          type = 'DIR';
          rawString = rawString.replaceFirst('★★★ [방향 판별 완료]', '').trim();
        } else if ((rawString.startsWith('<==') && rawString.contains('Raw]')) || rawString.startsWith('<== [수신 RX]')) {
          // [버그 패치] IDE 스펠링 체커에서 특정 제조사명을 오타로 간주하지 않도록
          // 하드코딩된 특정 명칭을 빼고, 더 범용적인 문자열 체크 방식으로 리팩토링했습니다.
          type = 'RAW';
          rawString = rawString.replaceAll(RegExp(r'^<== \[[^\]]+\]\s*'), '').trim();
        } else if (rawString.startsWith('🔍') || rawString.startsWith('ℹ️')) {
          type = 'INFO';
        }
      } catch (e) {
        // 파싱 방어 코드
      }

      return {
        "time": time,
        "type": type,
        "ant": ant,
        "epc": epc,
        "tid": tid,
        "rssi": rssi,
        "raw": rawString.isEmpty && type != 'TAG' ? rawLog : rawString,
      };
    }

    showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return ChangeNotifierProvider<DeviceProvider>.value(
            value: provider,
            child: AlertDialog(
              backgroundColor: theme.scaffoldBackgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              title: Row(
                children: [
                  Icon(Icons.router, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      d.name,
                      style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isOnline ? "ONLINE" : "OFFLINE",
                      style: TextStyle(fontFamily: AppTheme.fontPretendard, color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
              content: SizedBox(
                // 기존 1200 ➔ 650 으로 대폭 축소하여 어수선함 제거
                width: 650,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),

                    // [변경] 무거웠던 박스형 요약 정보를 가벼운 칩(Chip) 형태로 전환
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMiniChip(Icons.memory, d.model, theme),
                        _buildMiniChip(Icons.lan, d.ipAddress.isEmpty ? 'IP 미설정' : '${d.ipAddress}:${d.port}', theme),
                        _buildMiniChip(Icons.label_important_outline, d.settings['usage_role'] ?? '상시감지', theme),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 터미널 헤더
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "실시간 패킷 모니터링",
                          style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14),
                        ),
                        TextButton.icon(
                          onPressed: () => provider.clearLogs(d.id),
                          icon: const Icon(Icons.delete_sweep, size: 16),
                          label: const Text("비우기", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.danger, padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 미니멀 터미널 컨테이너
                    Container(
                      height: 300, // 높이도 상황판에 맞춰 축소
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black87),
                      ),
                      child: Consumer<DeviceProvider>(
                        builder: (ctx, dynamicProvider, child) {
                          final List<String> logs = dynamicProvider.getLogs(d.id).reversed.toList();

                          if (logs.isEmpty) {
                            return const Center(
                              child: Text("수신 대기 중...", style: TextStyle(color: Colors.white38, fontSize: 13, fontFamily: AppTheme.fontPretendard)),
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            itemCount: logs.length,
                            separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 12),
                            itemBuilder: (ctx, idx) {
                              final Map<String, String> parsed = parseLog(logs[idx]);

                              // [가독성 높은 블록 스타일 적용 완료]
                              Color typeColor = Colors.grey;
                              if (parsed['type'] == 'TAG') {
                                typeColor = Colors.cyanAccent;
                              } else if (parsed['type'] == 'RAW') {
                                typeColor = Colors.amberAccent;
                              } else if (parsed['type'] == 'SYS') {
                                typeColor = Colors.pinkAccent;
                              } else if (parsed['type'] == 'DIR') {
                                typeColor = Colors.greenAccent;
                              } else if (parsed['type'] == 'INFO') {
                                typeColor = Colors.blueAccent;
                              }

                              // 여러 컬럼으로 나뉘던 것을 한 줄의 직관적인 텍스트로 합쳤습니다.
                              String displayData = "";
                              if (parsed['type'] == 'TAG') {
                                displayData = "[ANT:${parsed['ant']}] EPC: ${parsed['epc']} (RSSI: ${parsed['rssi']})";
                              } else {
                                displayData = parsed['raw'] ?? "";
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(width: 60, child: Text(parsed['time']!, style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'Courier New'))),
                                  SizedBox(
                                    width: 40,
                                    child: Text(parsed['type']!, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                  Expanded(
                                      child: Text(
                                          displayData,
                                          style: TextStyle(
                                            color: parsed['type'] == 'RAW' ? Colors.amberAccent : (parsed['type'] == 'DIR' ? Colors.greenAccent : Colors.white),
                                            fontSize: 12,
                                            fontFamily: parsed['type'] == 'RAW' ? 'Courier New' : AppTheme.fontPretendard,
                                            fontWeight: parsed['type'] == 'TAG' ? FontWeight.w600 : FontWeight.normal,
                                            height: 1.2,
                                          )
                                      )
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.layers_clear, size: 16),
                  label: const Text("도면에서 빼기", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                  onPressed: () {
                    provider.handleSave(d: d, data: {'pos_x': 0.0, 'pos_y': 0.0});
                    Navigator.pop(dialogContext);
                  },
                ),
                AppTheme.actionButton(
                  label: "닫기",
                  onPressed: () => Navigator.pop(dialogContext),
                  color: AppTheme.primary,
                ),
              ],
            ),
          );
        }
    );
  }

  /// 장치 정보 요약 박스 내부에 들어가는 미니 칩(Chip) 형태의 헬퍼 함수입니다.
  /// 공간을 크게 차지하던 기존 _buildInfoRow를 완전히 대체하여 미니멀리즘을 극대화합니다.
  Widget _buildMiniChip(IconData icon, String text, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.dividerTheme.color?.withValues(alpha: 0.1) ?? Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        ],
      ),
    );
  }
}