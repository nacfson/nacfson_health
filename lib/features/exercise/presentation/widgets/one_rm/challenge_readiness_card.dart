import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/training/challenge_readiness.dart';

/// "1RM 도전 가이드" 카드 — 신호등(녹/황/적/회) + 헤드라인 + 사유 한 줄.
///
/// HTML의 "근력/근비대/근지구력 권장 무게 3행"을 대체.
/// 무게를 처방하지 않고 도전 시점의 적절성만 안내.
class ChallengeReadinessCard extends StatelessWidget {
  final ReadinessAssessment assessment;
  const ChallengeReadinessCard({super.key, required this.assessment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final colors = _signalColors(isDark, assessment.level);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.tint,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: colors.dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assessment.headline,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      assessment.reason,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 0.5, color: cs.outlineVariant),
          const SizedBox(height: 8),
          Text(
            '* 참고용 가이드입니다. 컨디션 · 통증 · 수면 상태도 함께 확인하세요.',
            style: TextStyle(
              fontSize: 10.5,
              color: cs.outline,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  _SignalColors _signalColors(bool isDark, ReadinessLevel level) {
    switch (level) {
      case ReadinessLevel.green:
        return _SignalColors(
          dot: isDark ? AppTheme.colorMintDark : AppTheme.colorMintDeep,
          tint: isDark ? AppTheme.colorMintTintDark : AppTheme.colorMintTint,
        );
      case ReadinessLevel.amber:
        return _SignalColors(
          dot: isDark ? AppTheme.colorCatDietDark : AppTheme.colorCatDiet,
          tint: isDark ? AppTheme.colorWarnBgDark : AppTheme.colorWarnBg,
        );
      case ReadinessLevel.red:
        return _SignalColors(
          dot: isDark ? AppTheme.colorCoralDark : AppTheme.colorCoralDeep,
          tint: isDark ? AppTheme.colorCoralTintDark : AppTheme.colorCoralTint,
        );
      case ReadinessLevel.gray:
        return _SignalColors(
          dot: isDark ? AppTheme.colorTextDimDark : AppTheme.colorTextDim,
          tint: isDark
              ? AppTheme.colorSurfaceAltDark
              : AppTheme.colorSurfaceAlt,
        );
    }
  }
}

class _SignalColors {
  final Color dot;
  final Color tint;
  _SignalColors({required this.dot, required this.tint});
}
