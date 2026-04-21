import 'package:flutter_test/flutter_test.dart';
import 'package:nacfson_health/core/ai/coach_chat_models.dart';
import 'package:nacfson_health/core/ai/suggested_prompts_provider.dart';
import 'package:nacfson_health/features/diet/domain/entities/diet_record.dart';
import 'package:nacfson_health/features/exercise/domain/entities/exercise_record.dart';
import 'package:nacfson_health/features/summary/domain/entities/daily_summary.dart';
import 'package:nacfson_health/features/weight/domain/entities/weight_record.dart';

DailySummary _summary({
  DateTime? date,
  DietNutrition? diet,
  WorkoutPerformance? workout,
}) {
  return DailySummary(
    date: date ?? DateTime(2026, 4, 21, 12),
    dietNutrition: diet,
    workoutPerformance: workout,
  );
}

DietNutrition _diet({
  required int consumed,
  required int target,
  double protein = 0,
  double proteinTarget = 100,
  double carbs = 0,
  double carbsTarget = 200,
  double fat = 0,
  double fatTarget = 60,
}) {
  return DietNutrition(
    consumedCalories: consumed,
    targetCalories: target,
    calorieResult: consumed >= target ? CalorieResult.exceeded : CalorieResult.under,
    macroStatus: {
      'protein': MacroInfo(consumed: protein, target: proteinTarget, percentage: 0),
      'carbs': MacroInfo(consumed: carbs, target: carbsTarget, percentage: 0),
      'fat': MacroInfo(consumed: fat, target: fatTarget, percentage: 0),
    },
  );
}

WeightRecord _weight(DateTime ts, double kg) => WeightRecord(
      uuid: ts.toIso8601String(),
      timestamp: ts,
      updatedAt: ts,
      weight: kg,
    );

ExerciseRecord _exercise(DateTime ts, String type, {double rpe = 7, double weight = 100, int reps = 10}) =>
    ExerciseRecord(
      uuid: '${ts.toIso8601String()}-$type',
      timestamp: ts,
      updatedAt: ts,
      exerciseType: type,
      exerciseName: type,
      currentSet: 1,
      weight: weight,
      reps: reps,
      rpe: rpe,
    );

