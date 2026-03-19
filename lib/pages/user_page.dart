import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'dart:convert'; // 태그 데이터 UTF-8 -> Hex 변환용
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/user_model.dart';
import '../utils/hangul_utils.dart';
import '../providers/user_provider.dart';
import '../providers/auth_provider.dart';
import '../models/device_model.dart';
import '../providers/device_provider.dart';
import '../theme/app_theme.dart';
import '../core/erp_sync_helper.dart';

// AI 자연어 스마트 검색 헬퍼 임포트
import '../core/ai_search_helper.dart';

// [공용 위젯 임포트] 표시 항목 설정 및 일괄 편집 다이얼로그
import '../widgets/column_selection_dialog.dart';
import '../widgets/bulk_edit_dialog.dart';

/// ---------------------------------------------------------------------------
/// [안전한 문자열 변환 유틸리티]
/// 데이터베이스의 null 값이나 빈 값을 UI에서 안전하게 처리합니다.
/// ---------------------------------------------------------------------------
String _safeStr(dynamic value, {String defaultVal = ""}) {
  if (value == null) {
    return defaultVal;
  }

  final String str = value.toString().trim();

  if (str.isEmpty || str == "null") {
    return defaultVal;
  }

  return str;
}

/// ---------------------------------------------------------------------------
/// [RFID 인원 관리 페이지 (UserPage)]
/// ---------------------------------------------------------------------------
class UserPage extends StatefulWidget {
  final String searchQuery;
  final String filter;
  final bool isMobile;
  final String baseUrl;

  const UserPage({
    super.key,
    required this.searchQuery,
    required this.filter,
    required this.isMobile,
    required this.baseUrl,
  });

  @override
  State<UserPage> createState() {
    return _UserPageState();
  }
}

class _UserPageState extends State<UserPage> {
  final TextEditingController _searchController = TextEditingController();

  String _currentSearchQuery = "";
  late String _currentFilter;
  String _activeMetricFilter = "전체";

  final Set<String> _selectedUserIds = {};
  bool _isSelectionMode = false;
  bool _isFullScreenLoading = false;

  List<String>? _aiFilteredIds;
  bool _isAiSearching = false;

  static const double _colImgSize = 70.0;
  static const double _colActionWidth = 300.0;

  static const Set<String> _excludedSystemKeys = {
    'import_source', 'original_row_data', 'id', 'created', 'updated',
    'collectionId', 'collectionName', 'last_access_type', 'last_access_time',
    'access_history', 'last_location_info', 'is_approved', 'last_approval_status',
    'image', 'avatar', 'name', 'code', 'department', 'tag_id', 'is_active', 'remarks',
    'excel_row', 'import_date', 'import_data', 'is_auto_tag', 'is_auto_atg',
    'excel_row_internal', 'import_data_internal', 'is_auto_tag_internal', 'error_reason',
    'email', 'username', 'password', 'passwordConfirm', 'app_login_id', 'app_login_email',
    'role'
  };

