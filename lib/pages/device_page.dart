import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

// 🔥 [크롬 에러 완벽 해결] 직접 임포트하던 원본 패키지를 삭제하고,
// 대표님께서 미리 만들어두신 안전한 래퍼(Stub) 클래스만 임포트합니다!
import '../services/scanner/app_serial_port.dart';

import '../models/device_model.dart';
import '../providers/device_provider.dart'; // 통신 로직 전담 DataModule
import '../services/device_protocols.dart'; // SupportedDeviceModels 참조를 위해 필수
import '../theme/app_theme.dart'; // 중앙 집중형 테마 임포트

/// ===========================================================================
/// [UI] 장치 관리 페이지 (DevicePage)
/// RFID 리더기, 바코드 스캐너, 프린터 등 하드웨어 장치들을 통합 관리합니다.
/// 미니멀리즘과 키오스크 디자인 철학을 적용하여 직관적으로 구성했습니다.
/// C++Builder의 DataModule 역할을 하는 DeviceProvider와 연결되어 상태를 갱신합니다.
/// ===========================================================================
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
  State<DevicePage> createState() {
    return _DevicePageState();
  }
}

class _DevicePageState extends State<DevicePage> {
  // ---------------------------------------------------------------------------
  // [상태 변수 선언부]
  // ---------------------------------------------------------------------------
  final TextEditingController _searchController = TextEditingController();
  String _currentQuery = "";

  String _activeMetricFilter = "전체"; // 필터링 상태 (전체, 온라인, 오프라인)

  final Set<String> _selectedItemIds = {}; // 다중 선택된 장치들의 ID 목록
  bool _isSelectionMode = false; // 다중 선택 모드 활성화 여부
  bool _isFullScreenLoading = false; // 일괄 작업 시 화면 전체 로딩 표시

  // 레이아웃 고정 치수 (미니멀 디자인 규격 적용)
  static const double _colImgSize = 70.0; // 목록의 장치 썸네일 크기
  static const double _colActionWidth = 350.0; // 우측 액션 버튼 영역 너비

  @override
  void initState() {
    super.initState();
    // 부모로부터 전달받은 초기 검색어를 텍스트 컨트롤러와 상태에 적용
    _currentQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
  }

  @override
  void dispose() {
    // 폼이 닫힐 때 메모리 누수를 방지하기 위해 컨트롤러 해제
    _searchController.dispose();
    super.dispose();
  }

  /// 모델명에 따라 적절한 FontAwesome 아이콘을 반환합니다.
  IconData _getDeviceIcon(String model) {
    if (model.contains('PRINTER')) {
      return FontAwesomeIcons.print;
    }
    if (model.contains('SCANNER') || model.contains('RS232')) {
      return FontAwesomeIcons.barcode;
    }
    return FontAwesomeIcons.rss; // 기본값은 RFID 리더기 아이콘
  }

  /// 장치 상태에 따라 테마에 맞는 색상을 반환합니다.
  Color _getStatusColor(String status) {
    if (status.toLowerCase() == 'online') {
      return AppTheme.success; // 초록색 (연결됨)
    }
    if (status.toLowerCase() == 'offline') {
      return AppTheme.danger; // 빨간색 (끊김)
    }
    return Colors.grey; // 알 수 없는 상태
  }

  /// 전체 장치 목록에서 전체, 온라인, 오프라인 장치 수를 계산합니다.
  Map<String, int> _calculateMetrics(List<DeviceModel> list) {
    int onlineCount = 0;
    int offlineCount = 0;

    for (final d in list) {
      if (d.status.toLowerCase() == 'online') {
        onlineCount++;
      } else {
        offlineCount++;
      }
    }
    return {
      'total': list.length,
      'online': onlineCount,
      'offline': offlineCount,
    };
  }

