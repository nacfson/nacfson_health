import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/sheet_state_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/selected_date_provider.dart';
import '../../../../shared/widgets/bottom_nav_shell.dart';
import '../../../../shared/widgets/date_navigation_bar.dart';
import '../../../../shared/widgets/record_form_sheet.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../domain/entities/exercise_record.dart';
import '../providers/exercise_provider.dart';
import '../widgets/exercise_form.dart';
import '../widgets/exercise_group_card.dart';

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
      ref.read(fabActionProvider.notifier).state = () => _openAddSheet(context);
    });
  }

  @override
  void dispose() {
    // ref.read in dispose can throw "used after dispose" during navigation transition
    try {
      ref.read(fabActionProvider.notifier).state = null;
    } catch (_) {}
    super.dispose();
  }

  void _openAddSheet(BuildContext context) {
    openSheet(
      context: context,
      ref: ref,
      type: SheetType.exercise,
      title: '운동 기록 추가',
      child: const RecordFormSheet(
        title: '운동 기록 추가',
        child: ExerciseForm(),
      ),
    );
  }

  void _openEditSheet(BuildContext context, ExerciseRecord record) {
    openSheet(
      context: context,
      ref: ref,
      type: SheetType.exercise,
      title: '운동 기록 수정',
      child: RecordFormSheet(
        title: '운동 기록 수정',
        child: ExerciseForm(initialRecord: record),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped     = ref.watch(selectedDateExerciseGroupedProvider);
    final totalVolume = ref.watch(selectedDateTotalVolumeProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    final isToday     = ref.watch(isSelectedDateTodayProvider);
    final isEmpty     = grouped.isEmpty;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(title: const Text('운동 기록')),
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
          if (isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.fitness_center,
                title: isToday ? '오늘의 운동 기록이 없어요' : '이 날짜의 운동 기록이 없어요',
                subtitle: isToday ? '+ 버튼으로 첫 운동을 기록해보세요' : '다른 날짜를 선택해보세요',
              ),
            )
          else
            for (final typeEntry in grouped.entries) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  exerciseType: typeEntry.key,
                  count: typeEntry.value.values.fold(0, (sum, list) => sum + list.length),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final nameEntry = typeEntry.value.entries.elementAt(i);
                    return ExerciseGroupCard(
                      exerciseName: nameEntry.key,
                      exerciseType: typeEntry.key,
                      records: nameEntry.value,
                      onEdit: (record) => _openEditSheet(context, record),
                      onDelete: (uuid) => ref
                          .read(exerciseRecordsProvider.notifier)
                          .deleteRecord(uuid),
                    );
                  },
                  childCount: typeEntry.value.length,
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
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
    final dateStr = '${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';

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
