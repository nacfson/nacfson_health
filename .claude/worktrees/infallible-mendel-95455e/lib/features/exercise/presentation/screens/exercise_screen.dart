import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/record_form_sheet.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../domain/entities/exercise_record.dart';
import '../providers/exercise_provider.dart';
import '../widgets/exercise_form.dart';
import '../widgets/exercise_group_card.dart';
import '../widgets/exercise_record_card.dart';

class ExerciseScreen extends ConsumerWidget {
  const ExerciseScreen({super.key});

  void _openAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RecordFormSheet(
        title: '운동 기록 추가',
        child: const ExerciseForm(),
      ),
    );
  }

  void _openEditSheet(BuildContext context, ExerciseRecord record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RecordFormSheet(
        title: '운동 기록 수정',
        child: ExerciseForm(initialRecord: record),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = ref.watch(todayExerciseGroupedProvider);
    final totalVolume = ref.watch(todayTotalVolumeProvider);
    final isEmpty = grouped.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('운동 기록')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _TodayExerciseBanner(totalVolume: totalVolume),
          ),
          if (isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.fitness_center,
                title: '오늘의 운동 기록이 없어요',
                subtitle: '+ 버튼으로 첫 운동을 기록해보세요',
                buttonLabel: '운동 추가',
                onAddPressed: () => _openAddSheet(context),
              ),
            )
          else
            for (final typeEntry in grouped.entries) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  exerciseType: typeEntry.key,
                  count: typeEntry.value.values
                      .fold(0, (sum, list) => sum + list.length),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final nameEntry = typeEntry.value.entries.elementAt(i);
                    return ExerciseGroupCard(
                      exerciseName: nameEntry.key,
                      exerciseType: typeEntry.key,
                      records: nameEntry.value,
                      onEdit: (record) => _openEditSheet(context, record),
                      onDelete: (uuid) => ref
                          .read(exerciseRecordsProvider.notifier)
                          .deleteRecord(uuid),
                    );
                  },
                  childCount: typeEntry.value.length,
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TodayExerciseBanner extends StatelessWidget {
  final double totalVolume;
  const _TodayExerciseBanner({required this.totalVolume});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final dateStr =
        '${now.month}월 ${now.day}일 (${weekdays[now.weekday - 1]})';

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '오늘',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              Text(
                dateStr,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '총 볼륨',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              Text(
                totalVolume == 0
                    ? '—'
                    : '${_formatVolume(totalVolume)} kg',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatVolume(double v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(1)}k';
    }
    return v.toStringAsFixed(0);
  }
}

class _SectionHeader extends StatelessWidget {
  final String exerciseType;
  final int count;
  const _SectionHeader({required this.exerciseType, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(exerciseTypeIcon(exerciseType), size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            exerciseType,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            '$count개',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
