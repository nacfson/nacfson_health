import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/workout_routine.dart';
import '../providers/routine_planner_provider.dart';
import '../providers/workout_routine_provider.dart';

/// 저장된 루틴 프리셋 시트. 탭하면 오늘 루틴에 불러오고, 메뉴에서 이름 변경/삭제.
Future<void> showRoutinePresetSheet({
  required BuildContext context,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _RoutinePresetSheet(),
  );
}

class _RoutinePresetSheet extends ConsumerWidget {
  const _RoutinePresetSheet();

  Future<_LoadAction?> _confirmLoad(
      BuildContext context, WorkoutRoutine routine) {
    return showDialog<_LoadAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('"${routine.name}" 불러오기'),
        content: const Text('현재 오늘 루틴에 운동이 있습니다. 어떻게 할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _LoadAction.append),
            child: const Text('추가'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _LoadAction.replace),
            child: const Text('교체'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, WorkoutRoutine r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('프리셋 삭제'),
        content: Text('"${r.name}" 루틴을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(workoutRoutinesProvider.notifier).deletePreset(r.uuid);
    }
  }

  Future<void> _renamePrompt(
      BuildContext context, WidgetRef ref, WorkoutRoutine r) async {
    final controller = TextEditingController(text: r.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('루틴 이름 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '루틴 이름'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != r.name) {
      await ref
          .read(workoutRoutinesProvider.notifier)
          .renamePreset(r.uuid, newName);
    }
  }

  Future<void> _loadPreset(
      BuildContext context, WidgetRef ref, WorkoutRoutine r) async {
    final planner = ref.read(routinePlannerProvider.notifier);
    final current = ref.read(routinePlannerProvider);
    if (current.isEmpty) {
      await planner.replaceAll(r.items);
    } else {
      final action = await _confirmLoad(context, r);
      if (action == null) return;
      if (action == _LoadAction.replace) {
        await planner.replaceAll(r.items);
      } else {
        await planner.appendMany(r.items);
      }
    }
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final routines = ref.watch(workoutRoutinesProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: cs.outlineVariant),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8, bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '저장된 루틴',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      color: cs.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close,
                          size: 20, color: cs.onSurfaceVariant),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: routines.isEmpty
                    ? _Empty(cs: cs)
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: routines.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.4),
                        ),
                        itemBuilder: (context, i) {
                          final r = routines[i];
                          return Dismissible(
                            key: ValueKey(r.uuid),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) async {
                              await _confirmDelete(context, ref, r);
                              return false;
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: cs.errorContainer,
                              child: Icon(Icons.delete_outline,
                                  color: cs.onErrorContainer),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              title: Text(r.name),
                              subtitle: Text(
                                '운동 ${r.items.length}개 · ${_formatDate(r.createdAt)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (v) async {
                                  if (v == 'rename') {
                                    await _renamePrompt(context, ref, r);
                                  } else if (v == 'delete') {
                                    await _confirmDelete(context, ref, r);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('이름 변경'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('삭제'),
                                  ),
                                ],
                              ),
                              onTap: () => _loadPreset(context, ref, r),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}

enum _LoadAction { replace, append }

class _Empty extends StatelessWidget {
  final ColorScheme cs;
  const _Empty({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bookmark_border, size: 40, color: cs.outline),
          const SizedBox(height: 12),
          Text(
            '저장된 루틴이 없습니다.\n오늘 루틴을 구성한 뒤 "루틴으로 저장"을 눌러보세요.',
            style: TextStyle(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
