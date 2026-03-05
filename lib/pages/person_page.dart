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

import '../models/persons.dart';
import '../utils/hangul_utils.dart';
import '../providers/person_provider.dart';
import '../theme/app_theme.dart';

/// RFID 인원 관리 페이지입니다.
/// 현장에 출입하는 인원들의 상태(입장/퇴장)와 상세 정보를 실시간으로 추적/관리합니다.
/// [디자인 철학] 미니멀리즘, 키오스크 스타일, Semi Bold(w600), Silver 텍스트 가이드 적용
class PersonPage extends StatefulWidget {
  final String searchQuery; // 상위 화면(MainPage)에서 전달받은 초기 검색어
  final String filter;      // 상위 화면에서 전달받은 초기 필터 상태
  final bool isMobile;      // 화면 레이아웃을 모바일/PC로 분기하기 위한 플래그
  final String baseUrl;     // 백엔드 API 및 이미지 서버 주소

  const PersonPage({
    super.key,
    required this.searchQuery,
    required this.filter,
    required this.isMobile,
    required this.baseUrl,
  });

  @override
  State<PersonPage> createState() => _PersonPageState();
}

/// PersonPage의 상태와 비즈니스 로직(검색, 필터, 엑셀 입출력 등)을 관리하는 클래스입니다.
class _PersonPageState extends State<PersonPage> {
  // --- UI 컨트롤러 및 상태 관리 변수 ---

  /// 상단 검색바의 입력을 관리하는 컨트롤러입니다.
  final TextEditingController _searchController = TextEditingController();

  String _currentSearchQuery = ""; // 현재 실시간으로 입력된 검색어 상태
  late String _currentFilter;      // 리스트에 적용될 필터 상태 ('전체', '등록' 등)
  String _activeMetricFilter = "전체"; // 상단 대시보드 통계 카드에서 선택된 필터 조건
  String? _selectedPersonId;       // 현재 리스트에서 클릭하여 선택된 인원의 고유 ID

  // --- UI 규격 디자인 상수 ---
  static const double _colImgSize = 70.0;      // 아바타 썸네일 이미지의 가로/세로 크기
  static const double _colActionWidth = 240.0; // 우측 액션 버튼(기록, 입장, 퇴장, 삭제) 영역의 고정 너비

  /// PocketBase 시스템 필드 및 화면 노출(표시 항목 설정)에서 제외해야 할 내부 관리용 데이터 키 목록입니다.
  static const Set<String> _excludedSystemKeys = {
    'import_source', 'original_row_data', 'id', 'created', 'updated',
    'collectionId', 'collectionName', 'last_access_type', 'last_access_time',
    'access_history', 'last_location_info', 'is_approved', 'last_approval_status',
    'image', 'name', 'code', 'department', 'tag_id', 'is_active', 'remarks',
    'excel_row', 'import_date', 'import_data', 'is_auto_tag', 'is_auto_atg',
    'excel_row_internal', 'import_data_internal', 'is_auto_tag_internal'
  };

  @override
  void initState() {
    super.initState();
    // 위젯 생성 시 부모로부터 넘겨받은 필터와 검색어로 초기 상태를 설정합니다.
    _currentFilter = widget.filter == '정상 등록' ? '등록' : widget.filter;
    _currentSearchQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
  }

  @override
  void dispose() {
    // 메모리 릭(누수)을 방지하기 위해 위젯 파괴 시 컨트롤러를 안전하게 해제합니다.
    _searchController.dispose();
    super.dispose();
  }

  // --- FA 대시보드용 통계 계산 로직 ---

  /// 전체 인원 리스트를 순회하여 오늘 날짜 기준으로 입장, 퇴장, 현재 잔류 인원을 계산합니다.
  Map<String, dynamic> _calculateMetrics(List<Person> list) {
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int todayIn = 0;
    int todayOut = 0;
    int currentRemained = 0;

    for (final p in list) {
      // 메타데이터에 기록된 마지막 출입 정보 확인
      final String lastType = p.metadata['last_access_type'] ?? "";
      final String lastTime = p.metadata['last_access_time'] ?? "";

      // 오늘 날짜에 발생한 이력만 카운트합니다.
      if (lastTime.startsWith(todayStr)) {
        if (lastType == '입장') {
          todayIn++;
        } else if (lastType == '퇴장') {
          todayOut++;
        }
      }

      // 현재 공장/현장 내부에 잔류하고 있는(마지막 상태가 '입장'인) 인원을 카운트합니다.
      if (lastType == '입장') {
        currentRemained++;
      }
    }
    return {'in': todayIn, 'out': todayOut, 'current': currentRemained};
  }

  // --- 비동기 출입 처리 로직 (Async Gap 린트 완벽 해결) ---

  /// 사용자가 수동으로 '입장' 또는 '퇴장' 버튼을 눌렀을 때 위치 정보를 입력받고 서버에 처리하는 프로세스입니다.
  Future<void> _processAccessWithLocation(PersonProvider provider, Person p, String type) async {
    final messenger = ScaffoldMessenger.of(context);

    // 1. 출입 건물 및 게이트를 선택하는 다이얼로그 호출
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _LocationSelectionDialog(type: type, existingPersons: provider.list),
    );

