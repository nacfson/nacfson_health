import 'package:flutter_test/flutter_test.dart';
import 'package:nacfson_health/core/nutrition/nutrition_calculator.dart';

void main() {
  group('calculateTargets', () {
    test('male 30s 70kg 175cm leanMass → kcal ≈ 2720, protein 126g', () {
      final t = calculateTargets(const NutritionCalculationInput(
        heightCm: 175,
        weightKg: 70,
        gender: UserGender.male,
        ageGroup: AgeGroup.thirties,
        goal: FitnessGoal.leanMass,
      ));
      expect(t.calories, 2720);
      expect(t.protein, 126.0);
      expect(t.fat, 68.0);
      expect(t.carbs, 401.0);
    });

    test('female 30s 60kg 165cm diet → kcal 1510 (no floor)', () {
      final t = calculateTargets(const NutritionCalculationInput(
        heightCm: 165,
        weightKg: 60,
        gender: UserGender.female,
        ageGroup: AgeGroup.thirties,
        goal: FitnessGoal.diet,
      ));
      expect(t.calories, 1510);
      expect(t.protein, 108.0);
    });

    test('bulkUp is exactly 200 kcal above leanMass for same inputs', () {
      const base = NutritionCalculationInput(
        heightCm: 180,
        weightKg: 80,
        gender: UserGender.male,
        ageGroup: AgeGroup.twenties,
        goal: FitnessGoal.leanMass,
      );
      final lean = calculateTargets(base);
      final bulk = calculateTargets(const NutritionCalculationInput(
        heightCm: 180,
        weightKg: 80,
        gender: UserGender.male,
        ageGroup: AgeGroup.twenties,
        goal: FitnessGoal.bulkUp,
      ));
      expect(bulk.calories - lean.calories, 200);
    });

    test('diet 하한 동작: 40kg 여성 diet → 1200 kcal로 clamp', () {
      final t = calculateTargets(const NutritionCalculationInput(
        heightCm: 160,
        weightKg: 40,
        gender: UserGender.female,
        ageGroup: AgeGroup.thirties,
        goal: FitnessGoal.diet,
      ));
      expect(t.calories, 1200);
    });

    test('매크로 합산이 kcal과 근사 (±15 kcal 이내)', () {
      final t = calculateTargets(const NutritionCalculationInput(
        heightCm: 170,
        weightKg: 65,
        gender: UserGender.female,
        ageGroup: AgeGroup.forties,
        goal: FitnessGoal.leanMass,
      ));
      final sumKcal = t.protein * 4 + t.fat * 9 + t.carbs * 4;
      expect((sumKcal - t.calories).abs(), lessThanOrEqualTo(15));
    });

    test('탄수화물은 음수가 되지 않음 (극단 입력)', () {
      final t = calculateTargets(const NutritionCalculationInput(
        heightCm: 150,
        weightKg: 30,
        gender: UserGender.female,
        ageGroup: AgeGroup.fiftiesPlus,
        goal: FitnessGoal.diet,
      ));
      expect(t.carbs, greaterThanOrEqualTo(0));
    });

    test('weightKg ≤ 0 → ArgumentError', () {
      expect(
        () => calculateTargets(const NutritionCalculationInput(
          heightCm: 170,
          weightKg: 0,
          gender: UserGender.male,
          ageGroup: AgeGroup.thirties,
          goal: FitnessGoal.leanMass,
        )),
        throwsArgumentError,
      );
    });

    test('heightCm ≤ 0 → ArgumentError', () {
      expect(
        () => calculateTargets(const NutritionCalculationInput(
          heightCm: 0,
          weightKg: 70,
          gender: UserGender.male,
          ageGroup: AgeGroup.thirties,
          goal: FitnessGoal.leanMass,
        )),
        throwsArgumentError,
      );
    });
  });

  group('FitnessGoalX', () {
    test('prefsKey 왕복', () {
      for (final goal in FitnessGoal.values) {
        expect(FitnessGoalX.fromPrefsKey(goal.prefsKey), goal);
      }
    });

    test('fromPrefsKey: unknown → fallback', () {
      expect(
        FitnessGoalX.fromPrefsKey('unknown'),
        FitnessGoal.leanMass,
      );
      expect(
        FitnessGoalX.fromPrefsKey(null, fallback: FitnessGoal.diet),
        FitnessGoal.diet,
      );
    });

    test('label is Korean', () {
      expect(FitnessGoal.diet.label, '다이어트');
      expect(FitnessGoal.leanMass.label, '린매스업');
      expect(FitnessGoal.bulkUp.label, '벌크업');
    });
  });

  group('UserGenderX', () {
    test('prefsKey 왕복', () {
      for (final g in UserGender.values) {
        expect(UserGenderX.fromPrefsKey(g.prefsKey), g);
      }
    });
  });

  group('AgeGroupX', () {
    test('prefsKey 왕복', () {
      for (final a in AgeGroup.values) {
        expect(AgeGroupX.fromPrefsKey(a.prefsKey), a);
      }
    });

    test('midpointAge는 정해진 값', () {
      expect(AgeGroup.twenties.midpointAge, 25);
      expect(AgeGroup.thirties.midpointAge, 35);
      expect(AgeGroup.forties.midpointAge, 45);
      expect(AgeGroup.fiftiesPlus.midpointAge, 55);
    });
  });
}
