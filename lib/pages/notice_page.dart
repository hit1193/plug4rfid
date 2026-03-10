import 'package:flutter/material.dart';

// 앞서 만들어둔 데이터 모델과 중앙 테마를 불러옵니다.
import '../models/notice_model.dart';
import '../theme/app_theme.dart';

/// ---------------------------------------------------------------------------
/// [공지사항 통합 관리 페이지]
/// 리스트 조회, 상세 보기, 신규 등록, 수정 기능은 물론,
/// 다중 선택(일괄 삭제), 전체 초기화, 건별 즉시 삭제 기능이 포함되어 있습니다.
///
/// [디자인 개편 사항]
/// - 출입 기록 페이지와 동일하게 상단 타이틀부 수직 중앙 정렬
/// - 조작 버튼(다중선택, 초기화, 등록)을 미니멀한 필터 박스로 그룹화
/// - 모바일/데스크톱 완벽 대응 및 키오스크 스타일의 넓고 깔끔한 여백 확보
/// ---------------------------------------------------------------------------
class NoticePage extends StatefulWidget {
  final bool isMobile;     // 모바일 환경인지 여부 (반응형 레이아웃용)
  final String baseUrl;    // DB 연결용 URL

  const NoticePage({
    super.key,
    required this.isMobile,
    required this.baseUrl,
  });

  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage> {
  // 화면에 보여줄 공지사항 데이터를 담을 리스트입니다.
  List<NoticeModel> noticeList = [];

  // ---------------------------------------------------------------------------
  // [상태 변수 선언부 - 다중 선택 및 기능 관련]
  // ---------------------------------------------------------------------------
  final Set<String> _selectedNoticeIds = {}; // 선택된 공지사항의 ID를 보관하는 집합(Set)
  bool _isSelectionMode = false;             // 다중 선택 모드 활성화 여부

  @override
  void initState() {
    super.initState();
    _loadMockData(); // 초기 가짜 데이터 로드 (추후 DB 연동 코드로 대체)
  }

  /// 테스트를 위해 임의의 데이터를 생성하고 정렬하는 함수입니다.
  void _loadMockData() {
    noticeList = [
      NoticeModel(
        id: 'notice-001',
        title: '[필독] 2026년 3월 시스템 정기 점검 안내',
        content: '안녕하세요. 시스템 관리자입니다.\n\n안정적인 서비스 제공을 위해 아래와 같이 시스템 정기 점검을 진행합니다.\n\n- 일시: 2026년 3월 15일 02:00 ~ 06:00 (4시간)\n- 대상: 물류창고 및 생산라인 전산 시스템 전체\n- 영향: 점검 시간 동안 RFID 태그 인식 및 데이터 동기화가 중단됩니다.\n\n현장 근무자분들께서는 업무에 참고하시기 바랍니다.',
        author: 'IT지원팀',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        isImportant: true, // 중요 공지사항
        viewCount: 152,
      ),
      NoticeModel(
        id: 'notice-002',
        title: '신규 RFID 스캐너 장비 도입 및 사용법 교육',
        content: '생산라인에 신규 도입된 고성능 RFID 스캐너 사용법 교육을 실시합니다.\n각 부서 파트장님들은 필수 참석 바랍니다.\n\n장소: 본관 3층 대회의실\n시간: 금주 목요일 오후 2시',
        author: '생산관리본부',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        isImportant: false,
        viewCount: 89,
      ),
      NoticeModel(
        id: 'notice-003',
        title: '방문객 출입 통제 절차 강화 안내',
        content: '최근 보안 지침이 강화됨에 따라 방문객 출입 통제 절차를 안내해 드립니다.',
        author: '보안팀',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        isImportant: false,
        viewCount: 45,
      ),
    ];
    _sortNotices(); // 데이터를 중요도 및 최신순으로 정렬합니다.
  }

  /// 중요 공지가 위로 오고, 그다음 최신순으로 정렬하는 로직입니다.
  void _sortNotices() {
    noticeList.sort((NoticeModel a, NoticeModel b) {
      if (a.isImportant && !b.isImportant) {
        return -1;
      }
      if (!a.isImportant && b.isImportant) {
        return 1;
      }
      return b.createdAt.compareTo(a.createdAt); // 내림차순 정렬
    });
  }

  /// ---------------------------------------------------------------------------
  /// [1] 공지사항 상세 보기 다이얼로그 호출 함수
  /// ---------------------------------------------------------------------------
  void _showDetailDialog(NoticeModel notice) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return _NoticeDetailDialog(
          notice: notice,
          isMobile: widget.isMobile,
          onEdit: () {
            Navigator.pop(dialogContext); // 상세 창을 닫고
            _showEditDialog(notice: notice); // 편집 창을 엽니다.
          },
          onDelete: () {
            Navigator.pop(dialogContext); // 상세 창을 닫고
            _deleteNotice(notice.id); // 개별 삭제 로직을 실행합니다.
          },
        );
      },
    );
  }

  /// ---------------------------------------------------------------------------
  /// [2] 공지사항 등록 및 수정 다이얼로그 호출 함수
  /// ---------------------------------------------------------------------------
  void _showEditDialog({NoticeModel? notice}) {
    showDialog<NoticeModel>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _NoticeEditDialog(
          notice: notice,
          isMobile: widget.isMobile,
        );
      },
    ).then((NoticeModel? result) {
      if (result != null) {
        setState(() {
          if (notice == null) {
            noticeList.add(result);
          } else {
            int index = noticeList.indexWhere((element) => element.id == result.id);
            if (index != -1) {
              noticeList[index] = result;
            }
          }
          _sortNotices();
        });
      }
    });
  }

  /// ---------------------------------------------------------------------------
  /// [3] 건별 공지사항 삭제 처리 함수 (확인 창 포함)
  /// ---------------------------------------------------------------------------
  void _deleteNotice(String noticeId) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (BuildContext confirmContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
          title: AppTheme.dialogTitle("공지사항 삭제", Icons.warning_amber_rounded, color: AppTheme.danger),
          content: Text("이 공지사항을 정말로 삭제하시겠습니까?", style: AppTheme.itemValueStyle(confirmContext)),
          actions: [
            TextButton(
              child: Text("취소", style: TextStyle(color: AppTheme.labelColor(isDarkMode))),
              onPressed: () => Navigator.pop(confirmContext),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: () {
                setState(() {
                  noticeList.removeWhere((element) => element.id == noticeId);
                  _selectedNoticeIds.remove(noticeId); // 선택 목록에서도 제거
                });
                Navigator.pop(confirmContext);
              },
              child: const Text("삭제", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// ---------------------------------------------------------------------------
  /// [4] 다중 선택 일괄 삭제 처리 함수
  /// ---------------------------------------------------------------------------
  void _confirmBulkDelete(ThemeData theme) {
    final bool isDarkMode = theme.brightness == Brightness.dark;

    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("선택 항목 일괄 삭제", Icons.warning, color: AppTheme.danger),
              content: Text(
                  "선택하신 ${_selectedNoticeIds.length}건의 공지사항을 모두 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
                  style: const TextStyle(fontFamily: AppTheme.fontPretendard)
              ),
              actions: [
                AppTheme.actionButton(
                    label: "취소",
                    color: Colors.transparent,
                    textColor: AppTheme.labelColor(isDarkMode),
                    onPressed: () => Navigator.pop(ctx)
                ),
                AppTheme.actionButton(
                    label: "일괄 삭제",
                    color: AppTheme.danger,
                    onPressed: () {
                      setState(() {
                        noticeList.removeWhere((element) => _selectedNoticeIds.contains(element.id));
                        _selectedNoticeIds.clear();
                        _isSelectionMode = false;
                      });
                      Navigator.pop(ctx);

                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text("선택한 공지사항이 일괄 삭제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)),
                              elevation: 0
                          )
                      );
                    }
                )
              ]
          );
        }
    );
  }

  /// ---------------------------------------------------------------------------
  /// [5] 전체 데이터 초기화 처리 함수
  /// ---------------------------------------------------------------------------
  void _showResetConfirmationDialog(ThemeData theme) {
    final bool isDarkMode = theme.brightness == Brightness.dark;

    showDialog(
        context: context,
        builder: (BuildContext ctx) {
          return AlertDialog(
              title: AppTheme.dialogTitle("전체 데이터 초기화", Icons.delete_sweep, color: AppTheme.danger),
              content: const Text(
                  "모든 공지사항 정보를 영구 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
                  style: TextStyle(fontFamily: AppTheme.fontPretendard)
              ),
              actions: [
                AppTheme.actionButton(
                    label: "취소",
                    color: Colors.transparent,
                    textColor: AppTheme.labelColor(isDarkMode),
                    onPressed: () => Navigator.pop(ctx)
                ),
                AppTheme.actionButton(
                    label: "초기화 실행",
                    color: AppTheme.danger,
                    onPressed: () {
                      setState(() {
                        noticeList.clear();
                        _selectedNoticeIds.clear();
                        _isSelectionMode = false;
                      });
                      Navigator.pop(ctx);

                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('모든 공지사항이 초기화 되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
                              elevation: 0
                          )
                      );
                    }
                )
              ]
          );
        }
    );
  }

  /// ---------------------------------------------------------------------------
  /// [메인 화면 UI 구성]
  /// 기존 AppBar를 제거하고 커스텀 상단 패널로 교체하여 일관성을 확보했습니다.
  /// ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent, // 상위 탭/라우터의 배경색을 따르도록 투명처리
      // AppBar 제거! _buildTopControlPanel이 헤더 역할을 대신합니다.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 새롭게 개편된 상단 제어 패널 (타이틀 + 액션 박스)
          _buildTopControlPanel(theme, isDarkMode),

          // 2. 본문 영역 (선택 툴바 + 리스트뷰)
          Expanded(
            child: _buildListView(theme, isDarkMode),
          ),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [UI 개편] 상단 대시보드 제어 패널 (타이틀 및 컨트롤 박스)
  /// 출입 기록 페이지와 동일한 룩앤필(Look & Feel)을 제공합니다.
  /// ---------------------------------------------------------------------------
  Widget _buildTopControlPanel(ThemeData theme, bool isDark) {
    return Container(
      padding: EdgeInsets.all(widget.isMobile ? 16.0 : 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 헤더 (타이틀) 영역 - 수직 중앙 정렬 적용
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.campaign_rounded, color: AppTheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              // 부연 설명 텍스트 없이 타이틀만 깔끔하게 배치
              Text(
                "공지사항 관리",
                style: TextStyle(
                  fontFamily: AppTheme.fontPretendard,
                  fontSize: widget.isMobile ? 20 : 24,
                  fontWeight: AppTheme.weightMenu,
                  color: AppTheme.dataColor(isDark),
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 2. 조작 및 컨트롤 박스 (미니멀리즘 카드 스타일)
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            // 모바일과 PC 환경에 맞춰 버튼 배치를 다르게 합니다.
            child: widget.isMobile ? _buildMobileActionLayout(theme, isDark) : _buildDesktopActionLayout(theme, isDark),
          ),
        ],
      ),
    );
  }

  /// [UI 조각] 데스크톱/태블릿용 가로형 액션 레이아웃
  Widget _buildDesktopActionLayout(ThemeData theme, bool isDark) {
    return Row(
      children: [
        // 다중 선택 버튼 (토글)
        OutlinedButton.icon(
          icon: Icon(_isSelectionMode ? Icons.close_fullscreen_rounded : Icons.checklist_rtl_rounded, size: 18),
          label: Text(
            _isSelectionMode ? "다중 선택 끄기" : "다중 선택 켜기",
            style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightOthers, fontSize: 15),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _isSelectionMode ? AppTheme.primary : AppTheme.dataColor(isDark),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            side: BorderSide(color: (_isSelectionMode ? AppTheme.primary : AppTheme.silver).withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            backgroundColor: _isSelectionMode ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
          ),
          onPressed: () {
            setState(() {
              _isSelectionMode = !_isSelectionMode;
              if (!_isSelectionMode) {
                _selectedNoticeIds.clear(); // 모드를 끄면 선택 해제
              }
            });
          },
        ),
        const SizedBox(width: 12),

        // 데이터 초기화 버튼
        OutlinedButton.icon(
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text(
            "전체 초기화",
            style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightOthers, fontSize: 15),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.danger,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _showResetConfirmationDialog(theme),
        ),

        const Spacer(), // 남는 공간을 모두 차지하여 신규 등록 버튼을 우측 끝으로 밀어냅니다.

        // 신규 등록 버튼 (강조)
        ElevatedButton.icon(
          icon: const Icon(Icons.add_box_rounded, size: 20),
          label: const Text("새 공지 등록", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightMenu)),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _showEditDialog(),
        ),
      ],
    );
  }

  /// [UI 조각] 모바일용 세로형 액션 레이아웃
  Widget _buildMobileActionLayout(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, // 버튼들이 가로로 꽉 차도록 확장
      children: [
        // 모바일에서는 가장 중요한 '신규 등록' 버튼을 맨 위에 배치합니다.
        ElevatedButton.icon(
          icon: const Icon(Icons.add_box_rounded, size: 20),
          label: const Text("새 공지 등록", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightMenu)),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _showEditDialog(),
        ),
        const SizedBox(height: 12),

        // 하위 조작 버튼들은 한 줄에 나란히 배치 (공간 부족 시 줄바꿈)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: Icon(_isSelectionMode ? Icons.close_fullscreen_rounded : Icons.checklist_rtl_rounded, size: 18),
              label: Text(
                _isSelectionMode ? "다중 선택 끄기" : "다중 선택 켜기",
                style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightOthers, fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _isSelectionMode ? AppTheme.primary : AppTheme.dataColor(isDark),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                side: BorderSide(color: (_isSelectionMode ? AppTheme.primary : AppTheme.silver).withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                backgroundColor: _isSelectionMode ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
              ),
              onPressed: () {
                setState(() {
                  _isSelectionMode = !_isSelectionMode;
                  if (!_isSelectionMode) {
                    _selectedNoticeIds.clear();
                  }
                });
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text(
                "전체 초기화",
                style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightOthers, fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showResetConfirmationDialog(theme),
            ),
          ],
        ),
      ],
    );
  }

  /// [UI 조각] 선택 툴바와 공지사항 리스트를 포함하는 본문 영역입니다.
  Widget _buildListView(ThemeData theme, bool isDarkMode) {
    if (noticeList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 80, color: AppTheme.labelColor(isDarkMode).withValues(alpha: 0.3)),
            const SizedBox(height: 24),
            Text(
              '등록된 공지사항이 없습니다.',
              style: TextStyle(
                fontFamily: AppTheme.fontPretendard,
                fontWeight: AppTheme.weightMenu,
                fontSize: 20,
                color: AppTheme.labelColor(isDarkMode),
              ),
            ),
          ],
        ),
      );
    }

    final bool isAllSelected = noticeList.isNotEmpty && noticeList.every((NoticeModel p) => _selectedNoticeIds.contains(p.id));

    return Column(
      children: [
        // 다중 선택 모드가 켜졌을 때 나타나는 상단 툴바
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _isSelectionMode
              ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // 선택된 개수 뱃지
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text(
                        '${_selectedNoticeIds.length}건 선택됨',
                        style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: AppTheme.primary)
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 일괄 삭제 버튼
                  ElevatedButton.icon(
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text("일괄 삭제", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white, elevation: 0),
                    onPressed: _selectedNoticeIds.isEmpty ? null : () => _confirmBulkDelete(theme),
                  ),
                  const SizedBox(width: 16),

                  Container(width: 1, height: 24, color: theme.dividerTheme.color),
                  const SizedBox(width: 16),

                  // 전체 선택 / 선택 해제 버튼
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
                          _selectedNoticeIds.clear();
                        } else {
                          for (final NoticeModel e in noticeList) {
                            _selectedNoticeIds.add(e.id);
                          }
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          )
              : const SizedBox.shrink(), // 다중 선택 모드가 아닐 때는 숨김
        ),

        // 공지사항 항목 리스트
        Expanded(
          // [대표님 요청사항] 리스트뷰의 부모 컨테이너에 하단 여백 20px 추가
          child: Container(
            margin: const EdgeInsets.only(bottom: 20.0), // 하단 여백 설정
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: widget.isMobile ? 16.0 : 24.0, vertical: 8.0),
              itemCount: noticeList.length,
              itemBuilder: (BuildContext context, int index) {
                final NoticeModel notice = noticeList[index];
                return _buildNoticeItem(context, notice, theme, isDarkMode);
              },
            ),
          ),
        ),
      ],
    );
  }

  /// [UI 조각] 목록에 들어갈 각각의 항목(Card)을 만들어주는 함수입니다.
  Widget _buildNoticeItem(BuildContext context, NoticeModel notice, ThemeData theme, bool isDarkMode) {
    final bool isSelected = _selectedNoticeIds.contains(notice.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          // 다중 선택 모드일 때 나타나는 체크박스 애니메이션 영역
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
                      _selectedNoticeIds.remove(notice.id);
                    } else {
                      _selectedNoticeIds.add(notice.id);
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

          // 실제 공지사항 카드 영역
          Expanded(
            child: Card(
              clipBehavior: Clip.hardEdge,
              // 선택되었을 때 테두리 색상을 하이라이트 합니다.
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                side: BorderSide(
                  color: isSelected ? AppTheme.primary : (theme.dividerTheme.color ?? Colors.grey).withValues(alpha: 0.5),
                  width: isSelected ? 2.5 : 1.0,
                ),
              ),
              child: InkWell(
                onTap: () {
                  if (_isSelectionMode) {
                    // 다중 선택 모드일 때는 탭하면 선택 상태를 토글합니다.
                    setState(() {
                      if (isSelected) {
                        _selectedNoticeIds.remove(notice.id);
                      } else {
                        _selectedNoticeIds.add(notice.id);
                      }
                    });
                  } else {
                    // 일반 모드일 때는 상세 화면 다이얼로그를 띄웁니다.
                    _showDetailDialog(notice);
                  }
                },
                child: Padding(
                  padding: EdgeInsets.all(widget.isMobile ? 16.0 : 24.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 아이콘
                      Icon(
                        notice.isImportant ? Icons.campaign : Icons.article_outlined,
                        color: notice.isImportant ? AppTheme.danger : AppTheme.labelColor(isDarkMode),
                        size: widget.isMobile ? 28 : 36,
                      ),
                      SizedBox(width: widget.isMobile ? 12 : 20),

                      // 정보 텍스트 영역
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notice.title,
                              style: TextStyle(
                                fontFamily: AppTheme.fontPretendard,
                                fontSize: widget.isMobile ? 18 : 22,
                                fontWeight: notice.isImportant ? AppTheme.weightMenu : AppTheme.weightOthers,
                                letterSpacing: -0.4,
                                color: notice.isImportant ? AppTheme.danger : AppTheme.dataColor(isDarkMode),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.calendar_today, size: 14, color: AppTheme.labelColor(isDarkMode)),
                                const SizedBox(width: 6),
                                Text(notice.getFormattedDate(), style: AppTheme.itemLabelStyle(context)),
                                const SizedBox(width: 16),

                                Icon(Icons.person, size: 14, color: AppTheme.labelColor(isDarkMode)),
                                const SizedBox(width: 6),
                                Text(notice.author, style: AppTheme.itemLabelStyle(context)),

                                const Spacer(),

                                Icon(Icons.visibility, size: 14, color: AppTheme.labelColor(isDarkMode)),
                                const SizedBox(width: 6),
                                Text('${notice.viewCount}', style: AppTheme.itemLabelStyle(context)),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // 건별 즉시 삭제 아이콘 버튼 (선택 모드가 아닐 때만 표시)
                      if (!_isSelectionMode) ...[
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          color: AppTheme.danger.withValues(alpha: 0.7),
                          tooltip: "이 공지사항 삭제",
                          onPressed: () => _deleteNotice(notice.id),
                        ),
                      ]
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
}

/// ===========================================================================
/// 아래부터는 동일한 파일 내에서 다이얼로그(팝업)로 띄울 전용 내부 위젯들입니다.
/// 화면(파일)을 이동하지 않고 현재 페이지 위에서 오버레이 형태로 렌더링됩니다.
/// ===========================================================================

/// ---------------------------------------------------------------------------
/// [내부 위젯: 공지사항 상세 보기 다이얼로그]
/// ---------------------------------------------------------------------------
class _NoticeDetailDialog extends StatelessWidget {
  final NoticeModel notice;
  final bool isMobile;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NoticeDetailDialog({
    required this.notice,
    required this.isMobile,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDarkMode = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
      backgroundColor: theme.scaffoldBackgroundColor,
      insetPadding: EdgeInsets.all(isMobile ? 16.0 : 40.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 800, maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          children: [
            // 다이얼로그 상단 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '공지사항 상세',
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontWeight: AppTheme.weightMenu,
                        fontSize: 20,
                        color: AppTheme.dataColor(isDarkMode),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    icon: Icon(Icons.edit, size: 18, color: theme.colorScheme.primary),
                    label: Text("수정", style: TextStyle(color: theme.colorScheme.primary, fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightMenu)),
                    onPressed: onEdit,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.danger),
                    label: const Text("삭제", style: TextStyle(color: AppTheme.danger, fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightMenu)),
                    onPressed: onDelete,
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppTheme.labelColor(isDarkMode)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(color: theme.dividerTheme.color, height: 1),

            // 다이얼로그 본문 내용
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.title,
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontSize: isMobile ? 24 : 32,
                        fontWeight: AppTheme.weightMenu,
                        letterSpacing: -0.8,
                        color: notice.isImportant ? AppTheme.danger : AppTheme.dataColor(isDarkMode),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.business, color: AppTheme.labelColor(isDarkMode), size: 20),
                          const SizedBox(width: 8),
                          Text(notice.author, style: AppTheme.itemValueStyle(context)),
                          const SizedBox(width: 32),
                          Icon(Icons.calendar_month, color: AppTheme.labelColor(isDarkMode), size: 20),
                          const SizedBox(width: 8),
                          Text(notice.getFormattedDate(), style: AppTheme.itemValueStyle(context)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    Text(
                      notice.content,
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: AppTheme.weightOthers,
                        letterSpacing: -0.4,
                        height: 1.8,
                        color: AppTheme.dataColor(isDarkMode),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// [내부 위젯: 공지사항 등록/수정 폼 다이얼로그]
/// ---------------------------------------------------------------------------
class _NoticeEditDialog extends StatefulWidget {
  final NoticeModel? notice;
  final bool isMobile;

  const _NoticeEditDialog({
    this.notice,
    required this.isMobile,
  });

  @override
  State<_NoticeEditDialog> createState() => _NoticeEditDialogState();
}

class _NoticeEditDialogState extends State<_NoticeEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _authorController;
  late TextEditingController _contentController;
  bool _isImportant = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.notice?.title ?? '');
    _authorController = TextEditingController(text: widget.notice?.author ?? '');
    _contentController = TextEditingController(text: widget.notice?.content ?? '');
    _isImportant = widget.notice?.isImportant ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _saveNotice() {
    if (_formKey.currentState!.validate()) {
      final newNotice = NoticeModel(
        id: widget.notice?.id ?? 'notice-${DateTime.now().millisecondsSinceEpoch}',
        title: _titleController.text,
        content: _contentController.text,
        author: _authorController.text,
        createdAt: widget.notice?.createdAt ?? DateTime.now(),
        isImportant: _isImportant,
        viewCount: widget.notice?.viewCount ?? 0,
      );
      Navigator.pop(context, newNotice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDarkMode = theme.brightness == Brightness.dark;
    final String dialogTitle = widget.notice == null ? '새 공지 등록' : '공지사항 수정';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
      backgroundColor: theme.scaffoldBackgroundColor,
      insetPadding: EdgeInsets.all(widget.isMobile ? 16.0 : 40.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 800, maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      dialogTitle,
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontWeight: AppTheme.weightMenu,
                        fontSize: 20,
                        color: AppTheme.dataColor(isDarkMode),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppTheme.labelColor(isDarkMode)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(color: theme.dividerTheme.color, height: 1),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _titleController,
                        style: AppTheme.itemValueStyle(context),
                        decoration: AppTheme.inputDecoration(label: '제목을 입력하세요 (필수)', context: context, prefixIcon: Icons.title),
                        validator: (value) => (value == null || value.trim().isEmpty) ? '제목은 필수 항목입니다.' : null,
                      ),
                      const SizedBox(height: 24),

                      TextFormField(
                        controller: _authorController,
                        style: AppTheme.itemValueStyle(context),
                        decoration: AppTheme.inputDecoration(label: '작성자 또는 부서명 (필수)', context: context, prefixIcon: Icons.person),
                        validator: (value) => (value == null || value.trim().isEmpty) ? '작성자를 입력해주세요.' : null,
                      ),
                      const SizedBox(height: 24),

                      TextFormField(
                        controller: _contentController,
                        style: AppTheme.itemValueStyle(context),
                        maxLines: 12,
                        decoration: AppTheme.inputDecoration(label: '공지사항 본문 내용', context: context).copyWith(alignLabelWithHint: true),
                        validator: (value) => (value == null || value.trim().isEmpty) ? '본문 내용을 입력해주세요.' : null,
                      ),
                      const SizedBox(height: 24),

                      Container(
                        decoration: AppTheme.listItemDecoration(
                            context,
                            isSelected: _isImportant,
                            statusColor: theme.dividerTheme.color ?? Colors.grey
                        ),
                        child: SwitchListTile(
                          title: Text(
                            '상단 고정 및 빨간색 강조 (중요 공지)',
                            style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightOthers, color: _isImportant ? AppTheme.danger : AppTheme.dataColor(isDarkMode)),
                          ),
                          value: _isImportant,
                          activeThumbColor: AppTheme.danger,
                          activeTrackColor: AppTheme.danger.withValues(alpha: 0.4),
                          onChanged: (bool value) => setState(() => _isImportant = value),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: widget.isMobile ? 56 : 64,
                child: AppTheme.actionButton(
                  label: '저장하기',
                  color: theme.colorScheme.primary,
                  icon: Icons.save_rounded,
                  onPressed: _saveNotice,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}