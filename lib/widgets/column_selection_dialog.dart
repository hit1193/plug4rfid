import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// ---------------------------------------------------------------------------
/// [공용 표시 항목 설정 다이얼로그]
/// C++Builder의 공통 TFrame처럼, 여러 페이지(인원 관리, 물품 관리 등)에서
/// 동일한 스타일과 로직으로 표시 항목을 설정할 수 있도록 분리한 독립 컴포넌트입니다.
/// ---------------------------------------------------------------------------
class ColumnSelectionDialog extends StatefulWidget {
  final String title;                    // 다이얼로그 제목
  final List<String> baseFields;         // 기본 고정 항목 리스트
  final List<String> metaFields;         // 동적으로 수집된 추가 확장 항목 리스트
  final List<String> initialSelection;   // 다이얼로그가 열릴 때 처음 선택되어 있을 항목들
  final Future<void> Function(List<String>) onSave; // 저장 버튼을 눌렀을 때 실행될 콜백 함수

  const ColumnSelectionDialog({
    super.key,
    this.title = "표시 항목 설정",
    this.baseFields = const [],
    this.metaFields = const [],
    required this.initialSelection,
    required this.onSave,
  });

  @override
  State<ColumnSelectionDialog> createState() => _ColumnSelectionDialogState();
}

class _ColumnSelectionDialogState extends State<ColumnSelectionDialog> {
  // 현재 사용자가 체크/해제한 상태를 임시로 들고 있는 리스트
  late List<String> _tempSelection;

  @override
  void initState() {
    super.initState();
    // 처음 열렸을 때 부모로부터 전달받은 설정값을 복사하여 임시 상태로 만듭니다.
    _tempSelection = List.from(widget.initialSelection);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return AlertDialog(
      title: AppTheme.dialogTitle(widget.title, Icons.view_column_rounded),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // 1. 기본 제원 정보 렌더링
              if (widget.baseFields.isNotEmpty) ...[
                _buildColumnGroupHeader("기본 제원 정보"),
                const SizedBox(height: 12),
                ...widget.baseFields.map((String key) => _buildSelectionListItem(key, theme)),
                const SizedBox(height: 32),
              ],

              // 2. 추가 확장 정보 렌더링
              _buildColumnGroupHeader("추가 확장 정보"),
              const SizedBox(height: 12),
              if (widget.metaFields.isEmpty)
                const Text("추가된 메타데이터가 없습니다.", style: TextStyle(fontFamily: AppTheme.fontPretendard))
              else
                ...widget.metaFields.map((String key) => _buildSelectionListItem(key, theme)),
            ],
          ),
        ),
      ),
      actions: [
        // 취소 버튼
        AppTheme.actionButton(
          label: "취소",
          color: Colors.transparent,
          textColor: cancelColor,
          onPressed: () => Navigator.pop(context),
        ),
        // 설정 적용 버튼
        AppTheme.actionButton(
          label: "설정 적용",
          onPressed: () async {
            // 부모 페이지에서 전달한 저장 비즈니스 로직(Provider 통신 등)을 실행합니다.
            await widget.onSave(_tempSelection);

            // 작업이 완료되고 다이얼로그가 아직 떠 있다면 닫아줍니다.
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
        ),
      ],
    );
  }

  /// 섹션 타이틀 (예: 기본 제원 정보, 추가 확장 정보)을 그리는 헬퍼 함수
  Widget _buildColumnGroupHeader(String title) {
    return Row(
      children: [
        Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
                color: Colors.blueGrey,
                borderRadius: BorderRadius.circular(2)
            )
        ),
        const SizedBox(width: 10),
        Text(
            title,
            style: const TextStyle(
                fontFamily: AppTheme.fontPretendard,
                fontWeight: FontWeight.w900,
                color: Colors.blueGrey,
                fontSize: 14,
                letterSpacing: -0.5
            )
        )
      ],
    );
  }

  /// 개별 체크박스(원형 토글) 아이템을 그리는 헬퍼 함수
  Widget _buildSelectionListItem(String label, ThemeData theme) {
    final bool isSelected = _tempSelection.contains(label);
    final bool isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              // 화면에서 표시할 항목은 최소 1개는 유지해야 함
              if (_tempSelection.length > 1) {
                _tempSelection.remove(label);
              }
            } else {
              // 화면 레이아웃 보호를 위해 최대 5개까지만 선택 가능
              if (_tempSelection.length < 5) {
                _tempSelection.add(label);
              }
            }
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.05) : theme.cardTheme.color,
            borderRadius: BorderRadius.circular(8),
            // 다크모드 시 미선택 항목의 테두리가 묻히지 않도록 반투명 흰색 적용
            border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : (isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.15)),
                width: isSelected ? 2.5 : 1.0
            ),
          ),
          child: Row(
            children: [
              // 다크모드 시 미선택 원형 토글 색상 밝게 조절
              Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  size: 20,
                  color: isSelected ? theme.colorScheme.primary : (isDark ? Colors.white54 : Colors.black26)
              ),
              const SizedBox(width: 16),
              // 텍스트 역시 다크모드일 때 잘 보이도록 조절
              Expanded(
                  child: Text(
                      label,
                      style: TextStyle(
                          fontFamily: AppTheme.fontPretendard,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? theme.colorScheme.primary : (isDark ? Colors.white70 : Colors.black45)
                      )
                  )
              )
            ],
          ),
        ),
      ),
    );
  }
}