import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/selected_date_provider.dart';
import '../../../exercise/presentation/providers/exercise_provider.dart';

/// 최근 13주(91일) GitHub 스타일 운동 히트맵.
/// - 가로축: 주 (좌→우 과거→현재), 총 13열
/// - 세로축: 요일 (월~일), 총 7행
/// - 색상: 본세트 볼륨 분위수 기반 4단계 (0/Q1/Q2/Q3+)
/// - 셀 탭: `selectedDateProvider` 업데이트 + 운동 탭으로 이동
class WorkoutHeatmapCard extends ConsumerWidget {
  const WorkoutHeatmapCard({super.key});

  static const int _weeks = 13;
  static const double _cellSize = 14;
  static const double _cellGap = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final data = ref.watch(heatmapDataProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 13주 격자의 시작: 오늘을 포함한 주의 월요일 기준에서 12주 전의 월요일.
    final mondayOfThisWeek =
        today.subtract(Duration(days: today.weekday - 1));
    final gridStart = mondayOfThisWeek.subtract(Duration(days: 7 * (_weeks - 1)));

    final hasData = data.values.any((v) => v > 0);
    if (!hasData) {
      return Card(
        margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.calendar_month,
                  size: 32, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 8),
              Text(
                '운동 기록이 쌓이면\n이곳에 달력이 나타납니다',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    // 분위수(Q1, Q2, Q3) 계산 — 볼륨이 양수인 값만 대상
    final positives = data.values.where((v) => v > 0).toList()..sort();
    final q1 = _quantile(positives, 0.25);
    final q2 = _quantile(positives, 0.5);
    final q3 = _quantile(positives, 0.75);

    return Card(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department,
                    size: 18, color: AppTheme.colorMint),
                const SizedBox(width: 6),
                Text('운동 달력',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(
                  '최근 3개월',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MonthLabels(gridStart: gridStart, cellSize: _cellSize, cellGap: _cellGap),
            const SizedBox(height: 4),
            _HeatmapGrid(
              gridStart: gridStart,
              today: today,
              data: data,
              q1: q1,
              q2: q2,
              q3: q3,
              onCellTap: (date) {
                ref.read(selectedDateProvider.notifier).state = date;
                context.go('/exercise');
              },
            ),
            const SizedBox(height: 10),
            _Legend(),
          ],
        ),
      ),
    );
  }

  static double _quantile(List<double> sorted, double p) {
    if (sorted.isEmpty) return 0;
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx];
  }
}

class _MonthLabels extends StatelessWidget {
  final DateTime gridStart;
  final double cellSize;
  final double cellGap;

  const _MonthLabels({
    required this.gridStart,
    required this.cellSize,
    required this.cellGap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 주 경계가 달이 바뀌는 시점에만 월 라벨을 표시.
    final labels = <Widget>[];
    int? lastMonth;
    for (var w = 0; w < WorkoutHeatmapCard._weeks; w++) {
      final weekStart = gridStart.add(Duration(days: 7 * w));
      final showLabel = lastMonth != weekStart.month;
      labels.add(SizedBox(
        width: cellSize + cellGap,
        child: showLabel
            ? Text(
                '${weekStart.month}월',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                ),
              )
            : const SizedBox.shrink(),
      ));
      lastMonth = weekStart.month;
    }
    return Padding(
      padding: EdgeInsets.only(left: _HeatmapGrid._labelColWidth),
      child: Row(children: labels),
    );
  }
}

class _HeatmapGrid extends StatelessWidget {
  final DateTime gridStart;
  final DateTime today;
  final Map<DateTime, double> data;
  final double q1;
  final double q2;
  final double q3;
  final void Function(DateTime) onCellTap;

  static const double _labelColWidth = 20;

  const _HeatmapGrid({
    required this.gridStart,
    required this.today,
    required this.data,
    required this.q1,
    required this.q2,
    required this.q3,
    required this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];

    final rows = <Widget>[];
    for (var dow = 0; dow < 7; dow++) {
      final cells = <Widget>[];
      // 요일 라벨 — 월/수/금만 표시 (GitHub 스타일)
      cells.add(SizedBox(
        width: _HeatmapGrid._labelColWidth,
        height: WorkoutHeatmapCard._cellSize,
        child: (dow == 0 || dow == 2 || dow == 4)
            ? Text(
                weekdays[dow],
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                ),
              )
            : const SizedBox.shrink(),
      ));
      for (var w = 0; w < WorkoutHeatmapCard._weeks; w++) {
        final date = gridStart.add(Duration(days: 7 * w + dow));
        final key = DateTime(date.year, date.month, date.day);
        // 미래 날짜는 빈 셀로 처리(탭 비활성)
        final inRange = !date.isAfter(today);
        final volume = data[key] ?? 0;
        final color = _colorFor(volume, cs);
        final isToday = key == today;
        cells.add(Padding(
          padding: EdgeInsets.only(right: WorkoutHeatmapCard._cellGap),
          child: _Cell(
            color: color,
            isToday: isToday,
            enabled: inRange,
            volume: volume,
            date: key,
            onTap: inRange ? () => onCellTap(key) : null,
          ),
        ));
      }
      rows.add(Padding(
        padding: EdgeInsets.only(bottom: WorkoutHeatmapCard._cellGap),
        child: Row(children: cells),
      ));
    }
    return Column(children: rows);
  }

  Color _colorFor(double v, ColorScheme cs) {
    if (v <= 0) return cs.surfaceContainerHighest;
    if (v < q1 || q1 == 0) return AppTheme.colorMint.withValues(alpha: 0.25);
    if (v < q2) return AppTheme.colorMint.withValues(alpha: 0.5);
    if (v < q3) return AppTheme.colorMint.withValues(alpha: 0.75);
    return AppTheme.colorMint;
  }
}

class _Cell extends StatelessWidget {
  final Color color;
  final bool isToday;
  final bool enabled;
  final double volume;
  final DateTime date;
  final VoidCallback? onTap;

  const _Cell({
    required this.color,
    required this.isToday,
    required this.enabled,
    required this.volume,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tooltip = enabled
        ? (volume > 0
            ? '${date.month}/${date.day} · ${volume.toStringAsFixed(0)}kg'
            : '${date.month}/${date.day} · 기록 없음')
        : '';
    final cell = Container(
      width: WorkoutHeatmapCard._cellSize,
      height: WorkoutHeatmapCard._cellSize,
      decoration: BoxDecoration(
        color: enabled ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        border: isToday
            ? Border.all(color: cs.primary, width: 1.2)
            : null,
      ),
    );
    if (!enabled) return cell;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: cell,
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget dot(Color c) => Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('적음',
            style: theme.textTheme.labelSmall
                ?.copyWith(fontSize: 10, color: cs.onSurfaceVariant)),
        const SizedBox(width: 4),
        dot(cs.surfaceContainerHighest),
        dot(AppTheme.colorMint.withValues(alpha: 0.25)),
        dot(AppTheme.colorMint.withValues(alpha: 0.5)),
        dot(AppTheme.colorMint.withValues(alpha: 0.75)),
        dot(AppTheme.colorMint),
        const SizedBox(width: 4),
        Text('많음',
            style: theme.textTheme.labelSmall
                ?.copyWith(fontSize: 10, color: cs.onSurfaceVariant)),
      ],
    );
  }
}
