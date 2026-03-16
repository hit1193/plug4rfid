import 'package:flutter/material.dart';
import 'dart:typed_data'; // 파일(이미지) 데이터를 바이트 형태로 다루기 위해 필요합니다.

// 파일 선택기 및 HTTP 파일 업로드를 위한 패키지
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../models/notice_model.dart';
import '../theme/app_theme.dart';
import '../core/pocketbase_client.dart';
import '../core/erp_sync_helper.dart'; // [공용 모듈] 중앙 집중식 ERP 연동 헬퍼

/// ---------------------------------------------------------------------------
/// [데이터 전송용 DTO 클래스]
/// 다이얼로그에서 입력한 텍스트 데이터(NoticeModel)와
/// 선택한 이미지 파일(bytes, name)을 한 번에 묶어서 부모 창으로 전달하기 위한 캡슐입니다.
/// ---------------------------------------------------------------------------
class NoticeEditResult {
  final NoticeModel model;
  final Uint8List? imageBytes;
  final String? imageName;

  NoticeEditResult({
    required this.model,
    this.imageBytes,
    this.imageName,
  });
}

/// ---------------------------------------------------------------------------
/// [공지사항 통합 관리 페이지]
/// 중복되는 타이틀 렌더링 부분을 제거하고 액션 버튼들만 콤팩트하게 배치했습니다.
/// ---------------------------------------------------------------------------
class NoticePage extends StatefulWidget {
  final bool isMobile;
  final String baseUrl;

