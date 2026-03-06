import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// ---------------------------------------------------------------------------
/// [일괄 편집 필드 타입 정의]
/// 텍스트 입력, 드롭다운 선택, 스위치 토글 등 다양한 UI 요소에 대응합니다.
/// ---------------------------------------------------------------------------
enum BulkEditFieldType { text, dropdown, toggle }

/// ---------------------------------------------------------------------------
/// [일괄 편집 필드 구성 객체]
/// 어떤 항목을 일괄 편집창에 띄울 것인지 부모 폼(페이지)에서 정의하여 넘겨줍니다.
/// ---------------------------------------------------------------------------
class BulkEditField {
  final String key;               // 데이터베이스나 모델에 저장될 실제 필드명 (예: 'department', '비고')
  final String label;             // 화면에 보여질 안내 텍스트
  final BulkEditFieldType type;   // 입력 필드의 형태 (텍스트, 토글 등)
  final List<String>? options;    // 드롭다운일 경우 선택지 목록
  final dynamic initialValue;     // 스위치나 드롭다운의 초기값

  BulkEditField({
    required this.key,
    required this.label,
    this.type = BulkEditFieldType.text,
    this.options,
    this.initialValue,
  });
}

/// ---------------------------------------------------------------------------
/// [공용 일괄 편집 다이얼로그 (TFrame 역할)]
/// 인원 관리, 물품 관리 등 모든 화면에서 공통으로 사용할 수 있는 일괄 편집창입니다.
/// 동적으로 전달받은 필드 목록을 기반으로 입력 폼을 자동 생성하며,
/// 사용자가 '선택(체크)'한 항목들의 결과값만 Map 형태로 반환합니다.
/// ---------------------------------------------------------------------------
class BulkEditDialog extends StatefulWidget {
  final String title;                 // 다이얼로그 제목 (예: '10명 인원 일괄 편집')
  final List<BulkEditField> fields;   // 부모가 전달한 편집 가능한 필드 목록 (기본+추가항목 모두 포함)

  const BulkEditDialog({
    super.key,
    required this.title,
    required this.fields,
  });

  @override
  State<BulkEditDialog> createState() => _BulkEditDialogState();
}

class _BulkEditDialogState extends State<BulkEditDialog> {
  // 사용자가 해당 필드를 일괄 편집할지(체크박스 활성화 여부) 관리하는 상태
  final Map<String, bool> _activeStates = {};

  // 텍스트 입력을 위한 컨트롤러 모음
  final Map<String, TextEditingController> _textControllers = {};

  // 드롭다운 및 토글 스위치의 현재 값을 저장하는 모음
  final Map<String, dynamic> _dynamicValues = {};

  @override
  void initState() {
    super.initState();
    // 부모로부터 전달받은 필드들을 순회하며 컨트롤러와 초기 상태를 세팅합니다.
    for (var field in widget.fields) {
      _activeStates[field.key] = false; // 기본적으로 모두 체크 해제 상태

      if (field.type == BulkEditFieldType.text) {
        _textControllers[field.key] = TextEditingController(
          text: field.initialValue?.toString() ?? "",
        );
      } else if (field.type == BulkEditFieldType.dropdown || field.type == BulkEditFieldType.toggle) {
        _dynamicValues[field.key] = field.initialValue;
      }
    }
  }

