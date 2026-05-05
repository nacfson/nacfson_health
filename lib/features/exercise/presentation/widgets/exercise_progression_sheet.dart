import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/exercise_provider.dart';
import 'exercise_record_card.dart' show getExerciseTypeColor, exerciseTypeIcon;

/// 운동 종목 한 개의 진행 추세 차트 시트.
/// - 메트릭: 최고 무게 / e1RM / 세션 볼륨
/// - 기간: 1개월 / 3개월 / 6개월
Future<void> showExerciseProgressionSheet(
  BuildContext context, {
  required String exerciseType,
  required String exerciseName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // ShellRoute 의 shellNavigator 위가 아니라 rootNavigator 위로 push 해야
    // BottomNavShell 의 glassmorphic 하단 탭 바가 시트를 가리지 않는다.
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => ExerciseProgressionSheet(
      exerciseType: exerciseType,
      exerciseName: exerciseName,
    ),
  );
}

class ExerciseProgressionSheet extends ConsumerWidget {
  final String exerciseType;
  final String exerciseName;

  const ExerciseProgressionSheet({
    super.key,
    required this.exerciseType,
    required this.exerciseName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              _Handle(),
              _Header(
                exerciseType: exerciseType,
                exerciseName: exerciseName,
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    const _MetricToggle(),
                    const SizedBox(height: 8),
                    const _PeriodToggle(),
                    const SizedBox(height: 16),
                    _ProgressionChart(exerciseName: exerciseName),
                    const SizedBox(height: 16),
                    _SummaryRow(exerciseName: exerciseName),
                    const SizedBox(height: 24),
                    _RecentSessions(exerciseName: exerciseName),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          context.push(
                            '/exercise/coach/one-rm?exercise=${Uri.encodeComponent(exerciseName)}',
                          );
                        },
                        icon: const Icon(Icons.bolt_outlined, size: 18),
                        label: const Text('1RM 코치 보기'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: cs.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String exerciseType;
  final String exerciseName;

  const _Header({required this.exerciseType, required this.exerciseName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = getExerciseTypeColor(exerciseType, theme.brightness);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: typeColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(exerciseTypeIcon(exerciseType),
                size: 18, color: AppTheme.colorNavy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exerciseName,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '$exerciseType · 진행 추세',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _MetricToggle extends ConsumerWidget {
  const _MetricToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(progressionMetricProvider);
    return SegmentedButton<ProgressionMetric>(
      segments: const [
        ButtonSegment(
          value: ProgressionMetric.topWeight,
          label: Text('최고 무게'),
        ),
        ButtonSegment(
          value: ProgressionMetric.e1rm,
          label: Text('e1RM'),
        ),
        ButtonSegment(
          value: ProgressionMetric.sessionVolume,
          label: Text('세션 볼륨'),
        ),
      ],
      selected: {current},
      onSelectionChanged: (s) => ref
          .read(progressionMetricProvider.notifier)
          .state = s.first,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _PeriodToggle extends ConsumerWidget {
  const _PeriodToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(progressionPeriodProvider);
    return SegmentedButton<ProgressionPeriod>(
      segments: const [
        ButtonSegment(value: ProgressionPeriod.m1, label: Text('1개월')),
        ButtonSegment(value: ProgressionPeriod.m3, label: Text('3개월')),
        ButtonSegment(value: ProgressionPeriod.m6, label: Text('6개월')),
      ],
      selected: {current},
      onSelectionChanged: (s) => ref
          .read(progressionPeriodProvider.notifier)
          .state = s.first,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _ProgressionChart extends ConsumerWidget {
  final String exerciseName;
  const _ProgressionChart({required this.exerciseName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final points = ref.watch(exerciseProgressionDataProvider(exerciseName));
    final metric = ref.watch(progressionMetricProvider);

    if (points.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insights,
                  size: 36, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              const SizedBox(height: 8),
              Text(
                '데이터 누적 중',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                '세션 2회 이상 기록하면 추세가 보입니다',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final values = points.map((p) => p.value).toList();
    final maxV = values.reduce(max);
    final minV = values.reduce(min);
    final range = (maxV - minV).abs();
    final pad = range == 0 ? max(maxV * 0.1, 1.0) : range * 0.15;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: (minV - pad).clamp(0, double.infinity),
          maxY: maxV + pad,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (v, _) => Text(
                  _formatValue(v, metric),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: max(1, (points.length / 5).floorToDouble()),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= points.length) {
                    return const SizedBox();
                  }
                  final d = points[idx].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${d.month}/${d.day}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                points.length,
                (i) => FlSpot(i.toDouble(), points[i].value),
              ),
              isCurved: true,
              curveSmoothness: 0.25,
              color: AppTheme.colorMint,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                  radius: 3,
                  color: AppTheme.colorMint,
                  strokeWidth: 1.5,
                  strokeColor: cs.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppTheme.colorMint.withValues(alpha: 0.08),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((s) {
                final p = points[s.x.toInt()];
                return LineTooltipItem(
                  '${p.date.month}/${p.date.day}\n'
                  '${_formatValue(p.value, metric)} ${metric.unit}',
                  theme.textTheme.labelSmall!.copyWith(
                    color: cs.onInverseSurface,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  String _formatValue(double v, ProgressionMetric metric) {
    if (metric == ProgressionMetric.sessionVolume && v >= 1000) {
      return '${(v / 1000).toStringAsFixed(1)}k';
    }
    return v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
  }
}

class _SummaryRow extends ConsumerWidget {
  final String exerciseName;
  const _SummaryRow({required this.exerciseName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = ref.watch(exerciseProgressionSummaryProvider(exerciseName));
    if (s.sessionCount == 0) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: '최고 기록',
            value: s.maxWeight % 1 == 0
                ? '${s.maxWeight.toInt()}kg × ${s.maxWeightReps}'
                : '${s.maxWeight}kg × ${s.maxWeightReps}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: '세션 수',
            value: '${s.sessionCount}회',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: '평균 RPE',
            value: s.avgRpe.toStringAsFixed(1),
            color: cs.primary,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatCard({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSessions extends ConsumerWidget {
  final String exerciseName;
  const _RecentSessions({required this.exerciseName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final points = ref.watch(exerciseProgressionDataProvider(exerciseName));
    if (points.isEmpty) return const SizedBox.shrink();

    final recent = points.reversed.take(10).toList();
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '최근 세션',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Divider(color: cs.outlineVariant, height: 16),
        ...recent.map((p) {
          final dayLabel = weekdays[p.date.weekday - 1];
          final weightStr = p.topWeight % 1 == 0
              ? '${p.topWeight.toInt()}'
              : p.topWeight.toStringAsFixed(1);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    '${p.date.month}/${p.date.day} ($dayLabel)',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: Text(
                    '탑셋 ${weightStr}kg × ${p.topReps}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  'RPE ${p.avgRpe.toStringAsFixed(1)}',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: cs.primary),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
