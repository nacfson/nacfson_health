import 'package:flutter/material.dart';
import '../../domain/entities/exercise_record.dart';
import './exercise_record_card.dart';

class ExerciseGroupCard extends StatelessWidget {
  final String exerciseName;
  final String exerciseType;
  final List<ExerciseRecord> records;
  final Function(ExerciseRecord) onEdit;
  final Function(String) onDelete;

  const ExerciseGroupCard({
    super.key,
    required this.exerciseName,
    required this.exerciseType,
    required this.records,
    required this.onEdit,
    required this.onDelete,
  });

  double get totalVolume =>
      records.fold(0.0, (sum, r) => sum + r.volume);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final typeColor = getExerciseTypeColor(exerciseType);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: typeColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(exerciseTypeIcon(exerciseType), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exerciseName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        exerciseType,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${totalVolume.toStringAsFixed(0)}kg',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Sets List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: records.length,
            separatorBuilder: (context, index) => const Divider(height: 1, indent: 48),
            itemBuilder: (context, index) {
              final record = records[index];
              return _SetRow(
                record: record,
                onTap: () => onEdit(record),
                onDelete: () => onDelete(record.uuid),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  final ExerciseRecord record;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SetRow({
    required this.record,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey(record.uuid),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: colorScheme.errorContainer,
        child: Icon(Icons.delete_outline, color: colorScheme.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  '${record.currentSet}세트',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    _StatItem(
                      label: record.weight % 1 == 0
                          ? '${record.weight.toInt()}kg'
                          : '${record.weight}kg',
                    ),
                    const SizedBox(width: 8),
                    _StatItem(label: '${record.reps}회'),
                    const SizedBox(width: 8),
                    _StatItem(label: 'RPE ${record.rpe.toStringAsFixed(1)}'),
                  ],
                ),
              ),
              Text(
                '${record.volume.toStringAsFixed(0)}kg',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  const _StatItem({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