  @override
  void dispose() {
    // 메모리 누수를 방지하기 위해 텍스트 컨트롤러들을 모두 해제합니다.
    for (var controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color cancelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return AlertDialog(
      title: AppTheme.dialogTitle(widget.title, Icons.edit_note, color: AppTheme.primary),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 안내 메시지
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8)
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "체크된 항목(동그라미 활성화)만 일괄 변경됩니다.\n선택되지 않은 필드는 각 데이터의 기존 값이 그대로 유지됩니다.",
                        style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 13, color: AppTheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 부모가 넘겨준 필드 설정에 따라 입력 위젯들을 동적으로 렌더링합니다.
              ...widget.fields.map((field) {
                final bool isActive = _activeStates[field.key] ?? false;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: _buildBulkEditRow(
                    isActive: isActive,
                    onChanged: (bool? val) {
                      setState(() {
                        _activeStates[field.key] = val ?? false;
                      });
                    },
                    fieldWidget: _buildInputWidget(field, isActive, theme),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        AppTheme.actionButton(
          label: "취소",
          color: Colors.transparent,
          textColor: cancelColor,
          onPressed: () => Navigator.pop(context, null), // 취소 시 null 반환
        ),
        AppTheme.actionButton(
          label: "일괄 적용 실행",
          color: AppTheme.primary,
          onPressed: () {
            // 사용자가 하나라도 활성화(체크)했는지 검사
            if (!_activeStates.values.any((isActive) => isActive)) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("변경할 항목을 최소 1개 이상 체크해주세요.", style: TextStyle(fontFamily: AppTheme.fontPretendard)))
              );
              return;
            }

            // 체크된 항목들의 결과값만 모아서 맵(Map)으로 구성합니다.
            final Map<String, dynamic> result = {};
            for (var field in widget.fields) {
              if (_activeStates[field.key] == true) {
                if (field.type == BulkEditFieldType.text) {
                  result[field.key] = _textControllers[field.key]?.text.trim() ?? "";
                } else {
                  result[field.key] = _dynamicValues[field.key];
                }
              }
            }

            // 부모 폼으로 최종 결과값을 전달하며 다이얼로그를 닫습니다.
            Navigator.pop(context, result);
          },
        ),
      ],
    );
  }

  /// [키오스크 스타일 원형 토글 + 입력 필드 배치]
  Widget _buildBulkEditRow({required bool isActive, required void Function(bool?) onChanged, required Widget fieldWidget}) {
    return Row(
      children: [
        InkWell(
          onTap: () => onChanged(!isActive),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? AppTheme.primary : Colors.transparent,
                border: Border.all(
                  color: isActive ? AppTheme.primary : Colors.grey.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Icon(
                  Icons.check,
                  size: 16,
                  color: isActive ? Colors.white : Colors.transparent,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: fieldWidget),
      ],
    );
  }

  /// [타입별 입력 위젯 생성기]
  Widget _buildInputWidget(BulkEditField field, bool isActive, ThemeData theme) {
    final bool isDark = theme.brightness == Brightness.dark;
    final Color disableBorderColor = theme.dividerTheme.color ?? Colors.grey.withValues(alpha: 0.3);
    final Color activeBorderColor = AppTheme.primary;

    if (field.type == BulkEditFieldType.text) {
      return TextField(
        controller: _textControllers[field.key],
        enabled: isActive,
        style: TextStyle(
          fontFamily: AppTheme.fontPretendard,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isActive ? AppTheme.dataColor(isDark) : Colors.grey,
        ),
        decoration: AppTheme.inputDecoration(label: field.label, context: context).copyWith(
          disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: disableBorderColor, width: 1.0)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isActive ? activeBorderColor : Colors.grey, width: isActive ? 2.0 : 1.0)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: activeBorderColor, width: 2.5)),
        ),
      );
    } else if (field.type == BulkEditFieldType.dropdown) {
      return DropdownButtonFormField<String>(
        // [수정됨] 최신 Flutter 권장사항에 따라 value 대신 initialValue를 사용합니다.
        initialValue: _dynamicValues[field.key],
        decoration: AppTheme.inputDecoration(label: field.label, context: context).copyWith(
          disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: disableBorderColor, width: 1.0)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isActive ? activeBorderColor : Colors.grey, width: isActive ? 2.0 : 1.0)),
        ),
        items: (field.options ?? []).map((String e) {
          return DropdownMenuItem<String>(
              value: e, // DropdownMenuItem의 value 속성은 정상 유지
              child: Text(e, style: TextStyle(fontFamily: AppTheme.fontPretendard, fontWeight: FontWeight.bold, color: isActive ? null : Colors.grey))
          );
        }).toList(),
        onChanged: isActive ? (String? v) {
          if (v != null) setState(() => _dynamicValues[field.key] = v);
        } : null,
      );
    } else if (field.type == BulkEditFieldType.toggle) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: isActive ? activeBorderColor : disableBorderColor, width: isActive ? 2.0 : 1.0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(
                field.label,
                style: TextStyle(fontFamily: AppTheme.fontPretendard, fontSize: 16, fontWeight: FontWeight.w600, color: isActive ? AppTheme.dataColor(isDark) : Colors.grey)
            ),
            const Spacer(),
            Switch(
              value: _dynamicValues[field.key] ?? true,
              activeThumbColor: AppTheme.success,
              activeTrackColor: AppTheme.success.withValues(alpha: 0.5),
              onChanged: isActive ? (bool v) {
                setState(() => _dynamicValues[field.key] = v);
              } : null,
            ),
          ],
        ),
      );
    }
    return const SizedBox();
  }
}