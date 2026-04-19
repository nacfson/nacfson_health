import 'package:flutter/material.dart';
import '../../domain/entities/exercise_record.dart';

class ExerciseRecordCard extends StatelessWidget {
  final ExerciseRecord record;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const ExerciseRecordCard({
    super.key,
    required this.record,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final typeColor = getExerciseTypeColor(record.exerciseType, theme.brightness);
    final timeStr = _formatTime(record.timestamp);

    return Dismissible(
      key: ValueKey(record.uuid),
      direction: DismissDirection.endToStart,
      background: _DeleteBackground(colorScheme: colorScheme),
      confirmDismiss: (_) => _showDeleteConfirm(context, record.exerciseName),
      onDismissed: (_) => onDelete?.call(),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _TypeIcon(exerciseType: record.exerciseType, color: typeColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.exerciseName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _TypeChip(
                            label: record.exerciseType,
                            backgroundColor: typeColor,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'RPE ${record.rpe.toStringAsFixed(1)}',
                          style: theme.textTheme.labelMedium,
                        ),
                        Text(
                          timeStr,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StatChip(label: '${record.currentSet}세트'),
                    const SizedBox(width: 6),
                    _StatChip(
                        label: record.weight % 1 == 0
                            ? '${record.weight.toInt()}kg'
                            : '${record.weight}kg'),
                    const SizedBox(width: 6),
                    _StatChip(label: '${record.reps}회'),
                    const Spacer(),
                    Text(
                      'Vol ${record.volume.toStringAsFixed(0)}kg',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color getExerciseTypeColor(String type, [Brightness brightness = Brightness.light]) {
  final isDark = brightness == Brightness.dark;
  return switch (type) {
    '가슴' || '등' || '어깨' => isDark ? const Color(0xFF143129) : const Color(0xFFE7F8F4),
    '하체' || '둔근'         => isDark ? const Color(0xFF3A1D1A) : const Color(0xFFFFECE8),
    '팔' || '코어'           => isDark ? const Color(0xFF1E2540) : const Color(0xFFF0F4FF),
    '유산소'                 => isDark ? const Color(0xFF1B2A3F) : const Color(0xFFEEF5FF),
    _                       => isDark ? const Color(0xFF22303C) : const Color(0xFFF4F5F7),
  };
}

IconData exerciseTypeIcon(String type) {
  return switch (type) {
    '가슴' => Icons.fitness_center,
    '등' => Icons.accessibility_new,
    '하체' => Icons.directions_run,
    '어깨' => Icons.sports_gymnastics,
    '팔' => Icons.sports_handball,
    '코어' => Icons.self_improvement,
    '유산소' => Icons.directions_bike,
    _ => Icons.more_horiz,
  };
}

String _formatTime(DateTime dt) {
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

Future<bool?> _showDeleteConfirm(BuildContext context, String name) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('삭제 확인'),
      content: Text('"$name"을(를) 삭제하시겠습니까?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('삭제'),
        ),
      ],
    ),
  );
}

class _TypeIcon extends StatelessWidget {
  final String exerciseType;
  final Color color;
  const _TypeIcon({required this.exerciseType, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(exerciseTypeIcon(exerciseType), size: 20),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  const _TypeChip({required this.label, required this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  const _StatChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  final ColorScheme colorScheme;
  const _DeleteBackground({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, color: colorScheme.onErrorContainer, size: 28),
          Text(
            '삭제',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}
