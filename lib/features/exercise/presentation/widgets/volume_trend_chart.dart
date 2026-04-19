import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/exercise_provider.dart';

/// 운동 볼륨 추세 차트 (Template Method 패턴)
///
/// 주간/월간 전환 가능한 꺾은선 차트로 일별 총 볼륨을 시각화합니다.
/// 체중 차트(WeightChartCard)와 동일한 Strategy 패턴을 적용합니다.
class VolumeTrendChart extends ConsumerWidget {
  const VolumeTrendChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(volumeTrendDataProvider);
    final viewType = ref.watch(exerciseChartViewTypeProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 차트에 유효한 데이터가 없으면 표시하지 않음
    final hasData = data.any((d) => d.volume > 0);

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
                Icon(Icons.trending_up,
                    color: AppTheme.colorMint, size: 20),
                const SizedBox(width: 8),
                Text('볼륨 추세', style: theme.textTheme.titleMedium),
                const Spacer(),
                _ViewTypeToggle(
                  current: viewType,
                  onChanged: (type) => ref
                      .read(exerciseChartViewTypeProvider.notifier)
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
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: _calcInterval(data),
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
                            _formatVolume(value),
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
                          interval: viewType == ExerciseChartViewType.weekly ? 1 : 5,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= data.length) return const SizedBox();
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
                    lineBarsData: [
                      LineChartBarData(
                        spots: List.generate(
                          data.length,
                          (i) => FlSpot(i.toDouble(), data[i].volume),
                        ),
                        isCurved: true,
                        curveSmoothness: 0.3,
                        color: AppTheme.colorMint,
                        barWidth: 2.5,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, bar, index) =>
                              FlDotCirclePainter(
                            radius: data[index].volume > 0 ? 3 : 0,
                            color: AppTheme.colorMint,
                            strokeWidth: 1.5,
                            strokeColor: colorScheme.surface,
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppTheme.colorMint.withOpacity(0.08),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                          final idx = spot.x.toInt();
                          final date = data[idx].date;
                          return LineTooltipItem(
                            '${date.month}/${date.day}\n${_formatVolume(spot.y)} kg',
                            theme.textTheme.labelSmall!.copyWith(
                              color: colorScheme.onInverseSurface,
                            ),
                          );
                        }).toList(),
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

  double _calcInterval(List<({DateTime date, double volume})> data) {
    final maxV = data.map((d) => d.volume).reduce(max);
    if (maxV <= 0) return 1000;
    return (maxV / 4).ceilToDouble().clamp(100, double.infinity);
  }

  String _formatVolume(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }
}

/// 주간/월간 전환 토글 (Strategy 패턴 UI)
class _ViewTypeToggle extends StatelessWidget {
  final ExerciseChartViewType current;
  final ValueChanged<ExerciseChartViewType> onChanged;

  const _ViewTypeToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SegmentedButton<ExerciseChartViewType>(
      segments: const [
        ButtonSegment(value: ExerciseChartViewType.weekly, label: Text('주간')),
        ButtonSegment(value: ExerciseChartViewType.monthly, label: Text('월간')),
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