    // [린트 해결] 사용자가 다이얼로그를 취소했거나, 닫히는 동안 위젯이 트리를 벗어난 경우 방어 (context.mounted 사용)
    if (result == null || !context.mounted) {
      return;
    }

    final String now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final bool isApproved = result['is_approved'] ?? true;

    // 2. 메타데이터 갱신 (마지막 위치, 마지막 출입 시간, 승인 여부 업데이트)
    final updatedMeta = Map<String, dynamic>.from(p.metadata);
    updatedMeta['last_access_type'] = type;
    updatedMeta['last_access_time'] = now;
    updatedMeta['last_approval_status'] = isApproved;
    updatedMeta['last_location_info'] = {
      'building': result['building']?.trim() ?? "미지정",
      'gate': result['gate']?.trim() ?? "미지정",
      'full_name': "${result['building']} - ${result['gate']}"
    };

    // 3. 누적 출입 히스토리 리스트 맨 앞에 새 로그 추가 (최대 50개 이력 유지)
    List<dynamic> history = updatedMeta['access_history'] is List ? List.from(updatedMeta['access_history']) : [];
    history.insert(0, {
      'time': now,
      'type': type,
      'mode': '수동', // RFID 단말기를 통한 연동 시 '자동'으로 기록됨
      'is_approved': isApproved,
      'location': updatedMeta['last_location_info']
    });

    if (history.length > 50) {
      history = history.sublist(0, 50);
    }
    updatedMeta['access_history'] = history;

    // 4. Provider를 통해 서버로 변경된 정보(출입 상태 및 히스토리) 전송
    final success = await provider.handleSave(p: p, data: {'is_approved': isApproved, 'metadata': updatedMeta});

