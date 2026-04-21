import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/diet/domain/entities/diet_record.dart';
import '../../features/diet/presentation/providers/diet_provider.dart';
import '../../features/exercise/domain/entities/exercise_record.dart';
import '../../features/exercise/presentation/providers/exercise_provider.dart';
import '../../features/summary/domain/entities/daily_summary.dart';
import '../../features/summary/presentation/providers/summary_provider.dart';
import '../../features/weight/domain/entities/weight_record.dart';
import '../../features/weight/presentation/providers/weight_provider.dart';
import 'coach_chat_models.dart';

/// 챗봇 진입 시 노출되는 추천 칩 목록 (규칙 기반, Gemini 호출 0건).
///
/// 사용자 건강 데이터의 다양한 신호를 7개 카테고리에 걸쳐 평가하고,
/// 우선순위와 카테고리 다양성 규칙에 따라 최대 5개를 선별한다.
/// 어떤 규칙도 매칭되지 않으면 fallback 칩 3개를 반환한다.
final suggestedPromptsProvider = Provider<List<SuggestedPrompt>>((ref) {
  return evaluateSuggestedPrompts(
    now: DateTime.now(),
    summary: ref.watch(dailySummaryProvider),
    diets: ref.watch(dietRecordsProvider),
    exercises: ref.watch(exerciseRecordsProvider),
    latestWeight: ref.watch(latestWeightProvider),
    allWeights: ref.watch(weightRecordsProvider),
  );
});

/// 순수 함수 — 테스트 용이성을 위해 Provider 에서 분리.
///
/// 주어진 데이터 스냅샷에 대해 모든 규칙을 평가하고, 우선순위·카테고리 다양성을
/// 적용해 최대 5개의 추천 칩을 반환한다. 아무 규칙도 매칭되지 않으면 fallback.
List<SuggestedPrompt> evaluateSuggestedPrompts({
  required DateTime now,
  required DailySummary summary,
  required List<DietRecord> diets,
  required List<ExerciseRecord> exercises,
  required WeightRecord? latestWeight,
  required List<WeightRecord> allWeights,
}) {
  final ctx = _RuleContext(
    now: now,
    summary: summary,
    diets: diets,
    exercises: exercises,
    latestWeight: latestWeight,
    allWeights: allWeights,
  );
  final candidates = <_PromptCandidate>[];
  for (final rule in _rules) {
    final c = rule.evaluate(ctx);
    if (c != null) candidates.add(c);
  }

  // `_DietMissingTodayRule` 은 오늘 식단이 비기만 하면 매칭되므로, 신규
  // 사용자(데이터 0)에서 단독으로 1개만 노출되는 어색한 상태가 발생한다.
  // 다른 의미 있는 신호가 하나도 없으면 fallback 3개로 대체한다.
  final meaningful = candidates
      .where((c) => c.prompt.id != 'diet.missing_today')
      .toList();
  if (meaningful.isEmpty) return _fallbackPrompts();

  return _rank(candidates);
}

// ─────────────────────────────────────────────────────────────────────────────
// 규칙 컨텍스트 & 베이스 클래스
// ─────────────────────────────────────────────────────────────────────────────

class _RuleContext {
  final DateTime now;
  final DailySummary summary;
  final List<DietRecord> diets;
  final List<ExerciseRecord> exercises;
  final WeightRecord? latestWeight;
  final List<WeightRecord> allWeights;

  _RuleContext({
    required this.now,
    required this.summary,
    required this.diets,
    required this.exercises,
    required this.latestWeight,
    required this.allWeights,
  });

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<DietRecord> get todayDiets =>
      diets.where((d) => _isSameDay(d.timestamp, now)).toList();

  List<ExerciseRecord> get todayExercises =>
      exercises.where((e) => _isSameDay(e.timestamp, now)).toList();

  /// 최근 N일간 운동 기록 (오늘 포함).
  List<ExerciseRecord> exercisesInLastDays(int days) {
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    return exercises.where((e) => !e.timestamp.isBefore(start)).toList();
  }

