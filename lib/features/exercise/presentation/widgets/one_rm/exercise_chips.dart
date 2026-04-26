import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/one_rm_coach_provider.dart';

/// 1RM 코치 풀스크린 상단 종목 선택 칩 가로 스크롤.
/// 데이터 = `topExerciseNamesProvider` (최근 90일 볼륨 상위 8개).
class ExerciseChips extends ConsumerWidget {
  const ExerciseChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final namesAsync = ref.watch(topExerciseNamesProvider);
    final selected = ref.watch(selectedCoachExerciseProvider);

    return namesAsync.when(
      loading: () => const SizedBox(
        height: 44,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => SizedBox(
        height: 44,
        child: Center(
          child: Text(
            '종목을 불러올 수 없어요',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ),
      ),
      data: (names) {
        if (names.isEmpty) {
          return SizedBox(
            height: 44,
            child: Center(
              child: Text(
                '운동 기록을 추가하면 종목이 표시됩니다',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ),
          );
        }
        return SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: names.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final name = names[i];
              final isSelected = name == selected;
              return GestureDetector(
                onTap: () =>
                    ref.read(selectedCoachExerciseProvider.notifier).state = name,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? cs.inverseSurface : cs.surface,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: isSelected ? Colors.transparent : cs.outlineVariant,
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? cs.onInverseSurface
                            : cs.onSurface,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
