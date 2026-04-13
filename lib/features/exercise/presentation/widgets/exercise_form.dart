import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/settings/presentation/providers/exercise_template_provider.dart';
import '../../domain/entities/exercise_record.dart';
import '../providers/exercise_provider.dart';

class ExerciseForm extends ConsumerStatefulWidget {
  final ExerciseRecord? initialRecord;

  const ExerciseForm({super.key, this.initialRecord});

  @override
  ConsumerState<ExerciseForm> createState() => _ExerciseFormState();
}

class _ExerciseFormState extends ConsumerState<ExerciseForm> {
  final _formKey = GlobalKey<FormState>();
  final _exerciseTypeController = TextEditingController();
  final _exerciseNameController = TextEditingController();
  final _currentSetController = TextEditingController();
  final _weightController = TextEditingController();
  final _repsController = TextEditingController();
  final _rpeController = TextEditingController();

  final _exerciseTypes = ['가슴', '등', '하체', '어깨', '팔', '코어', '유산소', '기타'];

  bool get _isEditMode => widget.initialRecord != null;

  String? _selectedTemplateName;
  bool get _isDirectInput => _selectedTemplateName == null;

  @override
  void initState() {
    super.initState();
    final r = widget.initialRecord;
    final templates = ref.read(exerciseTemplatesProvider);

    if (r != null) {
      _exerciseTypeController.text = r.exerciseType;
      _currentSetController.text = r.currentSet.toString();
      _weightController.text = r.weight % 1 == 0
          ? r.weight.toInt().toString()
          : r.weight.toString();
      _repsController.text = r.reps.toString();
      _rpeController.text = r.rpe % 1 == 0
          ? r.rpe.toInt().toString()
          : r.rpe.toString();

      // 기존 이름이 템플릿에 있으면 선택, 없으면 직접입력 모드
      if (templates.any((t) => t.name == r.exerciseName)) {
        _selectedTemplateName = r.exerciseName;
      } else {
        _exerciseNameController.text = r.exerciseName;
      }
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
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
      ref.read(exerciseRecordsProvider.notifier).deleteRecord(widget.initialRecord!.uuid);
      Navigator.pop(context);
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final exerciseName = _isDirectInput
          ? _exerciseNameController.text.trim()
          : _selectedTemplateName!;

      final now = DateTime.now();
      if (_isEditMode) {
        final updated = widget.initialRecord!.copyWith(
          updatedAt: now,
          syncStatus: SyncStatus.modified,
          exerciseType: _exerciseTypeController.text,
          exerciseName: exerciseName,
          currentSet: int.parse(_currentSetController.text),
          weight: double.parse(_weightController.text),
          reps: int.parse(_repsController.text),
          rpe: double.parse(_rpeController.text),
        );
        ref.read(exerciseRecordsProvider.notifier).updateRecord(updated);
      } else {
        final record = ExerciseRecord(
          timestamp: now,
          updatedAt: now,
          exerciseType: _exerciseTypeController.text,
          exerciseName: exerciseName,
          currentSet: int.parse(_currentSetController.text),
          weight: double.parse(_weightController.text),
          reps: int.parse(_repsController.text),
          rpe: double.parse(_rpeController.text),
        );
        ref.read(exerciseRecordsProvider.notifier).addRecord(record);
      }
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(exerciseTemplatesProvider);
    final templateNames = templates.map((t) => t.name).toList();

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: '운동 유형'),
            initialValue: _exerciseTypeController.text.isEmpty
                ? null
                : _exerciseTypeController.text,
            items: _exerciseTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => _exerciseTypeController.text = v ?? '',
            validator: (v) => v == null ? '필수' : null,
          ),
          const SizedBox(height: 12),
          if (templateNames.isNotEmpty)
            DropdownButtonFormField<String?>(
              decoration: const InputDecoration(labelText: '운동 이름'),
              initialValue: _selectedTemplateName,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('직접 입력'),
                ),
                ...templateNames
                    .map((t) => DropdownMenuItem(value: t, child: Text(t))),
              ],
              onChanged: (v) {
                setState(() {
                  _selectedTemplateName = v;
                  _exerciseNameController.clear();
                });
              },
              validator: (v) =>
                  (v == null && _exerciseNameController.text.isEmpty)
                      ? '필수'
                      : null,
            )
          else
            TextFormField(
              controller: _exerciseNameController,
              decoration: const InputDecoration(labelText: '운동 이름'),
              validator: (v) => v?.isEmpty ?? true ? '필수' : null,
            ),
          if (_isDirectInput && templateNames.isNotEmpty) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _exerciseNameController,
              decoration: const InputDecoration(labelText: '운동 이름 입력'),
              validator: (v) => v?.isEmpty ?? true ? '필수' : null,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _currentSetController,
                  decoration: const InputDecoration(labelText: '세트'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1 || n > 99) return '1-99';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _weightController,
                  decoration: const InputDecoration(labelText: '중량(kg)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null || n < 0 || n > 999) return '0-999';
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
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1 || n > 999) return '1-999';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _rpeController,
                  decoration: const InputDecoration(labelText: 'RPE(1-10)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null || n < 1 || n > 10) return '1-10';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              child: Text(_isEditMode ? '수정' : '추가'),
            ),
          ),
          if (_isEditMode) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                ),
                onPressed: _delete,
                child: const Text('삭제'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
