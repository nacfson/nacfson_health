import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../features/settings/domain/entities/exercise_template.dart';
import '../../../../features/settings/presentation/providers/exercise_template_provider.dart';
import '../../../../shared/widgets/template_picker_sheet.dart';
import '../../domain/entities/exercise_record.dart';
import '../providers/exercise_provider.dart';
import '../providers/rest_timer_provider.dart';

class ExerciseForm extends ConsumerStatefulWidget {
  final ExerciseRecord? initialRecord;

  const ExerciseForm({super.key, this.initialRecord});

  @override
  ConsumerState<ExerciseForm> createState() => _ExerciseFormState();
}

class _ExerciseFormState extends ConsumerState<ExerciseForm> {
  final _formKey = GlobalKey<FormState>();
  final _exerciseNameController = TextEditingController();
  final _currentSetController = TextEditingController();
  final _weightController = TextEditingController();
  final _repsController = TextEditingController();
  final _rpeController = TextEditingController();

  final _exerciseTypes = ['가슴', '등', '하체', '어깨', '팔', '코어', '유산소', '기타'];
  String _selectedType = '가슴';
  bool _isLoading = false;

  bool get _isEditMode => widget.initialRecord != null;

  @override
  void initState() {
    super.initState();
    final r = widget.initialRecord;
    if (r != null) {
      _selectedType = r.exerciseType;
      _exerciseNameController.text = r.exerciseName;
      _currentSetController.text = r.currentSet.toString();
      _weightController.text = r.weight % 1 == 0
          ? r.weight.toInt().toString()
          : r.weight.toString();
      _repsController.text = r.reps.toString();
      _rpeController.text = r.rpe % 1 == 0
          ? r.rpe.toInt().toString()
          : r.rpe.toString();
    }
  }

  @override
  void dispose() {
    _exerciseNameController.dispose();
    _currentSetController.dispose();
    _weightController.dispose();
    _repsController.dispose();
    _rpeController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('"${widget.initialRecord!.exerciseName}"을(를) 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ref
          .read(exerciseRecordsProvider.notifier)
          .deleteRecord(widget.initialRecord!.uuid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('삭제되었습니다'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      if (_isEditMode) {
        final updated = widget.initialRecord!.copyWith(
          updatedAt: now,
          syncStatus: SyncStatus.modified,
          exerciseType: _selectedType,
          exerciseName: _exerciseNameController.text.trim(),
          currentSet: int.parse(_currentSetController.text),
          weight: double.parse(_weightController.text),
          reps: int.parse(_repsController.text),
          rpe: double.parse(_rpeController.text),
        );
        ref.read(exerciseRecordsProvider.notifier).updateRecord(updated);
      } else {
        final exerciseName = _exerciseNameController.text.trim();
        final record = ExerciseRecord(
          timestamp: now,
          updatedAt: now,
          exerciseType: _selectedType,
          exerciseName: exerciseName,
          currentSet: int.parse(_currentSetController.text),
          weight: double.parse(_weightController.text),
          reps: int.parse(_repsController.text),
          rpe: double.parse(_rpeController.text),
        );
        ref.read(exerciseRecordsProvider.notifier).addRecord(record);

        // 신규 세트 저장 시 휴식 타이머 자동 시작
        final defaultSec = ref.read(defaultRestSecondsProvider);
        ref
            .read(restTimerProvider.notifier)
            .start(defaultSec, exerciseName: exerciseName);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('저장되었습니다'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openTemplatePicker() async {
    final templates = ref.read(exerciseTemplatesProvider);
    final picked = await showTemplatePickerSheet<ExerciseTemplate>(
      context: context,
      title: '운동 템플릿 선택',
      templates: templates,
      labelOf: (t) => t.name,
      groupKeyOf: (t) => t.exerciseType,
      initialGroupKey: _selectedType,
      emptyHint: '등록된 운동 템플릿이 없습니다.\n설정에서 자주 하는 운동을 템플릿으로 추가해 보세요.',
      onEmptyAction: () => context.push('/settings'),
    );
    if (picked != null && mounted) {
      setState(() {
        _exerciseNameController.text = picked.name;
        if (picked.exerciseType.isNotEmpty) {
          _selectedType = picked.exerciseType;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 운동 부위 선택 (Horizontal Scroll)
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _exerciseTypes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final type = _exerciseTypes[index];
                final isSelected = _selectedType == type;
                return ChoiceChip(
                  label: Text(type),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedType = type;
                      });
                    }
                  },
                  backgroundColor: Colors.transparent,
                  selectedColor: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.1),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // 2. 운동 이름 입력 필드 (우측 suffixIcon으로 템플릿 피커 호출)
          TextFormField(
            controller: _exerciseNameController,
            decoration: InputDecoration(
              labelText: '어떤 운동을 하셨나요?',
              hintText: '예: 벤치 프레스',
              suffixIcon: IconButton(
                icon: const Icon(Icons.bookmark_border),
                tooltip: '템플릿에서 선택',
                onPressed: _openTemplatePicker,
              ),
            ),
            validator: (v) => v?.isEmpty ?? true ? '운동 이름을 입력해주세요' : null,
          ),
          const SizedBox(height: 8),

          // 5. 세트, 중량, 반복, RPE 입력 (2x2 Grid)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _currentSetController,
                  decoration: const InputDecoration(labelText: '세트'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1) return '1 이상';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _weightController,
                  decoration: const InputDecoration(labelText: '중량(kg)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null) return '숫자를 입력하세요';
                    if (n <= 0) return '0보다 커야 합니다';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _repsController,
                  decoration: const InputDecoration(labelText: '반복'),
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      (int.tryParse(v ?? '') ?? 0) < 1 ? '필수' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _rpeController,
                  decoration: const InputDecoration(labelText: 'RPE(1-10)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null || n < 1 || n > 10) return '1-10';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 6. 하단 버튼
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditMode ? '기록 수정하기' : '기록 완료'),
            ),
          ),
          if (_isEditMode) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _delete,
                child: const Text('운동 기록 삭제'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