  /// 최근 N일간 식단 기록.
  List<DietRecord> dietsInLastDays(int days) {
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    return diets.where((d) => !d.timestamp.isBefore(start)).toList();
  }
}

class _PromptCandidate {
  final SuggestedPrompt prompt;
  final int priority;
  const _PromptCandidate({required this.prompt, required this.priority});
}

abstract class _PromptRule {
  const _PromptRule();
  _PromptCandidate? evaluate(_RuleContext ctx);
}

// ─────────────────────────────────────────────────────────────────────────────
// 랭킹 & Fallback
// ─────────────────────────────────────────────────────────────────────────────

/// priority 내림차순 + 카테고리 다양성(연속 2개 초과 금지) + 최대 5개.
List<SuggestedPrompt> _rank(List<_PromptCandidate> candidates) {
  final sorted = [...candidates]
    ..sort((a, b) => b.priority.compareTo(a.priority));

  final selected = <SuggestedPrompt>[];
  final remaining = [...sorted];

  while (selected.length < 5 && remaining.isNotEmpty) {
    // 직전 2개와 같은 카테고리는 건너뛰고 다음 후보 시도
    final skipCategory = selected.length >= 2 &&
            selected[selected.length - 1].category ==
                selected[selected.length - 2].category
        ? selected.last.category
        : null;

    final idx = skipCategory == null
        ? 0
        : remaining.indexWhere((c) => c.prompt.category != skipCategory);

    if (idx == -1) {
      // 다양성 제약을 만족하는 후보가 없으면 그냥 상단 후보 선택
      selected.add(remaining.removeAt(0).prompt);
    } else {
      selected.add(remaining.removeAt(idx).prompt);
    }
  }

  return selected;
}

List<SuggestedPrompt> _fallbackPrompts() => const [
      SuggestedPrompt(
        id: 'fallback.today_health',
        label: '오늘 내 하루 건강 총평',
        fullPrompt:
            '오늘 기록된 식단/운동/체중 데이터를 종합해 내 하루 건강을 간단히 총평해줘. 200자 이내, 따뜻한 코치 말투.',
        category: PromptCategory.motivation,
      ),
      SuggestedPrompt(
        id: 'fallback.weekly_workout',
        label: '이번 주 운동 개선 포인트',
        fullPrompt:
            '이번 주 운동 기록을 보고 개선하면 좋을 포인트 2-3가지 알려줘. 200자 이내.',
        category: PromptCategory.workout,
      ),
      SuggestedPrompt(
        id: 'fallback.snack',
        label: '지금 먹으면 좋은 간식 추천',
        fullPrompt:
            '지금 시간대와 오늘 남은 매크로 목표를 고려해 먹기 좋은 간식 3가지를 추천해줘. 각 1줄씩.',
        category: PromptCategory.diet,
      ),
    ];

// ─────────────────────────────────────────────────────────────────────────────
// 🍱 식단 규칙
// ─────────────────────────────────────────────────────────────────────────────

class _DietMissingTodayRule extends _PromptRule {
  const _DietMissingTodayRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    if (ctx.todayDiets.isNotEmpty) return null;
    return const _PromptCandidate(
      priority: 110,
      prompt: SuggestedPrompt(
        id: 'diet.missing_today',
        label: '오늘 먹은 것 빠르게 기록하기',
        fullPrompt: '', // navigation — AI 호출 안 함
        category: PromptCategory.diet,
        kind: SuggestedPromptKind.navigation,
      ),
    );
  }
}

