import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/training/one_rm_calculator.dart';
import '../../providers/one_rm_coach_provider.dart';

/// 빠른 추정 카드: 중량/횟수 ±스테퍼 + 입력 신뢰도 안내.
class QuickEstimateStepper extends ConsumerWidget {
  const QuickEstimateStepper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mint = isDark ? AppTheme.colorMintDark : AppTheme.colorMintDeep;
    final coral = isDark ? AppTheme.colorCoralDark : AppTheme.colorCoralDeep;

    final weight = ref.watch(coachInputWeightProvider);
    final reps = ref.watch(coachInputRepsProvider);
    final confidence = inputConfidencePercent(reps);
    final band = confidenceBand(reps);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Stepper(
                  label: '중량 (kg)',
                  value: weight.toStringAsFixed(1),
                  onMinus: () => ref
                      .read(coachInputWeightProvider.notifier)
                      .state = (weight - 2.5).clamp(2.5, 500),
                  onPlus: () => ref
                      .read(coachInputWeightProvider.notifier)
                      .state = (weight + 2.5).clamp(2.5, 500),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stepper(
                  label: '횟수',
                  value: reps.toString(),
                  onMinus: () => ref.read(coachInputRepsProvider.notifier).state =
                      (reps - 1).clamp(1, 30),
                  onPlus: () => ref.read(coachInputRepsProvider.notifier).state =
                      (reps + 1).clamp(1, 30),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bolt_outlined,
                  size: 16,
                  color: reps <= 8 ? mint : coral,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    band,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
                _ConfidenceBadge(
                  percent: confidence,
                  good: confidence >= 90 ? mint : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _Stepper({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mint = isDark ? AppTheme.colorMintDark : AppTheme.colorMint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant, width: 0.5),
          ),
          child: Row(
            children: [
              _StepBtn(
                icon: Icons.remove,
                onTap: onMinus,
                background: cs.surface,
                foreground: cs.onSurfaceVariant,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ),
              _StepBtn(
                icon: Icons.add,
                onTap: onPlus,
                background: mint,
                foreground: AppTheme.colorNavy,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  const _StepBtn({
    required this.icon,
    required this.onTap,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: foreground),
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final int percent;
  final Color? good;
  const _ConfidenceBadge({required this.percent, this.good});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = percent >= 90
        ? (isDark ? AppTheme.colorMintDark : AppTheme.colorMintDeep)
        : percent >= 80
            ? (isDark ? AppTheme.colorCatDietDark : AppTheme.colorCatDiet)
            : (isDark ? AppTheme.colorCoralDark : AppTheme.colorCoralDeep);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$percent%',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
