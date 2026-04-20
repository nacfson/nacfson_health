import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/exercise_record.dart';
import '../providers/exercise_provider.dart';
import '../providers/rest_timer_provider.dart';

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
    final weight = double.tryParse(_weightCtl.text.trim());
    final reps = int.tryParse(_repsCtl.text.trim());
    final rpe = double.tryParse(_rpeCtl.text.trim());
    if (weight == null || weight <= 0 || reps == null || reps < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('중량(>0)·반복(≥1)을 입력해주세요'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (rpe == null || rpe < 1 || rpe > 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('RPE는 1-10 사이 값입니다'),
        duration: Duration(seconds: 1),
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
        // 휴식 타이머 자동 시작
        final defaultSec = ref.read(defaultRestSecondsProvider);
        ref
            .read(restTimerProvider.notifier)
            .start(defaultSec, exerciseName: widget.exerciseName);
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
            child: _NumField(
              controller: _weightCtl,
              focusNode: _weightFocus,
              label: 'kg',
              decimal: true,
              onSubmitted: (_) => _repsFocus.requestFocus(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _NumField(
              controller: _repsCtl,
              focusNode: _repsFocus,
              label: '회',
              decimal: false,
              onSubmitted: (_) => _rpeFocus.requestFocus(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _NumField(
              controller: _rpeCtl,
              focusNode: _rpeFocus,
              label: 'RPE',
              decimal: true,
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

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final bool decimal;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;

  const _NumField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.decimal,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      textAlign: TextAlign.center,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