class _CalorieOverRule extends _PromptRule {
  const _CalorieOverRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final diet = ctx.summary.dietNutrition;
    if (diet == null) return null;
    final over = diet.consumedCalories - diet.targetCalories;
    if (over < 300) return null;
    return _PromptCandidate(
      priority: 85,
      prompt: SuggestedPrompt(
        id: 'diet.cal_over',
        label: '칼로리 초과 원인 분석',
        fullPrompt:
            '오늘 칼로리를 목표보다 ${over}kcal 초과했어. 원인과 내일 식단 조절 팁을 200자 이내로 알려줘.',
        category: PromptCategory.diet,
      ),
    );
  }
}

class _CalorieUnderEveningRule extends _PromptRule {
  const _CalorieUnderEveningRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final diet = ctx.summary.dietNutrition;
    if (diet == null || diet.targetCalories <= 0) return null;
    final ratio = diet.consumedCalories / diet.targetCalories;
    if (ratio >= 0.6) return null;
    if (ctx.now.hour < 19) return null;
    final need = diet.targetCalories - diet.consumedCalories;
    return _PromptCandidate(
      priority: 75,
      prompt: SuggestedPrompt(
        id: 'diet.cal_under',
        label: '저녁에 가볍게 채울 음식 추천',
        fullPrompt:
            '오늘 칼로리 목표가 ${need}kcal 남았어. 지금 시간에 가볍게 먹을 한식 3가지를 추천해줘.',
        category: PromptCategory.diet,
      ),
    );
  }
}

class _DietRepetitiveRule extends _PromptRule {
  const _DietRepetitiveRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final weekly = ctx.dietsInLastDays(7);
    if (weekly.length < 10) return null;
    final counts = <String, int>{};
    for (final d in weekly) {
      counts[d.foodName] = (counts[d.foodName] ?? 0) + 1;
    }
    final entry =
        counts.entries.fold<MapEntry<String, int>?>(null, (acc, e) {
      if (acc == null || e.value > acc.value) return e;
      return acc;
    });
    if (entry == null || entry.value < 5) return null;
    return _PromptCandidate(
      priority: 40,
      prompt: SuggestedPrompt(
        id: 'diet.repetitive',
        label: '식단 다양성 개선 제안',
        fullPrompt:
            '최근 7일간 "${entry.key}"를 ${entry.value}회나 먹었어. 비슷한 영양소로 대체할 만한 음식 3가지를 알려줘.',
        category: PromptCategory.diet,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 🥗 매크로 규칙
// ─────────────────────────────────────────────────────────────────────────────

class _ProteinLowRule extends _PromptRule {
  const _ProteinLowRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final p = ctx.summary.dietNutrition?.macroStatus['protein'];
    if (p == null || p.target <= 0) return null;
    if (p.consumed >= p.target * 0.7) return null;
    final need = (p.target - p.consumed).round();
    return _PromptCandidate(
      priority: 80,
      prompt: SuggestedPrompt(
        id: 'macro.protein_low',
        label: '부족한 단백질 ${need}g 채울 한식',
        fullPrompt:
            '오늘 단백질 섭취 ${p.consumed.toStringAsFixed(0)}g / 목표 ${p.target.toStringAsFixed(0)}g. 부족한 ${need}g을 채울 한식 3가지를 1인분 단백질량과 함께 추천해줘. 200자 이내.',
        category: PromptCategory.macro,
      ),
    );
  }
}

class _ProteinHighRule extends _PromptRule {
  const _ProteinHighRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final p = ctx.summary.dietNutrition?.macroStatus['protein'];
    if (p == null || p.target <= 0) return null;
    if (p.consumed <= p.target * 1.3) return null;
    return const _PromptCandidate(
      priority: 35,
      prompt: SuggestedPrompt(
        id: 'macro.protein_high',
        label: '단백질 과다 시 주의할 점',
        fullPrompt: '오늘 단백질 목표의 130%를 넘겼어. 과다 섭취 시 주의사항 간단히 알려줘. 200자 이내.',
        category: PromptCategory.macro,
      ),
    );
  }
}

class _CarbLowWorkoutRule extends _PromptRule {
  const _CarbLowWorkoutRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final c = ctx.summary.dietNutrition?.macroStatus['carbs'];
    if (c == null || c.target <= 0) return null;
    if (c.consumed >= c.target * 0.5) return null;
    final isWorkoutDay =
        ctx.summary.workoutPerformance?.isWorkoutDay ?? false;
    if (!isWorkoutDay) return null;
    return const _PromptCandidate(
      priority: 70,
      prompt: SuggestedPrompt(
        id: 'macro.carb_low',
        label: '운동 전 탄수화물 간식 추천',
        fullPrompt:
            '오늘 탄수화물이 목표의 50% 미만이고 운동일이야. 운동 전에 먹기 좋은 빠른 탄수화물 간식 3가지 추천해줘. 200자 이내.',
        category: PromptCategory.macro,
      ),
    );
  }
}

