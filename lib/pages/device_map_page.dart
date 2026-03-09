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
  /// [완벽 개선 UI] 장치 상세 정보 및 실시간 로그 팝업창
  /// 새롭게 설계된 DeviceProvider의 규격(JSON 가공 완료 후 로깅)에 완벽 대응하여,
  /// 복잡한 정규식 없이 Provider가 던져준 마커를 기준으로 깔끔하게 분리하여 보여줍니다.
  /// ---------------------------------------------------------------------------
  void _showDeviceDetails(BuildContext context, DeviceModel d, DeviceProvider provider, ThemeData theme) {
    final bool isOnline = d.status.toLowerCase() == 'online';
    final Color statusColor = isOnline ? AppTheme.success : AppTheme.danger;

    // [로컬 변수 이름 규칙 준수]
    // 로컬 함수나 변수는 언더스코어(_)로 시작하지 않도록 수정하였습니다. (Dart 권장 사항)
    Map<String, String> parseLog(String rawLog) {
      String time = "-";
      String type = "MSG";
      String ant = "-";
      String epc = "-";
      String tid = "-";
      String rssi = "-";
      String rawString = rawLog;

      try {
        // 1. 시간 파싱 (Provider가 붙여준 "[HH:mm:ss] " 형식 캐치)
        final timeRegex = RegExp(r'^\[(\d{2}:\d{2}:\d{2})\]\s*');
        final timeMatch = timeRegex.firstMatch(rawLog);

        if (timeMatch != null) {
          time = timeMatch.group(1) ?? "-";
          rawString = rawLog.substring(timeMatch.end); // 시간 부분을 떼어낸 순수 메시지
        }

        // 2. 메시지 타입별 파싱 (Provider의 마커 규칙 적용)
        if (rawString.startsWith('🎯 [태그 인식]')) {
          type = 'TAG';
          // 예: "🎯 [태그 인식] EPC:E2001234 | Ant:1 | RSSI:-50"
          String dataPart = rawString.replaceFirst('🎯 [태그 인식]', '').trim();
          List<String> parts = dataPart.split('|');

          for (var part in parts) {
            part = part.trim();
            // [블록 스타일 준수] 모든 if-else 구문을 블록({ })으로 감싸 가독성을 높였습니다.
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
          // 태그 데이터는 표(Table)로 완벽하게 쪼개졌으므로 RAW 칸은 비워둡니다.
          rawString = "";

        } else if (rawString.startsWith('<<< [SYS]')) {
          type = 'SYS';
          rawString = rawString.replaceFirst('<<< [SYS]', '').trim();

        } else if (rawString.startsWith('★★★ [방향 판별 완료]')) {
          type = 'DIR'; // Direction (방향 판별)
          rawString = rawString.replaceFirst('★★★ [방향 판별 완료]', '').trim();

        } else if (rawString.startsWith('<== [IDRO900F Raw]') || rawString.startsWith('<== [수신 RX]')) {
          type = 'RAW';
          // "<== [수신 RX]" 같은 접두어만 제거하고 실제 통신 Hex 바이트를 표출합니다.
          rawString = rawString.replaceAll(RegExp(r'^<== \[[^\]]+\]\s*'), '').trim();

        } else if (rawString.startsWith('🔍') || rawString.startsWith('ℹ️')) {
          type = 'INFO';
        }
      } catch (e) {
        // 파싱에 실패하더라도 기존 원문을 살려 데이터 유실을 방지합니다 (안정성 원칙)
      }

      return {
        "time": time,
        "type": type,
        "ant": ant,
        "epc": epc,
        "tid": tid,
        "rssi": rssi,
        // 가공되어 빈값이 되었다면 냅두고, 파싱 안된 일반 로그라면 원본 텍스트를 출력합니다.
        "raw": rawString.isEmpty && type != 'TAG' ? rawLog : rawString,
      };
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        // 새로 열리는 팝업창(Route) 내부에서도 전역 Provider 상태를 바라볼 수 있도록 연결합니다.
        return ChangeNotifierProvider<DeviceProvider>.value(
          value: provider,
          child: AlertDialog(
            backgroundColor: theme.scaffoldBackgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
            ),
            title: const Text(
              "장치 상세 정보 및 제어",
              style: TextStyle(
                fontFamily: AppTheme.fontPretendard,
                fontWeight: FontWeight.bold,
                fontSize: 18.0,
              ),
            ),
            content: SizedBox(
              // 여러 컬럼과 원본(RAW) 데이터를 모두 표시하기 위해 팝업 너비를 충분히 크게 잡아줍니다.
              width: 1200,
              child: Column(
                mainAxisSize: MainAxisSize.min, // 내부 컨텐츠 크기만큼만 세로 공간을 차지하도록 설정
                children: [
                  // --- [섹션 A: 물리적 장치 정보 요약] ---
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardTheme.color,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.dividerTheme.color ?? Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow("물리적 모델", d.model),
                        const SizedBox(height: 8),
                        _buildInfoRow("IP 통신 주소", d.ipAddress.isEmpty ? '미설정' : '${d.ipAddress} : ${d.port}'),
                        const SizedBox(height: 8),
                        _buildInfoRow("운용 용도", d.settings['usage_role'] ?? '상시감지(출입/물류)'),
                        const SizedBox(height: 8),
                        _buildInfoRow("실시간 통신 상태", isOnline ? "ONLINE (정상 연결됨)" : "OFFLINE (연결 끊김)", valueColor: statusColor),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- [섹션 B: 실시간 터미널 로그 헤더] ---
                  Row(
                    children: [
                      const Icon(Icons.terminal, size: 18, color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      const Text(
                        "실시간 수신 패킷 (파싱 및 원본)",
                        style: TextStyle(
                          fontFamily: AppTheme.fontPretendard,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          provider.clearLogs(d.id);
                        },
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text(
                          "로그 비우기",
                          style: TextStyle(
                            fontFamily: AppTheme.fontPretendard,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                      )
                    ],
                  ),
                  const SizedBox(height: 6),

                  // --- [섹션 C: 실시간 터미널 테이블 영역] ---
                  Container(
                    height: 250, // 데이터를 볼 수 있는 높이 확보
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E), // 터미널 느낌의 검은색 배경
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // [컬럼 타이틀]
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF2D2D2D),
                            borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                          ),
                          child: const Row(
                              children: [
                                SizedBox(width: 70, child: Text("TIME", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold))),
                                SizedBox(width: 45, child: Text("TYPE", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold))),
                                SizedBox(width: 40, child: Text("ANT", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold))),
                                Expanded(flex: 3, child: Text("EPC", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text("TID", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold))),
                                SizedBox(width: 50, child: Text("RSSI", textAlign: TextAlign.right, style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold))),
                                SizedBox(width: 16), // 여백
                                Expanded(flex: 5, child: Text("RAW DATA (원본)", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold))),
                              ]
                          ),
                        ),

                        // [데이터 리스트]
                        Expanded(
                          child: Consumer<DeviceProvider>(
                            builder: (BuildContext ctx, DeviceProvider dynamicProvider, Widget? child) {
                              // 최신 로그가 맨 위로 오도록 뒤집습니다.
                              final List<String> logs = dynamicProvider.getLogs(d.id).reversed.toList();

                              if (logs.isEmpty) {
                                return const Center(
                                  child: Text(
                                    "수신된 패킷이 없습니다.",
                                    style: TextStyle(color: Colors.white38, fontSize: 12),
                                  ),
                                );
                              }

                              return ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                itemCount: logs.length,
                                separatorBuilder: (BuildContext context, int idx) {
                                  return Divider(color: Colors.white.withValues(alpha: 0.05), height: 1);
                                },
                                itemBuilder: (BuildContext context, int idx) {
                                  // 새로운 구조에 맞춰진 간결하고 정확한 데이터 파싱
                                  final Map<String, String> parsed = parseLog(logs[idx]);

                                  // 타입에 따른 뱃지 색상을 직관적으로 구분합니다.
                                  // [블록 스타일 준수]
                                  Color typeColor = Colors.grey;
                                  if (parsed['type'] == 'TAG') {
                                    typeColor = Colors.cyanAccent;
                                  } else if (parsed['type'] == 'RAW') {
                                    typeColor = Colors.amberAccent;
                                  } else if (parsed['type'] == 'SYS') {
                                    typeColor = Colors.pinkAccent;
                                  } else if (parsed['type'] == 'DIR') {
                                    typeColor = Colors.greenAccent; // 방향 판별 완료
                                  } else if (parsed['type'] == 'INFO') {
                                    typeColor = Colors.blueAccent;
                                  }

                                  // RSSI 수치에 따른 신호 강도 색상
                                  Color rssiColor = Colors.greenAccent;
                                  try {
                                    double rVal = double.parse(parsed['rssi']!);
                                    if (rVal < -80) {
                                      rssiColor = Colors.redAccent;
                                    } else if (rVal < -70) {
                                      rssiColor = Colors.orangeAccent;
                                    }
                                  } catch (_) {}

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(width: 70, child: Text(parsed['time']!, style: const TextStyle(color: Colors.white60, fontSize: 12, fontFamily: 'Courier New'))),

                                        SizedBox(
                                            width: 45,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                              decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                              child: Text(parsed['type']!, textAlign: TextAlign.center, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                            )
                                        ),

                                        SizedBox(width: 40, child: Text(parsed['ant']!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold))),

                                        Expanded(
                                            flex: 3,
                                            child: Padding(
                                              padding: const EdgeInsets.only(right: 8.0),
                                              child: Text(parsed['epc']!, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3)),
                                            )
                                        ),

                                        Expanded(
                                            flex: 2,
                                            child: Text(parsed['tid']!, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3))
                                        ),

                                        SizedBox(width: 50, child: Text(parsed['rssi']!, textAlign: TextAlign.right, style: TextStyle(color: rssiColor, fontSize: 12, fontWeight: FontWeight.bold))),

                                        const SizedBox(width: 16),

                                        // 통신 원본 데이터 및 시스템 메시지 출력
                                        Expanded(
                                            flex: 5,
                                            child: Text(
                                                parsed['raw']!,
                                                style: TextStyle(
                                                  // 타입에 따라 텍스트 색상을 약간 다르게 주어 가독성을 높입니다.
                                                    color: parsed['type'] == 'RAW' ? Colors.amberAccent : (parsed['type'] == 'DIR' ? Colors.greenAccent : Colors.white70),
                                                    fontSize: 11,
                                                    fontFamily: 'Courier New',
                                                    height: 1.3
                                                )
                                            )
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 3. 팝업창 하단 제어 버튼 영역
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.layers_clear, size: 18),
                label: const Text(
                  "도면에서 빼기",
                  style: TextStyle(
                    fontFamily: AppTheme.fontPretendard,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                onPressed: () {
                  // 도면 좌표를 초기화(0,0)하여 미배치 목록으로 돌려보냅니다.
                  provider.handleSave(d: d, data: {'pos_x': 0.0, 'pos_y': 0.0});
                  Navigator.pop(dialogContext); // 팝업 닫기
                },
              ),
              AppTheme.actionButton(
                label: "닫기",
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                color: AppTheme.primary,
              ),
            ],
          ),
        );
      },
    );
  }

  /// 장치 정보 요약 박스 내부에 들어가는 각 줄(Row)을 생성하는 헬퍼 함수입니다.
  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTheme.fontPretendard,
            color: Colors.grey,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTheme.fontPretendard,
            fontWeight: FontWeight.w900,
            fontSize: 14,
            // 별도로 지정된 색상이 없다면 테마 밝기(다크모드/라이트모드)에 맞춰 텍스트 색상을 설정합니다.
            color: valueColor ?? AppTheme.dataColor(Theme.of(context).brightness == Brightness.dark),
          ),
        ),
      ],
    );
  }
}