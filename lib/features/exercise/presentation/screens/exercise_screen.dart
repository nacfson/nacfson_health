import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/selected_date_provider.dart';
import '../../../../shared/widgets/bottom_nav_shell.dart';
import '../../../../shared/widgets/date_navigation_bar.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/template_picker_sheet.dart';
import '../../../settings/domain/entities/exercise_template.dart';
import '../../../settings/presentation/providers/exercise_template_provider.dart';
import '../../domain/entities/exercise_record.dart';
import '../../domain/entities/routine_item.dart';
import '../providers/exercise_provider.dart';
import '../providers/routine_planner_provider.dart';
import '../providers/workout_routine_provider.dart';
import '../widgets/exercise_group_card.dart';
import '../widgets/routine_preset_sheet.dart';

class ExerciseScreen extends ConsumerStatefulWidget {
  const ExerciseScreen({super.key});

  @override
  ConsumerState<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends ConsumerState<ExerciseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(fabActionProvider.notifier).state =
          () => _openTemplatePickerForRoutine();
    });
  }

  @override
  void dispose() {
    try {
      ref.read(fabActionProvider.notifier).state = null;
    } catch (_) {}
    super.dispose();
  }

  Future<void> _openTemplatePickerForRoutine() async {
    final templates = ref.read(exerciseTemplatesProvider);
    final picked = await showTemplatePickerSheet<ExerciseTemplate>(
      context: context,
      title: '오늘 루틴에 추가',
      templates: templates,
      labelOf: (t) => t.name,
      groupKeyOf: (t) => t.exerciseType,
      emptyHint: '등록된 운동 템플릿이 없습니다.\n설정에서 자주 하는 운동을 템플릿으로 추가해 보세요.',
      onEmptyAction: () => context.push('/settings'),
    );
    if (picked != null && mounted) {
      await ref.read(routinePlannerProvider.notifier).addItem(
            RoutineItem(
              exerciseType: picked.exerciseType,
              exerciseName: picked.name,
            ),
          );
    }
  }

  Future<void> _openSavePresetDialog() async {
    final routine = ref.read(routinePlannerProvider);
    if (routine.isEmpty) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('현재 루틴 저장'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '루틴 이름',
            hintText: '예: 가슴 & 삼두',
          ),
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
    if (name != null && name.isNotEmpty && mounted) {
      await ref
          .read(workoutRoutinesProvider.notifier)
          .savePreset(name, routine);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$name" 루틴이 저장되었습니다'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final isToday = ref.watch(isSelectedDateTodayProvider);
    final totalVolume = ref.watch(selectedDateTotalVolumeProvider);

    final cards = isToday ? ref.watch(todayExerciseCardsProvider) : null;
    final pastGrouped =
        isToday ? null : ref.watch(selectedDateExerciseGroupedProvider);
    final routinePlanned = isToday ? ref.watch(routinePlannerProvider) : null;
    final isEmpty = isToday
        ? (cards!.isEmpty)
        : (pastGrouped!.isEmpty);

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text('운동 기록'),
        actions: [
          if (isToday)
            IconButton(
              tooltip: '저장된 루틴',
              icon: const Icon(Icons.playlist_play),
              onPressed: () => showRoutinePresetSheet(context: context),
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: DateNavigationBar()),
          SliverToBoxAdapter(
            child: _ExerciseSummaryCard(
              date: selectedDate,
              totalVolume: totalVolume,
              isToday: isToday,
            ),
          ),
          if (isToday && (routinePlanned?.isNotEmpty ?? false))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('루틴으로 저장'),
                    onPressed: _openSavePresetDialog,
                  ),
                ),
              ),
            ),
          if (isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: isToday
                  ? _TodayEmptyState(
                      onAdd: _openTemplatePickerForRoutine,
                      onLoadRoutine: () =>
                          showRoutinePresetSheet(context: context),
                    )
                  : const EmptyState(
                      icon: Icons.fitness_center,
                      title: '이 날짜의 운동 기록이 없어요',
                      subtitle: '다른 날짜를 선택해보세요',
                    ),
            )
          else if (isToday)
            ..._buildCardSlivers(cards!)
          else
            ..._buildPastSlivers(pastGrouped!),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  List<Widget> _buildCardSlivers(List<ExerciseCardData> cards) {
    // 카드를 부위별로 묶어 섹션 헤더와 함께 렌더링
    const typeOrder = ['가슴', '등', '하체', '어깨', '팔', '코어', '유산소', '기타'];
    final byType = <String, List<ExerciseCardData>>{};
    for (final c in cards) {
      byType.putIfAbsent(c.exerciseType, () => []).add(c);
    }
    final orderedTypes = [
      ...typeOrder.where(byType.containsKey),
      ...byType.keys.where((k) => !typeOrder.contains(k)),
    ];

    final slivers = <Widget>[];
    for (final type in orderedTypes) {
      final list = byType[type]!;
      slivers.add(SliverToBoxAdapter(
        child: _SectionHeader(exerciseType: type, count: list.length),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            final c = list[i];
            return ExerciseGroupCard(
              key: ValueKey('today-${c.exerciseName}'),
              exerciseName: c.exerciseName,
              exerciseType: c.exerciseType,
              records: c.records,
              editable: true,
              onRemoveFromRoutine: () => ref
                  .read(routinePlannerProvider.notifier)
                  .removeByName(c.exerciseName),
              onDelete: (uuid) => ref
                  .read(exerciseRecordsProvider.notifier)
                  .deleteSetAndRenumber(uuid),
            );
          },
          childCount: list.length,
        ),
      ));
    }
    return slivers;
  }

  List<Widget> _buildPastSlivers(
      Map<String, Map<String, List<ExerciseRecord>>> grouped) {
    final slivers = <Widget>[];
    for (final typeEntry in grouped.entries) {
      slivers.add(SliverToBoxAdapter(
        child: _SectionHeader(
          exerciseType: typeEntry.key,
          count: typeEntry.value.values
              .fold(0, (sum, list) => sum + list.length),
        ),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            final nameEntry = typeEntry.value.entries.elementAt(i);
            return ExerciseGroupCard(
              key: ValueKey('past-${typeEntry.key}-${nameEntry.key}'),
              exerciseName: nameEntry.key,
              exerciseType: typeEntry.key,
              records: nameEntry.value,
              editable: false,
            );
          },
          childCount: typeEntry.value.length,
        ),
      ));
    }
    return slivers;
  }
}

