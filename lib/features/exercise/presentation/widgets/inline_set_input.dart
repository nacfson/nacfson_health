import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/numeric_stepper_field.dart';
import '../../../settings/presentation/providers/exercise_template_provider.dart';
import '../../domain/body_part_rest_defaults.dart';
import '../../domain/entities/exercise_record.dart';
import '../../domain/entities/routine_item.dart';
import '../providers/exercise_provider.dart';
import '../providers/rest_timer_provider.dart';
import '../providers/routine_planner_provider.dart';

/// 카드 하단에 인라인으로 펼쳐지는 1행 세트 입력기.
/// - `add` 모드: 직전 세트 값을 프리필하고 ✓ 저장 시 같은 운동의 다음 세트로 누적.
/// - `edit` 모드: 기존 세트(uuid) 값을 프리필하고 ✓ 저장 시 in-place 업데이트.
class InlineSetInput extends ConsumerStatefulWidget {
  final String exerciseType;
  final String exerciseName;
  final ExerciseRecord? editing;
  final VoidCallback onClose;

  const InlineSetInput({
    super.key,
    required this.exerciseType,
    required this.exerciseName,
    required this.onClose,
    this.editing,
  });

  @override
  ConsumerState<InlineSetInput> createState() => _InlineSetInputState();
}

class _InlineSetInputState extends ConsumerState<InlineSetInput> {
  late final TextEditingController _weightCtl;
  late final TextEditingController _repsCtl;
  late final TextEditingController _rpeCtl;
  final FocusNode _weightFocus = FocusNode();
  final FocusNode _repsFocus = FocusNode();
  final FocusNode _rpeFocus = FocusNode();
  bool _saving = false;
  late SetType _selectedType;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final r = widget.editing;
    if (r != null) {
      _weightCtl = TextEditingController(text: _fmtNum(r.weight));
      _repsCtl = TextEditingController(text: r.reps.toString());
      _rpeCtl = TextEditingController(text: _fmtNum(r.rpe));
      _selectedType = r.setType;
    } else {
      final last = ref.read(latestSetOfTodayProvider(widget.exerciseName));
      _weightCtl =
          TextEditingController(text: last == null ? '' : _fmtNum(last.weight));
      _repsCtl =
          TextEditingController(text: last == null ? '' : last.reps.toString());
      _rpeCtl = TextEditingController(text: last == null ? '' : _fmtNum(last.rpe));
      // 신규 입력 기본값은 항상 본세트(work).
      _selectedType = SetType.work;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _weightFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _weightCtl.dispose();
    _repsCtl.dispose();
    _rpeCtl.dispose();
    _weightFocus.dispose();
    _repsFocus.dispose();
    _rpeFocus.dispose();
    super.dispose();
  }

