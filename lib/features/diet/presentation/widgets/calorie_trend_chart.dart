import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/diet_provider.dart';

/// 식단 칼로리 히스토리 차트 (Template Method 패턴)
///
/// 주간/월간 전환 가능한 막대 차트로 일별 칼로리 섭취량을 시각화합니다.
/// 목표 칼로리 기준선을 점선으로 표시합니다.
class CalorieTrendChart extends ConsumerWidget {
  const CalorieTrendChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(calorieTrendDataProvider);
    final viewType = ref.watch(dietChartViewTypeProvider);
    final targets = ref.watch(nutritionTargetsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hasData = data.any((d) => d.calories > 0);
    final targetCalories = targets.calories.toDouble();

    return Card(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더: 제목 + 주간/월간 전환
            Row(
              children: [
                Icon(Icons.local_fire_department,
                    color: Colors.deepOrange, size: 20),
                const SizedBox(width: 8),
                Text('칼로리 추세', style: theme.textTheme.titleMedium),
                const Spacer(),
                _ViewTypeToggle(
                  current: viewType,
                  onChanged: (type) => ref
                      .read(dietChartViewTypeProvider.notifier)
                      .state = type,
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (!hasData)
              SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    '아직 데이터가 없습니다',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: _calcMaxY(data, targetCalories),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: _calcInterval(data, targetCalories),
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) => Text(
                            value >= 1000
                                ? '${(value / 1000).toStringAsFixed(1)}k'
                                : value.toStringAsFixed(0),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= data.length) return const SizedBox();
                            // 주간은 모두 표시, 월간은 5일 간격
                            if (viewType == DietChartViewType.monthly && idx % 5 != 0) {
                              return const SizedBox();
                            }
                            final date = data[idx].date;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${date.month}/${date.day}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(data.length, (i) {
                      final cal = data[i].calories.toDouble();
                      final isExceeded = targetCalories > 0 && cal > targetCalories * 1.05;
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: cal,
                            color: isExceeded
                                ? (theme.brightness == Brightness.dark
                                    ? AppTheme.colorCoralDark
                                    : AppTheme.colorCoral)
                                : AppTheme.catDiet(context),
                            width: viewType == DietChartViewType.weekly ? 20 : 6,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ],
                      );
                    }),
                    // 목표 칼로리 기준선
                    extraLinesData: targetCalories > 0
                        ? ExtraLinesData(
                            horizontalLines: [
                              HorizontalLine(
                                y: targetCalories,
                                color: theme.colorScheme.error.withValues(alpha: 0.7),
                                strokeWidth: 1.5,
                                dashArray: [6, 4],
                                label: HorizontalLineLabel(
                                  show: true,
                                  alignment: Alignment.topRight,
                                  padding: const EdgeInsets.only(right: 4, bottom: 2),
                                  style: theme.textTheme.labelSmall!.copyWith(
                                    color: theme.colorScheme.error,
                                    fontSize: 9,
                                  ),
                                  labelResolver: (line) => '목표 ${targetCalories.toInt()}',
                                ),
                              ),
                            ],
                          )
                        : null,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIdx, rod, rodIdx) {
                          final date = data[group.x].date;
                          return BarTooltipItem(
                            '${date.month}/${date.day}\n${rod.toY.toInt()} kcal',
                            theme.textTheme.labelSmall!.copyWith(
                              color: colorScheme.onInverseSurface,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _calcMaxY(
      List<({DateTime date, int calories})> data, double target) {
    final maxVal = data.map((d) => d.calories.toDouble()).reduce(max);
    return max(maxVal, target) * 1.2;
  }

  double _calcInterval(
      List<({DateTime date, int calories})> data, double target) {
    final maxVal = max(data.map((d) => d.calories.toDouble()).reduce(max), target);
    if (maxVal <= 0) return 500;
    return (maxVal / 4).ceilToDouble().clamp(100, double.infinity);
  }
}

/// 주간/월간 전환 토글 (Strategy 패턴 UI)
class _ViewTypeToggle extends StatelessWidget {
  final DietChartViewType current;
  final ValueChanged<DietChartViewType> onChanged;

  const _ViewTypeToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SegmentedButton<DietChartViewType>(
      segments: const [
        ButtonSegment(value: DietChartViewType.weekly, label: Text('주간')),
        ButtonSegment(value: DietChartViewType.monthly, label: Text('월간')),
      ],
      selected: {current},
      onSelectionChanged: (set) => onChanged(set.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(theme.textTheme.labelSmall),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }
}