  const NoticePage({
    super.key,
    required this.isMobile,
    required this.baseUrl,
  });

  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage> {
  List<NoticeModel> noticeList = [];

  final Set<String> _selectedNoticeIds = {};
  bool _isSelectionMode = false;
  bool _isLoading = false;

  // 키오스크(포스터) 모드 활성화 여부를 관리하는 상태 변수입니다.
  bool _isKioskMode = false;

  @override
  void initState() {
    super.initState();
    _fetchNotices();
  }

  /// DB에서 공지사항 목록을 가져옵니다.
  Future<void> _fetchNotices() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final records = await pb.collection('notices').getFullList(sort: '-created');
      if (mounted) {
        setState(() {
          noticeList = records.map((r) => NoticeModel.fromRecord(r)).toList();
          _sortNotices();
        });
      }
    } catch (e) {
      debugPrint("공지사항 로드 실패: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 중요 공지를 최상단에, 나머지는 최신순으로 정렬합니다.
  void _sortNotices() {
    noticeList.sort((NoticeModel a, NoticeModel b) {
      if (a.isImportant && !b.isImportant) {
        return -1;
      }
      if (!a.isImportant && b.isImportant) {
        return 1;
      }
      return b.created.compareTo(a.created);
    });
  }

  /// 상세 보기 팝업을 띄웁니다.
  void _showDetailDialog(NoticeModel notice) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return _NoticeDetailDialog(
          notice: notice,
          isMobile: widget.isMobile,
          baseUrl: widget.baseUrl,
          onEdit: () {
            Navigator.pop(dialogContext);
            _showEditDialog(notice: notice);
          },
          onDelete: () {
            Navigator.pop(dialogContext);
            _deleteNotice(notice.id);
          },
        );
      },
    );
  }

  /// ---------------------------------------------------------------------------
  /// [공용 모듈 호출] 거래처 ERP 연동
  /// DataModule 철학이 적용된 ErpSyncHelper 를 호출합니다.
  /// ---------------------------------------------------------------------------
  void _triggerErpSync(ThemeData theme) {
    ErpSyncHelper.fetchAndSync(
      context: context,
      theme: theme,
      moduleName: "공지사항",
      endpoint: 'posts?_limit=3',
      targetCollection: 'notices', // 저장할 DB 테이블명

      // [핵심] 수신된 ERP의 JSON 데이터를 어떻게 파싱할지 규칙만 전달합니다.
      dataMapper: (Map<String, dynamic> erpItem) {
        return {
          'title': '[ERP 연동] ${erpItem['title']}',
          'content': erpItem['body'],
          'author': 'ERP 시스템 (자동화)',
          'is_important': false,
          'view_count': 0,
          'attachments': '',
        };
      },

      // 상태 관리(로딩창 제어 및 목록 새로고침)를 콜백으로 전달합니다.
      onLoadingStart: () {
        if (mounted) setState(() { _isLoading = true; });
      },
      onLoadingComplete: () {
        if (mounted) setState(() { _isLoading = false; });
      },
      onSuccess: () {
        _fetchNotices(); // 성공 시 공지사항 목록 새로고침
      },
    );
  }

  /// ---------------------------------------------------------------------------
  /// [등록/수정] 이미지 파일(attachments) Multipart Upload 로직 포함
  /// ---------------------------------------------------------------------------
  void _showEditDialog({NoticeModel? notice}) {
    showDialog<NoticeEditResult>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _NoticeEditDialog(
          notice: notice,
          isMobile: widget.isMobile,
          baseUrl: widget.baseUrl,
        );
      },
    ).then((NoticeEditResult? result) async {
      if (result != null) {
        if (!mounted) return;
        setState(() {
          _isLoading = true;
        });

        try {
          final Map<String, dynamic> bodyData = result.model.toJson();

          List<http.MultipartFile> files = [];
          if (result.imageBytes != null && result.imageName != null) {
            files.add(http.MultipartFile.fromBytes(
              'attachments',
              result.imageBytes!,
              filename: result.imageName,
            ));
          }

          if (notice == null) {
            await pb.collection('notices').create(body: bodyData, files: files);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('✅ 새 공지사항이 성공적으로 등록되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
                elevation: 0,
              ));
            }
          } else {
            await pb.collection('notices').update(notice.id, body: bodyData, files: files);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('✅ 공지사항이 성공적으로 수정되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
                elevation: 0,
              ));
            }
          }
          await _fetchNotices();

        } catch (e, stackTrace) {
          debugPrint('\n=============================================================');
          debugPrint('🚨 [공지사항 저장/수정 실패] 🚨');
          debugPrint('오류 내용: $e');
          debugPrint('발생 위치(Stack Trace):\n$stackTrace');
          debugPrint('=============================================================\n');

          String userFriendlyMessage = '알 수 없는 오류가 발생했습니다.';
          final errorString = e.toString();

          if (errorString.contains('validation_missing_rel_records') && errorString.contains('author')) {
            userFriendlyMessage = 'DB 구조 오류: 포켓베이스 관리자 화면에서 "author" 필드를 Relation이 아닌 "Text" 타입으로 변경해 주세요!';
          } else if (errorString.contains('attachments')) {
            userFriendlyMessage = 'DB 구조 오류: 데이터베이스에 "attachments" 파일 필드가 정상적으로 존재하는지 확인해 주세요!';
          } else {
            userFriendlyMessage = '저장 실패: $errorString';
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('❌ $userFriendlyMessage', style: const TextStyle(fontFamily: AppTheme.fontPretendard, color: Colors.white, fontWeight: FontWeight.bold, height: 1.4)),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 7),
              behavior: SnackBarBehavior.floating,
            ));
          }
        } finally {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      }
    });
  }

  /// 단일 삭제
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
              onPressed: () async {
                Navigator.pop(confirmContext);

                if (!mounted) return;
                setState(() {
                  _isLoading = true;
                });

                try {
                  await pb.collection('notices').delete(noticeId);

                  if (mounted) {
                    setState(() {
                      _selectedNoticeIds.remove(noticeId);
                    });
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('공지사항이 안전하게 삭제되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
                      elevation: 0,
                    ));
                  }
                  await _fetchNotices();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
                  }
                } finally {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                }
              },
              child: const Text("삭제", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// 일괄 삭제
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
                    onPressed: () async {
                      Navigator.pop(ctx);

                      if (!mounted) return;
                      setState(() {
                        _isLoading = true;
                      });

                      try {
                        for (String id in _selectedNoticeIds) {
                          await pb.collection('notices').delete(id);
                        }

                        if (mounted) {
                          setState(() {
                            _selectedNoticeIds.clear();
                            _isSelectionMode = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text("선택한 공지사항이 일괄 삭제되었습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard)),
                              elevation: 0
                          ));
                        }
                        await _fetchNotices();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('일괄 삭제 실패: $e')));
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isLoading = false;
                          });
                        }
                      }
                    }
                )
              ]
          );
        }
    );
  }

  /// 전체 초기화
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
                    onPressed: () async {
                      Navigator.pop(ctx);

                      if (!mounted) return;
                      setState(() {
                        _isLoading = true;
                      });

                      try {
                        for (var notice in noticeList) {
                          await pb.collection('notices').delete(notice.id);
                        }

                        if (mounted) {
                          setState(() {
                            _selectedNoticeIds.clear();
                            _isSelectionMode = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('모든 공지사항이 초기화 되었습니다.', style: TextStyle(fontFamily: AppTheme.fontPretendard)),
                              elevation: 0
                          ));
                        }
                        await _fetchNotices();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('초기화 실패: $e')));
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isLoading = false;
                          });
                        }
                      }
                    }
                )
              ]
          );
        }
    );
  }

  /// ---------------------------------------------------------------------------
  /// [메인 화면 UI 구성]
  /// 키오스크 모드(_isKioskMode) 활성화 시 전체 화면 포스터 UI로 전환됩니다.
  /// ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDarkMode = theme.brightness == Brightness.dark;

    // 미니멀리즘 디자인 철학 반영: 키오스크 모드일 때는 군더더기 없이 단 한 장의 포스터만 띄웁니다.
    if (_isKioskMode) {
      return _buildKioskDisplayMode(theme);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔥 [업데이트] 중복된 타이틀을 삭제하고 액션 컨트롤 버튼들만 깔끔하게 남겼습니다.
              _buildTopControlPanel(theme, isDarkMode),
              Expanded(
                child: _buildListView(theme, isDarkMode),
              ),
            ],
          ),

          if (_isLoading) _buildGlobalLoadingOverlay(theme),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------------------
  /// [UI 조각] 키오스크 전용 디스플레이 모드 (포스터 배경 전체화면)
  /// ---------------------------------------------------------------------------
  Widget _buildKioskDisplayMode(ThemeData theme) {
    if (noticeList.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 80, color: Colors.white54),
              const SizedBox(height: 24),
              const Text(
                '등록된 공지사항이 없습니다.',
                style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 32, color: Colors.white),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text("관리자 모드로 돌아가기"),
                onPressed: () => setState(() => _isKioskMode = false),
              )
            ],
          ),
        ),
      );
    }

    // 통상적으로 대시보드에서는 정렬된 리스트의 가장 '첫 번째' (가장 중요하거나 최신인) 항목을 보여줍니다.
    final NoticeModel latestNotice = noticeList.first;
    final String imageUrl = latestNotice.getImageUrl(widget.baseUrl);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 포스터(배경) 이미지 렌더링
          if (imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.blueGrey.shade900),
            )
          else
            Container(color: Colors.blueGrey.shade900), // 이미지가 없을 때의 기본 배경색

          // 2. 가독성을 위한 어두운 그라데이션 오버레이 (미니멀리즘 & 실용성)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.8), // 상단은 살짝 어둡게 (제목 가독성)
                  Colors.transparent,                  // 중간은 이미지가 잘 보이게
                  Colors.black.withValues(alpha: 0.9), // 하단은 아주 어둡게 (본문 가독성)
                ],
              ),
            ),
          ),

          // 3. 텍스트 컨텐츠 렌더링
          Padding(
            padding: EdgeInsets.all(widget.isMobile ? 32.0 : 80.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 상단: 중요 태그 및 제목
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (latestNotice.isImportant)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.danger,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Text(
                          "❗ 중요 공지",
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: AppTheme.fontPretendard),
                        ),
                      ),
                    Text(
                      latestNotice.title,
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontSize: widget.isMobile ? 40 : 64,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1.5,
                        shadows: const [Shadow(color: Colors.black54, offset: Offset(2, 2), blurRadius: 4)],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),

                // 하단: 본문 내용 요약 및 작성 정보
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      latestNotice.content,
                      style: TextStyle(
                        fontFamily: AppTheme.fontPretendard,
                        fontSize: widget.isMobile ? 20 : 32,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.5,
                        shadows: const [Shadow(color: Colors.black, offset: Offset(1, 1), blurRadius: 3)],
                      ),
                      maxLines: widget.isMobile ? 5 : 8,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 40),
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.white70, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          latestNotice.author,
                          style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 24, color: Colors.white70),
                        ),
                        const SizedBox(width: 32),
                        const Icon(Icons.calendar_month, color: Colors.white70, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          latestNotice.getFormattedDate(),
                          style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 24, color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 4. 관리자 모드로 돌아가기 버튼 (구석에 작게 배치)
          Positioned(
            top: 24,
            right: 24,
            child: IconButton(
              icon: const Icon(Icons.close_fullscreen_rounded, color: Colors.white, size: 36),
              tooltip: "관리자 모드로 돌아가기",
              onPressed: () => setState(() => _isKioskMode = false),
            ),
          ),
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
                  "데이터베이스 통신 중...",
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
  /// [UI 개선] 상단 조작 패널 (불필요한 타이틀 제거, 버튼 우측 정렬)
  /// ---------------------------------------------------------------------------
  Widget _buildTopControlPanel(ThemeData theme, bool isDark) {
    return Container(
      padding: EdgeInsets.all(widget.isMobile ? 16.0 : 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end, // 버튼들을 우측으로 싹 밀어버립니다.
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.desktop_windows_outlined),
            label: const Text("키오스크(현장 디스플레이) 보기", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => setState(() => _isKioskMode = true),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: widget.isMobile ? _buildMobileActionLayout(theme, isDark) : _buildDesktopActionLayout(theme, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopActionLayout(ThemeData theme, bool isDark) {
    return Row(
      children: [
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
                _selectedNoticeIds.clear();
              }
            });
          },
        ),
        const SizedBox(width: 12),

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

        const SizedBox(width: 12),

        // [공통 모듈 호출 버튼] ERP 연동 버튼
        OutlinedButton.icon(
          icon: const Icon(Icons.sync_alt_rounded, size: 18),
          label: const Text(
            "ERP 연동",
            style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightOthers, fontSize: 15),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.teal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            side: BorderSide(color: Colors.teal.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          // 버튼을 누르면 위에서 정의한 공유 모듈 래퍼 함수가 실행됩니다.
          onPressed: () => _triggerErpSync(theme),
        ),

        const Spacer(),

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

  Widget _buildMobileActionLayout(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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

            // [공통 모듈 호출 버튼] 모바일용 ERP 연동 버튼
            OutlinedButton.icon(
              icon: const Icon(Icons.sync_alt_rounded, size: 18),
              label: const Text(
                "ERP 연동",
                style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: AppTheme.weightOthers, fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                side: BorderSide(color: Colors.teal.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _triggerErpSync(theme),
            ),
          ],
        ),
      ],
    );
  }

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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text(
                        '${_selectedNoticeIds.length}건 선택됨',
                        style: const TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: AppTheme.primary)
                    ),
                  ),
                  const SizedBox(width: 12),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text("일괄 삭제", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white, elevation: 0),
                    onPressed: _selectedNoticeIds.isEmpty ? null : () => _confirmBulkDelete(theme),
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
              : const SizedBox.shrink(),
        ),

        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 20.0),
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

  Widget _buildNoticeItem(BuildContext context, NoticeModel notice, ThemeData theme, bool isDarkMode) {
    final bool isSelected = _selectedNoticeIds.contains(notice.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
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

          Expanded(
            child: Card(
              clipBehavior: Clip.hardEdge,
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
                    setState(() {
                      if (isSelected) {
                        _selectedNoticeIds.remove(notice.id);
                      } else {
                        _selectedNoticeIds.add(notice.id);
                      }
                    });
                  } else {
                    _showDetailDialog(notice);
                  }
                },
                child: Padding(
                  padding: EdgeInsets.all(widget.isMobile ? 16.0 : 24.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (notice.attachment.isNotEmpty)
                        Container(
                          width: widget.isMobile ? 50 : 70,
                          height: widget.isMobile ? 50 : 70,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade200,
                            image: DecorationImage(
                              image: NetworkImage(notice.getImageUrl(widget.baseUrl)),
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      else
                        Container(
                          width: widget.isMobile ? 50 : 70,
                          height: widget.isMobile ? 50 : 70,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: isDarkMode ? Colors.white10 : Colors.black12,
                          ),
                          child: Icon(
                            notice.isImportant ? Icons.campaign : Icons.article_outlined,
                            color: notice.isImportant ? AppTheme.danger : AppTheme.labelColor(isDarkMode),
                            size: widget.isMobile ? 28 : 36,
                          ),
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

/// ---------------------------------------------------------------------------
/// [내부 위젯: 공지사항 상세 보기 다이얼로그]
/// ---------------------------------------------------------------------------
class _NoticeDetailDialog extends StatelessWidget {
  final NoticeModel notice;
  final bool isMobile;
  final String baseUrl;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NoticeDetailDialog({
    required this.notice,
    required this.isMobile,
    required this.baseUrl,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDarkMode = theme.brightness == Brightness.dark;
    final String imageUrl = notice.getImageUrl(baseUrl);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
      backgroundColor: theme.scaffoldBackgroundColor,
      insetPadding: EdgeInsets.all(isMobile ? 16.0 : 40.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 800, maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          children: [
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

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 포스터 이미지가 있으면 상단에 크게 렌더링
                    if (imageUrl.isNotEmpty)
                      Container(
                        width: double.infinity,
                        height: isMobile ? 200 : 350,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                          image: DecorationImage(
                            image: NetworkImage(imageUrl),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),

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
  final String baseUrl;

  const _NoticeEditDialog({
    this.notice,
    required this.isMobile,
    required this.baseUrl,
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

  // 사용자가 선택한 파일의 바이너리 데이터와 이름을 보관합니다.
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;

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

  /// 파일 픽커를 호출하여 이미지를 메모리로 읽어옵니다.
  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedImageBytes = result.files.first.bytes;
          _selectedImageName = result.files.first.name;
        });
      }
    } catch (e) {
      debugPrint("이미지 선택 오류: $e");
    }
  }

  void _saveNotice() {
    if (_formKey.currentState!.validate()) {
      final NoticeModel dataModel = NoticeModel(
        id: widget.notice?.id ?? '',
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        author: _authorController.text.trim(),
        isImportant: _isImportant,
        viewCount: widget.notice?.viewCount ?? 0,
        attachment: widget.notice?.attachment ?? '',
        created: widget.notice?.created ?? DateTime.now(),
        updated: widget.notice?.updated ?? DateTime.now(),
      );

      final result = NoticeEditResult(
        model: dataModel,
        imageBytes: _selectedImageBytes,
        imageName: _selectedImageName,
      );

      Navigator.pop(context, result);
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
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text("저장", style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      minimumSize: Size.zero, // 기본 버튼 여백을 없애서 콤팩트하게 만듭니다.
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: _saveNotice,
                  ),
                  const SizedBox(width: 8),
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
                      // [UI] 포스터 이미지 업로드 영역
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white10 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                          border: Border.all(color: theme.dividerTheme.color ?? Colors.grey.shade300, style: BorderStyle.solid),
                        ),
                        child: Column(
                          children: [
                            if (_selectedImageBytes != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(_selectedImageBytes!, height: 150, fit: BoxFit.cover),
                              ),
                              const SizedBox(height: 16),
                            ] else if (widget.notice != null && widget.notice!.attachment.isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(widget.notice!.getImageUrl(widget.baseUrl), height: 150, fit: BoxFit.cover),
                              ),
                              const SizedBox(height: 16),
                            ] else ...[
                              Icon(Icons.image_outlined, size: 48, color: AppTheme.labelColor(isDarkMode).withValues(alpha: 0.5)),
                              const SizedBox(height: 8),
                            ],

                            OutlinedButton.icon(
                              icon: const Icon(Icons.upload_file),
                              label: Text(_selectedImageBytes == null ? "키오스크용 포스터 이미지 첨부" : "다른 이미지로 변경하기"),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _pickImage,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

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
          ],
        ),
      ),
    );
  }
}