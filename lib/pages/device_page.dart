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
  // [상태 변수 선언부] (클래스 멤버 변수이므로 언더스코어 _ 사용이 올바름)
  // ---------------------------------------------------------------------------
  final TextEditingController _searchController = TextEditingController();
  String _currentQuery = "";

  String _activeMetricFilter = "전체";

  final Set<String> _selectedItemIds = {};
  bool _isSelectionMode = false;
  bool _isFullScreenLoading = false;

  // 레이아웃 고정 치수 (미니멀 디자인 규격)
  static const double _colImgSize = 70.0;
  // 파워 제어 버튼이 추가되었으므로 액션 영역의 가로폭을 조금 넓혀줍니다.
  static const double _colActionWidth = 300.0;

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
    if (model.contains('SCANNER') || model.contains('RS232')) return FontAwesomeIcons.barcode;
    return FontAwesomeIcons.rss;
  }

  Color _getStatusColor(String status) {
    if (status.toLowerCase() == 'online') return AppTheme.success;
    if (status.toLowerCase() == 'offline') return AppTheme.danger;
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

      if (!matchesSearch) return false;

      if (_activeMetricFilter == "전체") return true;
      if (_activeMetricFilter == "온라인(연결됨)" && d.status.toLowerCase() == 'online') return true;
      if (_activeMetricFilter == "오프라인(끊김)" && d.status.toLowerCase() != 'online') return true;

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
                // [수정됨] 다른 페이지와의 통일성을 위해 "신규 장치 등록" -> "신규 등록"으로 텍스트를 간결하게 변경했습니다.
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
                Text("등록된 장치가 없습니다.", style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 18))
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
                  _buildKeyValue("Client ID", item.clientId.isNotEmpty ? item.clientId : "-", context),
                  _buildKeyValue("초기 자동 연결", item.isAutoConnect ? "사용 (ON)" : "수동 (OFF)", context),
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
              // 장비가 온라인(연결됨) 상태일 때만 파워(출력) 조절 버튼을 활성화하여 보여줍니다.
              if (isOnline) ...[
                _buildCircleAction(Icons.tune, Colors.blueAccent, "출력(파워) 제어", () {
                  _showPowerControlDialog(context, provider, item);
                }),
                const SizedBox(width: 12),
              ],
              // 통신 연결/해제 버튼
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
            _buildKeyValue("초기 자동 연결", item.isAutoConnect ? "사용 (ON)" : "수동 (OFF)", context),
          ],
        ),
        const SizedBox(height: 16),
        Divider(color: theme.dividerTheme.color?.withValues(alpha: 0.5)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 모바일 환경에서도 파워 제어 아이콘 추가
            if (isOnline)
              _buildCircleAction(Icons.tune, Colors.blueAccent, "출력 제어", () {
                _showPowerControlDialog(context, provider, item);
              }),

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
  /// [신규 UI] 안테나 출력(Power) 제어 다이얼로그
  /// 키오스크와 유사하게 크고 직관적인 슬라이더(Slider)를 통해 주파수 세기를 설정합니다.
  /// ---------------------------------------------------------------------------
  void _showPowerControlDialog(BuildContext context, DeviceProvider provider, DeviceModel d) {
    final theme = Theme.of(context);
    int selectedAntenna = 0; // 0: 전체공통, 1~4: 개별 포트
    double currentPower = 300; // 고정식 리더기 매뉴얼상 Default는 300 (30.0 dBm)

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
                        // SegmentedButton으로 터치 친화적인 안테나 선택기를 구성합니다.
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
                        // 슬라이더: 50(5dBm) ~ 310(31dBm) 범위, 간격은 10(1dBm) 단위
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
                          // 브릿지 함수(Provider)를 통해 하드웨어 객체로 파워 변경 명령을 쏘아줍니다!
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
                width: isWide ? 700 : null,
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
                            // 폼 필드 생성 함수에 context, provider, d 객체를 전달하여 내부에서 버튼을 그릴 수 있게 합니다.
                            Expanded(child: _buildFormFields(context, provider, d, nameC, ipC, portC, clientIdC, modelV, activeV, autoConnectV, (m, a, ac) {
                              setDialogState(() {
                                if (m != null) modelV = m;
                                if (a != null) activeV = a;
                                if (ac != null) autoConnectV = ac;
                              });
                            }, theme)),
                          ],
                        )
                      else ...[
                        _buildImagePickerBox(context, d, null, (file, bytes) { }, theme),
                        const SizedBox(height: 20),
                        // 모바일 레이아웃 호출 시에도 동일하게 파라미터 전달
                        _buildFormFields(context, provider, d, nameC, ipC, portC, clientIdC, modelV, activeV, autoConnectV, (m, a, ac) {
                          setDialogState(() {
                            if (m != null) modelV = m;
                            if (a != null) activeV = a;
                            if (ac != null) autoConnectV = ac;
                          });
                        }, theme),
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

                    // 기존 기기 수정 시, 변경된 IP나 Port로 인한 충돌을 막기 위해
                    // 백그라운드 소켓 쓰레드를 안전하게 먼저 끊어버립니다.
                    if (d != null && d.status.toLowerCase() == 'online') {
                      provider.disconnectDevice(d.id);
                    }

                    final data = {
                      'name': nameC.text.trim(),
                      'model': modelV,
                      'ip_address': ipC.text.trim(),
                      'port': int.tryParse(portC.text.trim()) ?? 8080,
                      'client_id': clientIdC.text.trim(),
                      'is_active': activeV,
                      'is_auto_connect': autoConnectV,
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

  // 편집 폼 내부에서도 장치의 상태(d)와 프로바이더를 사용할 수 있도록 파라미터를 추가했습니다.
  Widget _buildFormFields(BuildContext context, DeviceProvider provider, DeviceModel? d, TextEditingController n, TextEditingController i, TextEditingController p, TextEditingController c, String mV, bool aV, bool acV, Function(String?, bool?, bool?) onC, ThemeData theme) {
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
          decoration: AppTheme.inputDecoration(label: "제조사/모델 프로토콜", context: context),
          items: SupportedDeviceModels.labels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)))).toList(),
          onChanged: (v) => onC(v, null, null),
        ),
        const SizedBox(height: 24),

        // 장치 편집창 내부에서도 실시간 파워 제어 다이얼로그를 띄울 수 있는 버튼을 추가합니다!
        // 사용자가 실수하지 않도록 장비가 '연결(Online)' 되어있을 때만 동작하도록 방어 로직을 적용했습니다.
        if (d != null) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.tune, size: 20),
              label: const Text("안테나 출력(RF Power) 실시간 제어", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: d.status.toLowerCase() == 'online' ? Colors.blueAccent.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                  foregroundColor: d.status.toLowerCase() == 'online' ? Colors.blueAccent : Colors.grey,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(color: d.status.toLowerCase() == 'online' ? Colors.blueAccent.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.3))
              ),
              onPressed: d.status.toLowerCase() == 'online' ? () {
                // 편집창 위에 파워 제어 팝업창을 겹쳐서 띄웁니다.
                _showPowerControlDialog(context, provider, d);
              } : () {
                // 연결되지 않았을 때는 툴팁처럼 스낵바를 띄워 직관성을 높입니다.
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
                  onChanged: (v) => onC(null, null, v)
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
                  onChanged: (v) => onC(null, v, null)
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
    if (_selectedItemIds.isEmpty) return;

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
    if (_selectedItemIds.isEmpty) return;

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

                      if (!mounted) return;

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

    if (!mounted || confirm != true) return;

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