void main() {
  final now = DateTime(2026, 4, 21, 12);

  group('evaluateSuggestedPrompts', () {
    test('데이터 없는 신규 사용자는 fallback 3개를 반환한다', () {
      final result = evaluateSuggestedPrompts(
        now: now,
        summary: _summary(),
        diets: const [],
        exercises: const [],
        latestWeight: null,
        allWeights: const [],
      );
      expect(result.length, 3);
      expect(result.map((p) => p.id), containsAll([
        'fallback.today_health',
        'fallback.weekly_workout',
        'fallback.snack',
      ]));
    });

    test('단백질 70% 미만이면 protein_low 칩이 노출된다', () {
      final result = evaluateSuggestedPrompts(
        now: now,
        summary: _summary(
          diet: _diet(
            consumed: 1500,
            target: 2000,
            protein: 50,
            proteinTarget: 100,
          ),
        ),
        diets: [
          DietRecord(
            uuid: 'd1',
            timestamp: now,
            updatedAt: now,
            mealType: 'lunch',
            foodName: '밥',
            totalCalories: 500,
            carbs: 0,
            protein: 50,
            fat: 0,
            satisfaction: 3,
          ),
        ],
        exercises: const [],
        latestWeight: null,
        allWeights: const [],
      );
      expect(result.any((p) => p.id == 'macro.protein_low'), isTrue);
    });

    test('같은 부위 3일 연속 운동 시 same_muscle_3d 칩 노출', () {
      final result = evaluateSuggestedPrompts(
        now: now,
        summary: _summary(),
        diets: const [],
        exercises: [
          _exercise(now.subtract(const Duration(days: 2)), 'chest'),
          _exercise(now.subtract(const Duration(days: 1)), 'chest'),
          _exercise(now, 'chest'),
        ],
        latestWeight: null,
        allWeights: const [],
      );
      expect(result.any((p) => p.id == 'workout.same_muscle_3d'), isTrue);
    });

    test('주간 체중 +1.5kg 증가 시 weight.weekly_gain 최고 우선순위로 노출', () {
      final result = evaluateSuggestedPrompts(
        now: now,
        summary: _summary(),
        diets: const [],
        exercises: const [],
        latestWeight: _weight(now, 72.5),
        allWeights: [
          _weight(now.subtract(const Duration(days: 6)), 71.0),
          _weight(now, 72.5),
        ],
      );
      expect(result.first.id, 'weight.weekly_gain');
    });

    test('오늘 식단 0개 & 19시 이후 → diet.cal_under 칩 노출', () {
      final evening = DateTime(2026, 4, 21, 20, 30);
      final result = evaluateSuggestedPrompts(
        now: evening,
        summary: _summary(
          diet: _diet(consumed: 800, target: 2000),
        ),
        diets: const [],
        exercises: const [],
        latestWeight: null,
        allWeights: const [],
      );
      expect(result.any((p) => p.id == 'diet.cal_under'), isTrue);
    });

    test('diet.missing_today 는 navigation 타입이며 priority 최상단', () {
      final result = evaluateSuggestedPrompts(
        now: now,
        summary: _summary(),
        diets: const [],
        exercises: const [],
        latestWeight: null,
        allWeights: const [],
      );
      // fallback 상태에서는 missing_today 도 매칭되지만 fallback 이 우선
      final withSignal = evaluateSuggestedPrompts(
        now: now,
        summary: _summary(
          diet: _diet(consumed: 0, target: 2000, protein: 20, proteinTarget: 100),
        ),
        diets: const [],
        exercises: const [],
        latestWeight: null,
        allWeights: const [],
      );
      final missing =
          withSignal.firstWhere((p) => p.id == 'diet.missing_today');
      expect(missing.kind, SuggestedPromptKind.navigation);
      expect(withSignal.first.id, 'diet.missing_today');
    });

    test('최대 5개까지만 반환한다', () {
      final evening = DateTime(2026, 4, 21, 23);
      final result = evaluateSuggestedPrompts(
        now: evening,
        summary: _summary(
          diet: _diet(
            consumed: 2800,
            target: 2000,
            protein: 30,
            proteinTarget: 100,
            carbs: 50,
            carbsTarget: 200,
            fat: 100,
            fatTarget: 60,
          ),
          workout: WorkoutPerformance(
            isWorkoutDay: true,
            targetedMuscles: ['chest'],
            totalVolume: 500,
            averageRpe: 9.0,
          ),
        ),
        diets: const [],
        exercises: [
          for (int i = 0; i < 10; i++)
            _exercise(now.subtract(Duration(days: i)), 'chest', rpe: 9),
        ],
        latestWeight: _weight(now, 73),
        allWeights: [
          _weight(now.subtract(const Duration(days: 6)), 71),
          _weight(now, 73),
        ],
      );
      expect(result.length, lessThanOrEqualTo(5));
    });

    test('카테고리 다양성: 같은 카테고리 3개 연속 금지', () {
      final result = evaluateSuggestedPrompts(
        now: now,
        summary: _summary(
          diet: _diet(
            consumed: 2500,
            target: 2000,
            protein: 30,
            proteinTarget: 100,
            fat: 100,
            fatTarget: 60,
          ),
        ),
        diets: const [],
        exercises: const [],
        latestWeight: null,
        allWeights: const [],
      );
      for (int i = 2; i < result.length; i++) {
        final a = result[i - 2].category;
        final b = result[i - 1].category;
        final c = result[i].category;
        expect(a == b && b == c, isFalse,
            reason: '같은 카테고리가 3개 연속 나타났다: ${result.map((p) => p.category).toList()}');
      }
    });
  });
}