  String _fmtNum(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();

  Future<void> _submit() async {
    if (_saving) return;
    final weightRaw = _weightCtl.text.trim();
    final repsRaw = _repsCtl.text.trim();
    final rpeRaw = _rpeCtl.text.trim();
    final weight = double.tryParse(weightRaw);
    final reps = int.tryParse(repsRaw);
    final rpe = double.tryParse(rpeRaw);
    if (weight == null || weight <= 0 || reps == null || reps < 1) {
      final issue = (weight == null || weight <= 0)
          ? '중량은 0보다 큰 값이어야 합니다 (입력: ${weightRaw.isEmpty ? "없음" : weightRaw})'
          : '반복은 1회 이상이어야 합니다 (입력: ${repsRaw.isEmpty ? "없음" : repsRaw})';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(issue),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (rpe == null || rpe < 1 || rpe > 10) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'RPE는 1~10 사이 값입니다 (입력: ${rpeRaw.isEmpty ? "없음" : rpeRaw})',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final notifier = ref.read(exerciseRecordsProvider.notifier);
      if (_isEdit) {
        final updated = widget.editing!.copyWith(
          weight: weight,
          reps: reps,
          rpe: rpe,
          setType: _selectedType,
        );
        await notifier.updateRecord(updated);
        if (mounted) widget.onClose();
      } else {
        await notifier.addSetAutoNumber(
          exerciseType: widget.exerciseType,
          exerciseName: widget.exerciseName,
          weight: weight,
          reps: reps,
          rpe: rpe,
          setType: _selectedType,
        );
        // 루틴 = 오늘 카드 컨테이너. 세트 기록 시 같은 이름이 루틴에 없으면 자동 편입.
        // addItem 내부에서 중복 이름은 무시되므로 항상 호출해도 안전.
        await ref.read(routinePlannerProvider.notifier).addItem(
              RoutineItem(
                exerciseType: widget.exerciseType,
                exerciseName: widget.exerciseName,
              ),
            );
        // 휴식 타이머 자동 시작.
        // 종목 템플릿의 override > 부위 기본값 > "기타" 폴백 순서로 해석.
        // 유산소는 `null` 을 돌려주므로 타이머 시작 자체를 건너뛴다.
        final matches = ref
            .read(exerciseTemplatesProvider)
            .where((t) => t.name == widget.exerciseName)
            .toList();
        final matched = matches.isEmpty ? null : matches.first;
        final int? restSec = matched != null
            ? resolveRestSeconds(matched)
            // 템플릿이 없는 즉흥 종목: 운동 유형 문자열만으로 부위 기본값 해석.
            : defaultRestForBodyPart(widget.exerciseType);
        if (restSec != null) {
          ref
              .read(restTimerProvider.notifier)
              .start(restSec, exerciseName: widget.exerciseName);
        }
        // 연속 입력: 필드 유지 + 중량 포커스 복귀
        // 연속 입력 시 타입은 직전 선택을 유지(웜업 3개 연속 입력 패턴 지원).
        if (mounted) {
          FocusScope.of(context).requestFocus(_weightFocus);
          _weightCtl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _weightCtl.text.length,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Row(
        children: [
          _SetTypeSelector(
            value: _selectedType,
            onChanged: (t) => setState(() => _selectedType = t),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: NumericStepperField(
              controller: _weightCtl,
              focusNode: _weightFocus,
              label: 'kg',
              step: 0.5,
              min: 0,
              onSubmitted: (_) => _repsFocus.requestFocus(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: NumericStepperField(
              controller: _repsCtl,
              focusNode: _repsFocus,
              label: '회',
              integer: true,
              step: 1.0,
              min: 0,
              onSubmitted: (_) => _rpeFocus.requestFocus(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: NumericStepperField(
              controller: _rpeCtl,
              focusNode: _rpeFocus,
              label: 'RPE',
              step: 0.5,
              min: 1,
              max: 10,
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.done,
            ),
          ),
          IconButton(
            tooltip: _isEdit ? '수정 저장' : '세트 저장',
            iconSize: 22,
            color: cs.primary,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle),
            onPressed: _saving ? null : _submit,
          ),
          IconButton(
            tooltip: '닫기',
            iconSize: 20,
            color: cs.onSurfaceVariant,
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : widget.onClose,
          ),
        ],
      ),
    );
  }
}

/// 세트 타입 드롭다운 — 웜업/본세트/드롭세트/실패 4가지를 한 글자로 표시.
class _SetTypeSelector extends StatelessWidget {
  final SetType value;
  final ValueChanged<SetType> onChanged;

  const _SetTypeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 52),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SetType>(
          value: value,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, size: 18, color: cs.onSurfaceVariant),
          items: const [
            DropdownMenuItem(
              value: SetType.warmup,
              child: Text('웜', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: SetType.work,
              child: Text('본', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: SetType.drop,
              child: Text('드', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: SetType.failure,
              child: Text('실', style: TextStyle(fontSize: 13)),
            ),
          ],
          onChanged: (t) {
            if (t != null) onChanged(t);
          },
        ),
      ),
    );
  }
}