  @override
  void initState() {
    super.initState();
    _currentFilter = (widget.filter == '정상 등록') ? '등록' : widget.filter;
    _currentSearchQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// [위치정보 파싱 헬퍼]
  String _getLocationFullName(UserModel item) {
    if (item.metadata['last_location_info'] is Map) {
      final Map locMap = item.metadata['last_location_info'] as Map;
      return _safeStr(locMap['full_name'], defaultVal: "위치 정보 없음");
    }
    return "위치 정보 없음";
  }

  Future<void> _performAiSearch(List<UserModel> allUsers, ThemeData theme) async {
    final String query = _searchController.text.trim();

    if (query.isEmpty) {
      _showInfoDialog("AI 검색 안내", "검색창에 찾고 싶은 조건을 자연어(문장)로 입력해 주세요.\n예: '영업팀이면서 권한이 관리자인 사람 찾아줘'", theme);
      return;
    }

    setState(() {
      _isAiSearching = true;
      _aiFilteredIds = null;
    });

    try {
      final List<String> resultIds = await AiSearchHelper.searchUsers(query, allUsers);

      if (!mounted) {
        return;
      }

      setState(() {
        _aiFilteredIds = resultIds;
      });

      if (resultIds.isEmpty) {
        _showInfoDialog("AI 검색 결과", "입력하신 조건과 일치하는 인원을 찾을 수 없습니다.", theme);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showInfoDialog("AI 검색 오류", e.toString(), theme);
    } finally {
      if (mounted) {
        setState(() {
          _isAiSearching = false;
        });
      }
    }
  }

  int _getRoleRank(String role) {
    final String r = role.toLowerCase();
    if (r.contains('admin') || r.contains('최고')) {
      return 3;
    }
    if (r.contains('manager') || r.contains('현장')) {
      return 2;
    }
    return 1;
  }

  String _getDisplayRole(String dbRole) {
    if (dbRole == 'Admin') {
      return '최고관리자 (Admin)';
    }
    if (dbRole == 'Manager') {
      return '현장관리자 (Manager)';
    }
    if (dbRole == 'Operator') {
      return '일반작업자 (Operator)';
    }
    if (dbRole.isNotEmpty) {
      return dbRole;
    }
    return '일반작업자 (Operator)';
  }

  String _getDbRole(String displayRole) {
    if (displayRole.contains('최고관리자') || displayRole.toLowerCase().contains('admin')) {
      return 'Admin';
    }
    if (displayRole.contains('현장관리자') || displayRole.toLowerCase().contains('manager')) {
      return 'Manager';
    }
    if (displayRole.contains('일반작업자') || displayRole.toLowerCase().contains('operator')) {
      return 'Operator';
    }
    return displayRole;
  }

  Map<String, dynamic> _calculateMetrics(List<UserModel> list) {
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0;
    int todayOut = 0;
    int currentRemained = 0;

    for (final UserModel p in list) {
      final String lastType = _safeStr(p.metadata['last_access_type']);
      final String lastTime = _safeStr(p.metadata['last_access_time']);

      if (lastTime.startsWith(todayStr)) {
        if (lastType == '입장') {
          todayIn++;
        } else if (lastType == '퇴장') {
          todayOut++;
        }
      }

      if (lastType == '입장') {
        currentRemained++;
      }
    }

    return {'in': todayIn, 'out': todayOut, 'current': currentRemained};
  }

  Future<void> _processAccessWithLocation(UserProvider provider, UserModel p, String type) async {
    final authProvider = context.read<AuthProvider>();
    bool isSelf = p.id == authProvider.currentUserId;
    int myRank = _getRoleRank(authProvider.role);
    int targetRank = _getRoleRank(p.role);

    if (!authProvider.isAdmin && !isSelf && myRank <= targetRank) {
      _showInfoDialog("권한 없음", "동일 등급이거나 상위 등급인 다른 사용자의 출입 기록은 조작할 수 없습니다.", Theme.of(context));
      return;
    }

    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext ctx) {
        return _LocationSelectionDialog(type: type, existingUsers: provider.list);
      },
    );

    if (!mounted || result == null) {
      return;
    }

    final String now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final dynamic rawApprove = result['is_approved'];
    final bool isApproved = (rawApprove is bool) ? rawApprove : true;

    final Map<String, dynamic> updatedMeta = Map<String, dynamic>.from(p.metadata);
    updatedMeta['last_access_type'] = type;
    updatedMeta['last_access_time'] = now;
    updatedMeta['last_approval_status'] = isApproved;
    updatedMeta['last_location_info'] = {
      'building': _safeStr(result['building'], defaultVal: "미지정"),
      'gate': _safeStr(result['gate'], defaultVal: "미지정"),
      'full_name': "${_safeStr(result['building'])} - ${_safeStr(result['gate'])}"
    };

    List<dynamic> history = (updatedMeta['access_history'] is List) ? List.from(updatedMeta['access_history']) : [];
    history.insert(0, {
      'time': now,
      'type': type,
      'mode': '수동',
      'is_approved': isApproved,
      'location': updatedMeta['last_location_info']
    });

    if (history.length > 50) {
      history = history.sublist(0, 50);
    }
    updatedMeta['access_history'] = history;

    final Map<String, dynamic> updateData = {
      'is_approved': isApproved,
      'metadata': updatedMeta,
    };

    final String saveResult = await provider.handleSave(p: p, data: updateData);

    if (!mounted) {
      return;
    }

    if (saveResult.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('[${p.name}]님 $type 처리 완료', style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
        backgroundColor: isApproved ? AppTheme.success : AppTheme.danger,
        elevation: 0,
        duration: const Duration(seconds: 1),
      ));
    } else {
      _showInfoDialog(
          "처리 실패",
          "데이터베이스 업데이트 중 오류가 발생했습니다.\n\n[상세 내용]\n$saveResult",
          Theme.of(context)
      );
    }
  }

  Future<void> _handleSingleUserImageUpdate(UserProvider provider, UserModel user, ThemeData theme) async {
    final authProvider = context.read<AuthProvider>();
    bool isSelf = user.id == authProvider.currentUserId;
    int myRank = _getRoleRank(authProvider.role);
    int targetRank = _getRoleRank(user.role);

    if (!authProvider.isAdmin && !isSelf && myRank <= targetRank) {
      _showInfoDialog("권한 없음", "동일 등급이거나 상위 등급인 다른 사용자의 사진은 변경할 수 없습니다.", theme);
      return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (!mounted || image == null) {
      return;
    }

    final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("프로필 사진 변경", Icons.photo_camera_front),
              content: Text("[${user.name}]님의 프로필 사진을 선택하신 이미지로 즉시 변경하시겠습니까?", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
              actions: [
                AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.6), onPressed: () {
                  Navigator.pop(ctx, false);
                }),
                AppTheme.actionButton(label: "사진 변경", color: AppTheme.primary, onPressed: () {
                  Navigator.pop(ctx, true);
                }),
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
      final Map<String, dynamic> data = {
        'name': user.name,
        'code': user.code,
        'tag_id': user.tagId,
        'department': user.department,
        'role': user.role,
        'is_approved': user.isApproved,
        'metadata': user.metadata,
      };

      final String saveResult = await provider.handleSave(p: user, data: data, imageXFile: image);

      if (!mounted) {
        return;
      }

      if (saveResult.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 사진이 성공적으로 변경되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
      } else {
        _showInfoDialog("변경 실패", "사진 업데이트 중 오류가 발생했습니다.\n\n[상세 내용]\n$saveResult", theme);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFullScreenLoading = false;
        });
      }
    }
  }

  void _triggerErpSync(ThemeData theme) {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAdmin && _getRoleRank(authProvider.role) < 2) {
      _showInfoDialog("권한 없음", "데이터 일괄 연동 작업은 현장관리자(Manager) 이상만 가능합니다.", theme);
      return;
    }

    ErpSyncHelper.fetchAndSync(
      context: context,
      theme: theme,
      moduleName: "인원(인사) 마스터 (REST API 동적 매핑)",
      endpoint: 'users?_limit=5',
      targetCollection: 'users',
      dataMapper: (Map<String, dynamic> erpItem) {
        String parsedName = "이름없음";
        String parsedCode = "";
        String parsedDept = "미지정";
        String parsedRole = "Operator";
        String parsedTagId = "";

        Map<String, dynamic> dynamicMetadata = {};

        erpItem.forEach((String key, dynamic value) {
          if (value == null) {
            return;
          }
          final String lowerKey = key.toLowerCase();
          final String strValue = value.toString().trim();

          if (lowerKey.contains('name') || lowerKey.contains('이름') || lowerKey.contains('성명')) {
            parsedName = strValue;
          } else if (lowerKey == 'id' || lowerKey.contains('code') || lowerKey.contains('사번') || lowerKey.contains('사원번호')) {
            parsedCode = strValue;
          } else if (lowerKey.contains('dept') || lowerKey.contains('department') || lowerKey.contains('company') || lowerKey.contains('부서') || lowerKey.contains('소속')) {
            parsedDept = strValue;
          } else if (lowerKey.contains('role') || lowerKey.contains('등급') || lowerKey.contains('직급') || lowerKey.contains('level')) {
            parsedRole = _getDbRole(strValue);
          } else if (lowerKey.contains('tag') || lowerKey.contains('rfid') || lowerKey.contains('epc')) {
            parsedTagId = strValue;
          } else {
            if (strValue.isNotEmpty && strValue != "null") {
              dynamicMetadata[key] = strValue;
            }
          }
        });

        if (parsedCode.isEmpty) {
          parsedCode = "EMP_${DateTime.now().millisecondsSinceEpoch % 100000}";
        }
        if (parsedTagId.isEmpty) {
          parsedTagId = "TAG_$parsedCode";
        }

        String safeUsername = parsedCode.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.-]'), '');
        if (safeUsername.isEmpty || safeUsername.length < 3) {
          safeUsername = 'user_${DateTime.now().millisecondsSinceEpoch % 1000000}';
        }

        return {
          'username': safeUsername,
          'email': '$safeUsername@plug4rfid.local',
          'password': 'password123',
          'passwordConfirm': 'password123',
          'name': '[ERP] $parsedName',
          'code': parsedCode,
          'tag_id': parsedTagId,
          'department': parsedDept,
          'role': parsedRole,
          'is_approved': true,
          'metadata': dynamicMetadata,
        };
      },
      onLoadingStart: () {
        if (mounted) {
          setState(() { _isFullScreenLoading = true; });
        }
      },
      onLoadingComplete: () {
        if (mounted) {
          setState(() { _isFullScreenLoading = false; });
        }
      },
      onSuccess: () {
        context.read<UserProvider>().fetchData();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final UserProvider provider = context.watch<UserProvider>();
    final ThemeData theme = Theme.of(context);
    final Map<String, dynamic> metrics = _calculateMetrics(provider.list);

    final List<UserModel> filteredList = provider.list.where((UserModel p) {
      if (_aiFilteredIds != null) {
        if (!_aiFilteredIds!.contains(p.id)) {
          return false;
        }
      } else {
        final bool matchesFilter = (_currentFilter == '전체') || (_currentFilter == '등록' ? p.tagId.isNotEmpty : p.tagId.isEmpty);

        bool matchesSearch = false;
        final String q = _currentSearchQuery.trim().toLowerCase();

        if (q.isEmpty) {
          matchesSearch = true;
        } else {
          matchesSearch = HangulUtils.matches(_currentSearchQuery, p.name) ||
              p.code.toLowerCase().contains(q) ||
              p.department.toLowerCase().contains(q) ||
              p.role.toLowerCase().contains(q) ||
              _getDisplayRole(p.role).toLowerCase().contains(q) ||
              p.tagId.toLowerCase().contains(q);

          if (!matchesSearch) {
            for (final dynamic value in p.metadata.values) {
              if (value != null && value.toString().toLowerCase().contains(q)) {
                matchesSearch = true;
                break;
              }
            }
          }
        }

        if (!matchesFilter || !matchesSearch) {
          return false;
        }
      }

      if (_activeMetricFilter == "전체") {
        return true;
      }

      final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final String lastType = _safeStr(p.metadata['last_access_type']);
      final String lastTime = _safeStr(p.metadata['last_access_time']);

      if (_activeMetricFilter == "당일 입장") {
        return (lastType == '입장' && lastTime.startsWith(todayStr));
      }
      if (_activeMetricFilter == "당일 퇴장") {
        return (lastType == '퇴장' && lastTime.startsWith(todayStr));
      }
      if (_activeMetricFilter == "현재 잔류") {
        return (lastType == '입장');
      }

      return true;
    }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              _buildDashboard(metrics, provider, theme),
              Divider(height: 1, color: theme.dividerTheme.color),
              _buildHeader(provider, filteredList, theme),
              const SizedBox(height: 16),
              Expanded(
                child: provider.isLoading
                    ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                    : _buildListView(filteredList, provider, provider.selectedColumns, theme),
              ),
            ],
          ),

          (provider.isSaving || _isFullScreenLoading) ? _buildGlobalLoadingOverlay(theme) : const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildGlobalLoadingOverlay(ThemeData theme) {
    return Container(
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
                CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 5),
                SizedBox(height: 25),
                Text("데이터베이스 처리 중...", textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 15)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(Map<String, dynamic> m, UserProvider provider, ThemeData theme) {
    if (widget.isMobile) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: theme.scaffoldBackgroundColor,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildStatTile("전체 보기", provider.list.length, Icons.people, Colors.blueGrey, theme, filterKey: "전체")),
                const SizedBox(width: 12),
                Expanded(child: _buildStatTile("당일 입장", m['in'] as int, Icons.login, AppTheme.success, theme, filterKey: "당일 입장")),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatTile("당일 퇴장", m['out'] as int, Icons.logout, AppTheme.warning, theme, filterKey: "당일 퇴장")),
                const SizedBox(width: 12),
                Expanded(child: _buildStatTile("현재 잔류", m['current'] as int, Icons.person_search, theme.colorScheme.primary, theme, filterKey: "현재 잔류")),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.scaffoldBackgroundColor,
      child: Row(
        children: [
          Expanded(child: _buildStatTile("전체 보기", provider.list.length, Icons.people, Colors.blueGrey, theme, filterKey: "전체")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("당일 입장", m['in'] as int, Icons.login, AppTheme.success, theme, filterKey: "당일 입장")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("당일 퇴장", m['out'] as int, Icons.logout, AppTheme.warning, theme, filterKey: "당일 퇴장")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("현재 잔류", m['current'] as int, Icons.person_search, theme.colorScheme.primary, theme, filterKey: "현재 잔류")),
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
          _activeMetricFilter = (_activeMetricFilter == filterKey) ? "전체" : filterKey;
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
                  Text(label, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 11, color: color.withValues(alpha: 0.7), fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  Text('$val', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 22, fontWeight: FontWeight.w900, color: color), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(UserProvider provider, List<UserModel> filtered, ThemeData theme) {
    Widget searchSuffix;

    if (_isAiSearching) {
      searchSuffix = const Padding(
        padding: EdgeInsets.all(14.0),
        child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.deepPurpleAccent),
        ),
      );
    } else {
      searchSuffix = IconButton(
        icon: const Icon(Icons.auto_awesome_rounded, color: Colors.deepPurpleAccent),
        tooltip: "AI 자연어 스마트 검색 (예: 영업팀 김씨 찾아줘)",
        onPressed: () {
          _performAiSearch(provider.list, theme);
        },
      );
    }

    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: widget.isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12, runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildActionIcon(Icons.refresh, "새로고침", () { provider.fetchData(); }, theme),
                    _buildActionIcon(
                      _isSelectionMode ? Icons.close_fullscreen_rounded : Icons.checklist_rtl_rounded,
                      _isSelectionMode ? "다중 선택 끄기" : "다중 선택 켜기",
                          () {
                        setState(() {
                          _isSelectionMode = !_isSelectionMode;
                          if (!_isSelectionMode) {
                            _selectedUserIds.clear();
                          }
                        });
                      },
                      theme,
                      color: _isSelectionMode ? AppTheme.primary : null,
                    ),
                    _buildActionIcon(Icons.sync_alt_rounded, "인사 시스템(ERP) 연동", () { _triggerErpSync(theme); }, theme, color: Colors.teal),
                    _buildActionIcon(FontAwesomeIcons.fileArrowUp, "엑셀 업로드", () { _handleBatchImport(provider, theme); }, theme, color: Colors.indigo),
                    _buildActionIcon(FontAwesomeIcons.fileArrowDown, "엑스포트", () { _exportToExcel(filtered); }, theme, color: Colors.green),
                    _buildActionIcon(Icons.settings_outlined, "표시 항목 설정", () { _showColumnSelectionDialog(provider, theme); }, theme),
                    _buildActionIcon(Icons.delete_sweep_outlined, "초기화", () { _showResetConfirmationDialog(provider, theme); }, theme, color: AppTheme.danger),
                    _buildActionIcon(Icons.person_add_alt_1, "신규 인원 등록", () { _showForm(provider, null, theme); }, theme, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (String v) {
              setState(() {
                _currentSearchQuery = v;
                _aiFilteredIds = null;
              });
            },
            style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(isDark)),
            decoration: AppTheme.inputDecoration(
                label: "일반 검색 또는 문장으로 작성 후 우측 AI 버튼 클릭...",
                context: context,
                prefixIcon: Icons.search
            ).copyWith(
                suffixIcon: searchSuffix
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, String tip, VoidCallback onTap, ThemeData theme, {Color? color, bool isLarge = false}) {
    final Color iconColor = color ?? theme.iconTheme.color ?? Colors.grey.shade600;

    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          width: 52, height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconColor.withValues(alpha: 0.08),
            border: Border.all(color: iconColor.withValues(alpha: 0.15), width: 1.5),
          ),
          child: Icon(icon, color: iconColor, size: isLarge ? 28 : 22),
        ),
      ),
    );
  }

  Widget _buildListView(List<UserModel> list, UserProvider provider, List<String> columns, ThemeData theme) {
    if (list.isEmpty) {
      return _buildEmptyState("데이터가 없습니다.");
    }

    final bool isAllSelected = list.isNotEmpty && list.every((UserModel p) => _selectedUserIds.contains(p.id));
    final bool isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        _isSelectionMode ? Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text('${_selectedUserIds.length}명 선택됨', style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  ),
                  const SizedBox(width: 12),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.wifi_tethering, size: 18),
                    label: const Text("태그 일괄 발행", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, elevation: 0),
                    onPressed: () {
                      if (_selectedUserIds.isEmpty) {
                        _showInfoDialog("알림", "태그발행 대상건을 선정하지 않았습니다!", theme);
                        return;
                      }

                      final authProvider = context.read<AuthProvider>();
                      int myRank = _getRoleRank(authProvider.role);
                      final List<UserModel> selectedUsers = list.where((UserModel u) => _selectedUserIds.contains(u.id)).toList();

                      bool hasUnauthorized = selectedUsers.any((u) {
                        bool isSelf = u.id == authProvider.currentUserId;
                        int targetRank = _getRoleRank(u.role);
                        return !authProvider.isAdmin && !isSelf && (myRank <= targetRank);
                      });

                      if (hasUnauthorized) {
                        _showInfoDialog("권한 없음", "선택된 항목 중 태그 발행 권한이 없는 사용자(동일/상위 등급)가 포함되어 있습니다.", theme);
                        return;
                      }

                      final deviceProvider = context.read<DeviceProvider>(); // 🔥 DeviceProvider를 직접 가져와서 주입
                      showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (BuildContext ctx) {
                            return _BulkTagIssueDialog(
                              selectedUsers: selectedUsers,
                              userProvider: provider,
                              deviceProvider: deviceProvider, // 전달
                              theme: theme,
                            );
                          }
                      );
                    },
                  ),
                  const SizedBox(width: 8),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text("일괄 편집", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, elevation: 0),
                    onPressed: () {
                      _showBulkEditDialog(provider, list, theme);
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
                          _selectedUserIds.clear();
                        } else {
                          for (final UserModel e in list) {
                            _selectedUserIds.add(e.id);
                          }
                        }
                      });
                    },
                  ),
                ],
              ),
            )
        ) : Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text('총 ${list.length}명 조회됨', style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13)),
        ),

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
                final UserModel item = list[idx];
                final bool isSelected = _selectedUserIds.contains(item.id);
                final String status = _safeStr(item.metadata['last_access_type'], defaultVal: "미확인");

                Color cardBgColor = theme.cardTheme.color ?? Colors.white;
                if (isSelected) {
                  cardBgColor = AppTheme.primary.withValues(alpha: 0.05);
                }

                Color cardBorderColor = Colors.black.withValues(alpha: 0.12);
                if (isSelected) {
                  cardBorderColor = AppTheme.primary;
                } else if (isDark) {
                  cardBorderColor = Colors.white.withValues(alpha: 0.15);
                }

                return Row(
                  children: [
                    _isSelectionMode ? Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedUserIds.remove(item.id);
                            } else {
                              _selectedUserIds.add(item.id);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Container(
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
                    ) : const SizedBox.shrink(),

                    Expanded(
                      child: Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: cardBgColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: cardBorderColor, width: isSelected ? 2.0 : 1.0),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: InkWell(
                          onTap: () {
                            if (_isSelectionMode) {
                              setState(() {
                                if (isSelected) {
                                  _selectedUserIds.remove(item.id);
                                } else {
                                  _selectedUserIds.add(item.id);
                                }
                              });
                            } else {
                              _showForm(provider, item, theme);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: widget.isMobile
                                ? _buildMobileListItem(item, provider, columns, status, theme)
                                : _buildDesktopListItem(item, provider, columns, status, theme),
                          ),
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

  Widget _buildDesktopListItem(UserModel item, UserProvider provider, List<String> columns, String status, ThemeData theme) {
    Color? nameColor;
    if (item.name == '형식에 맞지 않는 건') {
      nameColor = AppTheme.danger;
    }

    return Row(
      children: [
        GestureDetector(
          onTap: () {
            _handleSingleUserImageUpdate(provider, item, theme);
          },
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              _buildAvatar(item, theme, size: _colImgSize),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle, border: Border.all(color: theme.cardTheme.color ?? Colors.white, width: 2)),
                child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      item.name,
                      style: AppTheme.itemValueStyle(context).copyWith(fontSize: 19, color: nameColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildStatusBadge(status),
                  (!item.isApproved) ? const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18)) : const SizedBox.shrink(),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 20, runSpacing: 8,
                children: columns.map((String col) {
                  return SizedBox(
                    width: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(col, style: AppTheme.itemLabelStyle(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(_getMetaValue(item, col), style: AppTheme.itemValueStyle(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                  _getLocationFullName(item),
                  style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13, fontWeight: FontWeight.w500)
              ),
            ],
          ),
        ),
        SizedBox(
          width: _colActionWidth,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildCircleAction(Icons.nfc_rounded, Colors.indigo, "개별 태그 발행", () {
                  final authProvider = context.read<AuthProvider>();
                  bool isSelf = item.id == authProvider.currentUserId;
                  int myRank = _getRoleRank(authProvider.role);
                  int targetRank = _getRoleRank(item.role);

                  if (!authProvider.isAdmin && !isSelf && myRank <= targetRank) {
                    _showInfoDialog("권한 없음", "동일 등급이거나 상위 등급인 다른 사용자의 태그는 발행할 수 없습니다.", theme);
                    return;
                  }

                  final deviceProvider = context.read<DeviceProvider>(); // 🔥 DeviceProvider 주입
                  showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (BuildContext ctx) {
                        return _BulkTagIssueDialog(
                          selectedUsers: [item],
                          userProvider: provider,
                          deviceProvider: deviceProvider, // 전달
                          theme: theme,
                        );
                      }
                  );
                }),
                const SizedBox(width: 12),
                _buildCircleAction(Icons.history, Colors.blueGrey, "기록", () { _showHistoryDialog(context, item, theme); }),
                const SizedBox(width: 12),
                _buildCircleAction(Icons.login, AppTheme.success, "입장", () { _processAccessWithLocation(provider, item, '입장'); }),
                const SizedBox(width: 12),
                _buildCircleAction(Icons.logout, AppTheme.warning, "퇴장", () { _processAccessWithLocation(provider, item, '퇴장'); }),
                const SizedBox(width: 12),
                _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () { _confirmDelete(provider, item, theme); }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileListItem(UserModel item, UserProvider provider, List<String> columns, String status, ThemeData theme) {
    Color? nameColor;
    if (item.name == '형식에 맞지 않는 건') {
      nameColor = AppTheme.danger;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                _handleSingleUserImageUpdate(provider, item, theme);
              },
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  _buildAvatar(item, theme, size: _colImgSize),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle, border: Border.all(color: theme.cardTheme.color ?? Colors.white, width: 2)),
                    child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(item.name,
                          style: AppTheme.itemValueStyle(context).copyWith(fontSize: 19, color: nameColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(status),
                      (!item.isApproved) ? const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18)) : const SizedBox.shrink(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                      _getLocationFullName(item),
                      style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13, fontWeight: FontWeight.w500)
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16, runSpacing: 8,
          children: columns.map((String col) {
            return SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(col, style: AppTheme.itemLabelStyle(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(_getMetaValue(item, col), style: AppTheme.itemValueStyle(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Divider(color: theme.dividerTheme.color?.withValues(alpha: 0.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 12,
          alignment: WrapAlignment.spaceEvenly,
          children: [
            _buildCircleAction(Icons.nfc_rounded, Colors.indigo, "개별 태그 발행", () {
              final authProvider = context.read<AuthProvider>();
              bool isSelf = item.id == authProvider.currentUserId;
              int myRank = _getRoleRank(authProvider.role);
              int targetRank = _getRoleRank(item.role);

              if (!authProvider.isAdmin && !isSelf && myRank <= targetRank) {
                _showInfoDialog("권한 없음", "동일 등급이거나 상위 등급인 다른 사용자의 태그는 발행할 수 없습니다.", theme);
                return;
              }

              final deviceProvider = context.read<DeviceProvider>(); // 🔥 DeviceProvider 주입
              showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext ctx) {
                    return _BulkTagIssueDialog(
                      selectedUsers: [item],
                      userProvider: provider,
                      deviceProvider: deviceProvider, // 전달
                      theme: theme,
                    );
                  }
              );
            }),
            _buildCircleAction(Icons.history, Colors.blueGrey, "기록", () {
              _showHistoryDialog(context, item, theme);
            }),
            _buildCircleAction(Icons.login, AppTheme.success, "입장", () {
              _processAccessWithLocation(provider, item, '입장');
            }),
            _buildCircleAction(Icons.logout, AppTheme.warning, "퇴장", () {
              _processAccessWithLocation(provider, item, '퇴장');
            }),
            _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () {
              _confirmDelete(provider, item, theme);
            }),
          ],
        ),
      ],
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

  Widget _buildAvatar(UserModel item, ThemeData theme, {double size = 44}) {
    final String? url = item.getImageUrl(widget.baseUrl, thumb: '100x100');
    final bool isDark = theme.brightness == Brightness.dark;

    Color avatarBgColor = const Color(0xFFF1F3F5);
    if (isDark && theme.dividerTheme.color != null) {
      avatarBgColor = theme.dividerTheme.color!.withValues(alpha: 0.1);
    }

    if (url == null || url.isEmpty) {
      return Container(
          width: size, height: size,
          decoration: BoxDecoration(
              color: avatarBgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 1.5)
          ),
          clipBehavior: Clip.antiAlias,
          child: const Icon(Icons.person_outline, color: Colors.black12, size: 30)
      );
    }

    final String connector = url.contains('?') ? '&' : '?';
    final String fullUrl = "$url${connector}t=${item.hashCode}";

    return Container(
        width: size, height: size,
        decoration: BoxDecoration(
            color: avatarBgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 1.5)
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
            fullUrl,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
              return const Icon(Icons.person, color: Colors.black12);
            }
        )
    );
  }

  Widget _buildStatusBadge(String status) {
    Color badgeColor = Colors.grey;
    if (status == '입장') {
      badgeColor = AppTheme.success;
    } else if (status == '퇴장') {
      badgeColor = AppTheme.warning;
    }

    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(status, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: badgeColor, fontSize: 12, fontWeight: FontWeight.w900))
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 100, color: Colors.grey[300]),
              const SizedBox(height: 20),
              Text(msg, style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 18))
            ]
        )
    );
  }

  String _getMetaValue(UserModel item, String key) {
    final Map<String, String> baseFields = {
      '성명': item.name,
      '사번': item.code,
      '부서': item.department,
      '권한/등급': _getDisplayRole(item.role),
      '태그ID': item.tagId
    };

    if (baseFields.containsKey(key)) {
      return baseFields[key]!;
    }

    return _safeStr(item.metadata[key], defaultVal: "-");
  }

  void _showInfoDialog(String title, String msg, ThemeData theme) {
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle(title, Icons.info_outline),
              content: Text(msg, style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
              actions: [
                AppTheme.actionButton(label: "확인", onPressed: () {
                  Navigator.pop(ctx);
                })
              ]
          );
        }
    );
  }

  void _showBulkEditDialog(UserProvider provider, List<UserModel> visibleItems, ThemeData theme) async {
    final authProvider = context.read<AuthProvider>();
    int myRank = _getRoleRank(authProvider.role);

    final List<UserModel> selectedUsers = visibleItems.where((UserModel p) {
      return _selectedUserIds.contains(p.id);
    }).toList();

    bool hasUnauthorized = selectedUsers.any((u) {
      int targetRank = _getRoleRank(u.role);
      return !authProvider.isAdmin && (myRank <= targetRank);
    });

    if (hasUnauthorized) {
      _showInfoDialog("권한 없음", "선택된 항목 중 편집 권한이 없는 사용자(본인/동일/상위 등급)가 포함되어 있습니다.\n하위 등급의 작업자만 선택하여 일괄 편집해 주세요.", theme);
      return;
    }

    if (selectedUsers.isEmpty) {
      return;
    }

    List<BulkEditField> fields = [
      BulkEditField(key: 'department', label: '새로운 담당부서/소속', type: BulkEditFieldType.text),
      BulkEditField(key: 'role', label: '새로운 권한/등급', type: BulkEditFieldType.text),
      BulkEditField(key: 'remarks', label: '새로운 공통 비고', type: BulkEditFieldType.text),
      BulkEditField(key: 'is_approved', label: '출입 승인 상태 일괄 변경', type: BulkEditFieldType.toggle, initialValue: true),
    ];

    final Set<String> metaKeySet = {};
    for (final UserModel p in provider.list) {
      for (final String k in p.metadata.keys) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal')) {
          metaKeySet.add(k);
        }
      }
    }
    final List<String> metaFields = metaKeySet.toList()..sort();

    for (String metaKey in metaFields) {
      fields.add(BulkEditField(key: metaKey, label: '추가항목: $metaKey', type: BulkEditFieldType.text));
    }

    final Map<String, dynamic>? resultValues = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return BulkEditDialog(title: '${selectedUsers.length}명 인원 정보 일괄 편집', fields: fields);
        }
    );

    if (!mounted || resultValues == null) {
      return;
    }

    setState(() {
      _isFullScreenLoading = true;
    });

    for (final UserModel p in selectedUsers) {
      final Map<String, dynamic> data = {};
      final Map<String, dynamic> updatedMeta = Map<String, dynamic>.from(p.metadata);

      resultValues.forEach((String key, dynamic value) {
        if (key == 'department') {
          data['department'] = value;
        } else if (key == 'remarks') {
          data['remarks'] = value;
        } else if (key == 'is_approved') {
          data['is_approved'] = value;
        } else if (key == 'role') {
          data['role'] = _getDbRole(value.toString());
        } else {
          updatedMeta[key] = value;
        }
      });
      data['metadata'] = updatedMeta;
      await provider.handleSave(p: p, data: data);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isFullScreenLoading = false;
      _selectedUserIds.clear();
      _isSelectionMode = false;
    });
    _showInfoDialog("일괄 편집 완료", "선택하신 ${selectedUsers.length}명의 데이터가 성공적으로 업데이트 되었습니다.", theme);
  }

  void _confirmBulkDelete(UserProvider provider, ThemeData theme) {
    final authProvider = context.read<AuthProvider>();
    int myRank = _getRoleRank(authProvider.role);

    final List<UserModel> selectedUsers = provider.list.where((UserModel p) {
      return _selectedUserIds.contains(p.id);
    }).toList();

    bool hasUnauthorized = selectedUsers.any((u) {
      bool isSelf = u.id == authProvider.currentUserId;
      int targetRank = _getRoleRank(u.role);
      return isSelf || (!authProvider.isAdmin && (myRank <= targetRank));
    });

    if (hasUnauthorized) {
      _showInfoDialog("권한 없음", "선택된 항목 중 삭제 권한이 없는 사용자(본인, 동일 등급, 상위 등급)가 포함되어 있습니다.\n하위 등급의 작업자만 선택하여 일괄 삭제해 주세요.", theme);
      return;
    }

    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("선택 항목 일괄 삭제", Icons.warning, color: AppTheme.danger),
              content: Text("선택하신 ${_selectedUserIds.length}명의 인원 정보를 모두 삭제하시겠습니까?\n이 작업은 되돌릴 수 없으며, 출입 이력도 함께 삭제될 수 있습니다.", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
              actions: [
                AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: cancelColor, onPressed: () {
                  Navigator.pop(ctx);
                }),
                AppTheme.actionButton(
                    label: "일괄 삭제",
                    color: AppTheme.danger,
                    onPressed: () async {
                      Navigator.pop(ctx);
                      setState(() {
                        _isFullScreenLoading = true;
                      });

                      for (String id in _selectedUserIds) {
                        await provider.deletePerson(id);
                      }

                      if (!mounted) {
                        return;
                      }

                      setState(() {
                        _selectedUserIds.clear();
                        _isFullScreenLoading = false;
                        _isSelectionMode = false;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("선택한 인원 정보가 일괄 삭제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
                    }
                )
              ]
          );
        }
    );
  }

  void _showHistoryDialog(BuildContext context, UserModel p, ThemeData theme) {
    final List<dynamic> history = (p.metadata['access_history'] is List) ? List.from(p.metadata['access_history']) : [];
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: AppTheme.dialogTitle('[${p.name}]님 출입 히스토리', Icons.history, color: Colors.blueGrey),
            content: SizedBox(
                width: 550, height: 600,
                child: history.isEmpty
                    ? _buildEmptyState("기록 없음")
                    : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: history.length,
                    separatorBuilder: (BuildContext context, int index) {
                      return const SizedBox(height: 10);
                    },
                    itemBuilder: (BuildContext c, int i) {
                      final dynamic log = history[i];
                      final String type = _safeStr(log['type'], defaultVal: "-");
                      final String timeStr = _safeStr(log['time'], defaultVal: "-");
                      final dynamic rawApprove = log['is_approved'];
                      final bool approved = (rawApprove is bool) ? rawApprove : true;

                      Color col = AppTheme.danger;
                      if (approved) {
                        if (type == '입장') {
                          col = AppTheme.success;
                        } else {
                          col = AppTheme.warning;
                        }
                      }

                      String bldg = "미지정";
                      String gate = "미정";
                      if (log['location'] is Map) {
                        final Map locMap = log['location'] as Map;
                        bldg = _safeStr(locMap['building'], defaultVal: "미지정");
                        gate = _safeStr(locMap['gate'], defaultVal: "미정");
                      }

                      return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: theme.cardTheme.color, borderRadius: BorderRadius.circular(10), border: Border.all(color: col.withValues(alpha: 0.15))),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6, right: 16), decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(timeStr, style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold)),
                                                Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(color: col.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                                    child: Text(type, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: col, fontWeight: FontWeight.bold, fontSize: 12))
                                                ),
                                              ]
                                          ),
                                          const SizedBox(height: 6),
                                          Text('$bldg - $gate', style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.blueGrey, fontSize: 14, fontWeight: FontWeight.w600)),
                                        ]
                                    )
                                ),
                              ]
                          )
                      );
                    }
                )
            ),
            actions: [
              AppTheme.actionButton(label: "닫기", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () {
                Navigator.pop(ctx);
              })
            ],
          );
        }
    );
  }

  void _showColumnSelectionDialog(UserProvider provider, ThemeData theme) {
    final List<String> baseFields = ['성명', '사번', '부서', '권한/등급', '태그ID'];

    final Set<String> metaKeySet = {};
    for (final UserModel p in provider.list) {
      for (final String k in p.metadata.keys) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal')) {
          metaKeySet.add(k);
        }
      }
    }
    final List<String> metaFields = metaKeySet.toList()..sort();

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return ColumnSelectionDialog(
          title: "표시 항목 설정 (인원)",
          baseFields: baseFields,
          metaFields: metaFields,
          initialSelection: provider.selectedColumns,
          onSave: (List<String> newColumns) async {
            await provider.saveRemoteSettings(newColumns);
            if (!ctx.mounted) {
              return;
            }
            Navigator.pop(ctx);
          },
        );
      },
    );
  }

  Future<void> _showResetConfirmationDialog(UserProvider provider, ThemeData theme) async {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAdmin && _getRoleRank(authProvider.role) < 3) {
      _showInfoDialog("권한 없음", "데이터 전체 초기화 작업은 최고관리자(Admin)만 수행할 수 있습니다.", theme);
      return;
    }

    final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("전체 삭제 확인", Icons.warning, color: AppTheme.danger),
              content: const Text("서버의 모든 정보를 영구 삭제하시겠습니까?", style: TextStyle(fontFamily: AppTheme.fontPretendard)),
              actions: [
                AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () {
                  Navigator.pop(ctx, false);
                }),
                AppTheme.actionButton(label: "삭제 실행", color: AppTheme.danger, onPressed: () {
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

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext loadingCtx) {
        return PopScope(
          canPop: false,
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
                    Text("안전 데이터베이스 초기화 중...", textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    try {
      await provider.resetAllPersons();
    } finally {
      if (mounted) {
        setState(() {
          _isFullScreenLoading = false;
        });
      }
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('초기화 완료', style: TextStyle(fontFamily: AppTheme.fontPretendard))));
    }
  }

  Future<void> _handleBatchImport(UserProvider provider, ThemeData theme) async {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAdmin && _getRoleRank(authProvider.role) < 2) {
      _showInfoDialog("권한 없음", "데이터 일괄 엑셀 업로드 작업은 현장관리자(Manager) 이상만 가능합니다.", theme);
      return;
    }

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);

      if (!mounted || result == null) {
        return;
      }

      Uint8List? bytes = result.files.single.bytes;
      if (bytes == null && result.files.single.path != null) {
        bytes = await File(result.files.single.path!).readAsBytes();
      }

      if (!mounted || bytes == null) {
        return;
      }

      final excel_pkg.Excel excel = excel_pkg.Excel.decodeBytes(bytes);
      String targetSheet = excel.tables.keys.first;

      if (excel.tables.keys.contains('인원리스트')) {
        targetSheet = '인원리스트';
      }

      final excel_pkg.Sheet? sheet = excel.tables[targetSheet];
      if (sheet == null || sheet.maxRows <= 1) {
        return;
      }

      final List<String> headers = [];
      for (final List<excel_pkg.Data?> rowData in sheet.rows.take(1)) {
        for (final excel_pkg.Data? cell in rowData) {
          headers.add(_extractString(cell));
        }
      }

      int actualValidRows = 0;
      for (int i = 1; i < sheet.maxRows; i++) {
        bool hasData = false;
        for (final excel_pkg.Data? cell in sheet.row(i)) {
          if (_extractString(cell).isNotEmpty) {
            hasData = true;
            break;
          }
        }
        if (hasData) {
          actualValidRows++;
        }
      }

      final ValueNotifier<int> currentCountNotifier = ValueNotifier<int>(0);
      setState(() {
        _isFullScreenLoading = true;
      });

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return PopScope(
            canPop: false,
            child: Center(
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 40),
                  child: ValueListenableBuilder<int>(
                    valueListenable: currentCountNotifier,
                    builder: (BuildContext context, int currentCount, Widget? child) {
                      final double progress = actualValidRows > 0 ? currentCount / actualValidRows : 0.0;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(width: 80, height: 80, child: CircularProgressIndicator(value: progress, color: AppTheme.primary, strokeWidth: 8)),
                              Text('${(progress * 100).toInt()}%', style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 25),
                          const Text("인원 대량 전송 중...", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 18)),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      );

      for (int i = 1; i < sheet.maxRows; i++) {
        final List<excel_pkg.Data?> row = sheet.row(i);
        if (row.isEmpty) {
          continue;
        }

        String name = "", code = "", dept = "", tagId = "", role = "";
        final Map<String, dynamic> metadata = {};
        bool hasRowData = false;

        for (int colIdx = 0; colIdx < row.length; colIdx++) {
          if (colIdx >= headers.length) {
            break;
          }

          final String rawHeader = headers[colIdx];
          final String cleanHeader = rawHeader.replaceAll(RegExp(r'[\s_\-()]+'), '').toLowerCase();
          final String val = _extractString(row[colIdx]);

          if (val.isNotEmpty) {
            hasRowData = true;
          }

          if (cleanHeader.contains('성명') || cleanHeader.contains('이름')) {
            name = val;
          } else if (cleanHeader.contains('사번') || cleanHeader.contains('id')) {
            code = val;
          } else if (cleanHeader.contains('부서')) {
            dept = val;
          } else if (cleanHeader.contains('권한/등급') || cleanHeader.contains('role')) {
            role = _getDbRole(val);
          } else if (cleanHeader.contains('태그') || cleanHeader.contains('rfid')) {
            tagId = val;
          } else if (rawHeader.isNotEmpty && val.isNotEmpty) {
            metadata[rawHeader] = val;
          }
        }

        if (!hasRowData) {
          continue;
        }

        if (name.isEmpty) {
          name = "형식에 맞지 않는 건";
        }

        if (tagId.isEmpty) {
          tagId = "TAG_${DateTime.now().millisecondsSinceEpoch}_$i";
        }

        String safeUsername = code.isEmpty ? 'user_${DateTime.now().millisecondsSinceEpoch % 100000}_$i' : code.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.-]'), '');
        if (safeUsername.length < 3) {
          safeUsername = '${safeUsername}_$i';
        }

        final Map<String, dynamic> data = {
          'username': safeUsername,
          'email': '$safeUsername@plug4rfid.local',
          'password': 'password123',
          'passwordConfirm': 'password123',
          'name': name,
          'code': code,
          'tag_id': tagId,
          'department': dept,
          'role': role.isEmpty ? 'Operator' : role,
          'is_approved': name != "형식에 맞지 않는 건",
          'metadata': metadata
        };

        await provider.handleSave(p: null, data: data);
        currentCountNotifier.value++;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isFullScreenLoading = false;
      });
      Navigator.of(context).pop();

    } catch (e) {
      if (mounted) {
        setState(() {
          _isFullScreenLoading = false;
        });
      }
    }
  }

  String _extractString(excel_pkg.Data? cell) {
    if (cell == null || cell.value == null) {
      return "";
    }

    final String str = cell.value.toString();
    final RegExp regExp = RegExp(r'^[a-zA-Z]+CellValue\((.*)\)$', dotAll: true);
    final Match? match = regExp.firstMatch(str);

    if (match != null && match.groupCount >= 1) {
      String extracted = match.group(1) ?? "";
      if (extracted.startsWith('"') && extracted.endsWith('"') && extracted.length >= 2) {
        extracted = extracted.substring(1, extracted.length - 1);
      }
      return extracted.trim();
    }

    return str.trim();
  }

  Future<void> _exportToExcel(List<UserModel> dataList) async {
    if (dataList.isEmpty) {
      return;
    }

    try {
      final excel_pkg.Excel excel = excel_pkg.Excel.createExcel();
      final String defaultSheet = excel.tables.keys.first;
      excel.rename(defaultSheet, '인원리스트');
      final excel_pkg.Sheet sheet = excel['인원리스트'];

      final List<String> baseHeaders = ['성명', '사번', '부서', '권한/등급', '태그ID'];

      final Set<String> metaKeySet = {};
      for (final UserModel p in dataList) {
        for (final String k in p.metadata.keys) {
          if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal')) {
            metaKeySet.add(k);
          }
        }
      }
      final List<String> metaFields = metaKeySet.toList()..sort();
      final List<String> allHeaders = [...baseHeaders, ...metaFields];

      final List<excel_pkg.CellValue> headerRow = allHeaders.map<excel_pkg.CellValue>((String h) {
        return excel_pkg.TextCellValue(h);
      }).toList();
      sheet.appendRow(headerRow);

      for (final UserModel p in dataList) {
        final List<excel_pkg.CellValue> rowData = [
          excel_pkg.TextCellValue(p.name),
          excel_pkg.TextCellValue(p.code),
          excel_pkg.TextCellValue(p.department),
          excel_pkg.TextCellValue(_getDisplayRole(p.role)),
          excel_pkg.TextCellValue(p.tagId),
        ];

        for (final String metaKey in metaFields) {
          rowData.add(excel_pkg.TextCellValue(_safeStr(p.metadata[metaKey])));
        }
        sheet.appendRow(rowData);
      }

      final String? path = await FilePicker.platform.saveFile(
          fileName: 'User_Export_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx']
      );

      if (!mounted || path == null) {
        return;
      }

      await File(path).writeAsBytes(excel.encode()!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 엑셀 다운로드가 완료되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)), elevation: 0));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 내보내기 실패: $e', style: const TextStyle(fontFamily: AppTheme.fontPretendard))));
      }
    }
  }

  Widget _buildImagePickerBox(
      BuildContext context,
      UserModel? p,
      Uint8List? preview,
      bool isDeleted,
      Function(XFile, Uint8List) onPicked,
      VoidCallback onDeleted,
      ThemeData theme,
      ) {
    final String? url = p?.getImageUrl(widget.baseUrl, thumb: '200x200');
    final bool hasImage = (preview != null) || (url != null && url.isNotEmpty && !isDeleted);

    Widget avatarContent;
    if (preview != null) {
      avatarContent = ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(preview, fit: BoxFit.cover));
    } else if (hasImage) {
      final String connector = url!.contains('?') ? '&' : '?';
      final String fullUrl = "$url${connector}t=${p!.hashCode}";

      avatarContent = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
              fullUrl,
              fit: BoxFit.cover,
              errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                return const Icon(Icons.broken_image);
              }
          )
      );
    } else {
      avatarContent = const Icon(Icons.camera_alt, size: 50, color: Colors.grey);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () async {
            final ImagePicker picker = ImagePicker();
            final XFile? img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

            if (img != null) {
              final Uint8List b = await img.readAsBytes();
              onPicked(img, b);
            }
          },
          child: Container(
            width: 180, height: 210,
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 2)
            ),
            child: Center(
              child: avatarContent,
            ),
          ),
        ),
        if (hasImage) ...[
          Positioned(
            top: -10, right: -10,
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
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2))]
                  ),
                  child: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
                ),
              ),
            ),
          )
        ]
      ],
    );
  }

  Future<void> _showForm(UserProvider provider, UserModel? p, ThemeData theme) async {
    final authProvider = context.read<AuthProvider>();
    int myRank = _getRoleRank(authProvider.role);

    if (p != null) {
      bool isSelf = p.id == authProvider.currentUserId;
      int targetRank = _getRoleRank(p.role);

      if (!authProvider.isAdmin && !isSelf && myRank <= targetRank) {
        _showInfoDialog("권한 없음", "동일 등급이거나 상위 등급인 다른 사용자의 정보는 수정할 수 없습니다.", theme);
        return;
      }
    } else {
      if (!authProvider.isAdmin && myRank < 2) {
        _showInfoDialog("권한 없음", "신규 인원 등록은 현장관리자(Manager) 이상만 가능합니다.", theme);
        return;
      }
    }

    final TextEditingController nameC = TextEditingController(text: p?.name ?? "");
    final TextEditingController codeC = TextEditingController(text: p?.code ?? "");
    final TextEditingController deptC = TextEditingController(text: p?.department ?? "");

    String currentDisplayRole = '일반작업자 (Operator)';
    if (p != null && p.role.isNotEmpty) {
      currentDisplayRole = _getDisplayRole(p.role);
    }

    bool canEditRole = authProvider.isAdmin || myRank >= 2;
    List<String> roleOptions = [];

    if (authProvider.isAdmin || myRank == 3) {
      roleOptions = ['최고관리자 (Admin)', '현장관리자 (Manager)', '일반작업자 (Operator)'];
    } else if (myRank == 2) {
      roleOptions = ['현장관리자 (Manager)', '일반작업자 (Operator)'];
    } else {
      roleOptions = [currentDisplayRole];
    }

    if (!roleOptions.contains(currentDisplayRole)) {
      roleOptions.add(currentDisplayRole);
    }

    String initialEmail = "";
    if (p != null) {
      initialEmail = _safeStr(p.metadata['app_login_email']);
    }
    final TextEditingController emailC = TextEditingController(text: initialEmail);

    final TextEditingController pwdC = TextEditingController();
    final TextEditingController tagC = TextEditingController(text: p?.tagId ?? "");
    final TextEditingController remarksC = TextEditingController(text: p?.remarks ?? "");
    bool approved = p?.isApproved ?? true;

    XFile? file;
    Uint8List? preview;
    bool isImageDeleted = false;

    final Map<String, TextEditingController> metaC = {};
    final Set<String> allMetaKeys = {};

    for (final UserModel user in provider.list) {
      user.metadata.forEach((String k, dynamic v) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal') && v is! Map && v is! List) {
          allMetaKeys.add(k);
        }
      });
    }

    if (p != null) {
      p.metadata.forEach((String k, dynamic v) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal') && v is! Map && v is! List) {
          allMetaKeys.add(k);
        }
      });
    }

    final List<String> sortedMetaKeys = allMetaKeys.toList()..sort();
    for (final String key in sortedMetaKeys) {
      final String initialValue = p != null ? _safeStr(p.metadata[key]) : "";
      metaC[key] = TextEditingController(text: initialValue);
    }

    final String pwdLabel = (p == null)
        ? "로그인 비밀번호 (미입력시 '12345678' 자동설정, 8자리 이상)"
        : "새 비밀번호 (변경할 경우에만 입력, 미입력시 기존 유지)";

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogCtx) {
          return StatefulBuilder(
              builder: (BuildContext innerCtx, StateSetter setS) {

                Widget imagePickerWidget = _buildImagePickerBox(
                  context, p, preview, isImageDeleted,
                      (XFile pickedFile, Uint8List pickedBytes) {
                    setS(() {
                      file = pickedFile;
                      preview = pickedBytes;
                      isImageDeleted = false;
                    });
                  },
                      () {
                    setS(() {
                      file = null;
                      preview = null;
                      isImageDeleted = true;
                    });
                  }, theme,
                );

                return AlertDialog(
                    title: AppTheme.dialogTitle(
                        p == null ? '신규 인원 등록' : '정보 수정 및 편집',
                        p == null ? Icons.person_add : Icons.edit
                    ),
                    content: SizedBox(
                        width: 900,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 20),
                                  Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Column(
                                            children: [
                                              imagePickerWidget,
                                              const SizedBox(height: 16),
                                              Row(
                                                  children: [
                                                    const Text(
                                                        "출입 승인",
                                                        style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 14, fontWeight: FontWeight.bold)
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Switch(
                                                        value: approved,
                                                        activeThumbColor: AppTheme.success,
                                                        activeTrackColor: AppTheme.success.withValues(alpha: 0.5),
                                                        onChanged: (bool v) {
                                                          setS(() {
                                                            approved = v;
                                                          });
                                                        }
                                                    )
                                                  ]
                                              )
                                            ]
                                        ),
                                        const SizedBox(width: 30),
                                        Expanded(
                                            child: Column(
                                                children: [
                                                  _buildTextField(nameC, "성명 (필수)", theme),
                                                  const SizedBox(height: 16),

                                                  Row(
                                                    children: [
                                                      Expanded(child: _buildTextField(deptC, "담당부서/소속", theme)),
                                                      const SizedBox(width: 16),
                                                      Expanded(
                                                        child: _buildDropdownField(
                                                          value: currentDisplayRole,
                                                          label: canEditRole ? "권한/등급 (수정 가능)" : "권한/등급 (권한 부족)",
                                                          options: roleOptions,
                                                          theme: theme,
                                                          onChanged: canEditRole ? (String? newValue) {
                                                            if (newValue != null) {
                                                              setS(() {
                                                                currentDisplayRole = newValue;
                                                              });
                                                            }
                                                          } : null,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),

                                                  _buildTextField(codeC, "사번/코드", theme),
                                                  const SizedBox(height: 16),

                                                  _buildTextField(emailC, "로그인 이메일 (예: user01@plug4.com)", theme),
                                                  const SizedBox(height: 16),

                                                  _buildTextField(pwdC, pwdLabel, theme, isPassword: true),
                                                  const SizedBox(height: 16),

                                                  IntrinsicHeight(
                                                    child: Row(
                                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                                      children: [
                                                        Expanded(child: _buildTextField(tagC, "RFID 태그 EPC", theme)),
                                                        const SizedBox(width: 12),
                                                        ElevatedButton.icon(
                                                          onPressed: () {
                                                            showDialog(
                                                                context: context,
                                                                barrierDismissible: false,
                                                                builder: (BuildContext ctx) {
                                                                  return _BulkTagIssueDialog(
                                                                    selectedUsers: p != null ? [p] : [],
                                                                    userProvider: provider,
                                                                    deviceProvider: context.read<DeviceProvider>(),
                                                                    theme: theme,
                                                                    onWriteComplete: (String writtenHex) {
                                                                      setS(() {
                                                                        tagC.text = writtenHex;
                                                                      });
                                                                    },
                                                                  );
                                                                }
                                                            );
                                                          },
                                                          icon: const Icon(Icons.nfc_rounded),
                                                          label: const Text("장비로 기록", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 15)),
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor: Colors.indigo,
                                                            foregroundColor: Colors.white,
                                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 16),
                                                  _buildTextField(remarksC, "비고", theme),
                                                ]
                                            )
                                        )
                                      ]
                                  ),
                                  (metaC.isNotEmpty) ? Column(
                                      children: [
                                        const SizedBox(height: 32),
                                        const Divider(),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Icon(Icons.post_add, color: theme.colorScheme.primary, size: 20),
                                            const SizedBox(width: 8),
                                            const Text(
                                                "추가 항목 (사용자 정의 필드)",
                                                style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Wrap(
                                            spacing: 16,
                                            runSpacing: 16,
                                            children: metaC.entries.map((MapEntry<String, TextEditingController> e) {
                                              return SizedBox(width: 360, child: _buildTextField(e.value, e.key, theme));
                                            }).toList()
                                        )
                                      ]
                                  ) : const SizedBox.shrink()
                                ]
                            )
                        )
                    ),
                    actions: [
                      AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () {
                        Navigator.pop(dialogCtx);
                      }),
                      AppTheme.actionButton(label: "통합 저장", onPressed: () async {
                        String inputEmail = emailC.text.trim();
                        if (inputEmail.isEmpty || !inputEmail.contains('@') || !inputEmail.contains('.')) {
                          _showInfoDialog("이메일 입력 오류", "올바른 이메일 형식을 입력해 주세요.\n(예: user01@plug4.com)", theme);
                          return;
                        }

                        final String inputPwd = pwdC.text.trim();
                        String finalPwd = inputPwd;
                        if (p == null && finalPwd.isEmpty) {
                          finalPwd = '12345678';
                        }

                        if (finalPwd.isNotEmpty && finalPwd.length < 8) {
                          _showInfoDialog("비밀번호 오류", "비밀번호는 최소 8자리 이상이어야 합니다.", theme);
                          return;
                        }

                        final Map<String, dynamic> meta = Map<String, dynamic>.from(p?.metadata ?? {});
                        metaC.forEach((String k, TextEditingController c) {
                          meta[k] = c.text.trim();
                        });

                        meta['app_login_email'] = inputEmail;

                        final Map<String, dynamic> data = {
                          'email': inputEmail,
                          'name': nameC.text.trim(),
                          'code': codeC.text.trim(),
                          'tag_id': tagC.text.trim(),
                          'department': deptC.text.trim(),
                          'role': _getDbRole(currentDisplayRole),
                          'is_approved': approved,
                          'remarks': remarksC.text.trim(),
                          'metadata': meta,
                        };

                        if (isImageDeleted) {
                          data['avatar'] = null;
                        }

                        if (finalPwd.isNotEmpty) {
                          data['password'] = finalPwd;
                          data['passwordConfirm'] = finalPwd;
                        }

                        final String saveResult = await provider.handleSave(p: p, data: data, imageXFile: file);
                        if (!dialogCtx.mounted) {
                          return;
                        }

                        if (saveResult.isEmpty) {
                          Navigator.pop(dialogCtx);
                        } else {
                          _showInfoDialog("저장 실패", "데이터베이스 저장 중 오류가 발생했습니다.\n\n[상세 내용]\n$saveResult", theme);
                        }
                      })
                    ]
                );
              }
          );
        }
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, ThemeData theme, {bool isPassword = false}) {
    return TextField(
        controller: ctrl,
        obscureText: isPassword,
        style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
        decoration: AppTheme.inputDecoration(label: label, context: context)
    );
  }

  Widget _buildDropdownField({
    required String value,
    required String label,
    required List<String> options,
    required ThemeData theme,
    required ValueChanged<String?>? onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: AppTheme.inputDecoration(label: label, context: context),
      style: TextStyle(
          fontFamily: AppTheme.fontPretendard,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppTheme.dataColor(theme.brightness == Brightness.dark)
      ),
      dropdownColor: theme.cardTheme.color,
      icon: const Icon(Icons.arrow_drop_down_circle, color: Colors.indigo),
      items: options.map((String option) {
        return DropdownMenuItem<String>(
          value: option,
          child: Text(option),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  void _confirmDelete(UserProvider provider, UserModel p, ThemeData theme) {
    final authProvider = context.read<AuthProvider>();
    bool isSelf = p.id == authProvider.currentUserId;
    int myRank = _getRoleRank(authProvider.role);
    int targetRank = _getRoleRank(p.role);

    if (isSelf) {
      _showInfoDialog("삭제 불가", "본인의 계정은 직접 삭제할 수 없습니다.", theme);
      return;
    }

    if (!authProvider.isAdmin && myRank <= targetRank) {
      _showInfoDialog("권한 없음", "동일 등급이거나 상위 등급인 다른 사용자는 삭제할 수 없습니다.", theme);
      return;
    }

    showDialog(
        context: context,
        builder: (BuildContext c) {
          return AlertDialog(
              title: AppTheme.dialogTitle("삭제 확인", Icons.delete),
              content: Text("[${p.name}] 정보를 삭제하시겠습니까?", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
              actions: [
                AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () {
                  Navigator.pop(c);
                }),
                AppTheme.actionButton(label: "삭제 실행", color: AppTheme.danger, onPressed: () async {
                  final bool ok = await provider.deletePerson(p.id);
                  if (!c.mounted) {
                    return;
                  }

                  if (ok) {
                    Navigator.pop(c);
                  }
                })
              ]
          );
        }
    );
  }
}

/// ---------------------------------------------------------------------------
/// 🔥 태그 일괄 발행 통합 다이얼로그 (Bulk Tag Issue)
/// ---------------------------------------------------------------------------
class _BulkTagIssueDialog extends StatefulWidget {
  final List<UserModel> selectedUsers;
  final UserProvider userProvider;
  final DeviceProvider deviceProvider;
  final ThemeData theme;
  final Function(String)? onWriteComplete;

  const _BulkTagIssueDialog({
    required this.selectedUsers,
    required this.userProvider,
    required this.deviceProvider,
    required this.theme,
    this.onWriteComplete,
  });

  @override
  State<_BulkTagIssueDialog> createState() => _BulkTagIssueDialogState();
}

class _BulkTagIssueDialogState extends State<_BulkTagIssueDialog> {
  String? _selectedDeviceId;
  bool _isLoadingReaders = true;

  int _issueCount = 1;
  bool _isProcessing = false;
  bool _isCompleted = false;
  double _progressValue = 0.0;
  String _progressText = "";

  @override
  void initState() {
    super.initState();
    if (widget.selectedUsers.isEmpty) {
      _progressText = '대상을 알 수 없는 신규 단일 건입니다.\n데이터를 자동으로 생성하여 기록합니다.';
    } else {
      _progressText = '선택된 총 ${widget.selectedUsers.length}건에 대한 정보를 발급합니다.\n리더기와 발급 횟수를 설정하고 [발행 시작]을 눌러주세요.';
    }
    _fetchRegisteredReaders();
  }

  Future<void> _fetchRegisteredReaders() async {
    try {
      if (widget.deviceProvider.list.isEmpty) {
        await widget.deviceProvider.fetchData();
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (mounted) {
        setState(() {
          _isLoadingReaders = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingReaders = false;
        });
      }
    }
  }

  String _formatDataToTargetSize(String inputData, int targetByteSize) {
    List<int> utf8Bytes = utf8.encode(inputData);
    StringBuffer hexBuffer = StringBuffer();

    for (int i = 0; i < utf8Bytes.length; i++) {
      hexBuffer.write(utf8Bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }

    String hexString = hexBuffer.toString();
    int targetHexLength = targetByteSize * 2;

    if (hexString.length < targetHexLength) {
      return hexString.padRight(targetHexLength, '0');
    } else if (hexString.length > targetHexLength) {
      return hexString.substring(0, targetHexLength);
    } else {
      return hexString;
    }
  }

  Future<void> _startBulkIssue() async {
    DeviceModel? targetDevice;
    try {
      targetDevice = widget.deviceProvider.list.firstWhere((d) => d.id == _selectedDeviceId);
    } catch (e) {
      targetDevice = null;
    }

    if (targetDevice == null) {
      setState(() {
        _progressText = '❌ 선택된 가용 리더기가 없습니다. 장치관리 메뉴에서 리더기를 먼저 등록해주세요.';
      });
      return;
    }

    final DeviceModel device = targetDevice;

    if (device.status.toLowerCase() != 'online') {
      setState(() {
        _progressText = '❌ 선택한 리더기(${device.name})가 미연결 상태입니다. 장치관리에서 [장치 연결]을 먼저 진행해주세요.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _progressValue = 0.0;
    });

    try {
      if (widget.selectedUsers.isEmpty) {
        String randomTag = "NEW_TAG_${DateTime.now().millisecondsSinceEpoch % 100000}";
        int memorySize = 12;

        for (int j = 0; j < _issueCount; j++) {
          setState(() {
            _progressValue = (j + 1) / _issueCount;
            _progressText = "신규 자동 태그의 ${j + 1}장째를 기록하고 있습니다...";
          });

          String hexData = _formatDataToTargetSize(randomTag, memorySize);

          bool isSuccess = await widget.deviceProvider.writeTagData(device.id, hexData, isHexMode: true);

          if (!isSuccess) {
            throw Exception("리더기(${device.name}) 통신 또는 기록 실패");
          }
          await Future.delayed(const Duration(milliseconds: 300));

          if (widget.onWriteComplete != null && j == _issueCount - 1) {
            widget.onWriteComplete!(hexData);
          }
        }
      } else {
        int totalUsers = widget.selectedUsers.length;
        int currentOperationCount = 0;
        int totalOperations = totalUsers * _issueCount;
        int memorySize = 12;

        for (int i = 0; i < totalUsers; i++) {
          UserModel user = widget.selectedUsers[i];
          String tagData = user.tagId.isNotEmpty ? user.tagId : user.code;

          for (int j = 0; j < _issueCount; j++) {
            currentOperationCount++;

            setState(() {
              _progressValue = currentOperationCount / totalOperations;
              _progressText = "발급대상 $totalUsers명 중 ${i + 1}번째 인원([${user.name}])의 ${j + 1}장째를 발급(기록) 중입니다...";
            });

            String hexData = _formatDataToTargetSize(tagData, memorySize);

            bool isSuccess = await widget.deviceProvider.writeTagData(device.id, hexData, isHexMode: true);

            if (!isSuccess) {
              await Future.delayed(const Duration(milliseconds: 500));
              isSuccess = await widget.deviceProvider.writeTagData(device.id, hexData, isHexMode: true);

              if(!isSuccess) {
                throw Exception("인원 [${user.name}] 태그 기록 실패 (리더기 응답 없음)");
              }
            }
            await Future.delayed(const Duration(milliseconds: 300));

            if (j == _issueCount - 1) {
              await widget.userProvider.handleSave(p: user, data: {'tag_id': hexData});
              if (widget.onWriteComplete != null && totalUsers == 1) {
                widget.onWriteComplete!(hexData);
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _isCompleted = true;
          _progressValue = 1.0;
          _progressText = '✅ 설정하신 모든 태그의 발행 작업이 완벽하게 완료되었습니다.';
        });

        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          Navigator.pop(context);
        }
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _progressText = '❌ 기록 중단됨: $e\n(장치를 다시 연결하거나 태그를 다시 올려주세요)';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: AppTheme.dialogTitle('RFID 태그 일괄 발급', Icons.wifi_tethering, color: Colors.indigo),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('1. 발급 대상 리더기', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.bold, color: widget.theme.colorScheme.onSurface)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(10),
                  color: widget.theme.cardTheme.color,
                ),
                child: ListenableBuilder(
                    listenable: widget.deviceProvider,
                    builder: (context, child) {
                      if (_isLoadingReaders) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.0),
                          child: Center(
                              child: SizedBox(
                                  width: 24, height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.indigo)
                              )
                          ),
                        );
                      }

                      final devices = widget.deviceProvider.list.where((d) => d.isActive).toList();

                      if (devices.isEmpty) {
                        return DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: null,
                              hint: const Text('등록된 장비가 없습니다.', style: TextStyle(color: Colors.redAccent, fontFamily: AppTheme.fontPretendard)),
                              items: const [],
                              onChanged: null,
                            )
                        );
                      }

                      String? displayId = _selectedDeviceId;
                      if (displayId == null || !devices.any((d) => d.id == displayId)) {
                        final onlineDevice = devices.where((d) => d.status.toLowerCase() == 'online').firstOrNull;
                        displayId = onlineDevice?.id ?? devices.first.id;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _selectedDeviceId != displayId) {
                            setState(() { _selectedDeviceId = displayId; });
                          }
                        });
                      }

                      return DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: displayId,
                          icon: const Icon(Icons.arrow_drop_down_circle, color: Colors.indigo),
                          style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w600, color: widget.theme.colorScheme.onSurface),
                          onChanged: _isProcessing ? null : (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedDeviceId = newValue;
                              });
                            }
                          },
                          items: devices.map<DropdownMenuItem<String>>((DeviceModel d) {
                            bool isOnline = d.status.toLowerCase() == 'online';
                            return DropdownMenuItem<String>(
                              value: d.id,
                              child: Row(
                                children: [
                                  Icon(Icons.router, size: 20, color: isOnline ? Colors.indigo : Colors.grey),
                                  const SizedBox(width: 12),
                                  Text(
                                      '${d.name} (${isOnline ? '연결됨' : '미연결'})',
                                      style: TextStyle(
                                          color: isOnline ? widget.theme.colorScheme.onSurface : Colors.grey,
                                          fontFamily: AppTheme.fontPretendard
                                      )
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }
                ),
              ),
              const SizedBox(height: 24),

              Text('2. 동일 정보 반복 발급 횟수 (1~99)', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.bold, color: widget.theme.colorScheme.onSurface)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(10),
                  color: widget.theme.cardTheme.color,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 36, color: Colors.blueGrey),
                      onPressed: _isProcessing ? null : () {
                        if (_issueCount > 1) {
                          setState(() { _issueCount--; });
                        }
                      },
                    ),
                    const SizedBox(width: 20),
                    Container(
                      width: 80,
                      alignment: Alignment.center,
                      child: Text(
                          '$_issueCount',
                          style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 32, fontWeight: FontWeight.w900, color: Colors.indigo)
                      ),
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 36, color: Colors.indigo),
                      onPressed: _isProcessing ? null : () {
                        if (_issueCount < 99) {
                          setState(() { _issueCount++; });
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: _isCompleted ? AppTheme.success.withValues(alpha: 0.1) : widget.theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: _progressText.contains('❌') ? AppTheme.danger : (_isCompleted ? AppTheme.success : Colors.grey.withValues(alpha: 0.3))),
                ),
                child: Column(
                  children: [
                    Text(
                      _progressText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontSize: 15.0,
                        height: 1.5,
                        color: _progressText.contains('❌') ? AppTheme.danger : (_isCompleted ? AppTheme.success : Colors.blueGrey.shade800),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    (_isProcessing || _isCompleted) ? Column(
                        children: [
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: _progressValue,
                              minHeight: 12,
                              backgroundColor: Colors.grey.withValues(alpha: 0.2),
                              color: _progressText.contains('❌') ? AppTheme.danger : (_isCompleted ? AppTheme.success : Colors.indigo),
                            ),
                          ),
                        ]
                    ) : const SizedBox.shrink()
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppTheme.actionButton(
            label: "돌아가기 (취소)",
            color: Colors.transparent,
            textColor: widget.theme.colorScheme.onSurface.withValues(alpha: 0.5),
            onPressed: () {
              if (!_isProcessing || _isCompleted || _progressText.contains('❌')) {
                Navigator.pop(context);
              }
            }
        ),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: (_isProcessing || _isCompleted || _isLoadingReaders || _selectedDeviceId == null) ? null : _startBulkIssue,
            icon: const Icon(Icons.play_circle_fill, size: 20),
            label: const Text('발행 시작', style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
            ),
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// [위치 선택 다이얼로그]
/// ---------------------------------------------------------------------------
class _LocationSelectionDialog extends StatefulWidget {
  final String type;
  final List<UserModel> existingUsers;

  const _LocationSelectionDialog({required this.type, required this.existingUsers});

  @override
  State<_LocationSelectionDialog> createState() => _LocationSelectionDialogState();
}

class _LocationSelectionDialogState extends State<_LocationSelectionDialog> {
  late List<String> _buildings, _gates;
  final TextEditingController _bC = TextEditingController();
  final TextEditingController _gC = TextEditingController();
  bool _ok = true;

  @override
  void initState() {
    super.initState();
    final Set<String> b = {'본관A', '공장B', '물류창고C', '연구소D'};
    final Set<String> g = {'정문G1', '후문G2', '하차장G3', '비상구G4'};

    for (final UserModel p in widget.existingUsers) {
      final dynamic loc = p.metadata['last_location_info'];
      if (loc is Map) {
        if (loc['building'] != null) {
          b.add(loc['building'].toString());
        }
        if (loc['gate'] != null) {
          g.add(loc['gate'].toString());
        }
      }
    }

    _buildings = b.toList()..sort();
    _gates = g.toList()..sort();
    _bC.text = _buildings.isNotEmpty ? _buildings.first : "";
    _gC.text = _gates.isNotEmpty ? _gates.first : "";
  }

  @override
  void dispose() {
    _bC.dispose();
    _gC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    Color colColor = _ok ? AppTheme.success.withValues(alpha: 0.05) : AppTheme.danger.withValues(alpha: 0.05);
    Color borderColor = _ok ? AppTheme.success.withValues(alpha: 0.2) : AppTheme.danger.withValues(alpha: 0.2);

    return AlertDialog(
      title: AppTheme.dialogTitle('${widget.type}처리', widget.type == '입장' ? Icons.login : Icons.logout),
      content: SizedBox(
          width: 420,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 20),
                _buildCombo('건물명 (Building)', _bC, _buildings, theme), const SizedBox(height: 24),
                _buildCombo('출입구 (GATE)', _gC, _gates, theme), const SizedBox(height: 24),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        color: colColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor)
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              _ok ? "승인됨" : "미승인",
                              style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: _ok ? AppTheme.success : AppTheme.danger)
                          ),
                          Switch(
                              value: _ok,
                              activeThumbColor: AppTheme.success,
                              activeTrackColor: AppTheme.success.withValues(alpha: 0.5),
                              onChanged: (bool v) {
                                setState(() {
                                  _ok = v;
                                });
                              }
                          )
                        ]
                    )
                )
              ]
          )
      ),
      actions: [
        AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () {
          Navigator.pop(context);
        }),
        AppTheme.actionButton(label: "위치 확정", onPressed: () {
          Navigator.pop(context, {'building': _bC.text, 'gate': _gC.text, 'is_approved': _ok});
        })
      ],
    );
  }

  Widget _buildCombo(String label, TextEditingController ctrl, List<String> opts, ThemeData theme) {
    return Autocomplete<String>(
        optionsBuilder: (TextEditingValue v) {
          if (v.text == '') {
            return opts;
          }
          return opts.where((String o) {
            return o.contains(v.text);
          });
        },
        onSelected: (String s) {
          ctrl.text = s;
        },
        fieldViewBuilder: (BuildContext ctx, TextEditingController tC, FocusNode fN, VoidCallback onFieldSubmitted) {
          if (tC.text != ctrl.text) {
            tC.text = ctrl.text;
          }
          tC.addListener(() {
            if (mounted) {
              ctrl.text = tC.text;
            }
          });
          return TextField(
              controller: tC, focusNode: fN,
              style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
              decoration: AppTheme.inputDecoration(label: label, context: context, hasFocus: fN.hasFocus)
          );
        }
    );
  }
}