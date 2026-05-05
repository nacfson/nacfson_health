import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/training/challenge_readiness.dart';
import '../../domain/entities/pr_summary.dart';
import '../providers/master_data_provider.dart';
import '../providers/one_rm_coach_provider.dart';
import '../widgets/exercise_progression_sheet.dart';
import '../widgets/one_rm/challenge_readiness_card.dart';
import '../widgets/one_rm/coach_note_card.dart';
import '../widgets/one_rm/current_e1rm_card.dart';
import '../widgets/one_rm/exercise_chips.dart';
import '../widgets/one_rm/percent_of_one_rm_table.dart';

/// 1RM 코치 풀스크린.
///
/// 진입 경로: 운동 탭 AppBar [⚡] / ExerciseGroupCard e1RM 칩 / ProgressionSheet 버튼 / 요약 탭 RecentPrCard.
/// [initialExerciseName] 이 주어지면 해당 종목으로 시작.
class OneRMCoachScreen extends ConsumerStatefulWidget {
  final String? initialExerciseName;

  const OneRMCoachScreen({super.key, this.initialExerciseName});

  @override
  ConsumerState<OneRMCoachScreen> createState() => _OneRMCoachScreenState();
}

class _OneRMCoachScreenState extends ConsumerState<OneRMCoachScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // v12: 1RM 코치 진입 시 master data TTL 24h fetch trigger.
      // 오프라인이면 SQLite 캐시 사용, 첫 설치라면 Supabase 호출 1회.
      ref.read(masterDataBundleProvider);
      _initSelectedExercise();
    });
  }

  Future<void> _initSelectedExercise() async {
    if (widget.initialExerciseName != null &&
        widget.initialExerciseName!.isNotEmpty) {
      ref.read(selectedCoachExerciseProvider.notifier).state =
          widget.initialExerciseName;
      return;
    }
    // query param 미지정 → 후보 목록 첫 항목으로
    final names = await ref.read(topExerciseNamesProvider.future);
    if (!mounted) return;
    final current = ref.read(selectedCoachExerciseProvider);
    if (current == null && names.isNotEmpty) {
      ref.read(selectedCoachExerciseProvider.notifier).state = names.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = ref.watch(selectedCoachExerciseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('1RM 코치'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '닫기',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            const ExerciseChips(),
            const SizedBox(height: 16),
            if (selected == null)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    '종목을 선택해 주세요',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              _Body(exerciseName: selected),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final String exerciseName;
  const _Body({required this.exerciseName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final summaryAsync = ref.watch(prSummaryProvider(exerciseName));

    return summaryAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'PR 데이터를 불러오지 못했어요',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      ),
      data: (summary) {
        final readiness = assessReadiness(ReadinessInput(
          weeklyHistory: summary.weeklyHistory,
          recentWorkSetCount: summary.recentWorkSetCount,
          recentRpeAvg: summary.recentRpeAvg,
          recentFailureCount: summary.recentFailureCount,
        ));

        final e1RM = summary.currentE1RM;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CurrentE1RMCard(summary: summary),
              const SizedBox(height: 18),

              _SectionLabel('1RM 도전 가이드'),
              const SizedBox(height: 8),
              ChallengeReadinessCard(assessment: readiness),
              const SizedBox(height: 18),

              _SectionLabel('% of 1RM 환산표'),
              const SizedBox(height: 8),
              if (e1RM != null)
                PercentOfOneRMTable(e1RM: e1RM)
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: cs.outlineVariant, width: 0.5),
                  ),
                  child: Text(
                    '운동 기록을 추가하면 환산표가 표시됩니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 18),

              if (summary.currentE1RM != null) ...[
                CoachNoteCard(
                  request: CoachNoteRequest(
                    exerciseName: exerciseName,
                    currentE1RM: summary.currentE1RM!,
                    deltaKg: summary.deltaKg,
                    readiness: readiness.level,
                  ),
                ),
                const SizedBox(height: 14),
              ],

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openRecentSessions(context, summary),
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: const Text('최근 기록 보기'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

/// "최근 기록 보기" → 종목별 ProgressionSheet 오픈.
/// PrSummary 에 exerciseType 이 있으면 그대로 사용, 없으면 사용자에게 안내.
void _openRecentSessions(BuildContext context, PrSummary summary) {
  final type = summary.exerciseType;
  if (type == null || type.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('이 종목에 대한 기록이 아직 충분하지 않아요'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }
  showExerciseProgressionSheet(
    context,
    exerciseType: type,
    exerciseName: summary.exerciseName,
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
