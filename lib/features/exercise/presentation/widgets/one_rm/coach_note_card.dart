import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../providers/one_rm_coach_provider.dart';

/// AI 코치 노트 — Gemini 응답을 코랄 톤 카드로 표시.
/// 데이터가 부족하면 표시하지 않음 (Screen 측에서 conditional render).
class CoachNoteCard extends ConsumerWidget {
  final CoachNoteRequest request;
  const CoachNoteCard({super.key, required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coral = isDark ? AppTheme.colorCoralDark : AppTheme.colorCoralDeep;
    final coralTint =
        isDark ? AppTheme.colorCoralTintDark : AppTheme.colorCoralTint;

    final noteAsync = ref.watch(oneRmCoachNoteProvider(request));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: coralTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: coral,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.psychology_outlined,
                size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '코치 노트',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: coral,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                noteAsync.when(
                  loading: () => SizedBox(
                    height: 18,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: coral,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '코치 노트를 불러오는 중…',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  error: (_, _) => Text(
                    '코치 노트를 불러오지 못했어요.',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  data: (text) => Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      letterSpacing: -0.2,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
