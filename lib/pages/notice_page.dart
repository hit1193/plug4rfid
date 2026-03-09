import 'package:flutter/material.dart';

// 앞서 만들어둔 데이터 모델과 중앙 테마를 불러옵니다.
import '../models/notice_model.dart';
import '../theme/app_theme.dart';

/// ---------------------------------------------------------------------------
/// [공지사항 통합 관리 페이지]
/// 리스트 조회, 상세 보기, 신규 등록, 수정 기능을 이 파일 하나에서 모두 처리합니다.
/// 화면 이동(Navigator.push) 대신 세련된 다이얼로그(팝업) 방식을 사용하여
/// 키오스크 및 데스크톱 환경에 최적화된 미니멀리즘 UX를 제공합니다.
/// ---------------------------------------------------------------------------
class NoticePage extends StatefulWidget {
  final bool isMobile;     // 모바일 환경인지 여부 (반응형 다이얼로그 크기 조절용)
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
    ];
    _sortNotices(); // 데이터를 중요도 및 최신순으로 정렬합니다.
  }

  /// 중요 공지가 위로 오고, 그다음 최신순으로 정렬하는 로직입니다.
  void _sortNotices() {
    noticeList.sort((NoticeModel a, NoticeModel b) {
      if (a.isImportant && !b.isImportant) return -1;
      if (!a.isImportant && b.isImportant) return 1;
      return b.createdAt.compareTo(a.createdAt); // 내림차순 정렬
    });
  }

  /// ---------------------------------------------------------------------------
  /// [1] 공지사항 상세 보기 다이얼로그 호출 함수
  /// 리스트에서 항목을 클릭했을 때 화면 중앙에 뜨는 팝업창입니다.
  /// ---------------------------------------------------------------------------
  void _showDetailDialog(NoticeModel notice) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return _NoticeDetailDialog(
          notice: notice,
          isMobile: widget.isMobile,
          // 팝업 안에서 '수정' 버튼을 눌렀을 때 실행될 콜백 함수
          onEdit: () {
            Navigator.pop(dialogContext); // 상세 창을 닫고
            _showEditDialog(notice: notice); // 편집 창을 엽니다.
          },
          // 팝업 안에서 '삭제' 버튼을 눌렀을 때 실행될 콜백 함수
          onDelete: () {
            Navigator.pop(dialogContext); // 상세 창을 닫고
            _deleteNotice(notice.id); // 삭제 로직을 실행합니다.
          },
        );
      },
    );
  }

  /// ---------------------------------------------------------------------------
  /// [2] 공지사항 등록 및 수정 다이얼로그 호출 함수
  /// 새 공지 등록 버튼이나 상세 보기의 수정 버튼을 눌렀을 때 뜹니다.
  /// ---------------------------------------------------------------------------
  void _showEditDialog({NoticeModel? notice}) {
    showDialog<NoticeModel>(
      context: context,
      barrierDismissible: false, // 작성 중 실수로 바깥을 눌러 꺼지는 것을 방지합니다.
      builder: (BuildContext dialogContext) {
        return _NoticeEditDialog(
          notice: notice,
          isMobile: widget.isMobile,
        );
      },
    ).then((NoticeModel? result) {
      // 다이얼로그가 닫히고 넘어온 결과값이 있다면 화면을 갱신합니다.
      if (result != null) {
        setState(() {
          if (notice == null) {
            // 새로 등록한 경우 (리스트에 추가)
            noticeList.add(result);
          } else {
            // 기존 내용을 수정한 경우 (해당 ID를 찾아 교체)
            int index = noticeList.indexWhere((element) => element.id == result.id);
            if (index != -1) {
              noticeList[index] = result;
            }
          }
          _sortNotices(); // 변경 후 재정렬
        });
      }
    });
  }

  /// ---------------------------------------------------------------------------
  /// [3] 공지사항 삭제 처리 함수 (확인 창 포함)
  /// ---------------------------------------------------------------------------
  void _deleteNotice(String noticeId) {
    showDialog(
      context: context,
      builder: (BuildContext confirmContext) {
        // [수정점] Theme.of(context).brightness 값을 bool 타입인 isDarkMode로 변환합니다.
        final bool isDarkMode = Theme.of(confirmContext).brightness == Brightness.dark;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
          title: AppTheme.dialogTitle("공지사항 삭제", Icons.warning_amber_rounded, color: AppTheme.danger),
          content: Text("이 공지사항을 정말로 삭제하시겠습니까?", style: AppTheme.itemValueStyle(confirmContext)),
          actions: [
            TextButton(
              // [수정점] AppTheme.labelColor에 bool 값(isDarkMode)을 정상적으로 넘겨줍니다.
              child: Text("취소", style: TextStyle(color: AppTheme.labelColor(isDarkMode))),
              onPressed: () => Navigator.pop(confirmContext),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: () {
                // 삭제 확인 시 리스트에서 제거하고 화면을 갱신합니다.
                setState(() {
                  noticeList.removeWhere((element) => element.id == noticeId);
                });
                Navigator.pop(confirmContext); // 다이얼로그 닫기
              },
              child: const Text("삭제", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// ---------------------------------------------------------------------------
  /// [메인 화면 (리스트) UI 구성]
  /// ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          '공지사항',
          style: TextStyle(
            fontFamily: AppTheme.fontPretendard,
            fontWeight: AppTheme.weightMenu,
            letterSpacing: -0.8,
            color: AppTheme.dataColor(isDarkMode),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          // 우측 상단 '새 공지 등록' 버튼 (클릭 시 팝업 띄움)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: AppTheme.actionButton(
              label: '새 공지 등록',
              icon: Icons.add_circle_outline,
              color: theme.colorScheme.primary,
              onPressed: () => _showEditDialog(), // 파라미터 없이 호출하면 '등록 모드'
            ),
          ),
        ],
      ),
      body: noticeList.isEmpty
          ? Center(
        child: Text(
          '등록된 공지사항이 없습니다.',
          style: TextStyle(
            fontFamily: AppTheme.fontPretendard,
            fontWeight: AppTheme.weightOthers,
            fontSize: 18,
            color: AppTheme.labelColor(isDarkMode),
          ),
        ),
      )
          : ListView.builder(
        padding: EdgeInsets.all(widget.isMobile ? 12.0 : 24.0),
        itemCount: noticeList.length,
        itemBuilder: (BuildContext context, int index) {
          final NoticeModel notice = noticeList[index];
          return _buildNoticeItem(context, notice, theme, isDarkMode);
        },
      ),
    );
  }

  /// 목록에 들어갈 각각의 항목(Card)을 만들어주는 함수입니다.
  Widget _buildNoticeItem(BuildContext context, NoticeModel notice, ThemeData theme, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Card(
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          // 항목 터치 시 상세 보기 팝업을 띄웁니다.
          onTap: () => _showDetailDialog(notice),
          child: Padding(
            padding: EdgeInsets.all(widget.isMobile ? 16.0 : 24.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  notice.isImportant ? Icons.campaign : Icons.article_outlined,
                  color: notice.isImportant ? AppTheme.danger : AppTheme.labelColor(isDarkMode),
                  size: widget.isMobile ? 28 : 36,
                ),
                SizedBox(width: widget.isMobile ? 12 : 20),
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
              ],
            ),
          ),
        ),
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
      // PC/태블릿에서는 다이얼로그의 최대 너비를 제한하여 가독성을 높입니다.
      insetPadding: EdgeInsets.all(isMobile ? 16.0 : 40.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 800, maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          children: [
            // 다이얼로그 상단 헤더 (제목 및 닫기, 수정, 삭제 버튼)
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
                    onPressed: () => Navigator.pop(context), // 창 닫기
                  ),
                ],
              ),
            ),
            Divider(color: theme.dividerTheme.color, height: 1),

            // 다이얼로그 본문 내용 (스크롤 가능)
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
  final NoticeModel? notice; // 데이터가 있으면 '수정', 없으면 '등록'
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
    // 수정 모드일 경우 기존 데이터로 컨트롤러 초기화
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

  /// 폼을 검증하고 데이터를 반환하며 창을 닫습니다.
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
      Navigator.pop(context, newNotice); // 부모 위젯으로 결과 전송
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
            // 다이얼로그 상단 헤더
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
                    onPressed: () => Navigator.pop(context), // 취소하고 닫기
                  ),
                ],
              ),
            ),
            Divider(color: theme.dividerTheme.color, height: 1),

            // 다이얼로그 입력 폼 영역 (스크롤 가능)
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
                        maxLines: 12, // 넓은 본문 영역
                        decoration: AppTheme.inputDecoration(label: '공지사항 본문 내용', context: context).copyWith(alignLabelWithHint: true),
                        validator: (value) => (value == null || value.trim().isEmpty) ? '본문 내용을 입력해주세요.' : null,
                      ),
                      const SizedBox(height: 24),

                      Container(
                        // [수정점] context 매개변수를 위치(Positional) 매개변수로 처리합니다.
                        // [수정점] 존재하지 않는 cardTheme.side 대신 dividerTheme.color를 사용합니다.
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
                          // [수정점] 사용 중단된(Deprecated) activeColor 대신, 최신 권장 사항인 Thumb과 Track 색상으로 나눠 지정합니다.
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

            // 하단 버튼 영역
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