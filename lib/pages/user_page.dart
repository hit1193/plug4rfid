import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/user_model.dart';
import '../utils/hangul_utils.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';
import '../core/pocketbase_client.dart';
import '../core/erp_sync_helper.dart'; // [신규 추가] 공용 ERP 연동 헬퍼

// [공용 위젯 임포트] 표시 항목 설정 및 일괄 편집 다이얼로그
import '../widgets/column_selection_dialog.dart';
import '../widgets/bulk_edit_dialog.dart';

/// ---------------------------------------------------------------------------
/// [안전한 문자열 변환 유틸리티]
/// Null 값이나 빈 문자열, 혹은 "null"이라는 문자열을 안전하게 처리하여
/// UI 렌더링 시 오류를 방지하고 기본값을 반환하는 유틸리티 함수입니다.
/// 데이터베이스에서 넘어오는 null 값을 방어하는 최신 Dart의 널 세이프티(Null Safety) 대응 패턴입니다.
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
/// 메인 화면의 우측 영역에 표출되는 인원 관리 통합 관제 화면입니다.
/// 미니멀리즘과 키오스크 디자인 철학을 적용하여 직관적으로 구성했습니다.
/// ---------------------------------------------------------------------------
class UserPage extends StatefulWidget {
  final String searchQuery;
  final String filter;
  final bool isMobile; // 화면 너비에 따라 전달받는 모바일 여부 플래그입니다.
  final String baseUrl;

  const UserPage({
    super.key,
    required this.searchQuery,
    required this.filter,
    required this.isMobile,
    required this.baseUrl,
  });

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  // ---------------------------------------------------------------------------
  // [상태 변수 선언부]
  // ---------------------------------------------------------------------------
  final TextEditingController _searchController = TextEditingController();

  String _currentSearchQuery = "";
  late String _currentFilter;
  String _activeMetricFilter = "전체";

  // 단일 선택(String?)에서 다중 선택을 위한 Set<String>으로 변경 (일괄 처리 지원)
  final Set<String> _selectedUserIds = {};

  // 다중 선택 모드(동그라미 토글 보이기/숨기기) 활성화 플래그
  bool _isSelectionMode = false;

  bool _isFullScreenLoading = false;

  // 데스크탑 레이아웃 고정 치수 (미니멀 디자인 규격)
  static const double _colImgSize = 70.0;
  static const double _colActionWidth = 240.0;

  // UI에 노출되지 않아야 할 내부 시스템 키 목록
  static const Set<String> _excludedSystemKeys = {
    'import_source', 'original_row_data', 'id', 'created', 'updated',
    'collectionId', 'collectionName', 'last_access_type', 'last_access_time',
    'access_history', 'last_location_info', 'is_approved', 'last_approval_status',
    'image', 'avatar', 'name', 'code', 'department', 'tag_id', 'is_active', 'remarks',
    'excel_row', 'import_date', 'import_data', 'is_auto_tag', 'is_auto_atg',
    'excel_row_internal', 'import_data_internal', 'is_auto_tag_internal', 'error_reason',
    'email', 'username', 'password', 'passwordConfirm'
  };

  @override
  void initState() {
    super.initState();
    _currentFilter = widget.filter == '정상 등록' ? '등록' : widget.filter;
    _currentSearchQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- FA 대시보드용 통계 계산 로직 ---
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

  /// ---------------------------------------------------------------------------
  /// [수기 출입 처리]
  /// ---------------------------------------------------------------------------
  Future<void> _processAccessWithLocation(UserProvider provider, UserModel p, String type) async {
    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext ctx) {
        return _LocationSelectionDialog(type: type, existingUsers: provider.list);
      },
    );

    // [Linter 완벽 대응] async 갭 이후에 context를 사용하기 전 mounted 여부를 철저히 검사합니다.
    if (!mounted || result == null) return;

    final String now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final dynamic rawApprove = result['is_approved'];
    final bool isApproved = rawApprove is bool ? rawApprove : true;