class _FatHighRule extends _PromptRule {
  const _FatHighRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final f = ctx.summary.dietNutrition?.macroStatus['fat'];
    if (f == null || f.target <= 0) return null;
    if (f.consumed <= f.target * 1.3) return null;
    return const _PromptCandidate(
      priority: 45,
      prompt: SuggestedPrompt(
        id: 'macro.fat_high',
        label: '지방 과다 조절 식단 팁',
        fullPrompt: '오늘 지방 섭취가 목표의 130%를 넘겼어. 내일 식단에서 지방을 줄이는 실용 팁 3가지 알려줘.',
        category: PromptCategory.macro,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 💪 운동 규칙
// ─────────────────────────────────────────────────────────────────────────────

class _VolumeDropRule extends _PromptRule {
  const _VolumeDropRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final thisWeek = ctx.exercisesInLastDays(7);
    final lastWeekStart = DateTime(ctx.now.year, ctx.now.month, ctx.now.day)
        .subtract(const Duration(days: 13));
    final lastWeekEnd = DateTime(ctx.now.year, ctx.now.month, ctx.now.day)
        .subtract(const Duration(days: 7));
    final lastWeek = ctx.exercises.where((e) =>
        !e.timestamp.isBefore(lastWeekStart) &&
        e.timestamp.isBefore(lastWeekEnd));

    final thisVol = thisWeek
        .where((e) => e.countsTowardVolume)
        .fold<double>(0, (s, e) => s + e.volume);
    final lastVol = lastWeek
        .where((e) => e.countsTowardVolume)
        .fold<double>(0, (s, e) => s + e.volume);
    if (lastVol < 100) return null; // 비교 대상 부족
    final dropRatio = (lastVol - thisVol) / lastVol;
    if (dropRatio < 0.2) return null;
    return _PromptCandidate(
      priority: 75,
      prompt: SuggestedPrompt(
        id: 'workout.volume_drop',
        label: '주간 운동량 감소 원인과 회복법',
        fullPrompt:
            '이번 주 운동 볼륨이 전주 대비 ${(dropRatio * 100).round()}% 감소했어. 원인과 회복 전략을 알려줘. 200자 이내.',
        category: PromptCategory.workout,
      ),
    );
  }
}

class _SameMuscle3DaysRule extends _PromptRule {
  const _SameMuscle3DaysRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final days = <DateTime, Set<String>>{};
    for (final e in ctx.exercisesInLastDays(3)) {
      final key = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
      (days[key] ??= <String>{}).add(e.exerciseType);
    }
    if (days.length < 3) return null;
    final muscles = days.values.map((s) => s.toSet()).toList();
    final common = muscles.fold<Set<String>>(
      muscles.first,
      (acc, s) => acc.intersection(s),
    );
    if (common.isEmpty) return null;
    final muscle = common.first;
    return _PromptCandidate(
      priority: 85,
      prompt: SuggestedPrompt(
        id: 'workout.same_muscle_3d',
        label: '과훈련 주의 — 오늘 분할 추천',
        fullPrompt:
            '"$muscle" 부위를 3일 연속 훈련했어. 과훈련 위험과 오늘 다른 부위 분할 루틴을 추천해줘. 200자 이내.',
        category: PromptCategory.workout,
      ),
    );
  }
}

class _RpeHighRule extends _PromptRule {
  const _RpeHighRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final weekly = ctx
        .exercisesInLastDays(7)
        .where((e) => e.countsTowardVolume && e.rpe > 0)
        .toList();
    if (weekly.length < 6) return null;
    final avg = weekly.fold<double>(0, (s, e) => s + e.rpe) / weekly.length;
    if (avg <= 8.5) return null;
    return _PromptCandidate(
      priority: 70,
      prompt: SuggestedPrompt(
        id: 'workout.rpe_high',
        label: '피로 누적 신호 — 디로드 제안',
        fullPrompt:
            '주간 평균 RPE가 ${avg.toStringAsFixed(1)}로 높아. 피로 누적 신호인지, 이번 주 디로드가 필요한지 조언해줘.',
        category: PromptCategory.workout,
      ),
    );
  }
}