  /// ===========================================================================
  /// [지능형 로그 통합 파서]
  /// 터미널 창과 동작 테스트 창 양쪽에서 동일하게 패킷을 예쁘게 파싱하기 위해
  /// 클래스 공용 메서드로 작성되었습니다. Provider가 던져주는 JSON 브릿지를 해독합니다.
  /// ===========================================================================
  Map<String, String> _parseLogData(String rawLog) {
    String time = "-";
    String type = "INFO";
    String ant = "-";
    String epc = "-";
    String tid = "-";
    String rssi = "-";
    String rawString = rawLog;

    try {
      // 시간 추출 (예: [14:22:33])
      final timeRegex = RegExp(r'^\[(\d{2}:\d{2}:\d{2})\]\s*');
      final timeMatch = timeRegex.firstMatch(rawString);

      if (timeMatch != null) {
        time = timeMatch.group(1) ?? "-";
        rawString = rawString.substring(timeMatch.end);
      }

      // 불필요한 특수문자 제거
      rawString = rawString.replaceAll(RegExp(r'^[ℹ️🔍🎯★<=\?\s]+'), '').trim();

      // [핵심 변경] Provider가 만들어준 JSON 브릿지 문자열 해독 (태그 데이터)
      if (rawString.contains('JSON:{')) {
        type = 'TAG';
        final int jsonStart = rawString.indexOf('JSON:{') + 5;
        final String jsonPart = rawString.substring(jsonStart);

        // 정규식으로 안전하게 추출
        final epcMatch = RegExp(r'"epc"\s*:\s*"([^"]+)"').firstMatch(jsonPart);
        final antMatch = RegExp(r'"ant"\s*:\s*"?(\d+)"?').firstMatch(jsonPart);
        final rssiMatch = RegExp(r'"rssi"\s*:\s*"([^"]+)"').firstMatch(jsonPart);
        final tidMatch = RegExp(r'"tid"\s*:\s*"([^"]+)"').firstMatch(jsonPart);

        if (epcMatch != null) {
          epc = epcMatch.group(1)!;
        }
        if (antMatch != null) {
          ant = antMatch.group(1)!;
        }
        if (rssiMatch != null && rssiMatch.group(1)! != "-") {
          rssi = rssiMatch.group(1)!;
        }
        if (tidMatch != null) {
          tid = tidMatch.group(1)!;
        }
        rawString = "EPC Data Received";
      }
      else {
        // 일반 시스템 로그나 RAW 데이터 판별
        if (rawString.contains('[SYS]')) {
          type = 'SYS';
          rawString = rawString.replaceAll('[SYS]', '').trim();
        } else if (rawString.contains('방향 판별')) {
          type = 'DIR';
        } else if (rawString.contains('Raw') || rawString.contains('수신') || rawString.contains('프레임')) {
          type = 'RAW';
        }
      }
    } catch (e) {
      debugPrint("로그 파싱 오류: $e");
    }

    return {
      "time": time,
      "type": type,
      "ant": ant,
      "epc": epc,
      "tid": tid,
      "rssi": rssi,
      "raw": rawString,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Provider를 통해 장치 목록 데이터를 가져옵니다. (DataModule 감시)
    final provider = Provider.of<DeviceProvider>(context);
    final theme = Theme.of(context);
    final metrics = _calculateMetrics(provider.list);

    // 검색어 및 필터 조건에 따라 화면에 표시할 리스트를 걸러냅니다.
    final List<DeviceModel> filteredList = provider.list.where((d) {
      final String q = _currentQuery.toLowerCase();
      bool matchesSearch = d.name.toLowerCase().contains(q) ||
          d.ipAddress.contains(q) ||
          d.model.toLowerCase().contains(q);

      if (!matchesSearch) {
        return false;
      }

      if (_activeMetricFilter == "전체") {
        return true;
      }
      if (_activeMetricFilter == "온라인(연결됨)" && d.status.toLowerCase() == 'online') {
        return true;
      }
      if (_activeMetricFilter == "오프라인(끊김)" && d.status.toLowerCase() != 'online') {
        return true;
      }

      return false;
    }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // 전체 세로 레이아웃 구성
          Column(
            children: [
              _buildDashboard(metrics, theme), // 상단 요약 카드 (대시보드)
              Divider(height: 1, color: theme.dividerTheme.color),
              _buildHeader(provider, theme), // 검색창 및 액션 버튼
              const SizedBox(height: 16),
              // 장치 목록 출력 (로딩 중이면 스피너 표시)
              Expanded(
                child: provider.isLoading
                    ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                    : _buildListView(filteredList, provider, theme),
              ),
              const SizedBox(height: 20),
            ],
          ),

          // 일괄 삭제/초기화 등 무거운 작업 시 사용자의 조작을 막는 풀스크린 로딩 오버레이
          if (_isFullScreenLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.1),
              child: Center(
                child: Card(
                  elevation: 10,
                  color: theme.cardTheme.color,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 50, vertical: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.danger, strokeWidth: 5),
                        SizedBox(height: 25),
                        Text(
                          "시스템을 안전하게 제어 중입니다...\n(통신 해제 및 데이터 처리)",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 상단 대시보드 위젯 (PC/모바일에 따라 레이아웃 변경)
  Widget _buildDashboard(Map<String, int> m, ThemeData theme) {
    if (widget.isMobile) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: theme.scaffoldBackgroundColor,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildStatTile("등록된 장치", m['total']!, Icons.memory, Colors.blueGrey, theme, filterKey: "전체")),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatTile("온라인(연결됨)", m['online']!, Icons.wifi, AppTheme.success, theme, filterKey: "온라인(연결됨)")),
                const SizedBox(width: 12),
                Expanded(child: _buildStatTile("오프라인(끊김)", m['offline']!, Icons.wifi_off, AppTheme.danger, theme, filterKey: "오프라인(끊김)")),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: theme.scaffoldBackgroundColor,
      child: Row(
        children: [
          Expanded(child: _buildStatTile("등록된 장치", m['total']!, Icons.memory, Colors.blueGrey, theme, filterKey: "전체")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("온라인(연결됨)", m['online']!, Icons.wifi, AppTheme.success, theme, filterKey: "온라인(연결됨)")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("오프라인(끊김)", m['offline']!, Icons.wifi_off, AppTheme.danger, theme, filterKey: "오프라인(끊김)")),
        ],
      ),
    );
  }

  /// 대시보드의 개별 타일 (클릭 시 목록 필터링 기능 포함)
  Widget _buildStatTile(String label, int val, IconData icon, Color color, ThemeData theme, {required String filterKey}) {
    final bool isSelected = _activeMetricFilter == filterKey;
    final bool isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        setState(() {
          _activeMetricFilter = _activeMetricFilter == filterKey ? "전체" : filterKey;
          _selectedItemIds.clear(); // 필터 변경 시 다중 선택 초기화
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: isDark ? 0.15 : 0.08) : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.4), width: isSelected ? 3.0 : 1.8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  Text('$val', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 22, fontWeight: FontWeight.w900, color: color), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 헤더 영역 (다중선택 버튼, 등록 버튼, 통합 검색창)
  Widget _buildHeader(DeviceProvider provider, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: widget.isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildActionIconButton(Icons.refresh, "새로고침", () {
                      provider.fetchData();
                    }, theme),
                    _buildActionIconButton(
                      _isSelectionMode ? Icons.close_fullscreen_rounded : Icons.checklist_rtl_rounded,
                      _isSelectionMode ? "다중 선택 끄기" : "다중 선택 켜기",
                          () {
                        setState(() {
                          _isSelectionMode = !_isSelectionMode;
                          if (!_isSelectionMode) {
                            _selectedItemIds.clear();
                          }
                        });
                      },
                      theme,
                      color: _isSelectionMode ? AppTheme.primary : null,
                    ),
                    _buildActionIconButton(Icons.delete_sweep_outlined, "전체 초기화", () {
                      _showResetConfirmationDialog(provider, theme);
                    }, theme, color: AppTheme.danger),

                    _buildActionIconButton(Icons.add_to_queue_rounded, "신규 장치 등록", () {
                      _showForm(context, provider, null);
                    }, theme, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 키오스크 스타일의 큼직한 통합 검색창
          TextField(
            controller: _searchController,
            onChanged: (val) {
              setState(() {
                _currentQuery = val;
              });
            },
            style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
            decoration: AppTheme.inputDecoration(label: "장치명, 모델, IP 주소 통합 검색...", context: context, prefixIcon: Icons.search),
          ),
        ],
      ),
    );
  }

  /// 원형 액션 버튼을 생성하는 헬퍼 함수
  Widget _buildActionIconButton(IconData icon, String tip, VoidCallback onTap, ThemeData theme, {Color? color}) {
    final Color iconColor = color ?? theme.iconTheme.color ?? Colors.grey.shade600;

    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconColor.withValues(alpha: 0.08),
            border: Border.all(color: iconColor.withValues(alpha: 0.15), width: 1.5),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
      ),
    );
  }

  /// 메인 장치 목록 뷰 구성 (리스트뷰)
  Widget _buildListView(List<DeviceModel> list, DeviceProvider provider, ThemeData theme) {
    if (list.isEmpty) {
      return Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.router_outlined, size: 80, color: Colors.black12),
                const SizedBox(height: 16),
                const Text("등록된 장치가 없습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 18))
              ]
          )
      );
    }

    final bool isAllSelected = list.isNotEmpty && list.every((d) {
      return _selectedItemIds.contains(d.id);
    });

    return Column(
      children: [
        // 상단 다중 선택 제어 패널 (선택 모드일 때만 내려옵니다)
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _isSelectionMode
              ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text('${_selectedItemIds.length}개 선택됨', style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.sensors_off, size: 18),
                    label: const Text("일괄 통신 해제", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning, foregroundColor: Colors.white, elevation: 0),
                    onPressed: () {
                      _handleBulkDisconnect(provider, theme);
                    },
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text("일괄 삭제", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white, elevation: 0),
                    onPressed: () {
                      _confirmBulkDelete(provider, theme);
                    },
                  ),
                  const SizedBox(width: 16),
                  Container(width: 1, height: 24, color: theme.dividerTheme.color),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all, size: 18),
                    label: Text(isAllSelected ? "선택 해제" : "전체 선택", style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isAllSelected ? Colors.grey : AppTheme.primary,
                      side: BorderSide(color: isAllSelected ? Colors.grey.withValues(alpha: 0.5) : AppTheme.primary.withValues(alpha: 0.5)),
                    ),
                    onPressed: () {
                      setState(() {
                        if (isAllSelected) {
                          _selectedItemIds.clear();
                        } else {
                          for (final d in list) {
                            _selectedItemIds.add(d.id);
                          }
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          )
              : Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('총 ${list.length}개 장치', style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13)),
          ),
        ),

        // 실제 리스트 뷰 영역
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 20.0),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: list.length,
              separatorBuilder: (BuildContext context, int index) {
                return const SizedBox(height: 12);
              },
              itemBuilder: (BuildContext ctx, int idx) {
                final DeviceModel item = list[idx];
                final Color statusColor = _getStatusColor(item.status);
                final bool isSelected = _selectedItemIds.contains(item.id);

                return Row(
                  children: [
                    // 좌측 체크박스 영역 (선택 모드일 때만 나타납니다)
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      alignment: Alignment.centerLeft,
                      child: _isSelectionMode
                          ? Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedItemIds.remove(item.id);
                              } else {
                                _selectedItemIds.add(item.id);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? AppTheme.primary : Colors.transparent,
                                border: Border.all(
                                  color: isSelected ? AppTheme.primary : Colors.grey.withValues(alpha: 0.5),
                                  width: 2,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(
                                  Icons.check,
                                  size: 16,
                                  color: isSelected ? Colors.white : Colors.transparent,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                          : const SizedBox.shrink(),
                    ),

                    // 아이템 본체 카드
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          if (_isSelectionMode) {
                            setState(() {
                              if (isSelected) {
                                _selectedItemIds.remove(item.id);
                              } else {
                                _selectedItemIds.add(item.id);
                              }
                            });
                          } else {
                            // 일반 모드에서는 클릭 시 수정 폼 오픈
                            _showForm(context, provider, item);
                          }
                        },
                        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: AppTheme.listItemDecoration(context, isSelected: isSelected, statusColor: statusColor),
                          child: widget.isMobile
                              ? _buildMobileListItem(item, provider, statusColor, theme)
                              : _buildDesktopListItem(item, provider, statusColor, theme),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 데스크탑(PC/태블릿) 환경의 가로 배치 리스트 아이템
  Widget _buildDesktopListItem(DeviceModel item, DeviceProvider provider, Color statusColor, ThemeData theme) {
    bool isOnline = item.status.toLowerCase() == 'online';
    String usageText = item.settings['usage_role'] ?? '상시감지(출입/물류)';

    return Row(
      children: [
        _buildDeviceThumbnail(item, theme, size: _colImgSize),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(item.name, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 19)),
                  const SizedBox(width: 12),
                  _buildStatusBadge(item.status, statusColor),
                  if (!item.isActive) ...[
                    const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18)),
                  ]
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 20, runSpacing: 8,
                children: [
                  _buildKeyValue("모델 (제조사)", item.model, context),
                  _buildKeyValue("IP 주소/포트명", item.ipAddress, context),
                  _buildKeyValue("연결 포트/속도", item.port.toString(), context),
                  _buildKeyValue("운용 용도", usageText, context),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          width: _colActionWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildCircleAction(Icons.terminal, Colors.teal, "실시간 로그 보기", () {
                _showTerminalDialog(context, item.id, provider, item);
              }),
              const SizedBox(width: 12),

              _buildCircleAction(Icons.science, Colors.deepPurpleAccent, "장치 동작 테스트 (읽기/쓰기)", () {
                _showDeviceTestDialog(context, provider, item);
              }),
              const SizedBox(width: 12),

              if (isOnline) ...[
                _buildCircleAction(Icons.tune, Colors.blueAccent, "출력(파워) 제어", () {
                  _showPowerControlDialog(context, provider, item);
                }),
                const SizedBox(width: 12),
              ],

              // 연결 / 연결해제 버튼
              SizedBox(
                width: 100,
                child: isOnline
                    ? OutlinedButton(
                  onPressed: () async {
                    // [OS 예외 방어 코드] 메인 리스트에서 통신을 끊을 때도 반드시 읽기 스레드를 중지하고 대기합니다.
                    try { provider.stopDeviceRead(item.id); } catch(_) {}
                    await Future.delayed(const Duration(milliseconds: 300));
                    provider.disconnectDevice(item.id);
                  },
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: const BorderSide(color: AppTheme.danger),
                      padding: const EdgeInsets.symmetric(vertical: 12)
                  ),
                  child: const Text("연결 해제", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                )
                    : ElevatedButton(
                  onPressed: () {
                    provider.connectDevice(item);
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12)
                  ),
                  child: const Text("장치 연결", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () {
                _confirmDelete(context, provider, item);
              }),
            ],
          ),
        ),
      ],
    );
  }

  /// 모바일 환경의 세로 배치 리스트 아이템
  Widget _buildMobileListItem(DeviceModel item, DeviceProvider provider, Color statusColor, ThemeData theme) {
    bool isOnline = item.status.toLowerCase() == 'online';
    String usageText = item.settings['usage_role'] ?? '상시감지(출입/물류)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDeviceThumbnail(item, theme, size: _colImgSize),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                          child: Text(item.name,
                            style: AppTheme.itemValueStyle(context).copyWith(fontSize: 19),
                            overflow: TextOverflow.ellipsis,
                          )
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(item.status, statusColor),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(item.model, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16, runSpacing: 8,
          children: [
            _buildKeyValue("IP 주소/포트명", item.ipAddress, context),
            _buildKeyValue("연결 포트/속도", item.port.toString(), context),
            _buildKeyValue("운용 용도", usageText, context),
          ],
        ),
        const SizedBox(height: 16),
        Divider(color: theme.dividerTheme.color?.withValues(alpha: 0.5)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildCircleAction(Icons.terminal, Colors.teal, "로그 보기", () {
              _showTerminalDialog(context, item.id, provider, item);
            }),

            _buildCircleAction(Icons.science, Colors.deepPurpleAccent, "장치 테스트", () {
              _showDeviceTestDialog(context, provider, item);
            }),

            if (isOnline) ...[
              _buildCircleAction(Icons.tune, Colors.blueAccent, "출력 제어", () {
                _showPowerControlDialog(context, provider, item);
              }),
            ],

            Expanded(
              child: isOnline
                  ? OutlinedButton(
                onPressed: () async {
                  // [OS 예외 방어 코드] 모바일 화면에서도 연결 해제 시 안전 장치를 가동합니다.
                  try { provider.stopDeviceRead(item.id); } catch(_) {}
                  await Future.delayed(const Duration(milliseconds: 300));
                  provider.disconnectDevice(item.id);
                },
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    padding: const EdgeInsets.symmetric(vertical: 12)
                ),
                child: const Text("연결 해제", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
              )
                  : ElevatedButton(
                onPressed: () {
                  provider.connectDevice(item);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12)
                ),
                child: const Text("장치 연결", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () {
              _confirmDelete(context, provider, item);
            }),
          ],
        ),
      ],
    );
  }

  /// ===========================================================================
  /// [장치 테스트 다이얼로그]
  /// 읽기(Read)와 쓰기(Write)를 테스트하는 핵심 화면입니다.
  /// 윈도우 OS 핸들 충돌 방지를 위해 읽기 스레드를 꼼꼼히 관리합니다.
  /// ===========================================================================
  void _showDeviceTestDialog(BuildContext context, DeviceProvider provider, DeviceModel d) {
    final theme = Theme.of(context);
    final TextEditingController writeCtrl = TextEditingController();
    bool isWriting = false;
    bool isHexMode = false;
    bool isReading = false; // [추가] 현재 읽기(스캔)가 진행 중인지 상태를 추적합니다.

    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          // Provider의 변경사항을 다이얼로그 내부에서도 즉시 감지하기 위해 다시 주입
          return ChangeNotifierProvider<DeviceProvider>.value(
            value: provider,
            child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setDialogState) {
                  // 최신 장치 상태 추적
                  DeviceModel currentDevice = provider.list.firstWhere((element) {
                    return element.id == d.id;
                  }, orElse: () {
                    return d;
                  });
                  bool isOnline = currentDevice.status.toLowerCase() == 'online';

                  return AlertDialog(
                      title: AppTheme.dialogTitle('${currentDevice.name} 동작 제어', Icons.science, color: Colors.deepPurpleAccent),
                      content: SizedBox(
                          width: 800,
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 연결 상태 패널
                                Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                        color: isOnline ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.danger.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: isOnline ? AppTheme.success.withValues(alpha: 0.3) : AppTheme.danger.withValues(alpha: 0.3))
                                    ),
                                    child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                              children: [
                                                Icon(isOnline ? Icons.wifi : Icons.wifi_off, color: isOnline ? AppTheme.success : AppTheme.danger),
                                                const SizedBox(width: 8),
                                                Text(
                                                    isOnline ? "장치가 온라인 상태입니다 (명령 전송 가능)" : "장치가 오프라인입니다. 먼저 연결하세요.",
                                                    style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: isOnline ? AppTheme.success : AppTheme.danger)
                                                ),
                                              ]
                                          ),
                                          ElevatedButton(
                                            onPressed: () async {
                                              if (isOnline) {
                                                // [OS 예외 방어 코드]
                                                // 강제로 포트를 닫으면 C/C++ 네이티브 레벨에서 Access Violation이나 핸들 예외가 터지므로,
                                                // 연결을 끊기 전에 읽기 스레드를 중단하고 OS 락이 풀릴 시간을 확보합니다.
                                                if (isReading) {
                                                  setDialogState(() { isReading = false; });
                                                  try { provider.stopDeviceRead(currentDevice.id); } catch(_) {}
                                                  await Future.delayed(const Duration(milliseconds: 300)); // OS 포트 락 해제 대기 (Sleep)
                                                }
                                                provider.disconnectDevice(currentDevice.id);
                                              } else {
                                                provider.connectDevice(currentDevice);
                                              }

                                              // 연결/해제 후 상태 업데이트를 위해 지연 갱신
                                              Future.delayed(const Duration(milliseconds: 1000), () {
                                                if (ctx.mounted) {
                                                  setDialogState(() {});
                                                }
                                              });
                                            },
                                            style: ElevatedButton.styleFrom(backgroundColor: isOnline ? AppTheme.danger : AppTheme.primary, foregroundColor: Colors.white),
                                            child: Text(isOnline ? "통신 끊기" : "장치 연결 시도", style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                                          )
                                        ]
                                    )
                                ),
                                const SizedBox(height: 24),

                                // [쓰기 영역] 태그 Write
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("📝 데이터 기록 (Tag Write)", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 16)),
                                    ToggleButtons(
                                      constraints: const BoxConstraints(minHeight: 32, minWidth: 100),
                                      borderRadius: BorderRadius.circular(8),
                                      isSelected: [!isHexMode, isHexMode],
                                      onPressed: (int index) {
                                        setDialogState(() {
                                          isHexMode = index == 1;
                                        });
                                      },
                                      children: const [
                                        Text("일반 문자(ASCII)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        Text("헥사값(HEX)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                    children: [
                                      Expanded(
                                          child: TextField(
                                            controller: writeCtrl,
                                            enabled: isOnline && !isWriting,
                                            decoration: AppTheme.inputDecoration(
                                                label: isHexMode ? "헥사값 입력 (예: 313233...)" : "일반 문자 입력 (예: ITEM01...)",
                                                context: context,
                                                prefixIcon: isHexMode ? Icons.code : Icons.text_fields
                                            ),
                                            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                                          )
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                          height: 56,
                                          child: ElevatedButton.icon(
                                            onPressed: (!isOnline || isWriting) ? null : () async {
                                              if (writeCtrl.text.isEmpty) {
                                                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("기록할 데이터를 입력해주세요.", style: TextStyle(fontFamily: AppTheme.fontPretendard))));
                                                return;
                                              }

                                              setDialogState(() {
                                                isWriting = true;
                                              });

                                              bool ok = await provider.writeTagData(
                                                  currentDevice.id,
                                                  writeCtrl.text.trim(),
                                                  isHexMode: isHexMode
                                              );

                                              if (!ctx.mounted) return;

                                              setDialogState(() {
                                                isWriting = false;
                                              });
                                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(ok ? "기록 명령 전송 성공!" : "기록 실패 (로그 참조)", style: const TextStyle(fontFamily: AppTheme.fontPretendard))));
                                            },
                                            icon: isWriting
                                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                : const Icon(Icons.nfc),
                                            label: const Text("태그에 쓰기 발사", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                          )
                                      )
                                    ]
                                ),
                                const SizedBox(height: 24),

                                // [읽기 영역] 미니 터미널
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("🔍 실시간 읽기 로그 (Mini Terminal)", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 16)),
                                    Row(
                                      children: [
                                        // [핵심 변경] 단일 스캔 버튼을 '시작/중단' (Start/Stop) 토글 구조로 변경했습니다.
                                        ElevatedButton.icon(
                                          onPressed: !isOnline ? null : () async {
                                            if (isReading) {
                                              // 스캔 중지
                                              setDialogState(() { isReading = false; });
                                              try {
                                                provider.stopDeviceRead(currentDevice.id);
                                              } catch (e) {
                                                debugPrint("읽기 중단 에러: $e");
                                              }
                                            } else {
                                              // 스캔 시작
                                              setDialogState(() { isReading = true; });
                                              try {
                                                provider.triggerDeviceRead(currentDevice.id);
                                              } catch (e) {
                                                debugPrint("읽기 시작 에러: $e");
                                              }
                                            }
                                          },
                                          icon: Icon(isReading ? Icons.stop_circle : Icons.sensors, size: 16),
                                          label: Text(isReading ? "읽기 중단 (Stop)" : "연속 읽기 (Scan)", style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            // 동작 중일 때는 경고색(노란색)으로 바꾸어 사용자에게 중지해야 함을 인지시킵니다.
                                              backgroundColor: isReading ? AppTheme.warning : Colors.teal,
                                              foregroundColor: Colors.white,
                                              elevation: 0
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        TextButton.icon(
                                          onPressed: () {
                                            provider.clearLogs(currentDevice.id);
                                          },
                                          icon: const Icon(Icons.delete_outline, size: 16),
                                          label: const Text("로그 지우기", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 12)),
                                          style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                                        ),
                                      ],
                                    )
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // 콘솔 느낌의 로그 뷰어
                                Container(
                                    height: 220,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E1E1E),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.black87, width: 2),
                                    ),
                                    child: Consumer<DeviceProvider>(
                                        builder: (BuildContext consumerCtx, DeviceProvider dynamicProvider, Widget? child) {
                                          final logs = dynamicProvider.getLogs(currentDevice.id).reversed.toList();

                                          if (logs.isEmpty) {
                                            return const Center(child: Text("수신 대기 중... (패킷 없음)", style: TextStyle(color: Colors.white38, fontFamily: AppTheme.fontPretendard)));
                                          }

                                          return ListView.separated(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              itemCount: logs.length,
                                              separatorBuilder: (BuildContext context, int index) {
                                                return Divider(color: Colors.white.withValues(alpha: 0.05), height: 1);
                                              },
                                              itemBuilder: (BuildContext context, int idx) {
                                                final Map<String, String> parsed = _parseLogData(logs[idx]);

                                                Color typeColor = Colors.grey;
                                                if (parsed['type'] == 'TAG') {
                                                  typeColor = Colors.cyanAccent;
                                                } else if (parsed['type'] == 'RAW') {
                                                  typeColor = Colors.amberAccent;
                                                } else if (parsed['type'] == 'SYS') {
                                                  typeColor = Colors.pinkAccent;
                                                } else if (parsed['type'] == 'DIR') {
                                                  typeColor = Colors.greenAccent;
                                                }

                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      SizedBox(width: 60, child: Text(parsed['time']!, style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white60, fontSize: 11))),
                                                      SizedBox(
                                                          width: 40,
                                                          child: Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                                            decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                                            child: Text(parsed['type']!, textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: typeColor, fontSize: 9, fontWeight: FontWeight.bold)),
                                                          )
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                          child: Text(
                                                              parsed['type'] == 'TAG' ? "EPC: ${parsed['epc']} (Ant: ${parsed['ant']})" : parsed['raw']!,
                                                              style: TextStyle(
                                                                  fontFamily: AppTheme.fontPretendard,
                                                                  color: parsed['type'] == 'RAW' ? Colors.amberAccent : (parsed['type'] == 'TAG' ? Colors.white : Colors.white70),
                                                                  fontSize: 12,
                                                                  fontWeight: parsed['type'] == 'TAG' ? FontWeight.bold : FontWeight.normal
                                                              )
                                                          )
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }
                                          );
                                        }
                                    )
                                )
                              ]
                          )
                      ),
                      actions: [
                        AppTheme.actionButton(
                            label: "닫기",
                            color: Colors.transparent,
                            textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            onPressed: () {
                              // 폼을 닫을 때도 안전을 위해 스캔 중지 명령을 한번 더 날립니다.
                              if (isReading) {
                                try { provider.stopDeviceRead(currentDevice.id); } catch(_) {}
                              }
                              Navigator.pop(ctx);
                            }
                        )
                      ]
                  );
                }
            ),
          );
        }
    );
  }

  /// ===========================================================================
  /// [터미널 다이얼로그]
  /// 대용량 패킷을 상세 표 형태로 실시간 모니터링합니다.
  /// ===========================================================================
  void _showTerminalDialog(BuildContext context, String deviceId, DeviceProvider provider, DeviceModel d) {
    final theme = Theme.of(context);

    showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return ChangeNotifierProvider<DeviceProvider>.value(
            value: provider,
            child: AlertDialog(
              title: AppTheme.dialogTitle('${d.name} 실시간 패킷 터미널', Icons.terminal, color: Colors.teal),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              content: SizedBox(
                width: 1200,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "실시간 수신 데이터 파싱 결과 (최대 100건)",
                          style: TextStyle(
                              fontFamily: AppTheme.fontPretendard,
                              fontWeight: AppTheme.weightMenu,
                              color: Colors.blueGrey,
                              fontSize: 14
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            provider.clearLogs(deviceId);
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text("터미널 창 비우기", style: TextStyle(fontFamily: AppTheme.fontPretendard)),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),

                    Container(
                      height: 350,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black87, width: 2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2D2D2D),
                              borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
                            ),
                            child: const Row(
                                children: [
                                  SizedBox(width: 70, child: Text("TIME", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 45, child: Text("TYPE", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 40, child: Text("ANT", textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                  Expanded(flex: 3, child: Text("EPC", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                  Expanded(flex: 2, child: Text("TID", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 50, child: Text("RSSI", textAlign: TextAlign.right, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 16),
                                  Expanded(flex: 5, child: Text("RAW DATA (원본/메시지)", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                ]
                            ),
                          ),

                          Expanded(
                            child: Consumer<DeviceProvider>(
                              builder: (BuildContext ctx, DeviceProvider dynamicProvider, Widget? child) {
                                final List<String> logs = dynamicProvider.getLogs(deviceId).reversed.toList();

                                if (logs.isEmpty) {
                                  return const Center(
                                    child: Text(
                                        "수신 대기 중... (패킷 없음)",
                                        style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 14,
                                            fontFamily: AppTheme.fontPretendard
                                        )
                                    ),
                                  );
                                }

                                return ListView.separated(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  itemCount: logs.length,
                                  separatorBuilder: (BuildContext context, int idx) {
                                    return Divider(color: Colors.white.withValues(alpha: 0.05), height: 1);
                                  },
                                  itemBuilder: (BuildContext ctx, int idx) {
                                    final Map<String, String> parsed = _parseLogData(logs[idx]);

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

                                    Color rssiColor = Colors.greenAccent;
                                    try {
                                      String rssiNum = parsed['rssi']!.replaceAll(' dBm', '');
                                      double rVal = double.parse(rssiNum);
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
                                          SizedBox(width: 70, child: Text(parsed['time']!, style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white60, fontSize: 12))),

                                          SizedBox(
                                              width: 45,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                                child: Text(parsed['type']!, textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: typeColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                              )
                                          ),

                                          SizedBox(width: 40, child: Text(parsed['ant']!, textAlign: TextAlign.center, style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold))),

                                          Expanded(
                                              flex: 3,
                                              child: Padding(
                                                padding: const EdgeInsets.only(right: 8.0),
                                                child: Text(parsed['epc']!, style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3)),
                                              )
                                          ),

                                          Expanded(
                                              flex: 2,
                                              child: Text(parsed['tid']!, style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white70, fontSize: 12, height: 1.3))
                                          ),

                                          SizedBox(width: 50, child: Text(parsed['rssi']!, textAlign: TextAlign.right, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: rssiColor, fontSize: 12, fontWeight: FontWeight.bold))),

                                          const SizedBox(width: 16),

                                          Expanded(
                                              flex: 5,
                                              child: Text(
                                                  parsed['raw']!,
                                                  style: TextStyle(
                                                      fontFamily: AppTheme.fontPretendard,
                                                      color: parsed['type'] == 'RAW' ? Colors.amberAccent : (parsed['type'] == 'DIR' ? Colors.greenAccent : Colors.white70),
                                                      fontSize: 12,
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
              actions: [
                AppTheme.actionButton(
                  label: "닫기",
                  color: Colors.transparent,
                  textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                ),
              ],
            ),
          );
        }
    );
  }

  /// 장비 썸네일 이미지 박스 렌더링
  Widget _buildDeviceThumbnail(DeviceModel item, ThemeData theme, {double size = 44}) {
    final String? imgUrl = item.getImageUrl(widget.baseUrl, thumb: '100x100');
    final bool isDark = theme.brightness == Brightness.dark;

    if (imgUrl == null || imgUrl.isEmpty) {
      return Container(
          width: size, height: size,
          padding: const EdgeInsets.all(6.0),
          decoration: BoxDecoration(
              color: isDark ? theme.dividerTheme.color?.withValues(alpha: 0.1) : const Color(0xFFF1F3F5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? Colors.grey.shade600 : Colors.grey.shade400, width: 1.5)
          ),
          alignment: Alignment.center,
          child: FaIcon(_getDeviceIcon(item.model), color: Colors.black26, size: 30)
      );
    }

    final String connector = imgUrl.contains('?') ? '&' : '?';
    final String fullUrl = "$imgUrl${connector}t=${item.hashCode}"; // 캐시 방지

    return Container(
        width: size, height: size,
        padding: const EdgeInsets.all(6.0),
        decoration: BoxDecoration(
            color: isDark ? theme.dividerTheme.color?.withValues(alpha: 0.1) : const Color(0xFFF1F3F5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? Colors.grey.shade600 : Colors.grey.shade400, width: 1.5)
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
            fullUrl,
            fit: BoxFit.contain,
            errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
              return FaIcon(_getDeviceIcon(item.model), color: Colors.black26, size: 30);
            }
        )
    );
  }

  /// 상태 배지(온라인/오프라인)
  Widget _buildStatusBadge(String status, Color color) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(status.toUpperCase(), style: TextStyle(fontFamily: AppTheme.fontPretendard, color: color, fontSize: 12, fontWeight: FontWeight.w900))
    );
  }

  /// 키:값 텍스트 출력용 위젯
  Widget _buildKeyValue(String label, String value, BuildContext ctx) {
    return SizedBox(
        width: 140,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTheme.itemLabelStyle(ctx)),
              Text(value, style: AppTheme.itemValueStyle(ctx)),
            ]
        )
    );
  }

  /// 원형 액션 버튼 (테스트/제어용)
  Widget _buildCircleAction(IconData icon, Color color, String tip, VoidCallback onTap) {
    return Tooltip(
        message: tip,
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(25),
            child: Container(
                width: 50, height: 50,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24)
            )
        )
    );
  }

  /// ===========================================================================
  /// [출력 제어 다이얼로그]
  /// 리더기의 안테나별 RF 파워(dBm)를 실시간으로 조절합니다.
  /// ===========================================================================
  void _showPowerControlDialog(BuildContext context, DeviceProvider provider, DeviceModel d) {
    final theme = Theme.of(context);
    int selectedAntenna = 0; // 0 = 전체
    double currentPower = 300; // 30.0 dBm 기본값

    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                return AlertDialog(
                  title: AppTheme.dialogTitle('${d.name} 출력(RF Power) 설정', Icons.settings_input_antenna, color: Colors.blueAccent),
                  content: SizedBox(
                    width: 450,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("안테나 포트 선택", style: AppTheme.itemLabelStyle(context)),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<int>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: 0, label: Text("전체")),
                              ButtonSegment(value: 1, label: Text("ANT 1")),
                              ButtonSegment(value: 2, label: Text("ANT 2")),
                              ButtonSegment(value: 3, label: Text("ANT 3")),
                              ButtonSegment(value: 4, label: Text("ANT 4")),
                            ],
                            selected: {selectedAntenna},
                            onSelectionChanged: (Set<int> val) {
                              setDialogState(() {
                                selectedAntenna = val.first;
                              });
                            },
                            style: SegmentedButton.styleFrom(
                                selectedBackgroundColor: Colors.blueAccent,
                                selectedForegroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                textStyle: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w600, fontSize: 14)
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("주파수 출력 파워", style: AppTheme.itemLabelStyle(context)),
                            Text("${(currentPower / 10).toStringAsFixed(1)} dBm",
                                style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 24, fontWeight: FontWeight.w900, color: Colors.blueAccent)
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: currentPower,
                          min: 50,
                          max: 310, // 5.0 ~ 31.0 dBm
                          divisions: 26,
                          activeColor: Colors.blueAccent,
                          label: "${(currentPower / 10).toStringAsFixed(1)} dBm",
                          onChanged: (double val) {
                            setDialogState(() {
                              currentPower = val;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: const Text(
                              "💡 적용 버튼을 누르면 리더기의 통신이 일시정지되며, 새로운 출력 설정값이 반영된 후 즉시 자동으로 통신이 재개됩니다.",
                              style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.blueGrey, fontSize: 13, height: 1.4)
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    AppTheme.actionButton(
                        label: "닫기",
                        color: Colors.transparent,
                        textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        onPressed: () {
                          Navigator.pop(ctx);
                        }
                    ),
                    AppTheme.actionButton(
                        label: "설정 적용하기",
                        color: Colors.blueAccent,
                        onPressed: () {
                          provider.setDevicePower(d.id, selectedAntenna, currentPower.toInt());
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("안테나 출력 설정 명령이 전송되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)))
                          );
                        }
                    ),
                  ],
                );
              }
          );
        }
    );
  }

  /// ===========================================================================
  /// [신규 등록 및 수정 폼 다이얼로그]
  /// 장치를 등록하거나 설정을 변경할 때 띄우는 팝업 화면입니다.
  /// 🔥 네이티브 환경(PC/모바일)에서는 미리 만들어두신 AppSerialPort 래퍼를 통해
  ///    실제 COM 포트 목록을 콤보박스로 깔끔하게 불러옵니다.
  /// ===========================================================================
  Future<void> _showForm(BuildContext context, DeviceProvider provider, DeviceModel? d) async {
    final theme = Theme.of(context);
    final nameC = TextEditingController(text: d?.name ?? "");
    final ipC = TextEditingController(text: d?.ipAddress ?? "");
    final portC = TextEditingController(text: (d?.port ?? 8080).toString());
    final clientIdC = TextEditingController(text: d?.clientId ?? "");

    final List<String> modelOptions = SupportedDeviceModels.list;
    String modelV = modelOptions.contains(d?.model) ? d!.model : modelOptions.first;
    bool activeV = d?.isActive ?? true;
    bool autoConnectV = d?.isAutoConnect ?? false;

    String usageRoleV = d?.settings['usage_role']?.toString() ?? '상시감지(출입/물류)';
    String dirModeV = d?.settings['dir_mode']?.toString() ?? 'none';
    String dirOptionV = d?.settings['dir_option']?.toString() ?? '3';
    final dirOptionC = TextEditingController(text: dirOptionV);

    XFile? imageFile;
    Uint8List? imagePreview;
    bool isImageDeleted = false;

    // 현재 장치의 연결 타입 (TCP, SERIAL, BLUETOOTH) 추론
    String connType = 'TCP';
    if (d != null) {
      String upperIp = d.ipAddress.toUpperCase();
      if (upperIp.startsWith('COM') || upperIp.startsWith('/DEV/')) {
        connType = 'SERIAL';
      } else if (RegExp(r'^([0-9A-F]{2}[:-]){5}([0-9A-F]{2})$').hasMatch(upperIp)) {
        connType = 'BLUETOOTH';
      }
    }

    // ------------------------------------------------------------------------
    // [조건부 임포트 적용 완료]
    // 기존의 SerialPort 대신, 래퍼 클래스인 AppSerialPort를 호출하여 포트를 스캔합니다.
    // ------------------------------------------------------------------------
    List<String> availablePorts = [];
    Map<String, String> portLabels = {};

    try {
      availablePorts = AppSerialPort.availablePorts;
      for (String port in availablePorts) {
        try {
          final sp = AppSerialPort(port);
          String desc = sp.description ?? "";
          bool isBt = sp.isBluetooth;

          if (desc.toLowerCase().contains('bluetooth') || desc.toLowerCase().contains('bt') || desc.toLowerCase().contains('bth')) {
            isBt = true;
          }

          portLabels[port] = isBt ? "블루투스 가상 포트" : (desc.isNotEmpty ? desc : "일반 시리얼 포트");
          sp.dispose(); // OS 핸들 안전 해제
        } catch (_) {
          portLabels[port] = "알 수 없는 장치";
        }
      }
    } catch (e) {
      debugPrint("시리얼 포트 자동 스캔 에러: $e");
    }

    String? selectedComPort;
    if (connType == 'SERIAL' && availablePorts.contains(d?.ipAddress)) {
      selectedComPort = d!.ipAddress;
    } else if (availablePorts.isNotEmpty) {
      selectedComPort = availablePorts.first;
    }

    if (!context.mounted) return;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return ListenableProvider.value(
            value: provider,
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                // 화면 너비에 따라 폼을 1단 또는 2단으로 반응형 렌더링
                bool isWide = MediaQuery.of(context).size.width > 750;

                Widget imagePickerWidget = _buildImagePickerBox(
                  context, d, imagePreview, isImageDeleted,
                      (XFile file, Uint8List bytes) {
                    setDialogState(() {
                      imageFile = file;
                      imagePreview = bytes;
                      isImageDeleted = false;
                    });
                  },
                      () {
                    setDialogState(() {
                      imageFile = null;
                      imagePreview = null;
                      isImageDeleted = true;
                    });
                  },
                  theme,
                );

                return AlertDialog(
                  title: AppTheme.dialogTitle(d == null ? '신규 장치 등록' : '장치 설정 수정', d == null ? Icons.router : Icons.edit),
                  content: SizedBox(
                    width: isWide ? 850 : null,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 20),
                          if (isWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                imagePickerWidget,
                                const SizedBox(width: 30),
                                Expanded(
                                    child: _buildFormFields(
                                        context, provider, d, nameC, ipC, portC, clientIdC, dirOptionC,
                                        modelV, activeV, autoConnectV, usageRoleV, dirModeV, dirOptionV,
                                        connType, selectedComPort, availablePorts, portLabels,
                                            (String? m, bool? a, bool? ac, String? uR, String? dM, String? dO, String? cT, String? sP) {
                                          setDialogState(() {
                                            if (m != null) { modelV = m; }
                                            if (a != null) { activeV = a; }
                                            if (ac != null) { autoConnectV = ac; }
                                            if (uR != null) { usageRoleV = uR; }
                                            if (dM != null) { dirModeV = dM; }
                                            if (dO != null) { dirOptionV = dO; }

                                            if (cT != null) {
                                              connType = cT;
                                              if (cT == 'TCP') {
                                                ipC.text = d?.ipAddress.contains('.') == true ? d!.ipAddress : '192.168.0.100';
                                                portC.text = d?.port.toString() ?? '9090';
                                              } else if (cT == 'SERIAL') {
                                                ipC.text = selectedComPort ?? (availablePorts.isNotEmpty ? availablePorts.first : '');
                                                portC.text = '115200';
                                              } else if (cT == 'BLUETOOTH') {
                                                ipC.text = d?.ipAddress.contains(':') == true ? d!.ipAddress : '';
                                                portC.text = '1';
                                              }
                                            }

                                            // 포트 콤보박스 선택 변경 시 처리
                                            if (sP != null) {
                                              selectedComPort = sP;
                                              ipC.text = sP;
                                            }
                                          });
                                        }, theme
                                    )
                                ),
                              ],
                            )
                          else ...[
                            imagePickerWidget,
                            const SizedBox(height: 20),
                            _buildFormFields(
                                context, provider, d, nameC, ipC, portC, clientIdC, dirOptionC,
                                modelV, activeV, autoConnectV, usageRoleV, dirModeV, dirOptionV,
                                connType, selectedComPort, availablePorts, portLabels,
                                    (String? m, bool? a, bool? ac, String? uR, String? dM, String? dO, String? cT, String? sP) {
                                  setDialogState(() {
                                    if (m != null) { modelV = m; }
                                    if (a != null) { activeV = a; }
                                    if (ac != null) { autoConnectV = ac; }
                                    if (uR != null) { usageRoleV = uR; }
                                    if (dM != null) { dirModeV = dM; }
                                    if (dO != null) { dirOptionV = dO; }

                                    if (cT != null) {
                                      connType = cT;
                                      if (cT == 'TCP') {
                                        ipC.text = d?.ipAddress.contains('.') == true ? d!.ipAddress : '192.168.0.100';
                                        portC.text = d?.port.toString() ?? '9090';
                                      } else if (cT == 'SERIAL') {
                                        ipC.text = selectedComPort ?? (availablePorts.isNotEmpty ? availablePorts.first : '');
                                        portC.text = '115200';
                                      } else if (cT == 'BLUETOOTH') {
                                        ipC.text = d?.ipAddress.contains(':') == true ? d!.ipAddress : '';
                                        portC.text = '1';
                                      }
                                    }

                                    // 포트 콤보박스 선택 변경 시 처리
                                    if (sP != null) {
                                      selectedComPort = sP;
                                      ipC.text = sP;
                                    }
                                  });
                                }, theme
                            ),
                          ],
                          if (provider.isSaving) ...[
                            const SizedBox(height: 20),
                            LinearProgressIndicator(color: theme.colorScheme.primary),
                          ]
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    AppTheme.actionButton(
                        label: "취소",
                        color: Colors.transparent,
                        textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        onPressed: () {
                          Navigator.pop(ctx);
                        }
                    ),
                    AppTheme.actionButton(
                      label: d == null ? "등록하기" : "수정완료",
                      onPressed: provider.isSaving ? () {} : () async {
                        // 유효성 검사
                        if (nameC.text.isEmpty || ipC.text.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("장치 명칭과 주소(포트)는 필수입니다.")));
                          return;
                        }

                        final nav = Navigator.of(ctx);

                        // [OS 예외 방어 코드] 수정 시 장치가 온라인이라면 먼저 통신을 끊습니다.
                        if (d != null && d.status.toLowerCase() == 'online') {
                          try { provider.stopDeviceRead(d.id); } catch(_) {}
                          await Future.delayed(const Duration(milliseconds: 300));
                          provider.disconnectDevice(d.id);
                        }

                        // 저장할 데이터 맵 구성
                        final Map<String, dynamic> data = {
                          'name': nameC.text.trim(),
                          'model': modelV,
                          'ip_address': ipC.text.trim(),
                          'port': int.tryParse(portC.text.trim()) ?? 0,
                          'client_id': clientIdC.text.trim(),
                          'is_active': activeV,
                          'is_auto_connect': autoConnectV,
                          'settings': {
                            ...(d?.settings ?? {}),
                            'usage_role': usageRoleV,
                            'dir_mode': dirModeV,
                            'dir_option': dirModeV == 'reader_fixed' ? dirOptionV : dirOptionC.text.trim(),
                          },
                          if (isImageDeleted) 'image': '',
                        };

                        // Provider를 통한 백엔드 API 호출 (업데이트/삽입)
                        bool success = await provider.handleSave(d: d, data: data, imageXFile: imageFile);

                        // 비동기 갭 이후 컨텍스트 사용에 대한 안전망 추가
                        if (!ctx.mounted) return;

                        if (success) {
                          nav.pop();
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text("장치 정보가 안전하게 저장되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)))
                          );
                        }
                      },
                    ),
                  ],
                );
              },
            ),
          );
        }
    );
  }

  /// 장치 사진 업로드 및 썸네일 표시 위젯
  Widget _buildImagePickerBox(
      BuildContext context,
      DeviceModel? d,
      Uint8List? preview,
      bool isDeleted,
      Function(XFile, Uint8List) onPicked,
      VoidCallback onDeleted,
      ThemeData theme
      ) {
    final String? imgUrl = d?.getImageUrl(widget.baseUrl, thumb: '200x200');
    final bool isDark = theme.brightness == Brightness.dark;

    final bool hasImage = preview != null || (imgUrl != null && imgUrl.isNotEmpty && !isDeleted);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () async {
            // 카메라가 아닌 갤러리에서만 이미지를 선택하도록 지정
            final ImagePicker picker = ImagePicker();
            final XFile? img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
            if (img != null) {
              final Uint8List b = await img.readAsBytes();
              onPicked(img, b);
            }
          },
          child: Container(
            width: 180, height: 210,
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: isDark ? Colors.grey.shade600 : Colors.grey.shade400, width: 2)
            ),
            child: Center(
              child: preview != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(preview, fit: BoxFit.contain))
                  : (hasImage
                  ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network("$imgUrl?t=${DateTime.now().millisecondsSinceEpoch}", fit: BoxFit.contain))
                  : const Icon(Icons.add_a_photo_outlined, size: 50, color: Colors.grey)),
            ),
          ),
        ),

        // 사진 삭제(X) 버튼
        if (hasImage)
          Positioned(
            top: -10,
            right: -10,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onDeleted,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: AppTheme.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 2.5),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2))
                      ]
                  ),
                  child: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 폼 내부의 여러 입력 필드들을 생성하는 헬퍼 함수
  Widget _buildFormFields(
      BuildContext context, DeviceProvider provider, DeviceModel? d,
      TextEditingController n, TextEditingController i, TextEditingController p, TextEditingController c, TextEditingController dirOptionC,
      String mV, bool aV, bool acV, String uRV, String dirModeV, String dirOptionV,
      String connTypeV, String? selectedComPortV, List<String> availablePortsV, Map<String, String> portLabelsV,
      Function(String?, bool?, bool?, String?, String?, String?, String?, String?) onC,
      ThemeData theme
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDialogTextField("장치 관리 명칭 (필수)", n, theme, icon: Icons.label_outline),
        const SizedBox(height: 24),

        const Text("통신 연결 방식", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 8),
        // 통신 방식 세그먼트 버튼
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: true,
            segments: const [
              ButtonSegment(value: 'TCP', label: Text('네트워크 (TCP/IP)'), icon: Icon(Icons.wifi)),
              ButtonSegment(value: 'SERIAL', label: Text('USB/시리얼 (RS-232)'), icon: Icon(Icons.usb)),
              ButtonSegment(value: 'BLUETOOTH', label: Text('블루투스 (SPP)'), icon: Icon(Icons.bluetooth)),
            ],
            selected: {connTypeV},
            onSelectionChanged: (Set<String> newSelection) {
              onC(null, null, null, null, null, null, newSelection.first, null);
            },
            style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Colors.indigo.withValues(alpha: 0.15),
                selectedForegroundColor: Colors.indigo,
                textStyle: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 13)
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 통신 방식에 따라 동적으로 IP/포트 입력창 렌더링
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildConnectionFields(connTypeV, i, p, selectedComPortV, availablePortsV, portLabelsV, onC, theme, context),
        ),

        const SizedBox(height: 16),
        _buildDialogTextField("Client ID (Host Serial)", c, theme, icon: Icons.fingerprint),
        const SizedBox(height: 16),

        // 프로토콜(모델) 선택 콤보박스
        DropdownButtonFormField<String>(
          initialValue: mV,
          decoration: AppTheme.inputDecoration(label: "제조사/물리적 모델 프로토콜", context: context),
          items: SupportedDeviceModels.labels.entries.map((MapEntry<String, String> e) {
            IconData mIcon = Icons.router_rounded;
            final String label = e.value;

            if (label.contains('고정')) {
              mIcon = Icons.router_rounded;
            } else if (label.contains('휴대') || label.contains('PDA')) {
              mIcon = Icons.smartphone_rounded;
            } else if (label.contains('데스크') || label.contains('USB')) {
              mIcon = Icons.desktop_mac_rounded;
            } else if (label.contains('프린터')) {
              mIcon = Icons.print_rounded;
            } else if (label.contains('스캐너') || label.contains('바코드')) {
              mIcon = Icons.barcode_reader;
            }

            return DropdownMenuItem(
                value: e.key,
                child: Row(
                    children: [
                      Icon(mIcon, size: 18, color: theme.colorScheme.primary.withValues(alpha: 0.8)),
                      const SizedBox(width: 8),
                      Text(e.value, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                    ]
                )
            );
          }).toList(),
          onChanged: (String? v) {
            onC(v, null, null, null, null, null, null, null);
          },
        ),
        const SizedBox(height: 16),

        // 장비 용도 선택 콤보박스
        DropdownButtonFormField<String>(
          initialValue: uRV,
          decoration: AppTheme.inputDecoration(label: "장비 운용 용도 (데이터 라우팅 기준)", context: context),
          items: ['상시감지(출입/물류)', '수동스캔(재고조사)', '수동스캔(단일등록)'].map((String e) {
            IconData uIcon = Icons.radar_rounded;
            Color uColor = Colors.teal;

            if (e.contains('재고조사')) {
              uIcon = Icons.inventory_rounded;
              uColor = Colors.orange;
            } else if (e.contains('단일등록')) {
              uIcon = Icons.qr_code_scanner_rounded;
              uColor = Colors.blue;
            }

            return DropdownMenuItem(
                value: e,
                child: Row(
                    children: [
                      Icon(uIcon, size: 18, color: uColor.withValues(alpha: 0.8)),
                      const SizedBox(width: 8),
                      Text(e, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                    ]
                )
            );
          }).toList(),
          onChanged: (String? v) {
            onC(null, null, null, v, null, null, null, null);
          },
        ),
        const SizedBox(height: 24),

        // 출입 방향 판별 로직 설정 박스
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.cyan.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.directions_walk, color: Colors.cyan, size: 20),
                  SizedBox(width: 8),
                  Text("현장 출입/방향 판별 기준 설정", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, color: Colors.cyan, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: dirModeV,
                decoration: AppTheme.inputDecoration(label: "출입/방향 판별 모드", context: context),
                items: [
                  DropdownMenuItem(value: 'none', child: Row(children: [const Icon(Icons.compare_arrows_rounded, size: 18, color: Colors.blueGrey), const SizedBox(width: 8), const Text('단순 교차 (일정 시간 후 재인식 시 상태 반전)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))])),
                  DropdownMenuItem(value: 'ant_fixed', child: Row(children: [const Icon(Icons.settings_input_antenna_rounded, size: 18, color: Colors.blueGrey), const SizedBox(width: 8), const Text('안테나 고정 (홀수 번호=IN, 짝수 번호=OUT)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))])),
                  DropdownMenuItem(value: 'reader_fixed', child: Row(children: [const Icon(Icons.push_pin_rounded, size: 18, color: Colors.blueGrey), const SizedBox(width: 8), const Text('리더기 고정 (설정한 단일 방향으로 무조건 판별)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))])),
                  DropdownMenuItem(value: 'ant_seq', child: Row(children: [const Icon(Icons.format_list_numbered_rtl_rounded, size: 18, color: Colors.blueGrey), const SizedBox(width: 8), const Text('안테나 시퀀스 (1번 ➔ 2번 순차 통과 시 IN)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))])),
                  DropdownMenuItem(value: 'reader_seq', child: Row(children: [const Icon(Icons.route_rounded, size: 18, color: Colors.blueGrey), const SizedBox(width: 8), const Text('리더기 시퀀스 (리더기간 이동 이력 추적)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))])),
                ],
                onChanged: (String? v) {
                  onC(null, null, null, null, v, null, null, null);
                },
              ),

              if (dirModeV == 'none') ...[
                const SizedBox(height: 16),
                _buildDialogTextField("재인식 방지 및 상태 반전 시간(초)", dirOptionC, theme, isNumber: true, icon: Icons.timer_outlined),
              ] else if (dirModeV == 'reader_fixed') ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: ['IN', 'OUT'].contains(dirOptionV) ? dirOptionV : 'IN',
                  decoration: AppTheme.inputDecoration(label: "무조건 고정할 판별 방향", context: context),
                  items: [
                    DropdownMenuItem(value: 'IN', child: Row(children: [const Icon(Icons.login_rounded, size: 18, color: AppTheme.success), const SizedBox(width: 8), const Text('입고 / 입장 (IN)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))])),
                    DropdownMenuItem(value: 'OUT', child: Row(children: [const Icon(Icons.logout_rounded, size: 18, color: AppTheme.warning), const SizedBox(width: 8), const Text('출고 / 퇴장 (OUT)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))])),
                  ],
                  onChanged: (String? v) {
                    onC(null, null, null, null, null, v, null, null);
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 신규 추가가 아닌 기존 장치 수정일 경우 나타나는 하단 액션 버튼들
        if (d != null) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.science, size: 24),
              label: const Text("장치 통신 및 동작 테스트 (Read/Write)", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent.withValues(alpha: 0.1),
                  foregroundColor: Colors.deepPurpleAccent,
                  elevation: 0,
                  minimumSize: const Size(double.infinity, 60),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(color: Colors.deepPurpleAccent.withValues(alpha: 0.3))
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("💡 IP/포트 등 설정값을 방금 변경하셨다면, 먼저 '수정완료'를 눌러 저장하신 후 다시 창을 열어 테스트해주세요.", style: TextStyle(fontFamily: AppTheme.fontPretendard)),
                      duration: Duration(seconds: 3),
                    )
                );
                _showDeviceTestDialog(context, provider, d);
              },
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.tune, size: 24),
              label: const Text("안테나 출력(RF Power) 실시간 제어", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: d.status.toLowerCase() == 'online' ? Colors.blueAccent.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                  foregroundColor: d.status.toLowerCase() == 'online' ? Colors.blueAccent : Colors.grey,
                  elevation: 0,
                  minimumSize: const Size(double.infinity, 60),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(color: d.status.toLowerCase() == 'online' ? Colors.blueAccent.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.3))
              ),
              onPressed: d.status.toLowerCase() == 'online' ? () {
                _showPowerControlDialog(context, provider, d);
              } : () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("장치가 온라인(연결됨) 상태일 때만 제어할 수 있습니다.")));
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 자동연결 활성화 스위치
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
              color: acV ? Colors.blueAccent.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: acV ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2))
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(acV ? "앱 시작 시 자동 연결 (ON)" : "수동으로만 연결 (OFF)", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 14, fontWeight: FontWeight.bold, color: acV ? Colors.blueAccent : Colors.grey)),
              Switch(
                  value: acV,
                  activeThumbColor: Colors.blueAccent,
                  activeTrackColor: Colors.blueAccent.withValues(alpha: 0.5),
                  onChanged: (bool v) {
                    onC(null, null, v, null, null, null, null, null);
                  }
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 장치 활성화/비활성화 스위치
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
              color: aV ? AppTheme.success.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: aV ? AppTheme.success.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2))
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(aV ? "장치 활성화 상태 (ON)" : "장치 비활성화 상태 (OFF)", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 14, fontWeight: FontWeight.bold, color: aV ? AppTheme.success : Colors.grey)),
              Switch(
                  value: aV,
                  activeThumbColor: AppTheme.success,
                  activeTrackColor: AppTheme.success.withValues(alpha: 0.5),
                  onChanged: (bool v) {
                    onC(null, v, null, null, null, null, null, null);
                  }
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 통신 방식에 따른 입력 필드를 다이나믹하게 전환하여 렌더링
  /// 🔥 윈도우 PC에 연결된 COM 포트를 콤보박스로 예쁘게 보여줍니다.
  Widget _buildConnectionFields(
      String connType, TextEditingController ipC, TextEditingController portC,
      String? selectedComPort, List<String> availablePorts, Map<String, String> portLabels,
      Function(String?, bool?, bool?, String?, String?, String?, String?, String?) onC,
      ThemeData theme, BuildContext context
      ) {
    if (connType == 'TCP') {
      return Row(
          key: const ValueKey('TCP'),
          children: [
            Expanded(flex: 5, child: _buildDialogTextField("IP 주소 (예: 192.168.0.100)", ipC, theme, icon: Icons.lan)),
            const SizedBox(width: 16),
            Expanded(flex: 3, child: _buildDialogTextField("포트 번호 (Port)", portC, theme, isNumber: true)),
          ]
      );
    } else if (connType == 'SERIAL') {
      String? safeComPort = selectedComPort;
      // 선택된 포트가 현재 물리적으로 존재하지 않는다면(빠졌다면) null로 처리하여 에러 방지
      if (safeComPort != null && !availablePorts.contains(safeComPort)) {
        safeComPort = null;
      }

      return Row(
          key: const ValueKey('SERIAL'),
          children: [
            Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 60,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(10), color: theme.cardTheme.color),
                        child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                                isExpanded: true,
                                value: safeComPort,
                                hint: const Text("PC에 연결된 가용 COM 포트 없음", style: TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.redAccent)),
                                items: availablePorts.map((String port) {
                                  bool isBt = portLabels[port]?.contains('블루투스') == true;
                                  IconData pIcon = isBt ? Icons.bluetooth_connected : Icons.usb;
                                  Color pColor = isBt ? Colors.blueAccent : Colors.indigo;
                                  String pDesc = portLabels[port] ?? "알 수 없는 장치";

                                  return DropdownMenuItem<String>(
                                      value: port,
                                      child: Row(
                                        children: [
                                          Icon(pIcon, color: pColor, size: 20),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text("$port ($pDesc)", style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                          ),
                                        ],
                                      )
                                  );
                                }).toList(),
                                onChanged: (String? newVal) {
                                  if (newVal != null) {
                                    onC(null, null, null, null, null, null, null, newVal);
                                  }
                                }
                            )
                        )
                    ),
                  ],
                )
            ),
            const SizedBox(width: 16),
            Expanded(flex: 3, child: _buildDialogTextField("통신 속도 (BaudRate)", portC, theme, isNumber: true)),
          ]
      );
    } else {
      return Column(
          key: const ValueKey('BLUETOOTH'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
                children: [
                  Expanded(flex: 5, child: _buildDialogTextField("장치 MAC 주소 (예: 00:11:22:33:44:55)", ipC, theme, icon: Icons.bluetooth_connected)),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: _buildDialogTextField("채널/포트 (보통 1)", portC, theme, isNumber: true)),
                ]
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        "블루투스는 SPP(Serial Port Profile) 통신을 위해 IP 대신 장치의 12자리 MAC 주소가 필요합니다. 향후 업데이트를 위해 준비된 기능입니다.",
                        style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: Colors.blueGrey, height: 1.4)
                    ),
                  ),
                ],
              ),
            )
          ]
      );
    }
  }

  /// 텍스트 입력창 공통 생성 헬퍼
  Widget _buildDialogTextField(String label, TextEditingController ctrl, ThemeData theme, {bool isNumber = false, IconData? icon}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
      decoration: AppTheme.inputDecoration(label: label, context: context, prefixIcon: icon),
    );
  }

  /// 개별 장치 삭제 확인 창
  void _confirmDelete(BuildContext context, DeviceProvider provider, DeviceModel d) {
    final theme = Theme.of(context);
    showDialog(context: context, builder: (BuildContext c) {
      return AlertDialog(
        title: AppTheme.dialogTitle("장치 삭제", Icons.delete, color: AppTheme.danger),
        content: Text("[${d.name}] 장치를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
        actions: [
          AppTheme.actionButton(
              label: "취소",
              color: Colors.transparent,
              textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              onPressed: () {
                Navigator.pop(c);
              }
          ),
          AppTheme.actionButton(
            label: "삭제 실행",
            color: AppTheme.danger,
            onPressed: () async {
              final nav = Navigator.of(c);

              // [OS 예외 방어 코드] 삭제 전에도 안전하게 포트를 닫기 위해 읽기 스레드를 중지합니다.
              try { provider.stopDeviceRead(d.id); } catch(_) {}
              await Future.delayed(const Duration(milliseconds: 300));

              provider.disconnectDevice(d.id);
              bool result = await provider.deleteDevice(d.id);

              if (!c.mounted) return; // 비동기 간격 안전망

              if (result) {
                nav.pop();
              }
            },
          ),
        ],
      );
    });
  }

  /// 다중 선택된 장치들의 통신 일괄 해제
  void _handleBulkDisconnect(DeviceProvider provider, ThemeData theme) async {
    if (_selectedItemIds.isEmpty) {
      return;
    }

    // [OS 예외 방어 코드] 다중 선택 해제 시에도 윈도우 OS 에러 방지를 위해 수신 스레드를 모두 먼저 중지하고 OS 락 해제를 대기합니다.
    for (String id in _selectedItemIds) {
      try { provider.stopDeviceRead(id); } catch(_) {}
    }
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return; // 비동기 간격 안전망

    // 대기 후 일괄 Close
    for (String id in _selectedItemIds) {
      provider.disconnectDevice(id);
    }

    setState(() {
      _selectedItemIds.clear();
      _isSelectionMode = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("선택한 장치들의 통신이 일괄 해제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)))
    );
  }

  /// 다중 선택된 장치 일괄 삭제
  void _confirmBulkDelete(DeviceProvider provider, ThemeData theme) {
    if (_selectedItemIds.isEmpty) {
      return;
    }

    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("선택 장치 일괄 삭제", Icons.warning, color: AppTheme.danger),
              content: Text("선택하신 ${_selectedItemIds.length}개의 장치를 모두 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
              actions: [
                AppTheme.actionButton(
                    label: "취소",
                    color: Colors.transparent,
                    textColor: cancelColor,
                    onPressed: () {
                      Navigator.pop(ctx);
                    }
                ),
                AppTheme.actionButton(
                    label: "일괄 삭제",
                    color: AppTheme.danger,
                    onPressed: () async {
                      Navigator.pop(ctx);
                      setState(() {
                        _isFullScreenLoading = true;
                      });

                      // [OS 예외 방어 코드] 삭제 전 일괄 읽기 스레드 중지
                      for (String id in _selectedItemIds) {
                        try { provider.stopDeviceRead(id); } catch(_) {}
                      }
                      await Future.delayed(const Duration(milliseconds: 300));

                      // 통신 끊기 및 삭제 진행
                      for (String id in _selectedItemIds) {
                        provider.disconnectDevice(id);
                        await provider.deleteDevice(id);
                      }

                      if (!mounted) return; // 비동기 간격 안전망

                      setState(() {
                        _selectedItemIds.clear();
                        _isFullScreenLoading = false;
                        _isSelectionMode = false;
                      });

                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("선택한 장치들이 일괄 삭제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
                    }
                )
              ]
          );
        }
    );
  }

  /// 전체 시스템 초기화(모두 삭제) 다이얼로그
  Future<void> _showResetConfirmationDialog(DeviceProvider provider, ThemeData theme) async {
    final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("전체 장치 초기화", Icons.warning, color: AppTheme.danger),
              content: const Text("시스템에 등록된 모든 장치 정보를 영구 삭제하시겠습니까?\n현재 연결된 모든 통신이 해제됩니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)),
              actions: [
                AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () {
                  Navigator.pop(ctx, false);
                }),
                AppTheme.actionButton(label: "전체 삭제 실행", color: AppTheme.danger, onPressed: () {
                  Navigator.pop(ctx, true);
                })
              ]
          );
        }
    );

    if (!mounted || confirm != true) {
      return;
    }

    setState(() {
      _isFullScreenLoading = true;
    });

    try {
      // [OS 예외 방어 코드] 전체 삭제 시 모든 장치의 읽기 스레드 중지 및 대기
      for (var device in provider.list) {
        try { provider.stopDeviceRead(device.id); } catch(_) {}
      }
      await Future.delayed(const Duration(milliseconds: 300));

      for (var device in provider.list) {
        provider.disconnectDevice(device.id);
      }

      for (var device in provider.list) {
        await provider.deleteDevice(device.id);
      }

    } finally {
      if (mounted) {
        setState(() {
          _isFullScreenLoading = false;
          _selectedItemIds.clear();
          _isSelectionMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('장치 초기화가 완료되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard))));
      }
    }
  }
}