import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../shared/widgets/error_overlay.dart';
import '../providers/exercise_template_provider.dart';

const _exerciseTypes = ['가슴', '등', '하체', '어깨', '팔', '코어', '유산소', '기타'];

class ExerciseTemplateCard extends ConsumerStatefulWidget {
  const ExerciseTemplateCard({super.key});

  @override
  ConsumerState<ExerciseTemplateCard> createState() =>
      _ExerciseTemplateCardState();
}

class _ExerciseTemplateCardState extends ConsumerState<ExerciseTemplateCard> {
  late final TextEditingController _templateNameCtrl;
  String? _selectedExerciseType;

  @override
  void initState() {
    super.initState();
    _templateNameCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _templateNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _addTemplate() async {
    final name = _templateNameCtrl.text.trim();
    if (name.isEmpty) {
      ErrorOverlay.show(title: '입력 오류', message: '운동 이름을 입력해주세요.');
      return;
    }
    if (_selectedExerciseType == null) {
      ErrorOverlay.show(title: '입력 오류', message: '운동 유형을 선택해주세요.');
      return;
    }

    final templates = ref.read(exerciseTemplatesProvider);
    if (templates.any((t) => t.name == name)) {
      ErrorOverlay.show(title: '중복 오류', message: '이미 있는 템플릿입니다.');
      return;
    }

    try {
      await ref
          .read(exerciseTemplatesProvider.notifier)
          .addTemplate(name, _selectedExerciseType!);
      _templateNameCtrl.clear();
    } catch (e) {
      debugPrint('ExerciseTemplateCard._addTemplate error: $e');
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(title: '저장 실패', message: '템플릿 추가 중 오류가 발생했습니다: $e');
      }
    }
  }

  Future<void> _deleteTemplate(String uuid) async {
    try {
      await ref.read(exerciseTemplatesProvider.notifier).deleteTemplate(uuid);
    } catch (e) {
      debugPrint('ExerciseTemplateCard._deleteTemplate error: $e');
      if (rootNavigatorKey.currentState?.overlay != null) {
        ErrorOverlay.show(title: '삭제 실패', message: '템플릿 삭제 중 오류가 발생했습니다: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templates = ref.watch(exerciseTemplatesProvider);

    // 유형별 그룹화 (typeOrder 순서 유지)
    final grouped = <String, List<String>>{};
    for (final type in _exerciseTypes) {
      final names = templates
          .where((t) => t.exerciseType == type)
          .map((t) => t.name)
          .toList();
      if (names.isNotEmpty) grouped[type] = names;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fitness_center, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('운동 템플릿', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '자주 사용하는 운동 이름을 미리 등록하세요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (grouped.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final entry in grouped.entries) ...[
                Text(
                  '[${entry.key}]',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final name in entry.value)
                      Chip(
                        label: Text(name),
                        onDeleted: () {
                          final t = templates.firstWhere((t) => t.name == name);
                          _deleteTemplate(t.uuid);
                        },
                        deleteIcon: const Icon(Icons.close, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: '운동 유형',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              initialValue: _selectedExerciseType,
              items: _exerciseTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedExerciseType = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _templateNameCtrl,
                    decoration: InputDecoration(
                      hintText: '운동 이름 입력',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _addTemplate(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addTemplate,
                  icon: const Icon(Icons.add),
                  tooltip: '템플릿 추가',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
