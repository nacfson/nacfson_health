import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/training/one_rm_calculator.dart';

/// % of 1RM 환산표. 100~65% (8행).
/// 현재 입력 reps 와 일치하는 행을 mint 강조 색으로 표시.
class PercentOfOneRMTable extends StatelessWidget {
  final double e1RM;
  final int currentReps;
  const PercentOfOneRMTable({
    super.key,
    required this.e1RM,
    required this.currentReps,
  });

  static const _rows = <(int, int)>[
    (100, 1),
    (95, 2),
    (90, 4),
    (85, 6),
    (80, 8),
    (75, 10),
    (70, 12),
    (65, 15),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mint = isDark ? AppTheme.colorMintDark : AppTheme.colorMintDeep;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _rows.length; i++)
            _Row(
              percent: _rows[i].$1,
              reps: _rows[i].$2,
              weight: weightForPercentage(e1RM, _rows[i].$1),
              highlight: currentReps == _rows[i].$2,
              mint: mint,
              isLast: i == _rows.length - 1,
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final int percent;
  final int reps;
  final double weight;
  final bool highlight;
  final Color mint;
  final bool isLast;
  const _Row({
    required this.percent,
    required this.reps,
    required this.weight,
    required this.highlight,
    required this.mint,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '$percent%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: highlight ? mint : cs.onSurface,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: cs.outlineVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                widthFactor: percent / 100,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: highlight
                        ? LinearGradient(
                            colors: [mint, mint.withValues(alpha: 0.7)],
                          )
                        : null,
                    color: highlight
                        ? null
                        : cs.outlineVariant.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              '${weight.toStringAsFixed(weight.truncateToDouble() == weight ? 0 : 1)}kg',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: highlight ? cs.onSurface : cs.onSurfaceVariant,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              '$reps회',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