class _RpeLowRule extends _PromptRule {
  const _RpeLowRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final weekly = ctx
        .exercisesInLastDays(7)
        .where((e) => e.countsTowardVolume && e.rpe > 0)
        .toList();
    if (weekly.length < 6) return null;
    final avg = weekly.fold<double>(0, (s, e) => s + e.rpe) / weekly.length;
    if (avg >= 6) return null;
    return _PromptCandidate(
      priority: 40,
      prompt: SuggestedPrompt(
        id: 'workout.rpe_low',
        label: '강도 올릴 포인트',
        fullPrompt:
            '주간 평균 RPE가 ${avg.toStringAsFixed(1)}로 낮아. 볼륨이나 강도를 올려야 할 구체적 포인트를 알려줘.',
        category: PromptCategory.workout,
      ),
    );
  }
}

class _RestDayLongRule extends _PromptRule {
  const _RestDayLongRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    if (ctx.exercises.isEmpty) return null;
    final last = ctx.exercises
        .map((e) => e.timestamp)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final daysSince = ctx.now.difference(last).inDays;
    if (daysSince < 4) return null;
    return _PromptCandidate(
      priority: 65,
      prompt: SuggestedPrompt(
        id: 'workout.rest_day_long',
        label: '복귀용 가벼운 루틴 추천',
        fullPrompt:
            '마지막 운동 후 $daysSince일이 지났어. 무리 없이 시작할 복귀 루틴 (전신 3종목, 세트/반복 포함) 추천해줘.',
        category: PromptCategory.workout,
      ),
    );
  }
}

