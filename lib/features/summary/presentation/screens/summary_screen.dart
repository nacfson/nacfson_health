import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/daily_summary.dart';
import '../providers/summary_provider.dart';

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dailySummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('오늘의 요약')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _DateHeader(date: summary.date)),
          if (summary.dietNutrition != null) ...[
            SliverToBoxAdapter(
              child: _CalorieDonutCard(nutrition: summary.dietNutrition!),
            ),
            SliverToBoxAdapter(
              child: _MacroProgressCard(nutrition: summary.dietNutrition!),
            ),
          ] else
            const SliverToBoxAdapter(child: _EmptyDietCard()),
          if (summary.workoutPerformance != null)
            SliverToBoxAdapter(
              child: _WorkoutSummaryCard(
                  performance: summary.workoutPerformance!),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 날짜 헤더
// ─────────────────────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final DateTime date;
  const _DateHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final dateStr =
        '${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        dateStr,
        style: theme.textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 칼로리 도넛 카드
// ─────────────────────────────────────────────────────────────────────────────

class _CalorieDonutCard extends StatelessWidget {
  final DietNutrition nutrition;
  const _CalorieDonutCard({required this.nutrition});

  Color _chartColor(BuildContext context, CalorieResult result) {
    final cs = Theme.of(context).colorScheme;
    return switch (result) {
      CalorieResult.achieved => Colors.green,
      CalorieResult.exceeded => Colors.orange,
      CalorieResult.under => cs.primary,
    };
  }

  String _resultLabel(CalorieResult result) => switch (result) {
        CalorieResult.achieved => '목표 달성',
        CalorieResult.exceeded => '목표 초과',
        CalorieResult.under => '목표 미달',
      };

  Color _badgeColor(CalorieResult result) => switch (result) {
        CalorieResult.achieved => Colors.green,
        CalorieResult.exceeded => Colors.orange,
        CalorieResult.under => Colors.blueGrey,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final consumed = nutrition.consumedCalories;
    final target = nutrition.targetCalories;
    final ratio = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;
    final remaining = 1.0 - ratio;
    final activeColor = _chartColor(context, nutrition.calorieResult);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department,
                    color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('칼로리', style: theme.textTheme.titleMedium),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _badgeColor(nutrition.calorieResult)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _resultLabel(nutrition.calorieResult),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _badgeColor(nutrition.calorieResult),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      startDegreeOffset: -90,
                      sectionsSpace: 2,
                      centerSpaceRadius: 60,
                      sections: [
                        PieChartSectionData(
                          value: ratio * 100,
                          color: activeColor,
                          radius: 28,
                          showTitle: false,
                        ),
                        if (remaining > 0)
                          PieChartSectionData(
                            value: remaining * 100,
                            color: colorScheme.surfaceContainerHighest,
                            radius: 24,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$consumed',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: activeColor,
                        ),
                      ),
                      Text(
                        '/ $target kcal',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${(ratio * 100).toStringAsFixed(0)}% 달성',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: activeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 매크로 프로그레스 카드
// ─────────────────────────────────────────────────────────────────────────────

class _MacroProgressCard extends StatelessWidget {
  final DietNutrition nutrition;
  const _MacroProgressCard({required this.nutrition});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final carbs = nutrition.macroStatus['carbs']!;
    final protein = nutrition.macroStatus['protein']!;
    final fat = nutrition.macroStatus['fat']!;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart_outline,
                    color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('매크로 영양소', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            _MacroRow(
              label: '탄수화물',
              info: carbs,
              color: Colors.orange[400]!,
            ),
            const SizedBox(height: 12),
            _MacroRow(
              label: '단백질',
              info: protein,
              color: Colors.blue[400]!,
            ),
            const SizedBox(height: 12),
            _MacroRow(
              label: '지방',
              info: fat,
              color: Colors.yellow[700]!,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final MacroInfo info;
  final Color color;
  const _MacroRow({
    required this.label,
    required this.info,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExceeded = info.consumed > info.target;
    final barColor = isExceeded ? Colors.red : color;
    final progress = info.target > 0
        ? min(1.0, info.consumed / info.target)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: barColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${info.consumed.toStringAsFixed(0)} / ${info.target.toStringAsFixed(0)}g',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (isExceeded) ...[
              const SizedBox(width: 4),
              Icon(Icons.arrow_upward, size: 12, color: Colors.red),
            ],
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 운동 요약 카드
// ─────────────────────────────────────────────────────────────────────────────

class _WorkoutSummaryCard extends StatelessWidget {
  final WorkoutPerformance performance;
  const _WorkoutSummaryCard({required this.performance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fitness_center,
                    color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('운동', style: theme.textTheme.titleMedium),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: performance.isWorkoutDay
                        ? Colors.green.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    performance.isWorkoutDay ? '운동함' : '휴식일',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: performance.isWorkoutDay
                          ? Colors.green
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (performance.isWorkoutDay) ...[
              if (performance.targetedMuscles.isNotEmpty) ...[
                Text('운동 부위',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: colorScheme.outline)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: performance.targetedMuscles
                      .map((m) => Chip(
                            label: Text(m),
                            labelStyle: theme.textTheme.labelSmall,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: colorScheme.primaryContainer,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.bar_chart,
                      label: '총 볼륨',
                      value: '${performance.totalVolume.toStringAsFixed(0)} kg',
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.speed,
                      label: '평균 RPE',
                      value: performance.averageRpe.toStringAsFixed(1),
                      color: colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
            ] else
              Text(
                '오늘은 휴식을 취했습니다. 내일도 화이팅!',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: color)),
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 식단 미입력 안내
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyDietCard extends StatelessWidget {
  const _EmptyDietCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.restaurant_outlined,
                size: 40, color: colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              '오늘의 식단 기록이 없습니다',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              '식단 탭에서 오늘 먹은 것을 기록해보세요.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