    // 5. 성공 시 화면 하단에 스낵바로 결과 알림 (context.mounted 확인 필수)
    if (success && context.mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text('[${p.name}]님 $type 처리 완료', style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
        backgroundColor: isApproved ? AppTheme.success : AppTheme.danger,
        elevation: 0,
        duration: const Duration(seconds: 1),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // PersonProvider를 통해 실시간 데이터 감시 및 테마 동기화
    final provider = context.watch<PersonProvider>();
    final theme = Theme.of(context);
    final metrics = _calculateMetrics(provider.list);

    // 검색어, 등록 상태 필터, 상단 통계 필터 3가지를 복합적으로 적용하는 엔진
    final filteredList = provider.list.where((p) {
      // 1. 일반 필터 (전체보기 vs 등록된 태그ID 유무 상태)
      final matchesFilter = _currentFilter == '전체' ||
          (_currentFilter == '등록' ? p.tagId.isNotEmpty : p.tagId.isEmpty);

      // 2. 검색어 매칭 (초성 검색 지원 기능 적용 및 사번, 부서명 검색)
      final matchesSearch = HangulUtils.matches(_currentSearchQuery, p.name) ||
          p.code.contains(_currentSearchQuery) ||
          p.department.contains(_currentSearchQuery);

      if (!matchesFilter || !matchesSearch) {
        return false;
      }

      // 3. 상단 대시보드 통계 카드 버튼 클릭 시 적용되는 필터
      if (_activeMetricFilter == "전체") {
        return true;
      }

      final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final lastTime = p.metadata['last_access_time'] ?? "";

      if (_activeMetricFilter == "당일 입장") {
        return (p.metadata['last_access_type'] == '입장' && lastTime.startsWith(todayStr));
      }
      if (_activeMetricFilter == "당일 퇴장") {
        return (p.metadata['last_access_type'] == '퇴장' && lastTime.startsWith(todayStr));
      }
      if (_activeMetricFilter == "현재 잔류") {
        return p.metadata['last_access_type'] == '입장';
      }
      return true;
    }).toList();

    return Scaffold(
      // 테마에서 정의한 톤온톤(Tone-on-Tone) 배경색 일괄 적용
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // 1. 상단 통계 대시보드
          _buildDashboard(metrics, provider, theme),
          Divider(height: 1, color: theme.dividerTheme.color),

          // 2. 검색창 및 엑셀 등 액션 버튼 바
          _buildHeader(provider, filteredList, theme),
          const SizedBox(height: 16),

          // 3. 메인 인원 리스트 뷰 영역
          Expanded(
            child: provider.isLoading
                ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                : _buildListView(filteredList, provider, provider.selectedColumns, theme),
          ),
        ],
      ),
    );
  }

  // --- UI 컴포넌트 구성 섹션 ---

  /// 화면 최상단에 위치한 4개의 통계 현황 카드(대시보드)입니다.
  Widget _buildDashboard(Map<String, dynamic> m, PersonProvider provider, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.scaffoldBackgroundColor,
      child: Row(
        children: [
          Expanded(child: _buildStatTile("전체 보기", provider.list.length, Icons.people, Colors.blueGrey, theme, filterKey: "전체")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("당일 입장", m['in'], Icons.login, AppTheme.success, theme, filterKey: "당일 입장")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("당일 퇴장", m['out'], Icons.logout, AppTheme.warning, theme, filterKey: "당일 퇴장")),
          const SizedBox(width: 12),
          Expanded(child: _buildStatTile("현재 잔류", m['current'], Icons.person_search, theme.colorScheme.primary, theme, filterKey: "현재 잔류")),
        ],
      ),
    );
  }

  /// 대시보드의 개별 통계 카드를 렌더링하며, 클릭 시 리스트를 해당 상태로 필터링합니다.
  Widget _buildStatTile(String label, int val, IconData icon, Color color, ThemeData theme, {required String filterKey}) {
    final bool isSelected = _activeMetricFilter == filterKey;
    return InkWell(
      onTap: () {
        setState(() {
          // 토글형 동작: 선택된 타일을 다시 누르면 필터 해제(전체 조회)
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

  /// 새로고침, 엑셀, 설정 등 핵심 액션 버튼들과 검색창을 품고 있는 헤더 위젯입니다.
  Widget _buildHeader(PersonProvider provider, List<Person> filtered, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildActionIcon(Icons.refresh, "새로고침", () => provider.fetchData(), theme),
                    _buildActionIcon(FontAwesomeIcons.fileArrowUp, "엑셀 업로드", () => _handleBatchImport(provider, theme), theme, color: Colors.indigo),
                    _buildActionIcon(FontAwesomeIcons.fileArrowDown, "엑스포트", () => _exportToExcel(filtered), theme, color: Colors.green),
                    _buildActionIcon(Icons.settings_outlined, "표시 항목 설정", () => _showColumnSelectionDialog(provider, theme), theme),
                    _buildActionIcon(Icons.delete_sweep_outlined, "초기화", () => _showResetConfirmationDialog(provider, theme), theme, color: AppTheme.danger),
                  ],
                ),
              ),
              AppTheme.actionButton(label: "신규 등록", icon: Icons.person_add_alt_1, onPressed: () => _showForm(provider, null, theme), color: theme.colorScheme.primary),
            ],
          ),
          const SizedBox(height: 16),
          // 검색어 입력 필드
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _currentSearchQuery = v),
            style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
            decoration: AppTheme.inputDecoration(label: "성명, 사번, 부서 또는 상세내용 검색...", context: context, prefixIcon: Icons.search),
          ),
        ],
      ),
    );
  }

  /// 상단 툴바에서 사용하는 아이콘 전용 사각 액션 버튼을 생성합니다.
  Widget _buildActionIcon(IconData icon, String tip, VoidCallback onTap, ThemeData theme, {Color? color, bool isLarge = false}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          child: Icon(icon, color: color ?? theme.iconTheme.color?.withValues(alpha: 0.6), size: isLarge ? 34 : 24),
        ),
      ),
    );
  }

  /// 중앙의 거대한 데이터 목록(인원 리스트)을 렌더링하는 리스트뷰 엔진입니다.
  Widget _buildListView(List<Person> list, PersonProvider provider, List<String> columns, ThemeData theme) {
    if (list.isEmpty) {
      return _buildEmptyState("데이터가 없습니다.");
    }

    return Container(
      // 디자인적 안정감을 위해 하단 여백 추가
      margin: const EdgeInsets.only(bottom: 20.0),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, idx) {
          final item = list[idx];
          final bool isSelected = _selectedPersonId == item.id;
          final status = item.metadata['last_access_type'] ?? "미확인";
          final statusColor = (status == '입장' ? AppTheme.success : (status == '퇴장' ? AppTheme.warning : theme.dividerTheme.color ?? Colors.grey));

          return InkWell(
            onTap: () {
              setState(() => _selectedPersonId = item.id);
              _showForm(provider, item, theme); // 목록 카드를 터치하면 수정 팝업 진입
            },
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: AppTheme.listItemDecoration(context, isSelected: isSelected, statusColor: statusColor),
              child: Row(
                children: [
                  _buildAvatar(item, theme, size: _colImgSize),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // 성명 출력 (크기 19px, 테마 속성 적용)
                            Text(
                              item.name,
                              style: AppTheme.itemValueStyle(context).copyWith(fontSize: 19),
                            ),
                            const SizedBox(width: 12),
                            _buildStatusBadge(status),
                            // 출입이 승인되지 않은 인원일 경우 경고 아이콘 노출
                            if (!item.isApproved)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: const Icon(Icons.gpp_maybe, color: AppTheme.danger, size: 18),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // '표시 항목 설정'에서 켜둔 컬럼들만 동적으로 매핑하여 화면에 렌더링합니다.
                        Wrap(
                          spacing: 20,
                          runSpacing: 8,
                          children: columns.map((col) {
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
                        Text(
                          item.metadata['last_location_info']?['full_name'] ?? "위치 정보 없음",
                          style: AppTheme.itemLabelStyle(context).copyWith(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  // 리스트 우측의 상태 제어 및 이력 조회 액션 버튼 영역
                  SizedBox(
                    width: _colActionWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildCircleAction(Icons.history, Colors.blueGrey, "기록", () => _showHistoryDialog(context, item, theme)),
                        const SizedBox(width: 12),
                        _buildCircleAction(Icons.login, AppTheme.success, "입장", () => _processAccessWithLocation(provider, item, '입장')),
                        const SizedBox(width: 12),
                        _buildCircleAction(Icons.logout, AppTheme.warning, "퇴장", () => _processAccessWithLocation(provider, item, '퇴장')),
                        const SizedBox(width: 12),
                        _buildCircleAction(Icons.delete_outline, AppTheme.danger, "삭제", () => _confirmDelete(provider, item, theme)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- 유틸리티 및 보조 UI 위젯 ---

  /// 카드의 가장 우측에서 사용되는 동그란 빠른 실행(Quick Action) 버튼입니다.
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

  /// 인원 사진(아바타)을 네모난 테두리에 맞게 예쁘게 잘라서 보여주는 위젯입니다.
  Widget _buildAvatar(Person item, ThemeData theme, {double size = 44}) {
    final url = item.getImageUrl(widget.baseUrl, thumb: '100x100');
    return Container(
        width: size, height: size,
        decoration: BoxDecoration(
            color: theme.dividerTheme.color?.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 1.5)
        ),
        clipBehavior: Clip.antiAlias,
        child: (url != null)
            ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.black12))
            : const Icon(Icons.person_outline, color: Colors.black12, size: 30)
    );
  }

  /// 인원의 현재 상태값(입장/퇴장)을 색상이 입혀진 둥근 배지 모양으로 만들어줍니다.
  Widget _buildStatusBadge(String status) {
    Color color = status == '입장' ? AppTheme.success : (status == '퇴장' ? AppTheme.warning : Colors.grey);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(status, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: color, fontSize: 12, fontWeight: FontWeight.w900))
    );
  }

  /// 검색 결과나 표시할 데이터가 없을 때 중앙에 위치하는 안내 컴포넌트입니다.
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

  /// 표시할 항목(라벨명)을 받아 해당 인원 객체(Person) 내에서 매칭되는 실제 데이터를 찾아 문자열로 반환합니다.
  String _getMetaValue(Person item, String key) {
    // 1. 기본 제공 속성 검사
    final baseFields = {'성명': item.name, '사번': item.code, '부서': item.department, '태그ID': item.tagId};
    if (baseFields.containsKey(key)) {
      return baseFields[key]!;
    }
    // 2. 기본 속성이 아니면 엑셀이나 폼으로 추가 등록한 동적 메타데이터 맵 안에서 값을 찾아 반환합니다.
    return item.metadata[key]?.toString() ?? "-";
  }

  // --- 시스템 기능 팝업 다이얼로그 (완벽 보존 구간) ---

  /// [에러 해결 1] 엑셀 처리 도중 에러가 나거나 일반 정보를 띄울 때 사용하던 다이얼로그를 복구했습니다.
  /// 단순 정보 및 오류를 사용자에게 안전하게 알리는 모달 위젯입니다.
  void _showInfoDialog(String title, String msg, ThemeData theme) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: AppTheme.dialogTitle(title, Icons.info_outline),
            content: Text(msg, style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
            actions: [
              AppTheme.actionButton(label: "확인", onPressed: () => Navigator.pop(ctx))
            ]
        )
    );
  }

  /// 특정 인원의 과거 출입 이력들(시간, 위치, 상태)을 시간 역순 리스트로 띄워줍니다.
  void _showHistoryDialog(BuildContext context, Person p, ThemeData theme) {
    final history = p.metadata['access_history'] is List ? List.from(p.metadata['access_history']) : [];
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: AppTheme.dialogTitle('[${p.name}]님 출입 히스토리', Icons.history, color: Colors.blueGrey),
          content: SizedBox(
              width: 550,
              height: 600,
              child: history.isEmpty
                  ? _buildEmptyState("기록 없음")
                  : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (c, i) {
                    final log = history[i];
                    final String type = log['type'] ?? "-";
                    final bool approved = log['is_approved'] ?? true;
                    // 승인 여부와 입장/퇴장 상태에 따라 점(Indicator)의 색상을 판별합니다.
                    Color col = approved ? (type == '입장' ? AppTheme.success : AppTheme.warning) : AppTheme.danger;
                    return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: theme.cardTheme.color, borderRadius: BorderRadius.circular(10), border: Border.all(color: col.withValues(alpha: 0.15))),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6, right: 16), decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Text(log['time'] ?? "-", style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: col.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text(type, style: TextStyle(fontFamily: AppTheme.fontPretendard, color: col, fontWeight: FontWeight.bold, fontSize: 12))),
                                ]),
                                const SizedBox(height: 6),
                                Text('${log['location']?['building'] ?? "미지정"} - ${log['location']?['gate'] ?? "미정"}', style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.blueGrey, fontSize: 14, fontWeight: FontWeight.w600)),
                              ])),
                            ]
                        )
                    );
                  }
              )
          ),
          actions: [AppTheme.actionButton(label: "닫기", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () => Navigator.pop(ctx))],
        )
    );
  }

  /// 사용자가 리스트뷰 카드에 어떤 동적 항목(직급, 전화번호 등)을 노출시킬지 고르는 설정 팝업입니다.
  void _showColumnSelectionDialog(PersonProvider provider, ThemeData theme) {
    // DB에 존재하는 모든 인원의 메타데이터를 순회하여 사용할 수 있는 '컬럼 키'들의 집합(Set)을 구성합니다.
    final Set<String> keySet = {};
    for (final p in provider.list) {
      for (final k in p.metadata.keys) {
        // 시스템 구동용 내부 키는 사용자가 선택할 수 없도록 제외시킵니다.
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal')) {
          keySet.add(k);
        }
      }
    }
    final available = keySet.toList()..sort();
    final List<String> temp = List.from(provider.selectedColumns); // 현재 유저가 보고 있는 설정값

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder( // 모달 안에서 체크박스 터치 시 UI를 즉시 갱신하기 위한 래퍼 위젯
            builder: (context, setS) => AlertDialog(
              title: AppTheme.dialogTitle("표시 항목 설정", Icons.view_column_rounded),
              content: SizedBox(
                  width: 480,
                  child: available.isEmpty
                      ? const Text("추가 필드 없음", style: TextStyle(fontFamily: AppTheme.fontPretendard))
                      : SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: available.map((key) {
                            final bool sel = temp.contains(key);
                            return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: InkWell(
                                  // 터치 시 선택 배열(temp)에 추가하거나 제거하는 토글 로직.
                                  // 화면이 망가지는 것을 막기 위해 항목 개수를 최소 1개, 최대 5개로 제한합니다.
                                    onTap: () => setS(() => sel ? (temp.length > 1 ? temp.remove(key) : null) : (temp.length < 5 ? temp.add(key) : null)),
                                    borderRadius: BorderRadius.circular(8),
                                    child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(color: sel ? theme.colorScheme.primary.withValues(alpha: 0.05) : Colors.transparent, borderRadius: BorderRadius.circular(8), border: Border.all(color: sel ? theme.colorScheme.primary : Colors.black.withValues(alpha: 0.15), width: sel ? 2.5 : 1.0)),
                                        child: Row(children: [Icon(sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 20, color: sel ? theme.colorScheme.primary : Colors.black26), const SizedBox(width: 16), Expanded(child: Text(key, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 15, fontWeight: FontWeight.bold, color: sel ? theme.colorScheme.primary : Colors.black45)))])
                                    )
                                )
                            );
                          }).toList()
                      )
                  )
              ),
              actions: [
                AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () => Navigator.pop(ctx)),
                AppTheme.actionButton(label: "설정 적용", onPressed: () async {
                  await provider.saveRemoteSettings(temp);
                  // [린트 해결 2] ctx 기반의 Navigator를 사용하므로 ctx.mounted로 비동기 후 안정성 확인
                  if (ctx.mounted) Navigator.pop(ctx);
                })
              ],
            )
        )
    );
  }

  /// 서버의 모든 데이터를 지워버리는 강력한 초기화(리셋) 경고창 및 실행 로직입니다.
  Future<void> _showResetConfirmationDialog(PersonProvider provider, ThemeData theme) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
            title: AppTheme.dialogTitle("삭제 확인", Icons.warning, color: AppTheme.danger),
            content: const Text("서버의 모든 정보를 영구 삭제하시겠습니까?", style: TextStyle(fontFamily: AppTheme.fontPretendard)),
            actions: [
              AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () => Navigator.pop(ctx, false)),
              AppTheme.actionButton(label: "삭제 실행", color: AppTheme.danger, onPressed: () => Navigator.pop(ctx, true))
            ]
        )
    );

    // [린트 해결] await 이후 context 사용에 대한 보호
    if (confirm == true && context.mounted) {
      await provider.resetAllPersons();
      messenger.showSnackBar(const SnackBar(content: Text('초기화 완료', style: TextStyle(fontFamily: AppTheme.fontPretendard))));
    }
  }

  /// 엑셀 파일(xlsx)을 파싱하여 시스템에 다수의 인원을 한 번에 밀어넣는 배치(Batch) 임포트 기능입니다.
  Future<void> _handleBatchImport(PersonProvider provider, ThemeData theme) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 1. 운영체제 고유 파일 선택기 호출
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      // [린트 해결]
      if (result == null || !context.mounted) return;

      Uint8List? bytes = result.files.single.bytes;
      if (bytes == null && result.files.single.path != null) {
        bytes = await File(result.files.single.path!).readAsBytes();
      }

      if (bytes == null) {
        if (context.mounted) _showInfoDialog("오류", "파일을 읽을 수 없습니다.", theme);
        return;
      }

      // 2. 엑셀 데이터 파싱
      final excel = excel_pkg.Excel.decodeBytes(bytes);
      String targetSheet = excel.tables.keys.first;
      if (excel.tables.keys.contains('인원리스트')) {
        targetSheet = '인원리스트';
      } else if (excel.tables.keys.contains('Sheet1')) {
        targetSheet = 'Sheet1';
      }

      final sheet = excel.tables[targetSheet];
      if (sheet == null || sheet.maxRows <= 1) {
        if (context.mounted) _showInfoDialog("알림", "데이터가 없습니다.", theme);
        return;
      }

      // 3. 첫 번째 행에서 컬럼 헤더 추출 (동적 메타데이터 구성을 위해)
      List<String> headers = [];
      final headerRow = sheet.row(0);
      for (var cell in headerRow) {
        headers.add(_extractString(cell));
      }

      int successCount = 0;
      int totalCount = 0;

      // 4. 각 행의 데이터를 파싱하여 인원 객체 형태로 서버 저장
      for (int i = 1; i < sheet.maxRows; i++) {
        final row = sheet.row(i);
        if (row.isEmpty) continue;

        String name = "";
        String code = "";
        String dept = "";
        String tagId = "";
        Map<String, dynamic> metadata = {};

        bool hasData = false;

        // 헤더 인덱스와 매칭하여 셀 데이터 분배
        for (int colIdx = 0; colIdx < row.length; colIdx++) {
          if (colIdx >= headers.length) break;

          String header = headers[colIdx];
          String val = _extractString(row[colIdx]);
          if (val.isNotEmpty) hasData = true;

          // 기본 관리 필드 매핑
          if (header == '성명' || header == '이름') {
            name = val;
          } else if (header == '사번' || header == 'ID') {
            code = val;
          } else if (header == '부서' || header == '소속' || header == '담당부서/소속') {
            dept = val;
          } else if (header == '태그ID' || header == 'RFID 태그 EPC') {
            tagId = val;
          } else {
            // 기본 필드가 아닌 항목은 모두 metadata 객체 속으로 집어넣어 동적 확장 지원
            if (header.isNotEmpty && val.isNotEmpty) {
              metadata[header] = val;
            }
          }
        }

        // 이름이 누락된 불량 데이터는 스킵
        if (!hasData || name.isEmpty) continue;

        // 태그ID가 비어있으면 현재 시간을 바탕으로 임시 ID를 발급
        if (tagId.isEmpty) {
          tagId = "TAG_${DateTime.now().millisecondsSinceEpoch}_$i";
        }

        totalCount++;

        final data = {
          'name': name,
          'code': code,
          'tag_id': tagId,
          'department': dept,
          'is_approved': true,
          'remarks': '',
          'metadata': metadata
        };

        // 데이터 저장 API 수행
        bool ok = await provider.handleSave(p: null, data: data, imageXFile: null);
        if (ok) successCount++;
      }

      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('총 $totalCount건 중 $successCount건 성공', style: const TextStyle(fontFamily: AppTheme.fontPretendard))));
      }

    } catch (e) {
      if (context.mounted) {
        _showInfoDialog("오류", "엑셀 업로드 중 오류가 발생했습니다: $e", theme);
      }
    }
  }

  /// 엑셀 패키지 버전에 따라 값이 TextCellValue 객체 등으로 리턴되는 것을
  /// 안전한 기본 문자열(String)로 추출해주는 보호 헬퍼 함수입니다.
  String _extractString(excel_pkg.Data? cell) {
    if (cell == null || cell.value == null) return "";
    final val = cell.value;
    String str = val.toString();

    if (str.startsWith("TextCellValue(")) {
      int start = str.indexOf('(') + 1;
      int end = str.lastIndexOf(')');
      if (start > 0 && end > start) return str.substring(start, end).trim();
    } else if (str.startsWith("IntCellValue(")) {
      int start = str.indexOf('(') + 1;
      int end = str.lastIndexOf(')');
      if (start > 0 && end > start) return str.substring(start, end).trim();
    } else if (str.startsWith("DoubleCellValue(")) {
      int start = str.indexOf('(') + 1;
      int end = str.lastIndexOf(')');
      if (start > 0 && end > start) return str.substring(start, end).trim();
    }
    return str.trim();
  }

  /// 현재 화면에 보여지고 있는 필터링된 데이터 목록을 엑셀 파일로 출력합니다.
  Future<void> _exportToExcel(List<Person> dataList) async {
    if (dataList.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['인원리스트'];
      excel.rename('Sheet1', '인원리스트');

      final headers = ['성명', '사번', '부서', '태그ID'];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = excel_pkg.TextCellValue(headers[i]);
      }

      for (int r = 0; r < dataList.length; r++) {
        final p = dataList[r];
        final row = [p.name, p.code, p.department, p.tagId];
        for (int c = 0; c < row.length; c++) {
          sheet.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value = excel_pkg.TextCellValue(row[c]);
        }
      }

      final path = await FilePicker.platform.saveFile(fileName: 'Person_Export_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx']);

      // [린트 해결] context.mounted 확인
      if (path != null && context.mounted) {
        await File(path).writeAsBytes(excel.encode()!);
        messenger.showSnackBar(const SnackBar(content: Text('✅ 엑셀 저장 완료', style: TextStyle(fontFamily: AppTheme.fontPretendard))));
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    }
  }

  /// 인원의 마스터 정보를 신규 등록하거나, 기존 프로필을 열어서 수정할 수 있는 통합 팝업 폼입니다.
  Future<void> _showForm(PersonProvider provider, Person? p, ThemeData theme) async {
    final navigator = Navigator.of(context); // [린트 해결] 비동기 이전에 네비게이터를 미리 추출합니다.

    // 화면에 보여줄 텍스트 필드 컨트롤러 선언 및 기존 데이터 바인딩
    final nameC = TextEditingController(text: p?.name ?? "");
    final codeC = TextEditingController(text: p?.code ?? "");
    final tagC = TextEditingController(text: p?.tagId ?? "");
    final deptC = TextEditingController(text: p?.department ?? "");
    final remarksC = TextEditingController(text: p?.remarks ?? "");
    bool approved = p?.isApproved ?? true; // 출입 승인 상태 토글값
    XFile? file; // 카메라/갤러리에서 선택된 이미지 파일
    Uint8List? preview; // 화면에 즉시 띄울 이미지 바이너리 뷰

    // 추가적인 메타데이터를 편집하기 위해 동적으로 컨트롤러 맵을 생성합니다.
    final Map<String, TextEditingController> metaC = {};
    if (p != null) {
      p.metadata.forEach((k, v) {
        if (!_excludedSystemKeys.contains(k) && !k.endsWith('_internal') && v is! Map && v is! List) {
          metaC[k] = TextEditingController(text: v?.toString() ?? "");
        }
      });
    }

    showDialog(
        context: context,
        barrierDismissible: false, // 여백 클릭으로 닫히는 것을 방지
        builder: (ctx) => StatefulBuilder( // 모달 안에서 이미지를 변경할 때 화면을 재구성하기 위해 감싸줍니다.
            builder: (dialogCtx, setS) => AlertDialog(
                title: AppTheme.dialogTitle(p == null ? '신규 인원 등록' : '정보 수정 및 편집', p == null ? Icons.person_add : Icons.edit),
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
                                    // 폼 좌측 영역: 프로필 사진 및 상태 제어
                                    Column(
                                        children: [
                                          GestureDetector(
                                              onTap: () async {
                                                // 클릭 시 시스템의 파일 브라우저를 띄워 이미지를 고릅니다.
                                                final img = await ImagePicker().pickImage(source: ImageSource.gallery);
                                                if (img != null) {
                                                  final b = await img.readAsBytes();
                                                  setS(() { file = img; preview = b; });
                                                }
                                              },
                                              child: Container(
                                                  width: 180,
                                                  height: 210,
                                                  decoration: BoxDecoration(color: theme.cardTheme.color, borderRadius: BorderRadius.circular(15), border: Border.all(color: theme.dividerTheme.color ?? Colors.grey, width: 2)),
                                                  child: Center(
                                                      child: preview != null
                                                          ? Image.memory(preview!, fit: BoxFit.cover)
                                                          : (p?.getImageUrl(widget.baseUrl) != null
                                                          ? Image.network(p!.getImageUrl(widget.baseUrl)!, fit: BoxFit.cover)
                                                          : const Icon(Icons.camera_alt, size: 40, color: Colors.grey))
                                                  )
                                              )
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                              children: [
                                                const Text("출입 승인", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 14, fontWeight: FontWeight.bold)),
                                                const SizedBox(width: 8),
                                                Switch(value: approved, activeThumbColor: AppTheme.success, activeTrackColor: AppTheme.success.withValues(alpha: 0.5), onChanged: (v) => setS(() => approved = v))
                                              ]
                                          )
                                        ]
                                    ),
                                    const SizedBox(width: 30),
                                    // 폼 우측 영역: 기본 필수 정보 텍스트 필드
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
                              // 엑셀 등으로 동적 생성된 확장 필드들이 있을 경우 하단에 나열
                              if (metaC.isNotEmpty) ...[
                                const SizedBox(height: 32),
                                const Divider(),
                                const SizedBox(height: 16),
                                Wrap(
                                    spacing: 16,
                                    runSpacing: 16,
                                    children: metaC.entries.map((e) => SizedBox(width: 360, child: _buildTextField(e.value, e.key, theme))).toList()
                                )
                              ]
                            ]
                        )
                    )
                ),
                actions: [
                  AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () => Navigator.pop(dialogCtx)),
                  AppTheme.actionButton(label: "통합 저장", onPressed: () async {
                    // 수정한 메타데이터 값들을 하나의 JSON 맵 형태로 결합합니다.
                    final meta = Map<String, dynamic>.from(p?.metadata ?? {});
                    metaC.forEach((k, c) => meta[k] = c.text.trim());

                    final data = {
                      'name': nameC.text.trim(),
                      'code': codeC.text.trim(),
                      'tag_id': tagC.text.trim(),
                      'department': deptC.text.trim(),
                      'is_approved': approved,
                      'remarks': remarksC.text.trim(),
                      'metadata': meta
                    };

                    // [린트 해결] 백엔드 전송 작업 완료 후 context.mounted 점검
                    if (await provider.handleSave(p: p, data: data, imageXFile: file) && context.mounted) {
                      navigator.pop();
                    }
                  })
                ]
            )
        )
    );
  }

  /// 폼에서 공통으로 재활용되는 텍스트 입력 위젯입니다.
  Widget _buildTextField(TextEditingController ctrl, String label, ThemeData theme) {
    return TextField(
        controller: ctrl,
        style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
        decoration: AppTheme.inputDecoration(label: label, context: context)
    );
  }

  /// 개별 인원 데이터를 삭제하기 전에 마지막으로 확인하는 다이얼로그입니다.
  void _confirmDelete(PersonProvider provider, Person p, ThemeData theme) {
    final nav = Navigator.of(context);
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
            title: AppTheme.dialogTitle("삭제 확인", Icons.delete),
            content: Text("[${p.name}] 정보를 삭제하시겠습니까?", style: const TextStyle(fontFamily: AppTheme.fontPretendard)),
            actions: [
              AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () => Navigator.pop(c)),
              AppTheme.actionButton(label: "삭제 실행", color: AppTheme.danger, onPressed: () async {
                // [린트 해결] 삭제 성공 여부와 context 안전성 검증
                if (await provider.deletePerson(p.id) && context.mounted) {
                  nav.pop();
                }
              })
            ]
        )
    );
  }
}

