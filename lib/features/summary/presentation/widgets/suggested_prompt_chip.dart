import 'package:flutter/material.dart';

import '../../../../core/ai/coach_chat_models.dart';

class SuggestedPromptChip extends StatelessWidget {
  final SuggestedPrompt prompt;
  final VoidCallback onTap;
  final bool enabled;

  const SuggestedPromptChip({
    super.key,
    required this.prompt,
    required this.onTap,
    this.enabled = true,
  });

  IconData _categoryIcon() {
    switch (prompt.category) {
      case PromptCategory.diet:
        return Icons.restaurant_rounded;
      case PromptCategory.macro:
        return Icons.donut_large_rounded;
      case PromptCategory.workout:
        return Icons.fitness_center_rounded;
      case PromptCategory.weight:
        return Icons.monitor_weight_rounded;
      case PromptCategory.routine:
        return Icons.event_repeat_rounded;
      case PromptCategory.motivation:
        return Icons.emoji_events_rounded;
      case PromptCategory.timebased:
        return Icons.schedule_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      onPressed: enabled ? onTap : null,
      avatar: Icon(_categoryIcon(), size: 16, color: cs.primary),
      label: Text(
        prompt.label,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: cs.surface,
      side: BorderSide(color: cs.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
  }
}

/// 어시스턴트 답변 바로 아래에 표시되는 follow-up 문자열 칩.
class FollowUpChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final bool enabled;

  const FollowUpChip({
    super.key,
    required this.text,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      onPressed: enabled ? onTap : null,
      label: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: cs.secondaryContainer,
      side: BorderSide.none,
    );
  }
}