class _TodayMissingWorkoutRule extends _PromptRule {
  const _TodayMissingWorkoutRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    if (ctx.todayExercises.isNotEmpty) return null;
    if (ctx.now.hour < 19) return null;
    return const _PromptCandidate(
      priority: 55,
      prompt: SuggestedPrompt(
        id: 'workout.today_missing',
        label: '짧은 홈트 15분 루틴',
        fullPrompt: '오늘 아직 운동을 못 했어. 집에서 15분 안에 끝내는 전신 홈트 루틴을 종목/세트/반복으로 짜줘.',
        category: PromptCategory.workout,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ⚖️ 체중 규칙
// ─────────────────────────────────────────────────────────────────────────────

class _WeeklyWeightGainRule extends _PromptRule {
  const _WeeklyWeightGainRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final weekly = _weightsInLastDays(ctx, 7);
    if (weekly.length < 2) return null;
    final delta = weekly.last.weight - weekly.first.weight;
    if (delta < 1.0) return null;
    return _PromptCandidate(
      priority: 90,
      prompt: SuggestedPrompt(
        id: 'weight.weekly_gain',
        label: '주간 체중 +${delta.toStringAsFixed(1)}kg 원인',
        fullPrompt:
            '최근 7일간 체중이 +${delta.toStringAsFixed(1)}kg 증가했어. 내 식단/운동 기록을 참고해 원인과 개선법을 알려줘.',
        category: PromptCategory.weight,
      ),
    );
  }
}

class _WeeklyWeightLossRule extends _PromptRule {
  const _WeeklyWeightLossRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final weekly = _weightsInLastDays(ctx, 7);
    if (weekly.length < 2) return null;
    final delta = weekly.last.weight - weekly.first.weight;
    if (delta > -1.0) return null;
    return _PromptCandidate(
      priority: 80,
      prompt: SuggestedPrompt(
        id: 'weight.weekly_loss',
        label: '빠른 감량 건강하게 유지하는 법',
        fullPrompt:
            '최근 7일간 체중이 ${delta.toStringAsFixed(1)}kg 감소했어. 너무 빠르지 않은지, 근손실 없이 유지하는 팁을 알려줘.',
        category: PromptCategory.weight,
      ),
    );
  }
}

class _PlateauRule extends _PromptRule {
  const _PlateauRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final recent = _weightsInLastDays(ctx, 14);
    if (recent.length < 5) return null;
    final max = recent.map((w) => w.weight).reduce(math.max);
    final min = recent.map((w) => w.weight).reduce(math.min);
    if ((max - min) > 0.3) return null;
    return const _PromptCandidate(
      priority: 60,
      prompt: SuggestedPrompt(
        id: 'weight.plateau',
        label: '정체기 돌파 전략',
        fullPrompt: '최근 2주간 체중 변화가 거의 없어. 정체기를 돌파할 구체적 전략 3가지를 알려줘.',
        category: PromptCategory.weight,
      ),
    );
  }
}

class _WeightVarianceRule extends _PromptRule {
  const _WeightVarianceRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    final recent = _weightsInLastDays(ctx, 7);
    if (recent.length < 5) return null;
    final mean =
        recent.fold<double>(0, (s, w) => s + w.weight) / recent.length;
    final variance = recent.fold<double>(
            0, (s, w) => s + math.pow(w.weight - mean, 2).toDouble()) /
        recent.length;
    final std = math.sqrt(variance);
    if (std <= 0.8) return null;
    return _PromptCandidate(
      priority: 50,
      prompt: SuggestedPrompt(
        id: 'weight.high_variance',
        label: '체중 변동성 원인 (수분/염분)',
        fullPrompt:
            '최근 7일 체중 표준편차가 ${std.toStringAsFixed(1)}kg로 변동이 커. 수분/염분/식사량 관점에서 원인을 해석해줘.',
        category: PromptCategory.weight,
      ),
    );
  }
}

class _WeightNoRecord3DRule extends _PromptRule {
  const _WeightNoRecord3DRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    if (ctx.latestWeight == null) return null;
    final daysSince = ctx.now.difference(ctx.latestWeight!.timestamp).inDays;
    if (daysSince < 3) return null;
    return const _PromptCandidate(
      priority: 35,
      prompt: SuggestedPrompt(
        id: 'weight.no_record_3d',
        label: '체중 기록 습관화 팁',
        fullPrompt: '3일 넘게 체중을 안 재고 있어. 꾸준히 기록하는 습관 팁과 측정 원칙 알려줘.',
        category: PromptCategory.weight,
      ),
    );
  }
}

List<WeightRecord> _weightsInLastDays(_RuleContext ctx, int days) {
  final start = DateTime(ctx.now.year, ctx.now.month, ctx.now.day)
      .subtract(Duration(days: days - 1));
  return ctx.allWeights
      .where((w) => !w.timestamp.isBefore(start))
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
}

// ─────────────────────────────────────────────────────────────────────────────
// 🔥 동기부여 & ⏰ 시간대 규칙
// ─────────────────────────────────────────────────────────────────────────────

