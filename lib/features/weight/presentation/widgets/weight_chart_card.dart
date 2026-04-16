import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/weight_provider.dart';

class WeightChartCard extends ConsumerWidget {
  const WeightChartCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chartData = ref.watch(weightChartDataProvider);
    final viewType = ref.watch(chartViewTypeProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('체중 변화 추이', style: theme.textTheme.titleMedium),
                SegmentedButton<ChartViewType>(
                  segments: const [
                    ButtonSegment(value: ChartViewType.weekly, label: Text('주')),
                    ButtonSegment(value: ChartViewType.monthly, label: Text('월')),
                    ButtonSegment(value: ChartViewType.yearly, label: Text('년')),
                  ],
                  selected: {viewType},
                  onSelectionChanged: (Set<ChartViewType> newSelection) {
                    ref.read(chartViewTypeProvider.notifier).state = newSelection.first;
                  },
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (chartData.isEmpty)
              SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    '데이터가 부족합니다',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ),
              )
            else
              SizedBox(
                height: 200,
                child: LineChart(
                  _buildChartData(chartData, viewType, colorScheme),
                ),
              ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildChartData(
    List<dynamic> data,
    ChartViewType viewType,
    ColorScheme colorScheme,
  ) {
    if (data.isEmpty) return LineChartData();

    final spots = data.map((r) {
      return FlSpot(
        r.timestamp.millisecondsSinceEpoch.toDouble(),
        r.weight,
      );
    }).toList();

    double minX = spots.first.x;
    double maxX = spots.last.x;

    // 패딩 추가 (X축)
    final now = DateTime.now();
    maxX = now.millisecondsSinceEpoch.toDouble();
    
    switch (viewType) {
      case ChartViewType.weekly:
        minX = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)).millisecondsSinceEpoch.toDouble();
        break;
      case ChartViewType.monthly:
        minX = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)).millisecondsSinceEpoch.toDouble();
        break;
      case ChartViewType.yearly:
        minX = DateTime(now.year, 1, 1).millisecondsSinceEpoch.toDouble();
        break;
    }

    double minY = data.map((e) => (e.weight as num).toDouble()).reduce(min) - 1.0;
    double maxY = data.map((e) => (e.weight as num).toDouble()).reduce(max) + 1.0;

    return LineChartData(
      gridData: const FlGridData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: _getBottomInterval(viewType),
            getTitlesWidget: (value, meta) {
              return _getBottomTitles(value, viewType);
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              return Text(
                value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: colorScheme.primary,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: colorScheme.primary.withValues(alpha: 0.1),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (List<LineBarSpot> touchedSpots) {
            return touchedSpots.map((spot) {
              final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
              final dateStr = DateFormat('MM/dd').format(date);
              return LineTooltipItem(
                '$dateStr\n${spot.y} kg',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  double _getBottomInterval(ChartViewType viewType) {
    const dayMs = 24 * 60 * 60 * 1000.0;
    switch (viewType) {
      case ChartViewType.weekly:
        return dayMs * 2;
      case ChartViewType.monthly:
        return dayMs * 7;
      case ChartViewType.yearly:
        return dayMs * 60;
    }
  }

  Widget _getBottomTitles(double value, ChartViewType viewType) {
    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    String text = '';
    switch (viewType) {
      case ChartViewType.weekly:
        text = DateFormat('E', 'ko_KR').format(date);
        break;
      case ChartViewType.monthly:
        text = '${date.month}/${date.day}';
        break;
      case ChartViewType.yearly:
        text = '${date.month}월';
        break;
    }
    return SideTitleWidget(
      axisSide: AxisSide.bottom,
      child: Text(text, style: const TextStyle(fontSize: 10)),
    );
  }
}
