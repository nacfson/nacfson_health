import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../exercise/domain/entities/pr_summary.dart';
import '../../../exercise/presentation/providers/one_rm_coach_provider.dart';

/// 요약 탭 — 최근 PR 진입 카드.
/// 상위 3종목의 e1RM + 4주 전 대비 변화량.
/// 카드/항목 탭 시 1RM 코치 풀스크린 진입 (해당 종목 기본 선택).
class RecentPrCard extends ConsumerWidget {
  const RecentPrCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mint = isDark ? AppTheme.colorMintDark : AppTheme.colorMintDeep;
    final coral = isDark ? AppTheme.colorCoralDark : AppTheme.colorCoralDeep;

    final prsAsync = ref.watch(topPrsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_outlined, size: 16, color: mint),
                const SizedBox(width: 6),
                Text(
                  '최근 PR',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => context.push('/exercise/coach/one-rm'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          '1RM 코치',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right,
                            size: 16, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            prsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (_, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'PR 데이터를 불러오지 못했어요',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              data: (prs) {
                final visible = prs.where((p) => p.currentE1RM != null).toList();
                if (visible.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '운동 기록을 추가하면 종목별 PR이 표시돼요',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (int i = 0; i < visible.length; i++) ...[
                      _Row(
                        summary: visible[i],
                        mint: mint,
                        coral: coral,
                        onTap: () => context.push(
                          '/exercise/coach/one-rm?exercise=${Uri.encodeComponent(visible[i].exerciseName)}',
                        ),
                      ),
                      if (i < visible.length - 1)
                        Divider(
                          height: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final PrSummary summary;
  final Color mint;
  final Color coral;
  final VoidCallback onTap;
  const _Row({
    required this.summary,
    required this.mint,
    required this.coral,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cur = summary.currentE1RM!;
    final delta = summary.deltaKg;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                summary.exerciseName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${cur.toStringAsFixed(0)}kg',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 70,
              child: delta == null
                  ? Text(
                      '첫 기록',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Text(
                      '${delta >= 0 ? '▲' : '▼'} ${delta.abs().toStringAsFixed(0)}kg',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: delta >= 0 ? mint : coral,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