class _Streak7DaysRule extends _PromptRule {
  const _Streak7DaysRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    int streak = 0;
    for (int i = 0; i < 14; i++) {
      final day = DateTime(ctx.now.year, ctx.now.month, ctx.now.day)
          .subtract(Duration(days: i));
      final has = ctx.diets.any((d) => _sameDay(d.timestamp, day)) ||
          ctx.exercises.any((e) => _sameDay(e.timestamp, day)) ||
          ctx.allWeights.any((w) => _sameDay(w.timestamp, day));
      if (has) {
        streak++;
      } else {
        break;
      }
    }
    if (streak < 7) return null;
    return _PromptCandidate(
      priority: 50,
      prompt: SuggestedPrompt(
        id: 'motivation.streak_7d',
        label: '$streak일 연속! 이번 주 성과 요약',
        fullPrompt: '$streak일 연속으로 기록을 이어가고 있어. 이번 주 성과를 칭찬과 함께 요약해줘.',
        category: PromptCategory.motivation,
      ),
    );
  }
}

class _WeeklyReviewRule extends _PromptRule {
  const _WeeklyReviewRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    if (ctx.now.weekday != DateTime.sunday) return null;
    if (ctx.now.hour < 18) return null;
    return const _PromptCandidate(
      priority: 55,
      prompt: SuggestedPrompt(
        id: 'motivation.weekly_review',
        label: '지난 주 요약 받기',
        fullPrompt: '지난 한 주 식단/운동/체중 기록을 종합한 주간 리포트를 작성해줘. 잘한 점과 개선점 포함.',
        category: PromptCategory.motivation,
      ),
    );
  }
}

class _MorningPlanRule extends _PromptRule {
  const _MorningPlanRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    if (ctx.now.hour < 6 || ctx.now.hour > 9) return null;
    if (ctx.todayDiets.isNotEmpty) return null;
    return const _PromptCandidate(
      priority: 60,
      prompt: SuggestedPrompt(
        id: 'time.morning_plan',
        label: '오늘 하루 추천 식단 플랜',
        fullPrompt: '오늘 하루 아침/점심/저녁/간식을 내 칼로리·매크로 목표에 맞춰 한끼당 1개씩 짜줘.',
        category: PromptCategory.timebased,
      ),
    );
  }
}

class _LateNightCravingRule extends _PromptRule {
  const _LateNightCravingRule();
  @override
  _PromptCandidate? evaluate(_RuleContext ctx) {
    if (ctx.now.hour < 22) return null;
    final diet = ctx.summary.dietNutrition;
    if (diet == null) return null;
    if (diet.consumedCalories <= diet.targetCalories) return null;
    return const _PromptCandidate(
      priority: 65,
      prompt: SuggestedPrompt(
        id: 'time.late_night_craving',
        label: '야식 대신 안전한 대안',
        fullPrompt: '지금 야식이 당기는데 이미 칼로리 목표를 초과했어. 최소한의 죄책감으로 먹을 안전한 대안 3가지 추천해줘.',
        category: PromptCategory.timebased,
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ─────────────────────────────────────────────────────────────────────────────
// 규칙 레지스트리
// ─────────────────────────────────────────────────────────────────────────────

const _rules = <_PromptRule>[
  // 식단
  _DietMissingTodayRule(),
  _CalorieOverRule(),
  _CalorieUnderEveningRule(),
  _DietRepetitiveRule(),
  // 매크로
  _ProteinLowRule(),
  _ProteinHighRule(),
  _CarbLowWorkoutRule(),
  _FatHighRule(),
  // 운동
  _VolumeDropRule(),
  _SameMuscle3DaysRule(),
  _RpeHighRule(),
  _RpeLowRule(),
  _RestDayLongRule(),
  _TodayMissingWorkoutRule(),
  // 체중
  _WeeklyWeightGainRule(),
  _WeeklyWeightLossRule(),
  _PlateauRule(),
  _WeightVarianceRule(),
  _WeightNoRecord3DRule(),
  // 동기부여
  _Streak7DaysRule(),
  _WeeklyReviewRule(),
  // 시간대
  _MorningPlanRule(),
  _LateNightCravingRule(),
];