// ============================================================================
// 위치 선택 다이얼로그 전용 위젯
// ============================================================================

/// 수동으로 입장/퇴장 처리를 할 때, 사용자가 위치(건물명/게이트)를 입력할 수 있게 하는 팝업입니다.
class _LocationSelectionDialog extends StatefulWidget {
  final String type; // 부모로부터 받은 '입장' 또는 '퇴장' 텍스트
  final List<Person> existingPersons; // 자동완성(추천) 기능을 구성하기 위한 기존 등록 인원 정보 리스트

  const _LocationSelectionDialog({required this.type, required this.existingPersons});

  @override
  State<_LocationSelectionDialog> createState() => _LocationSelectionDialogState();
}

class _LocationSelectionDialogState extends State<_LocationSelectionDialog> {
  late List<String> _buildings, _gates;
  final _bC = TextEditingController(); // 건물명 컨트롤러
  final _gC = TextEditingController(); // 게이트명 컨트롤러
  bool _ok = true; // 처리 시 출입을 승인할지(정상) 거부할지(기록만 남김) 여부

  @override
  void initState() {
    super.initState();
    // 기본적인 추천 건물명과 게이트명 세팅
    final Set<String> b = {'본관A', '공장B', '물류창고C', '연구소D'};
    final Set<String> g = {'정문G1', '후문G2', '하차장G3', '비상구G4'};

    // 이전에 등록된 사람들의 위치 데이터를 동적으로 파싱하여, 자동완성(추천) 옵션 사전에 추가합니다.
    for (var p in widget.existingPersons) {
      final loc = p.metadata['last_location_info'];
      if (loc is Map) {
        if (loc['building'] != null) b.add(loc['building']);
        if (loc['gate'] != null) g.add(loc['gate']);
      }
    }
    _buildings = b.toList()..sort();
    _gates = g.toList()..sort();

    // 가장 처음 추천 단어를 기본 입력값으로 할당
    _bC.text = _buildings.first;
    _gC.text = _gates.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                        color: _ok ? AppTheme.success.withValues(alpha: 0.05) : AppTheme.danger.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _ok ? AppTheme.success.withValues(alpha: 0.2) : AppTheme.danger.withValues(alpha: 0.2))
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_ok ? "승인됨" : "미승인", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: _ok ? AppTheme.success : AppTheme.danger)),
                          Switch(value: _ok, activeThumbColor: AppTheme.success, activeTrackColor: AppTheme.success.withValues(alpha: 0.5), onChanged: (v) => setState(() => _ok = v))
                        ]
                    )
                )
              ]
          )
      ),
      actions: [
        AppTheme.actionButton(label: "취소", color: Colors.transparent, textColor: theme.colorScheme.onSurface.withValues(alpha: 0.5), onPressed: () => Navigator.pop(context)),
        // 확인 시, 입력된 위치 정보들을 Map 객체로 포장하여 부모 컨텍스트로 리턴합니다.
        AppTheme.actionButton(label: "위치 확정", onPressed: () => Navigator.pop(context, {'building': _bC.text, 'gate': _gC.text, 'is_approved': _ok}))
      ],
    );
  }

  /// 일반 텍스트 입력창이면서, 사용자가 글자를 치면 사전에 등록된 단어들을 드롭다운으로 추천해주는 '자동완성(Autocomplete)' 하이브리드 위젯입니다.
  Widget _buildCombo(String label, TextEditingController ctrl, List<String> opts, ThemeData theme) {
    return Autocomplete<String>(
        optionsBuilder: (v) => v.text == '' ? opts : opts.where((o) => o.contains(v.text)),
        onSelected: (s) => ctrl.text = s,
        fieldViewBuilder: (ctx, tC, fN, __) {
          // 내부에서 관리되는 tC와 외부(부모)의 ctrl 값을 동기화시킵니다.
          tC.text = ctrl.text;
          tC.addListener(() => ctrl.text = tC.text);
          return TextField(
              controller: tC,
              focusNode: fN,
              style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.dataColor(theme.brightness == Brightness.dark)),
              decoration: AppTheme.inputDecoration(label: label, context: context, hasFocus: fN.hasFocus)
          );
        }
    );
  }
}