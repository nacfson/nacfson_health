import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../exercise/presentation/providers/rest_timer_provider.dart';

class RestTimerSettingsCard extends ConsumerWidget {
  const RestTimerSettingsCard({super.key});

  static const _options = [60, 90, 120, 180];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(defaultRestSecondsProvider);
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  '기본 휴식 시간',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '운동 세트 저장 후 자동으로 시작되는 휴식 타이머의 기본값입니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _options.map((sec) {
                final selected = current == sec;
                return ChoiceChip(
                  label: Text(_formatLabel(sec)),
                  selected: selected,
                  onSelected: (v) {
                    if (v) {
                      ref
                          .read(defaultRestSecondsProvider.notifier)
                          .set(sec);
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLabel(int seconds) {
    if (seconds < 60) return '$seconds초';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '$m분' : '$m분 $s초';
  }
}
