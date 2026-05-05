import 'package:flutter/material.dart';

import 'exercise_picker_field.dart';

/// 사용자가 picker 에서 선택한 등록 종목 정보.
/// `exerciseKey` 는 향후 RoutineItem 백필용으로 함께 보관한다.
class DirectRoutineInput {
  final String name;
  final String type;
  final String exerciseKey;
  const DirectRoutineInput({
    required this.name,
    required this.type,
    required this.exerciseKey,
  });
}

Future<DirectRoutineInput?> showDirectRoutineInputDialog(
  BuildContext context, {
  String? initialQuery,
}) {
  return showDialog<DirectRoutineInput>(
    context: context,
    builder: (_) => _DirectRoutineInputDialog(initialQuery: initialQuery),
  );
}

class _DirectRoutineInputDialog extends StatelessWidget {
  final String? initialQuery;
  const _DirectRoutineInputDialog({this.initialQuery});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('운동 추가'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '등록된 운동만 추가할 수 있습니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ExercisePickerField(
              autofocus: true,
              initialQuery: initialQuery,
              onPicked: (result) {
                Navigator.pop(
                  context,
                  DirectRoutineInput(
                    name: result.displayName,
                    type: result.legacyExerciseType,
                    exerciseKey: result.exerciseKey,
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
      ],
    );
  }
}
