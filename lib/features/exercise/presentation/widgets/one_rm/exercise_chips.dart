import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/one_rm_coach_provider.dart';

/// 1RM 코치 풀스크린 상단 종목 선택 칩 가로 스크롤.
/// 데이터 = `topExerciseNamesProvider` (최근 90일 볼륨 상위 8개).
///
/// 선택된 칩이 viewport 밖에 있으면 자동으로 중앙 부근으로 스크롤.
class ExerciseChips extends ConsumerStatefulWidget {
  const ExerciseChips({super.key});

  @override
  ConsumerState<ExerciseChips> createState() => _ExerciseChipsState();
}

class _ExerciseChipsState extends ConsumerState<ExerciseChips> {
  final _scrollController = ScrollController();
  // 종목 이름 → GlobalKey. itemBuilder 가 매 호출마다 새 GlobalKey 를
  // 만들면 ensureVisible 시점에 detach → null context. 영속 매핑이 안전.
  final _itemKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollSelectedIntoView(String? name) {
    if (name == null) return;
    // post-frame: GlobalKey.currentContext 는 build 완료 후만 valid.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _itemKeys[name]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final namesAsync = ref.watch(topExerciseNamesProvider);
    final selected = ref.watch(selectedCoachExerciseProvider);

    ref.listen<String?>(selectedCoachExerciseProvider, (prev, next) {
      if (next != null && next != prev) _scrollSelectedIntoView(next);
    });

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
        // 사용 안 하는 key 정리 (메모리 안정성)
        _itemKeys.removeWhere((k, _) => !names.contains(k));
        // 데이터 도착 직후에도 selected 가 viewport 밖이면 스크롤
        _scrollSelectedIntoView(selected);

        return SizedBox(
          height: 44,
          child: ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: names.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final name = names[i];
              final key = _itemKeys.putIfAbsent(name, () => GlobalKey());
              final isSelected = name == selected;
              return KeyedSubtree(
                key: key,
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: name,
                  child: GestureDetector(
                    onTap: () => ref
                        .read(selectedCoachExerciseProvider.notifier)
                        .state = name,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? cs.inverseSurface : cs.surface,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : cs.outlineVariant,
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
