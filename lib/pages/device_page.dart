import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

import '../models/device_model.dart';
import '../providers/device_provider.dart'; // 통신 로직 전담 DataModule
import '../services/device_protocols.dart';
import '../theme/app_theme.dart'; // 중앙 집중형 테마 임포트

/// ---------------------------------------------------------------------------
/// [UI] 장치 관리 페이지 (DevicePage)
/// RFID 리더기, 바코드 스캐너, 프린터 등 하드웨어 장치들을 통합 관리합니다.
/// 미니멀리즘과 키오스크 디자인 철학을 적용하여 직관적으로 구성했습니다.
/// ---------------------------------------------------------------------------
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
  // ---------------------------------------------------------------------------
  // [상태 변수 선언부]
  // ---------------------------------------------------------------------------
  final TextEditingController _searchController = TextEditingController();
  String _currentQuery = "";

  String _activeMetricFilter = "전체";

  final Set<String> _selectedItemIds = {};
  bool _isSelectionMode = false;
  bool _isFullScreenLoading = false;

  // 레이아웃 고정 치수 (미니멀 디자인 규격)
  static const double _colImgSize = 70.0;
  static const double _colActionWidth = 350.0;

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
    if (model.contains('PRINTER')) {
      return FontAwesomeIcons.print;
    }
    if (model.contains('SCANNER') || model.contains('RS232')) {
      return FontAwesomeIcons.barcode;
    }
    return FontAwesomeIcons.rss;
  }

  Color _getStatusColor(String status) {
    if (status.toLowerCase() == 'online') {
      return AppTheme.success;
    }
    if (status.toLowerCase() == 'offline') {
      return AppTheme.danger;
    }
    return Colors.grey;
  }

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

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DeviceProvider>(context);
    final theme = Theme.of(context);
    final metrics = _calculateMetrics(provider.list);

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
          Column(
            children: [
              _buildDashboard(metrics, theme),
              Divider(height: 1, color: theme.dividerTheme.color),
              _buildHeader(provider, theme),
              const SizedBox(height: 16),
              Expanded(
                child: provider.isLoading
                    ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                    : _buildListView(filteredList, provider, theme),
              ),
              const SizedBox(height: 20),
            ],
          ),

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

  Widget _buildStatTile(String label, int val, IconData icon, Color color, ThemeData theme, {required String filterKey}) {
    final bool isSelected = _activeMetricFilter == filterKey;
    final bool isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        setState(() {
          _activeMetricFilter = _activeMetricFilter == filterKey ? "전체" : filterKey;
          _selectedItemIds.clear();
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
                  spacing: 8,
                  runSpacing: 8,
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
                  ],
                ),
              ),
              if (widget.isMobile) const SizedBox(width: 8),
              AppTheme.actionButton(
                  label: widget.isMobile ? "등록" : "신규 등록",
                  icon: Icons.add_box,
                  onPressed: () {
                    _showForm(context, provider, null);
                  },
                  color: theme.colorScheme.primary
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _currentQuery = val),
            style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
            decoration: AppTheme.inputDecoration(label: "장치명, 모델, IP 주소 통합 검색...", context: context, prefixIcon: Icons.search),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIconButton(IconData icon, String tip, VoidCallback onTap, ThemeData theme, {Color? color}) {
    return Tooltip(
        message: tip,
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                child: Icon(icon, color: color ?? theme.iconTheme.color?.withValues(alpha: 0.6), size: 24)
            )
        )
    );
  }

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

    final bool isAllSelected = list.isNotEmpty && list.every((d) => _selectedItemIds.contains(d.id));

    return Column(
      children: [
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

        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 20.0),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (BuildContext ctx, int idx) {
                final DeviceModel item = list[idx];
                final Color statusColor = _getStatusColor(item.status);
                final bool isSelected = _selectedItemIds.contains(item.id);

                return Row(
                  children: [
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

  /// ---------------------------------------------------------------------------
  /// [반응형 UI 적용] 데스크탑용 리스트 아이템 레이아웃
  /// ---------------------------------------------------------------------------
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
                  _buildKeyValue("IP 주소", item.ipAddress, context),
                  _buildKeyValue("포트 (Port)", item.port.toString(), context),
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

              if (isOnline) ...[
                _buildCircleAction(Icons.tune, Colors.blueAccent, "출력(파워) 제어", () {
                  _showPowerControlDialog(context, provider, item);
                }),
                const SizedBox(width: 12),
              ],

              SizedBox(
                width: 100,
                child: isOnline
                    ? OutlinedButton(
                  onPressed: () => provider.disconnectDevice(item.id),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: const BorderSide(color: AppTheme.danger),
                      padding: const EdgeInsets.symmetric(vertical: 12)
                  ),
                  child: const Text("연결 해제", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                )
                    : ElevatedButton(
                  onPressed: () => provider.connectDevice(item),
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

  /// ---------------------------------------------------------------------------
  /// [반응형 UI 적용] 모바일용 리스트 아이템 레이아웃
  /// ---------------------------------------------------------------------------
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
            _buildKeyValue("IP 주소", item.ipAddress, context),
            _buildKeyValue("포트 (Port)", item.port.toString(), context),
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

            if (isOnline) ...[
              _buildCircleAction(Icons.tune, Colors.blueAccent, "출력 제어", () {
                _showPowerControlDialog(context, provider, item);
              }),
            ],

            Expanded(
              child: isOnline
                  ? OutlinedButton(
                onPressed: () => provider.disconnectDevice(item.id),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    padding: const EdgeInsets.symmetric(vertical: 12)
                ),
                child: const Text("연결 해제", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
              )
                  : ElevatedButton(
                onPressed: () => provider.connectDevice(item),
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

  /// ---------------------------------------------------------------------------
  /// [개선 UI] 실시간 통신 로그 전용 모달(Modal) 팝업 창
  /// Map 상황판에서 구축한 최신식 7컬럼 터미널 UI를 이 페이지에도 완벽히 똑같이 이식했습니다.
  /// ---------------------------------------------------------------------------
  void _showTerminalDialog(BuildContext context, String deviceId, DeviceProvider provider, DeviceModel d) {
    final theme = Theme.of(context);

    // [로컬 변수 이름 규칙 준수 및 정밀 파싱 로직 적용]
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

        } else if (rawString.startsWith('<== [IDRO900F Raw]') || rawString.startsWith('<== [수신 RX]')) {
          type = 'RAW';
          rawString = rawString.replaceAll(RegExp(r'^<== \[[^\]]+\]\s*'), '').trim();

        } else if (rawString.startsWith('🔍') || rawString.startsWith('ℹ️')) {
          type = 'INFO';
        }
      } catch (e) {
        // 방어 코드 유지
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
                          onPressed: () => provider.clearLogs(deviceId),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text("터미널 창 비우기"),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),

                    Container(
                      height: 350,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E), // 찐 다크모드
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
                                  SizedBox(width: 70, child: Text("TIME", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 45, child: Text("TYPE", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 40, child: Text("ANT", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                  Expanded(flex: 3, child: Text("EPC", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                  Expanded(flex: 2, child: Text("TID", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 50, child: Text("RSSI", textAlign: TextAlign.right, style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 16),
                                  Expanded(flex: 5, child: Text("RAW DATA (원본/메시지)", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
                                ]
                            ),
                          ),

                          Expanded(
                            child: Consumer<DeviceProvider>(
                              builder: (ctx, dynamicProvider, child) {
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
                                  itemBuilder: (ctx, idx) {
                                    final Map<String, String> parsed = parseLog(logs[idx]);

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

                                          Expanded(
                                              flex: 5,
                                              child: Text(
                                                  parsed['raw']!,
                                                  style: TextStyle(
                                                      color: parsed['type'] == 'RAW' ? Colors.amberAccent : (parsed['type'] == 'DIR' ? Colors.greenAccent : Colors.white70),
                                                      fontSize: 12,
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
              actions: [
                AppTheme.actionButton(
                  label: "닫기",
                  color: Colors.transparent,
                  textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
          );
        }
    );
  }

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
    final String fullUrl = "$imgUrl${connector}t=${item.hashCode}";

    return Container(
        width: size, height: size,
        padding: const EdgeInsets.all(6.0),
        decoration: BoxDecoration(
            color: isDark ? theme.dividerTheme.color?.withValues(alpha: 0.1) : const Color(0xFFF1F3F5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? Colors.grey.shade600 : Colors.grey.shade400, width: 1.5)
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(fullUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => FaIcon(_getDeviceIcon(item.model), color: Colors.black26, size: 30))
    );
  }

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(status.toUpperCase(), style: TextStyle(fontFamily: AppTheme.fontPretendard, color: color, fontSize: 12, fontWeight: FontWeight.w900))
    );
  }

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

  /// ---------------------------------------------------------------------------
  /// [UI] 안테나 출력(Power) 제어 다이얼로그
  /// ---------------------------------------------------------------------------
  void _showPowerControlDialog(BuildContext context, DeviceProvider provider, DeviceModel d) {
    final theme = Theme.of(context);
    int selectedAntenna = 0;
    double currentPower = 300;

    showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
              builder: (context, setDialogState) {
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
                            segments: const [
                              ButtonSegment(value: 0, label: Text("전체 (All)")),
                              ButtonSegment(value: 1, label: Text("ANT 1")),
                              ButtonSegment(value: 2, label: Text("ANT 2")),
                              ButtonSegment(value: 3, label: Text("ANT 3")),
                              ButtonSegment(value: 4, label: Text("ANT 4")),
                            ],
                            selected: {selectedAntenna},
                            onSelectionChanged: (val) {
                              setDialogState(() { selectedAntenna = val.first; });
                            },
                            style: SegmentedButton.styleFrom(
                                selectedBackgroundColor: Colors.blueAccent,
                                selectedForegroundColor: Colors.white,
                                textStyle: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)
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
                          max: 310,
                          divisions: 26,
                          activeColor: Colors.blueAccent,
                          label: "${(currentPower / 10).toStringAsFixed(1)} dBm",
                          onChanged: (val) {
                            setDialogState(() { currentPower = val; });
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
                        onPressed: () => Navigator.pop(ctx)
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

  /// ---------------------------------------------------------------------------
  /// [기능] 장치 등록/수정 다이얼로그 (편집창)
  /// 개발자님이 요청하신 출입 방향 판별 모드(dir_mode) 및 세부 옵션(dir_option) 설정 추가 완료
  /// ---------------------------------------------------------------------------
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

    // [핵심 복구 포인트] 이전에 설계했던 방향 판별 관련 변수들을 선언합니다.
    String dirModeV = d?.settings['dir_mode']?.toString() ?? 'none';
    String dirOptionV = d?.settings['dir_option']?.toString() ?? '3';
    final dirOptionC = TextEditingController(text: dirOptionV);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ListenableProvider.value(
        value: provider,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            bool isWide = MediaQuery.of(context).size.width > 750;
            return AlertDialog(
              title: AppTheme.dialogTitle(d == null ? '신규 장치 등록' : '장치 설정 수정', d == null ? Icons.router : Icons.edit),
              content: SizedBox(
                width: isWide ? 800 : null, // 폼의 요소가 늘어났으므로 살짝 넓혀줍니다.
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 20),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildImagePickerBox(context, d, null, (file, bytes) {}, theme),
                            const SizedBox(width: 30),
                            Expanded(child: _buildFormFields(
                                context, provider, d, nameC, ipC, portC, clientIdC, dirOptionC,
                                modelV, activeV, autoConnectV, usageRoleV, dirModeV, dirOptionV,
                                    (m, a, ac, uR, dM, dO) {
                                  setDialogState(() {
                                    if (m != null) modelV = m;
                                    if (a != null) activeV = a;
                                    if (ac != null) autoConnectV = ac;
                                    if (uR != null) usageRoleV = uR;
                                    if (dM != null) dirModeV = dM;
                                    if (dO != null) dirOptionV = dO;
                                  });
                                }, theme)
                            ),
                          ],
                        )
                      else ...[
                        _buildImagePickerBox(context, d, null, (file, bytes) { }, theme),
                        const SizedBox(height: 20),
                        _buildFormFields(
                            context, provider, d, nameC, ipC, portC, clientIdC, dirOptionC,
                            modelV, activeV, autoConnectV, usageRoleV, dirModeV, dirOptionV,
                                (m, a, ac, uR, dM, dO) {
                              setDialogState(() {
                                if (m != null) modelV = m;
                                if (a != null) activeV = a;
                                if (ac != null) autoConnectV = ac;
                                if (uR != null) usageRoleV = uR;
                                if (dM != null) dirModeV = dM;
                                if (dO != null) dirOptionV = dO;
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
                    onPressed: () => Navigator.pop(ctx)
                ),
                AppTheme.actionButton(
                  label: d == null ? "등록하기" : "수정완료",
                  onPressed: provider.isSaving ? () {} : () async {
                    if (nameC.text.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("장치 명칭은 필수입니다.")));
                      return;
                    }

                    final nav = Navigator.of(ctx);

                    if (d != null && d.status.toLowerCase() == 'online') {
                      provider.disconnectDevice(d.id);
                    }

                    // 입력된 값을 종합하여 저장용 Map 생성
                    final data = {
                      'name': nameC.text.trim(),
                      'model': modelV,
                      'ip_address': ipC.text.trim(),
                      'port': int.tryParse(portC.text.trim()) ?? 8080,
                      'client_id': clientIdC.text.trim(),
                      'is_active': activeV,
                      'is_auto_connect': autoConnectV,
                      'settings': {
                        ...(d?.settings ?? {}),
                        'usage_role': usageRoleV,
                        // [추가] 저장할 때 상태 판별 모드와 옵션값도 포함시킵니다!
                        'dir_mode': dirModeV,
                        // 리더기 고정 모드일 때는 드롭다운 값(IN/OUT)을, 그 외(교차 모드 초(Seconds) 설정 등)일 때는 텍스트 필드 값을 저장합니다.
                        'dir_option': dirModeV == 'reader_fixed' ? dirOptionV : dirOptionC.text.trim(),
                      }
                    };

                    bool success = await provider.handleSave(d: d, data: data);

                    if (success && ctx.mounted) {
                      nav.pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("장치 정보가 안전하게 저장되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)))
                      );
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildImagePickerBox(BuildContext context, DeviceModel? d, Uint8List? preview, Function(XFile, Uint8List) onP, ThemeData theme) {
    final imgUrl = d?.getImageUrl(widget.baseUrl, thumb: '200x200');
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 180, height: 210,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isDark ? Colors.grey.shade600 : Colors.grey.shade400, width: 2)
      ),
      child: imgUrl != null && imgUrl.isNotEmpty
          ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(imgUrl, fit: BoxFit.contain))
          : const Icon(Icons.add_a_photo_outlined, size: 50, color: Colors.grey),
    );
  }

  /// 폼 영역을 그리는 내부 헬퍼 함수 (파라미터를 확장하여 방향 설정 컨트롤을 포함)
  Widget _buildFormFields(
      BuildContext context, DeviceProvider provider, DeviceModel? d,
      TextEditingController n, TextEditingController i, TextEditingController p, TextEditingController c, TextEditingController dirOptionC,
      String mV, bool aV, bool acV, String uRV, String dirModeV, String dirOptionV,
      Function(String?, bool?, bool?, String?, String?, String?) onC,
      ThemeData theme
      ) {
    return Column(
      children: [
        _buildDialogTextField("장치 관리 명칭 (필수)", n, theme, icon: Icons.label_outline),
        const SizedBox(height: 16),
        Row(
            children: [
              Expanded(child: _buildDialogTextField("IP 주소", i, theme, icon: Icons.lan)),
              const SizedBox(width: 16),
              SizedBox(width: 120, child: _buildDialogTextField("Port", p, theme, isNumber: true))
            ]
        ),
        const SizedBox(height: 16),
        _buildDialogTextField("Client ID (Host Serial)", c, theme, icon: Icons.fingerprint),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: mV,
          decoration: AppTheme.inputDecoration(label: "제조사/물리적 모델 프로토콜", context: context),
          items: SupportedDeviceModels.labels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)))).toList(),
          onChanged: (v) => onC(v, null, null, null, null, null),
        ),
        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          initialValue: uRV,
          decoration: AppTheme.inputDecoration(label: "장비 운용 용도 (데이터 라우팅 기준)", context: context),
          items: ['상시감지(출입/물류)', '수동스캔(재고조사)', '수동스캔(단일등록)'].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)))).toList(),
          onChanged: (v) => onC(null, null, null, v, null, null),
        ),
        const SizedBox(height: 24),

        // ---------------------------------------------------------------------
        // [방향 판별 로직 UI 컨트롤 추가 영역]
        // ---------------------------------------------------------------------
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
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('단순 교차 (일정 시간 후 재인식 시 상태 반전)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))),
                  DropdownMenuItem(value: 'ant_fixed', child: Text('안테나 고정 (홀수 번호=IN, 짝수 번호=OUT)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))),
                  DropdownMenuItem(value: 'reader_fixed', child: Text('리더기 고정 (설정한 단일 방향으로 무조건 판별)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))),
                  DropdownMenuItem(value: 'ant_seq', child: Text('안테나 시퀀스 (1번 ➔ 2번 순차 통과 시 IN)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))),
                  DropdownMenuItem(value: 'reader_seq', child: Text('리더기 시퀀스 (리더기간 이동 이력 추적)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))),
                ],
                onChanged: (v) => onC(null, null, null, null, v, null),
              ),

              // 모드에 따른 조건부 하위 옵션 표시
              if (dirModeV == 'none') ...[
                const SizedBox(height: 16),
                _buildDialogTextField("재인식 방지 및 상태 반전 시간(초)", dirOptionC, theme, isNumber: true, icon: Icons.timer_outlined),
              ] else if (dirModeV == 'reader_fixed') ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: ['IN', 'OUT'].contains(dirOptionV) ? dirOptionV : 'IN',
                  decoration: AppTheme.inputDecoration(label: "무조건 고정할 판별 방향", context: context),
                  items: const [
                    DropdownMenuItem(value: 'IN', child: Text('입고 / 입장 (IN)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))),
                    DropdownMenuItem(value: 'OUT', child: Text('출고 / 퇴장 (OUT)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold))),
                  ],
                  onChanged: (v) => onC(null, null, null, null, null, v),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        // ---------------------------------------------------------------------

        if (d != null) ...[
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
                  onChanged: (v) => onC(null, null, v, null, null, null)
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
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
                  onChanged: (v) => onC(null, v, null, null, null, null)
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDialogTextField(String label, TextEditingController ctrl, ThemeData theme, {bool isNumber = false, IconData? icon}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
      decoration: AppTheme.inputDecoration(label: label, context: context, prefixIcon: icon),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [기능] 단일 장치 삭제
  /// ---------------------------------------------------------------------------
  void _confirmDelete(BuildContext context, DeviceProvider provider, DeviceModel d) {
    final theme = Theme.of(context);
    showDialog(context: context, builder: (c) {
      return AlertDialog(
        title: AppTheme.dialogTitle("장치 삭제", Icons.delete, color: AppTheme.danger),
        content: Text("[${d.name}] 장치를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
        actions: [
          AppTheme.actionButton(
              label: "취소",
              color: Colors.transparent,
              textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              onPressed: () => Navigator.pop(c)
          ),
          AppTheme.actionButton(
            label: "삭제 실행",
            color: AppTheme.danger,
            onPressed: () async {
              final nav = Navigator.of(c);

              provider.disconnectDevice(d.id);
              bool result = await provider.deleteDevice(d.id);

              if (result && c.mounted) {
                nav.pop();
              }
            },
          ),
        ],
      );
    });
  }

  /// ---------------------------------------------------------------------------
  /// [기능] 다중 선택: 일괄 통신 해제
  /// ---------------------------------------------------------------------------
  void _handleBulkDisconnect(DeviceProvider provider, ThemeData theme) {
    if (_selectedItemIds.isEmpty) {
      return;
    }

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

  /// ---------------------------------------------------------------------------
  /// [기능] 다중 선택: 일괄 장치 삭제
  /// ---------------------------------------------------------------------------
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
                    onPressed: () => Navigator.pop(ctx)
                ),
                AppTheme.actionButton(
                    label: "일괄 삭제",
                    color: AppTheme.danger,
                    onPressed: () async {
                      Navigator.pop(ctx);
                      setState(() { _isFullScreenLoading = true; });

                      for (String id in _selectedItemIds) {
                        provider.disconnectDevice(id);
                        await provider.deleteDevice(id);
                      }

                      if (!mounted) {
                        return;
                      }

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

  /// ---------------------------------------------------------------------------
  /// [기능] 전체 초기화 (Factory Reset)
  /// ---------------------------------------------------------------------------
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

    setState(() { _isFullScreenLoading = true; });

    try {
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