import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../domain/entities/pr_summary.dart';

/// 메인 카드: 추정 1RM (큰 숫자) + 4주 전 대비 변화량 + 5주 스파크라인.
///
/// 데이터가 부족한 경우(currentE1RM == null)는 안내 문구로 대체.
class CurrentE1RMCard extends StatelessWidget {
  final PrSummary summary;

  const CurrentE1RMCard({
    super.key,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final mint = isDark ? AppTheme.colorMintDark : AppTheme.colorMintDeep;
    final mintTint =
        isDark ? AppTheme.colorMintTintDark : AppTheme.colorMintTint;
    final coral = isDark ? AppTheme.colorCoralDark : AppTheme.colorCoralDeep;
    final coralTint =
        isDark ? AppTheme.colorCoralTintDark : AppTheme.colorCoralTint;

    final cur = summary.currentE1RM;
    final delta = summary.deltaKg;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [mintTint, cs.surface],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 라벨
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: mint),
              const SizedBox(width: 6),
              Text(
                '예상 1RM (Epley)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: mint,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  summary.exerciseName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 큰 숫자 + 변화량
          if (cur == null)
            _EmptyValue(
              cs: cs,
              message: '이 종목으로 세트를 추가해 보세요',
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  cur.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    letterSpacing: -2,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'kg',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                if (delta != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: delta >= 0 ? mintTint : coralTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${delta >= 0 ? '▲' : '▼'} ${delta.abs().toStringAsFixed(0)}kg',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: delta >= 0 ? mint : coral,
                      ),
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.outlineVariant, width: 0.5),
                    ),
                    child: Text(
                      '첫 기록 측정 중',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          if (cur != null) ...[
            const SizedBox(height: 4),
            Text(
              '최근 5주 최고 추정',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: _Sparkline(
                weeklyHistory: summary.weeklyHistory,
                color: mint,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _AxisLabel('4주 전', cs: cs),
                _AxisLabel('3주 전', cs: cs),
                _AxisLabel('2주 전', cs: cs),
                _AxisLabel('지난주', cs: cs),
                _AxisLabel('오늘', cs: cs, highlight: mint),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyValue extends StatelessWidget {
  final ColorScheme cs;
  final String message;
  const _EmptyValue({required this.cs, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '—',
            style: TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
              letterSpacing: -2,
              height: 1,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AxisLabel extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  final Color? highlight;
  const _AxisLabel(this.text, {required this.cs, this.highlight});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: highlight ?? cs.outline,
      ),
    );
  }
}

/// 5주치 스파크라인. null 슬롯은 자동으로 끊김 (FlSpot 제외).
class _Sparkline extends StatelessWidget {
  final List<double?> weeklyHistory;
  final Color color;
  const _Sparkline({required this.weeklyHistory, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final spots = <FlSpot>[];
    for (int i = 0; i < weeklyHistory.length; i++) {
      final v = weeklyHistory[i];
      if (v != null) spots.add(FlSpot(i.toDouble(), v));
    }
    if (spots.isEmpty) {
      return Center(
        child: Text(
          '추세 데이터 없음',
          style: TextStyle(
            fontSize: 11,
            color: cs.outline,
          ),
        ),
      );
    }

    final values = weeklyHistory.whereType<double>().toList();
    final minY = values.reduce((a, b) => a < b ? a : b) - 2;
    final maxY = values.reduce((a, b) => a > b ? a : b) + 2;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (weeklyHistory.length - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, _, _) {
                final isLast = spot.x.toInt() == weeklyHistory.length - 1;
                return FlDotCirclePainter(
                  radius: isLast ? 4.5 : 2.5,
                  color: isLast ? color : cs.surface,
                  strokeColor: color,
                  strokeWidth: isLast ? 0 : 1.6,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.4),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
