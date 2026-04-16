import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/record_form_sheet.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../domain/entities/diet_record.dart';
import '../providers/diet_provider.dart';
import '../widgets/diet_form.dart';
import '../widgets/diet_record_card.dart';

class DietScreen extends ConsumerWidget {
  const DietScreen({super.key});

  void _openAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RecordFormSheet(
        title: '식단 기록 추가',
        child: const DietForm(),
      ),
    );
  }

  void _openEditSheet(BuildContext context, DietRecord record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RecordFormSheet(
        title: '식단 기록 수정',
        child: DietForm(initialRecord: record),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = ref.watch(todayDietGroupedProvider);
    final summary = ref.watch(todayDietSummaryProvider);
    final isEmpty = grouped.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('식단 기록')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _TodayDietBanner(summary: summary),
          ),
          if (isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.restaurant,
                title: '오늘의 식단 기록이 없어요',
                subtitle: '+ 버튼으로 첫 식사를 기록해보세요',
                buttonLabel: '식사 추가하기',
                onAddPressed: () => _openAddSheet(context),
              ),
            )
          else
            for (final entry in grouped.entries) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  mealType: entry.key,
                  count: entry.value.length,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final record = entry.value[i];
                    return DietRecordCard(
                      record: record,
                      onTap: () => _openEditSheet(context, record),
                      onDelete: () => ref
                          .read(dietRecordsProvider.notifier)
                          .deleteRecord(record.uuid),
                    );
                  },
                  childCount: entry.value.length,
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

class _TodayDietBanner extends StatelessWidget {
  final ({int kcal, double carbs, double protein, double fat}) summary;
  const _TodayDietBanner({required this.summary});

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
        gradient: LinearGradient(
          colors: [colorScheme.primaryContainer, colorScheme.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                    '총 칼로리',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    summary.kcal == 0 ? '—' : '${summary.kcal} kcal',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (summary.kcal > 0) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MacroChip(
                  label: '탄',
                  value: '${summary.carbs.toStringAsFixed(0)}g',
                  color: Colors.orange[400]!,
                ),
                _MacroChip(
                  label: '단',
                  value: '${summary.protein.toStringAsFixed(0)}g',
                  color: Colors.blue[400]!,
                ),
                _MacroChip(
                  label: '지',
                  value: '${summary.fat.toStringAsFixed(0)}g',
                  color: Colors.yellow[700]!,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MacroChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MacroChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String mealType;
  final int count;
  const _SectionHeader({required this.mealType, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(mealTypeIcon(mealType), size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            mealType,
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
