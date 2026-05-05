import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/record_form_sheet.dart';
import '../providers/weight_provider.dart';
import 'weight_form.dart';

class WeightInputCard extends ConsumerWidget {
  const WeightInputCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayWeight = ref.watch(todayWeightProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: InkWell(
        onTap: () {
          final formKey = GlobalKey<WeightFormState>();
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            // ShellRoute 의 shellNavigator 위가 아니라 rootNavigator 위로 push 해야
            // BottomNavShell 의 glassmorphic 하단 탭 바가 시트를 가리지 않는다.
            useRootNavigator: true,
            useSafeArea: true,
            builder: (context) => RecordFormSheet(
              title: '체중 수정',
              onConfirmClose: () => _confirmDiscardIfDirty(context, formKey),
              child: WeightForm(key: formKey, initialRecord: todayWeight),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.scale, color: colorScheme.primary, size: 24),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘의 체중',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    todayWeight != null
                        ? '${todayWeight.weight} kg'
                        : '기록 없음',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: todayWeight != null ? colorScheme.primary : colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Icon(
                todayWeight != null ? Icons.edit : Icons.add_circle,
                color: colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDiscardIfDirty(
    BuildContext context,
    GlobalKey<WeightFormState> formKey,
  ) async {
    final state = formKey.currentState;
    if (state == null || !state.isDirty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('작성 중인 내용이 사라집니다'),
        content: const Text('닫을까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속 작성'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}
