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
      if (!mounted) return;
      _weightFocus.requestFocus();
      // 카드가 화면 하단 가까이 있을 때 키보드가 올라오면 입력 행이 가려진다.
      // 부모 CustomScrollView 가 자동으로 입력 행을 화면 중앙으로 끌어오도록 보장.
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
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
    // 2행 레이아웃 — 한 행에 [세트타입][- kg +][- 회 +][- RPE +][✓][✗] 을 모두 욱여넣으면
    // iPhone 13 mini(375pt) 같은 좁은 화면에서 카드 가용 폭(~335)을 넘어 TextField 가
    // 0폭으로 압축되며 ± 버튼들만 인접해 보이는 시각 버그가 발생한다 (v12-3 회귀).
    // 첫 줄: [세트타입]                    [✓ 저장][✗ 닫기]
    // 둘째 줄: [- kg +] [- 회 +] [- RPE +]
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _SetTypeSelector(
                value: _selectedType,
                onChanged: (t) => setState(() => _selectedType = t),
              ),
              const Spacer(),
              IconButton(
                tooltip: _isEdit ? '수정 저장' : '세트 저장',
                iconSize: 22,
                color: cs.primary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                visualDensity: VisualDensity.compact,
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
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                onPressed: _saving ? null : widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 라벨을 필드 바깥 위쪽으로 분리 — Expanded 의 전체 폭을 라벨 영역으로 쓸 수 있어
          // "강도 (RPE)" 같은 긴 라벨도 잘리지 않고, 폰트도 키워 시각성 강화.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 1,
                child: _LabeledField(
                  label: '중량',
                  child: NumericStepperField(
                    controller: _weightCtl,
                    focusNode: _weightFocus,
                    suffix: 'kg',
                    step: 0.5,
                    min: 0,
                    // 중량은 사용자가 직접 타이핑하는 입력이라 ± 버튼이 거의 미사용.
                    showSteppers: false,
                    onSubmitted: (_) => _repsFocus.requestFocus(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _LabeledField(
                  label: '횟수',
                  child: NumericStepperField(
                    controller: _repsCtl,
                    focusNode: _repsFocus,
                    suffix: '회',
                    integer: true,
                    step: 1.0,
                    min: 0,
                    onSubmitted: (_) => _rpeFocus.requestFocus(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _LabeledField(
                  // 1-10 척도는 라벨 자체에 명시 → suffix 없이 입력값 가시성 100%.
                  // ("/10" suffix 가 좁은 필드에서 입력 영역 위에 겹쳐 보여 회귀.)
                  label: '강도 (RPE 1-10)',
                  child: NumericStepperField(
                    controller: _rpeCtl,
                    focusNode: _rpeFocus,
                    step: 0.5,
                    min: 1,
                    max: 10,
                    onSubmitted: (_) => _submit(),
                    textInputAction: TextInputAction.done,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 필드 바깥쪽 위에 작은 라벨을 노출하는 래퍼.
/// `NumericStepperField` 내부 floating label 은 TextField 폭(±버튼 제외)에 맞춰 잘리지만,
/// 외부 Text 라벨은 Expanded 전체 폭을 사용 가능 → 긴 라벨("강도 (RPE)")도 안 잘림.
class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            label,
            // softWrap:false + clip → "강도 (RPE)" 가 폭 부족해도 절대 2줄로 안 떨어짐.
            softWrap: false,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
              height: 1.2,
            ),
          ),
        ),
        // SizedBox 로 자식 높이를 강제하면 InputDecorator 의 intrinsic 레이아웃을 짓눌러
        // hit-test/포커스가 제대로 동작 안 하는 케이스가 있음 (RPE 입력 불가 회귀).
        // 자연 높이 그대로 두고 부모 Row 의 crossAxisAlignment.end 로 하단 정렬.
        child,
      ],
    );
  }
}

/// 세트 타입 드롭다운 — 웜업/본세트/드롭세트/실패 4가지를 풀 텍스트로 표시.
/// 첫 행은 [SetType ... ✓ ✗] 만 들어가서 가용 폭이 넉넉하므로 한 글자 축약 대신 전체 단어 노출.
class _SetTypeSelector extends StatelessWidget {
  final SetType value;
  final ValueChanged<SetType> onChanged;

  const _SetTypeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      // "드롭세트" 4글자 + 화살표 들어갈 폭.
      constraints: const BoxConstraints(minWidth: 96),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SetType>(
          value: value,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, size: 20, color: cs.onSurfaceVariant),
          items: const [
            DropdownMenuItem(
              value: SetType.warmup,
              child: Text('웜업', style: TextStyle(fontSize: 14)),
            ),
            DropdownMenuItem(
              value: SetType.work,
              child: Text('본세트', style: TextStyle(fontSize: 14)),
            ),
            DropdownMenuItem(
              value: SetType.drop,
              child: Text('드롭세트', style: TextStyle(fontSize: 14)),
            ),
            DropdownMenuItem(
              value: SetType.failure,
              child: Text('실패', style: TextStyle(fontSize: 14)),
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