    final Map<String, dynamic> updatedMeta = Map<String, dynamic>.from(p.metadata);
    updatedMeta['last_access_type'] = type;
    updatedMeta['last_access_time'] = now;
    updatedMeta['last_approval_status'] = isApproved;
    updatedMeta['last_location_info'] = {
      'building': _safeStr(result['building'], defaultVal: "미지정"),
      'gate': _safeStr(result['gate'], defaultVal: "미지정"),
      'full_name': "${_safeStr(result['building'])} - ${_safeStr(result['gate'])}"
    };

    List<dynamic> history = updatedMeta['access_history'] is List ? List.from(updatedMeta['access_history']) : [];
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

    final bool success = await provider.handleSave(
      p: p,
      data: updateData,
    );

    // [Linter 완벽 대응] DB 저장(await) 이후 mounted 재검사
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('[${p.name}]님 $type 처리 완료', style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
        backgroundColor: isApproved ? AppTheme.success : AppTheme.danger,
        elevation: 0,
        duration: const Duration(seconds: 1),
      ));
    } else {
      _showInfoDialog(
          "처리 실패",
          "데이터베이스 업데이트 중 오류가 발생했습니다.\n\n💡 관리자 화면에서 users 컬렉션의 API Rules 중 Update 권한이 TRUE로 입력되어 있는지 다시 확인해 주세요.",
          Theme.of(context)
      );
    }
  }

  /// ---------------------------------------------------------------------------
  /// [신규 추가] 리스트뷰 내 인원 프로필 사진(아바타) 다이렉트 업데이트
  /// 복잡한 수정 폼을 열지 않고 클릭 한 번으로 사진만 덮어씌우는 강력한 퀵 액션입니다.
  /// ---------------------------------------------------------------------------
  Future<void> _handleSingleUserImageUpdate(UserProvider provider, UserModel user, ThemeData theme) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (!mounted || image == null) return;

    final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
            title: AppTheme.dialogTitle("프로필 사진 변경", Icons.photo_camera_front),
            content: Text(
                "[${user.name}]님의 프로필 사진을 선택하신 이미지로 즉시 변경하시겠습니까?",
                style: const TextStyle(fontFamily: AppTheme.fontPretendard)
            ),
            actions: [
              AppTheme.actionButton(
                  label: "취소",
                  color: Colors.transparent,
                  textColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  onPressed: () => Navigator.pop(ctx, false)
              ),
              AppTheme.actionButton(
                  label: "사진 변경",
                  color: AppTheme.primary,
                  onPressed: () => Navigator.pop(ctx, true)
              ),
            ]
        )
    );

    if (!mounted || confirm != true) return;

    setState(() { _isFullScreenLoading = true; });

    try {
      final Map<String, dynamic> data = {
        'name': user.name,
        'code': user.code,
        'tag_id': user.tagId,
        'department': user.department,
        'is_approved': user.isApproved,
        'metadata': user.metadata,
      };

      final bool success = await provider.handleSave(p: user, data: data, imageXFile: image);

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ 사진이 성공적으로 변경되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
          elevation: 0,
        ));
      } else {
        _showInfoDialog("변경 실패", "사진 업데이트 중 오류가 발생했습니다.", theme);
      }
    } finally {
      if (mounted) {
        setState(() { _isFullScreenLoading = false; });
      }
    }
  }

  /// ---------------------------------------------------------------------------
  /// [ERP 연동] 외부 시스템에서 인원 명부를 가져와 DB에 적용합니다.
  /// (업데이트됨) 수신된 JSON의 키값을 분석하여 기본 필드는 매핑하고,
  /// 나머지 비정형 데이터는 모조리 metadata에 쑤셔넣는 스키마리스 구조를 적용했습니다.
  /// ---------------------------------------------------------------------------
  void _triggerErpSync(ThemeData theme) {
    ErpSyncHelper.fetchAndSync(
      context: context,
      theme: theme,
      moduleName: "인원(인사) 마스터 (REST API 동적 매핑)",
      endpoint: 'users?_limit=5', // 실제 연동하실 인사 ERP의 엔드포인트로 변경하세요.
      targetCollection: 'users',

      // [핵심 로직] 엑셀 파싱과 동일하게 수신 데이터를 동적으로 분리합니다.
      dataMapper: (Map<String, dynamic> erpItem) {
        String parsedName = "이름없음";
        String parsedCode = "";
        String parsedDept = "미지정";
        String parsedTagId = "";

        // 나머지 비정형 데이터를 담을 마법의 주머니
        Map<String, dynamic> dynamicMetadata = {};

        // JSON으로 날아온 모든 키-값 쌍을 순회합니다.
        erpItem.forEach((key, value) {
          if (value == null) return; // Null 값 안전 처리

          final String lowerKey = key.toLowerCase();
          final String strValue = value.toString().trim();

          // 1. 시스템을 구동하기 위한 '기본 뼈대' 필드 매핑 규칙 (인사 정보용)
          if (lowerKey.contains('name') || lowerKey.contains('이름') || lowerKey.contains('성명')) {
            parsedName = strValue;
          }
          else if (lowerKey == 'id' || lowerKey.contains('code') || lowerKey.contains('사번') || lowerKey.contains('사원번호')) {
            parsedCode = strValue;
          }
          else if (lowerKey.contains('dept') || lowerKey.contains('department') || lowerKey.contains('company') || lowerKey.contains('부서') || lowerKey.contains('소속')) {
            parsedDept = strValue;
          }
          else if (lowerKey.contains('tag') || lowerKey.contains('rfid') || lowerKey.contains('epc')) {
            parsedTagId = strValue;
          }
          // 2. 기본 필드에 해당하지 않는 '나머지 모든 데이터(직급, 전화번호 등)'는 metadata 주머니로 쏙!
          else {
            if (strValue.isNotEmpty && strValue != "null") {
              dynamicMetadata[key] = strValue;
            }
          }
        });

        // 빈 필수값 보정 처리
        if (parsedCode.isEmpty) {
          parsedCode = "EMP_${DateTime.now().millisecondsSinceEpoch % 100000}";
        }
        if (parsedTagId.isEmpty) {
          parsedTagId = "TAG_$parsedCode";
        }

        // PocketBase users 컬렉션에 필수로 필요한 계정(Auth) 정보 생성
        String safeUsername = parsedCode.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.-]'), '');
        if (safeUsername.isEmpty || safeUsername.length < 3) {
          safeUsername = 'user_${DateTime.now().millisecondsSinceEpoch % 1000000}';
        }

        // 3. 완벽하게 파싱 및 분리된 데이터를 UserModel 규격에 맞게 반환
        return {
          'username': safeUsername,
          'email': '$safeUsername@plug4rfid.local',
          'password': 'password123',
          'passwordConfirm': 'password123',
          'name': '[ERP] $parsedName', // ERP 데이터임을 표기
          'code': parsedCode,
          'tag_id': parsedTagId,
          'department': parsedDept,
          'is_approved': true,
          'metadata': dynamicMetadata, // <--- 무한한 확장성을 가진 비정형 데이터 저장소
        };
      },
      onLoadingStart: () {
        if (mounted) {
          setState(() {
            _isFullScreenLoading = true;
          });
        }
      },
      onLoadingComplete: () {
        if (mounted) {
          setState(() {
            _isFullScreenLoading = false;
          });
        }
      },
      onSuccess: () {
        // UserProvider가 최신 데이터를 다시 DB로부터 불러오게 합니다.
        context.read<UserProvider>().fetchData();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final UserProvider provider = context.watch<UserProvider>();
    final ThemeData theme = Theme.of(context);
    final Map<String, dynamic> metrics = _calculateMetrics(provider.list);

    // -------------------------------------------------------------------------
    // [비즈니스 로직: 리스트 필터링 및 전방위 검색 엔진]
    // -------------------------------------------------------------------------
    final List<UserModel> filteredList = provider.list.where((UserModel p) {
      final bool matchesFilter = _currentFilter == '전체' ||
          (_currentFilter == '등록' ? p.tagId.isNotEmpty : p.tagId.isEmpty);

      bool matchesSearch = false;
      final String q = _currentSearchQuery.trim().toLowerCase();

      if (q.isEmpty) {
        matchesSearch = true;
      } else {
        matchesSearch = HangulUtils.matches(_currentSearchQuery, p.name) ||
            p.code.toLowerCase().contains(q) ||
            p.department.toLowerCase().contains(q) ||
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
        return lastType == '입장';
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

          if (provider.isSaving || _isFullScreenLoading)
            _buildGlobalLoadingOverlay(theme),
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
                Text(
                  "데이터베이스 처리 중...",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [반응형 UI 적용] 상단 통계 대시보드 위젯
  /// 모바일 화면일 경우 4개의 타일을 가로 1줄이 아닌 2x2 그리드로 자동 분할합니다.
  /// ---------------------------------------------------------------------------
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
    return InkWell(
      onTap: () {
        setState(() {
          _activeMetricFilter = _activeMetricFilter == filterKey ? "전체" : filterKey;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: theme.brightness == Brightness.dark ? 0.15 : 0.08) : theme.cardTheme.color,
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

  /// ---------------------------------------------------------------------------
  /// [반응형 UI 적용] 헤더 및 검색, 기능 버튼 영역
  /// '인사 시스템 연동(ERP)' 버튼이 새롭게 추가되었습니다.
  /// ---------------------------------------------------------------------------
  Widget _buildHeader(UserProvider provider, List<UserModel> filtered, ThemeData theme) {
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
                    _buildActionIcon(Icons.refresh, "새로고침", () {
                      provider.fetchData();
                    }, theme),
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

                    // [신규 버튼] ERP 동기화 (수신) 버튼
                    _buildActionIcon(Icons.sync_alt_rounded, "인사 시스템(ERP) 연동", () {
                      _triggerErpSync(theme);
                    }, theme, color: Colors.teal),

                    _buildActionIcon(FontAwesomeIcons.fileArrowUp, "엑셀 업로드", () {
                      _handleBatchImport(provider, theme);
                    }, theme, color: Colors.indigo),
                    _buildActionIcon(FontAwesomeIcons.fileArrowDown, "엑스포트", () {
                      _exportToExcel(filtered);
                    }, theme, color: Colors.green),
                    _buildActionIcon(Icons.settings_outlined, "표시 항목 설정", () {
                      _showColumnSelectionDialog(provider, theme);
                    }, theme),
                    _buildActionIcon(Icons.delete_sweep_outlined, "초기화", () {
                      _showResetConfirmationDialog(provider, theme);
                    }, theme, color: AppTheme.danger),
                    _buildActionIcon(
                      Icons.person_add_alt_1,
                      "신규 인원 등록",
                          () {
                        _showForm(provider, null, theme);
                      },
                      theme,
                      color: theme.colorScheme.primary,
                    ),
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
              });
            },
            style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
            decoration: AppTheme.inputDecoration(label: "성명, 사번, 부서 또는 추가 상세내용 검색...", context: context, prefixIcon: Icons.search),
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
          width: 52,
          height: 52,
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
                    child: Text('${_selectedUserIds.length}명 선택됨', style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  ),
                  const SizedBox(width: 12),
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
            ),
          )
              : Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('총 ${list.length}명 조회됨', style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13)),
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
                final UserModel item = list[idx];
                final bool isSelected = _selectedUserIds.contains(item.id);
                final String status = _safeStr(item.metadata['last_access_type'], defaultVal: "미확인");
                final Color statusColor = (status == '입장' ? AppTheme.success : (status == '퇴장' ? AppTheme.warning : theme.dividerTheme.color ?? Colors.grey));

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
                                _selectedUserIds.remove(item.id);
                              } else {
                                _selectedUserIds.add(item.id);
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
                                _selectedUserIds.remove(item.id);
                              } else {
                                _selectedUserIds.add(item.id);
                              }
                            });
                          } else {
                            _showForm(provider, item, theme);
                          }
                        },
                        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: AppTheme.listItemDecoration(context, isSelected: isSelected, statusColor: statusColor),
                          child: widget.isMobile
                              ? _buildMobileListItem(item, provider, columns, status, theme)
                              : _buildDesktopListItem(item, provider, columns, status, theme),
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
  Widget _buildDesktopListItem(UserModel item, UserProvider provider, List<String> columns, String status, ThemeData theme) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => _handleSingleUserImageUpdate(provider, item, theme),
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              _buildAvatar(item, theme, size: _colImgSize),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.cardTheme.color ?? Colors.white, width: 2),
                ),
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
                  Text(item.name, style: AppTheme.itemValueStyle(context).copyWith(fontSize: 19, color: item.name == '형식에 맞지 않는 건' ? AppTheme.danger : null)),
                  const SizedBox(width: 12),
                  _buildStatusBadge(status),
                  if (!item.isApproved) ...[
                    const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18)),
                  ]
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
                        Text(col, style: AppTheme.itemLabelStyle(context)),
                        Text(_getMetaValue(item, col), style: AppTheme.itemValueStyle(context)),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(_safeStr(item.metadata['last_location_info']?['full_name'], defaultVal: "위치 정보 없음"), style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        SizedBox(
          width: _colActionWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildCircleAction(Icons.history, Colors.blueGrey, "기록", () {
                _showHistoryDialog(context, item, theme);
              }),
              const SizedBox(width: 12),
              _buildCircleAction(Icons.login, AppTheme.success, "입장", () {
                _processAccessWithLocation(provider, item, '입장');
              }),
              const SizedBox(width: 12),
              _buildCircleAction(Icons.logout, AppTheme.warning, "퇴장", () {
                _processAccessWithLocation(provider, item, '퇴장');
              }),
              const SizedBox(width: 12),
              _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () {
                _confirmDelete(provider, item, theme);
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
  Widget _buildMobileListItem(UserModel item, UserProvider provider, List<String> columns, String status, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _handleSingleUserImageUpdate(provider, item, theme),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  _buildAvatar(item, theme, size: _colImgSize),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.cardTheme.color ?? Colors.white, width: 2),
                    ),
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
                          style: AppTheme.itemValueStyle(context).copyWith(fontSize: 19, color: item.name == '형식에 맞지 않는 건' ? AppTheme.danger : null),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(status),
                      if (!item.isApproved) ...[
                        const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18)),
                      ]
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_safeStr(item.metadata['last_location_info']?['full_name'], defaultVal: "위치 정보 없음"), style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
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
                  Text(col, style: AppTheme.itemLabelStyle(context)),
                  Text(_getMetaValue(item, col), style: AppTheme.itemValueStyle(context)),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Divider(color: theme.dividerTheme.color?.withValues(alpha: 0.5)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
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

    if (url == null || url.isEmpty) {
      return Container(
          width: size, height: size,
          decoration: BoxDecoration(
              color: isDark ? theme.dividerTheme.color?.withValues(alpha: 0.1) : const Color(0xFFF1F3F5),
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
            color: isDark ? theme.dividerTheme.color?.withValues(alpha: 0.1) : const Color(0xFFF1F3F5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 1.5)
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(fullUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.black12))
    );
  }

  Widget _buildStatusBadge(String status) {
    final Color color = status == '입장' ? AppTheme.success : (status == '퇴장' ? AppTheme.warning : Colors.grey);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(status, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: color, fontSize: 12, fontWeight: FontWeight.w900))
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
    final Map<String, String> baseFields = {'성명': item.name, '사번': item.code, '부서': item.department, '태그ID': item.tagId};
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
    final List<UserModel> selectedUsers = visibleItems.where((UserModel p) => _selectedUserIds.contains(p.id)).toList();
    if (selectedUsers.isEmpty) return;

    List<BulkEditField> fields = [
      BulkEditField(key: 'department', label: '새로운 담당부서/소속', type: BulkEditFieldType.text),
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
          return BulkEditDialog(
            title: '${selectedUsers.length}명 인원 정보 일괄 편집',
            fields: fields,
          );
        }
    );

    if (!mounted || resultValues == null) return;

    setState(() { _isFullScreenLoading = true; });

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
        } else {
          updatedMeta[key] = value;
        }
      });

      data['metadata'] = updatedMeta;

      await provider.handleSave(p: p, data: data);
    }

    if (!mounted) return;

    setState(() {
      _isFullScreenLoading = false;
      _selectedUserIds.clear();
      _isSelectionMode = false;
    });

    _showInfoDialog("일괄 편집 완료", "선택하신 ${selectedUsers.length}명의 데이터가 성공적으로 업데이트 되었습니다.", theme);
  }

  void _confirmBulkDelete(UserProvider provider, ThemeData theme) {
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("선택 항목 일괄 삭제", Icons.warning, color: AppTheme.danger),
              content: Text("선택하신 ${_selectedUserIds.length}명의 인원 정보를 모두 삭제하시겠습니까?\n이 작업은 되돌릴 수 없으며, 출입 이력도 함께 삭제될 수 있습니다.", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
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

                      for (String id in _selectedUserIds) {
                        await provider.deletePerson(id);
                      }

                      if (!mounted) return;

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
    final List<dynamic> history = p.metadata['access_history'] is List ? List.from(p.metadata['access_history']) : [];
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
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext c, int i) {
                      final dynamic log = history[i];
                      final String type = _safeStr(log['type'], defaultVal: "-");
                      final String timeStr = _safeStr(log['time'], defaultVal: "-");
                      final dynamic rawApprove = log['is_approved'];
                      final bool approved = rawApprove is bool ? rawApprove : true;
                      final Color col = approved ? (type == '입장' ? AppTheme.success : AppTheme.warning) : AppTheme.danger;

                      return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: theme.cardTheme.color, borderRadius: BorderRadius.circular(10), border: Border.all(color: col.withValues(alpha: 0.15))),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6, right: 16), decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                    Text(timeStr, style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold)),
                                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: col.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text(type, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: col, fontWeight: FontWeight.bold, fontSize: 12))),
                                  ]),
                                  const SizedBox(height: 6),
                                  Text('${_safeStr(log['location']?['building'], defaultVal: "미지정")} - ${_safeStr(log['location']?['gate'], defaultVal: "미정")}', style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.blueGrey, fontSize: 14, fontWeight: FontWeight.w600)),
                                ])),
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
    final List<String> baseFields = ['성명', '사번', '부서', '태그ID'];

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
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
          },
        );
      },
    );
  }

  Future<void> _showResetConfirmationDialog(UserProvider provider, ThemeData theme) async {
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

    if (!mounted || confirm != true) return;

    setState(() { _isFullScreenLoading = true; });

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
        setState(() { _isFullScreenLoading = false; });
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('초기화 완료', style: TextStyle(fontFamily: AppTheme.fontPretendard))));
      }
    }
  }

  Future<void> _handleBatchImport(UserProvider provider, ThemeData theme) async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
      if (!mounted || result == null) return;

      Uint8List? bytes = result.files.single.bytes;
      if (bytes == null && result.files.single.path != null) {
        bytes = await File(result.files.single.path!).readAsBytes();
      }

      if (!mounted || bytes == null) return;

      final excel_pkg.Excel excel = excel_pkg.Excel.decodeBytes(bytes);
      String targetSheet = excel.tables.keys.first;
      if (excel.tables.keys.contains('인원리스트')) {
        targetSheet = '인원리스트';
      }
      final excel_pkg.Sheet? sheet = excel.tables[targetSheet];
      if (sheet == null || sheet.maxRows <= 1) return;

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
      setState(() { _isFullScreenLoading = true; });

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
        String name = "", code = "", dept = "", tagId = "";
        final Map<String, dynamic> metadata = {};
        bool hasRowData = false;

        for (int colIdx = 0; colIdx < row.length; colIdx++) {
          if (colIdx >= headers.length) {
            break;
          }
          final String rawHeader = headers[colIdx];
          // [린터 반영 완료] 정규표현식에서 불필요한 escape 문자를 제거했습니다.
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

        String safeUsername = code.isEmpty
            ? 'user_${DateTime.now().millisecondsSinceEpoch % 100000}_$i'
            : code.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.-]'), '');
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
          'is_approved': name != "형식에 맞지 않는 건",
          'metadata': metadata
        };

        await provider.handleSave(p: null, data: data);
        currentCountNotifier.value++;
      }

      if (!mounted) return;
      setState(() { _isFullScreenLoading = false; });
      Navigator.of(context).pop();

    } catch (e) {
      if (mounted) {
        setState(() { _isFullScreenLoading = false; });
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

      final List<String> baseHeaders = ['성명', '사번', '부서', '태그ID'];

      final Set<String> metaKeySet = {};
      for (final UserModel p in dataList) {
        for (final String k in p.metadata.keys) {
          if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal')) {
            metaKeySet.add(k);
          }
        }
      }
      final List<String> metaHeaders = metaKeySet.toList()..sort();
      final List<String> allHeaders = [...baseHeaders, ...metaHeaders];

      final List<excel_pkg.CellValue> headerRow = allHeaders.map<excel_pkg.CellValue>((String h) => excel_pkg.TextCellValue(h)).toList();
      sheet.appendRow(headerRow);

      for (final UserModel p in dataList) {
        final List<excel_pkg.CellValue> rowData = [
          excel_pkg.TextCellValue(p.name),
          excel_pkg.TextCellValue(p.code),
          excel_pkg.TextCellValue(p.department),
          excel_pkg.TextCellValue(p.tagId),
        ];

        for (final String metaKey in metaHeaders) {
          rowData.add(excel_pkg.TextCellValue(_safeStr(p.metadata[metaKey])));
        }

        sheet.appendRow(rowData);
      }

      final String? path = await FilePicker.platform.saveFile(
          fileName: 'User_Export_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          type: FileType.custom,
          allowedExtensions: ['xlsx']
      );

      if (!mounted || path == null) return;

      await File(path).writeAsBytes(excel.encode()!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ 엑셀 다운로드가 완료되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
            elevation: 0
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 내보내기 실패: $e', style: const TextStyle(fontFamily: AppTheme.fontPretendard))));
      }
    }
  }

  /// ---------------------------------------------------------------------------
  /// [기능] 개선된 이미지 픽커 위젯 (선택, 미리보기, 삭제 기능 통합)
  /// 상세 정보 편집창 상단에 위치하며, 삭제(휴지통) 버튼을 직관적으로 제공합니다.
  /// ---------------------------------------------------------------------------
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
    final bool hasImage = preview != null || (url != null && url.isNotEmpty && !isDeleted);

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
            width: 180, height: 210, // 기존 UserPage 크기에 맞춤
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 2)
            ),
            child: Center(
              child: preview != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(preview, fit: BoxFit.cover))
                  : (hasImage
                  ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                      "${url!}${url.contains('?') ? '&' : '?'}t=${p!.hashCode}",
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)
                  )
              )
                  : const Icon(Icons.camera_alt, size: 50, color: Colors.grey)),
            ),
          ),
        ),

        // 이미지 삭제(X) 아이콘
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

  /// ---------------------------------------------------------------------------
  /// [인원 정보 등록 및 편집 다이얼로그]
  /// ---------------------------------------------------------------------------
  Future<void> _showForm(UserProvider provider, UserModel? p, ThemeData theme) async {
    final TextEditingController nameC = TextEditingController(text: p?.name ?? "");
    final TextEditingController codeC = TextEditingController(text: p?.code ?? "");
    final TextEditingController tagC = TextEditingController(text: p?.tagId ?? "");
    final TextEditingController deptC = TextEditingController(text: p?.department ?? "");
    final TextEditingController remarksC = TextEditingController(text: p?.remarks ?? "");
    bool approved = p?.isApproved ?? true;

    // 이미지 선택 및 삭제 상태 관리 변수
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

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogCtx) {
          return StatefulBuilder(
              builder: (BuildContext innerCtx, StateSetter setS) {

                Widget imagePickerWidget = _buildImagePickerBox(
                  context,
                  p,
                  preview,
                  isImageDeleted,
                      (pickedFile, pickedBytes) {
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
                      isImageDeleted = true; // 삭제(X) 클릭 시 플래그 켬
                    });
                  },
                  theme,
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
                                              Row(children: [const Text("출입 승인", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 14, fontWeight: FontWeight.bold)), const SizedBox(width: 8), Switch(value: approved, activeThumbColor: AppTheme.success, activeTrackColor: AppTheme.success.withValues(alpha: 0.5), onChanged: (bool v) { setS(() { approved = v; }); })])
                                            ]
                                        ),
                                        const SizedBox(width: 30),
                                        Expanded(
                                            child: Column(
                                                children: [
                                                  _buildTextField(nameC, "성명 (필수)", theme), const SizedBox(height: 16),
                                                  _buildTextField(deptC, "담당부서/소속", theme), const SizedBox(height: 16),
                                                  _buildTextField(codeC, "사번/ID", theme), const SizedBox(height: 16),
                                                  _buildTextField(tagC, "RFID 태그 EPC", theme), const SizedBox(height: 16),
                                                  _buildTextField(remarksC, "비고", theme),
                                                ]
                                            )
                                        )
                                      ]
                                  ),
                                  if (metaC.isNotEmpty) ...[
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
                                        children: metaC.entries.map((MapEntry<String, TextEditingController> e) => SizedBox(width: 360, child: _buildTextField(e.value, e.key, theme))).toList()
                                    )
                                  ]
                                ]
                            )
                        )
                    ),
                    actions: [
                      AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () {
                        Navigator.pop(dialogCtx);
                      }),
                      AppTheme.actionButton(label: "통합 저장", onPressed: () async {
                        final Map<String, dynamic> meta = Map<String, dynamic>.from(p?.metadata ?? {});
                        metaC.forEach((String k, TextEditingController c) {
                          meta[k] = c.text.trim();
                        });

                        String safeUsername = p != null && p.username.isNotEmpty
                            ? p.username
                            : codeC.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.-]'), '');
                        if (safeUsername.isEmpty) {
                          safeUsername = 'user_${DateTime.now().millisecondsSinceEpoch % 1000000}';
                        }
                        if (safeUsername.length < 3) {
                          safeUsername += '_u';
                        }

                        final Map<String, dynamic> data = {
                          'name': nameC.text.trim(),
                          'code': codeC.text.trim(),
                          'tag_id': tagC.text.trim(),
                          'department': deptC.text.trim(),
                          'is_approved': approved,
                          'remarks': remarksC.text.trim(),
                          'metadata': meta,
                          // 삭제 플래그가 켜졌다면 포켓베이스에 null을 보내어 파일을 초기화합니다.
                          if (isImageDeleted) 'avatar': null,
                        };

                        if (p == null) {
                          data['username'] = safeUsername;
                          data['email'] = '$safeUsername@plug4rfid.local';
                          data['password'] = 'password123';
                          data['passwordConfirm'] = 'password123';
                        }

                        final bool ok = await provider.handleSave(p: p, data: data, imageXFile: file);
                        if (!dialogCtx.mounted) return;

                        if (ok) {
                          Navigator.pop(dialogCtx);
                        }
                      })
                    ]
                );
              }
          );
        }
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, ThemeData theme) {
    return TextField(
        controller: ctrl,
        style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
        decoration: AppTheme.inputDecoration(label: label, context: context)
    );
  }

  void _confirmDelete(UserProvider provider, UserModel p, ThemeData theme) {
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
                  if (!c.mounted) return;

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
                    decoration: BoxDecoration(color: _ok ? AppTheme.success.withValues(alpha: 0.05) : AppTheme.danger.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: _ok ? AppTheme.success.withValues(alpha: 0.2) : AppTheme.danger.withValues(alpha: 0.2))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_ok ? "승인됨" : "미승인", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: _ok ? AppTheme.success : AppTheme.danger)), Switch(value: _ok, activeThumbColor: AppTheme.success, activeTrackColor: AppTheme.success.withValues(alpha: 0.5), onChanged: (bool v) { setState(() { _ok = v; }); })])
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
          return opts.where((String o) => o.contains(v.text));
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