// ── 오늘 빈 상태 ──────────────────────────────────────────────────────────────

class _TodayEmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onLoadRoutine;
  const _TodayEmptyState({required this.onAdd, required this.onLoadRoutine});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.fitness_center, size: 56, color: cs.outline),
          const SizedBox(height: 16),
          Text(
            '오늘의 운동 기록이 없어요',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '템플릿으로 오늘 루틴을 구성하거나,\n저장된 루틴을 불러오세요',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('운동 추가'),
                onPressed: onAdd,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.playlist_play),
                label: const Text('루틴 불러오기'),
                onPressed: onLoadRoutine,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 운동 요약 카드 ────────────────────────────────────────────────────────────

class _ExerciseSummaryCard extends StatelessWidget {
  final DateTime date;
  final double totalVolume;
  final bool isToday;
  const _ExerciseSummaryCard({
    required this.date,
    required this.totalVolume,
    required this.isToday,
  });

  String _formatVolume(double v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final dateStr =
        '${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.colorNavy,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppTheme.colorNavy.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isToday ? '오늘' : dateStr,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.colorMint,
                  letterSpacing: -0.3,
                ),
              ),
              if (isToday)
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '총 볼륨',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.colorTextDim,
                ),
              ),
              Text(
                totalVolume == 0 ? '—' : '${_formatVolume(totalVolume)} kg',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.colorMint,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 섹션 헤더 ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String exerciseType;
  final int count;
  const _SectionHeader({required this.exerciseType, required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.colorMintDark : AppTheme.colorMint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            exerciseType,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            '$count개',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
