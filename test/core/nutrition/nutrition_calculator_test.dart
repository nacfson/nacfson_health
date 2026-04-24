import 'package:flutter_test/flutter_test.dart';
import 'package:nacfson_health/core/nutrition/nutrition_calculator.dart';

void main() {
  const baseInput = NutritionCalculationInput(
    heightCm: 175,
    weightKg: 70,
    gender: UserGender.male,
    age: 35,
    goal: FitnessGoal.leanMassGain,
    activityLevel: ActivityLevel.moderate,
    intensity: TrainingIntensity.moderate,
  );

  group('calculateTargets · 기본 케이스', () {
    test('male 35세 70kg 175cm leanGain moderate/moderate → kcal 2720, protein 140', () {
      final t = calculateTargets(baseInput);
      expect(t.calories, 2720);
      expect(t.protein, 140.0);
      expect(t.fat, 68.0);
      expect(t.carbs, 387.0);
    });

    test('female 35세 60kg 165cm diet → 1510 kcal, protein 120', () {
      final t = calculateTargets(const NutritionCalculationInput(
        heightCm: 165,
        weightKg: 60,
        gender: UserGender.female,
        age: 35,
        goal: FitnessGoal.diet,
      ));
      expect(t.calories, 1510);
      expect(t.protein, 120.0);
    });

    test('매크로 합산이 kcal과 근사 (±15 kcal 이내)', () {
      final t = calculateTargets(const NutritionCalculationInput(
        heightCm: 170,
        weightKg: 65,
        gender: UserGender.female,
        age: 45,
        goal: FitnessGoal.leanMassGain,
      ));
      final sumKcal = t.protein * 4 + t.fat * 9 + t.carbs * 4;
      expect((sumKcal - t.calories).abs(), lessThanOrEqualTo(15));
    });

    test('탄수화물은 음수가 되지 않음 (극단 입력)', () {
      final t = calculateTargets(const NutritionCalculationInput(
        heightCm: 150,
        weightKg: 30,
        gender: UserGender.female,
        age: 55,
        goal: FitnessGoal.diet,
      ));
      expect(t.carbs, greaterThanOrEqualTo(0));
    });

    test('diet 하한: 40kg 여성 diet → 1200 kcal로 clamp', () {
      final t = calculateTargets(const NutritionCalculationInput(
        heightCm: 160,
        weightKg: 40,
        gender: UserGender.female,
        age: 35,
        goal: FitnessGoal.diet,
      ));
      expect(t.calories, 1200);
    });
  });

  group('목표별 kcal 조정값', () {
    test('diet TDEE−500 / leanCut TDEE−200 / leanGain TDEE+200 / bulkUp TDEE+500', () {
      final diet = calculateTargets(
          const NutritionCalculationInput(
              heightCm: 175,
              weightKg: 70,
              gender: UserGender.male,
              age: 35,
              goal: FitnessGoal.diet));
      final leanCut = calculateTargets(
          const NutritionCalculationInput(
              heightCm: 175,
              weightKg: 70,
              gender: UserGender.male,
              age: 35,
              goal: FitnessGoal.leanMassCut));
      final leanGain = calculateTargets(
          const NutritionCalculationInput(
              heightCm: 175,
              weightKg: 70,
              gender: UserGender.male,
              age: 35,
              goal: FitnessGoal.leanMassGain));
      final bulk = calculateTargets(
          const NutritionCalculationInput(
              heightCm: 175,
              weightKg: 70,
              gender: UserGender.male,
              age: 35,
              goal: FitnessGoal.bulkUp));

      // 10 단위 반올림 때문에 정확히 300/400/1000 이 되지 않을 수 있어 ±10 허용
      expect((leanGain.calories - leanCut.calories), closeTo(400, 10));
      expect((bulk.calories - leanGain.calories), closeTo(300, 10));
      expect((bulk.calories - diet.calories), closeTo(1000, 10));
    });
  });

  group('ActivityLevel · 활동계수 반영', () {
    test('활동 단계가 올라갈수록 목표 kcal 단조 증가', () {
      int kcalFor(ActivityLevel a) {
        return calculateTargets(NutritionCalculationInput(
          heightCm: 175,
          weightKg: 70,
          gender: UserGender.male,
          age: 30,
          goal: FitnessGoal.leanMassGain,
          activityLevel: a,
        )).calories;
      }

      final seq = ActivityLevel.values.map(kcalFor).toList();
      for (var i = 1; i < seq.length; i++) {
        expect(seq[i], greaterThan(seq[i - 1]),
            reason: '$seq[$i] should be > $seq[${i - 1}]');
      }
    });

    test('multiplier 매핑: 1.2 / 1.375 / 1.55 / 1.725 / 1.9', () {
      expect(ActivityLevel.sedentary.multiplier, 1.2);
      expect(ActivityLevel.light.multiplier, 1.375);
      expect(ActivityLevel.moderate.multiplier, 1.55);
      expect(ActivityLevel.active.multiplier, 1.725);
      expect(ActivityLevel.veryActive.multiplier, 1.9);
    });
  });

  group('TrainingIntensity · 단백질 g/kg 반영', () {
    test('70kg 기준 단백질: low 126 / moderate 140 / high 154 / veryHigh 168', () {
      double proteinFor(TrainingIntensity x) {
        return calculateTargets(NutritionCalculationInput(
          heightCm: 175,
          weightKg: 70,
          gender: UserGender.male,
          age: 30,
          goal: FitnessGoal.leanMassGain,
          intensity: x,
        )).protein;
      }

      expect(proteinFor(TrainingIntensity.low), 126.0);
      expect(proteinFor(TrainingIntensity.moderate), 140.0);
      expect(proteinFor(TrainingIntensity.high), 154.0);
      expect(proteinFor(TrainingIntensity.veryHigh), 168.0);
    });

    test('강도 올라갈수록 단백질 단조 증가', () {
      double proteinFor(TrainingIntensity x) {
        return calculateTargets(NutritionCalculationInput(
          heightCm: 170,
          weightKg: 75,
          gender: UserGender.female,
          age: 40,
          goal: FitnessGoal.leanMassCut,
          intensity: x,
        )).protein;
      }

      final seq = TrainingIntensity.values.map(proteinFor).toList();
      for (var i = 1; i < seq.length; i++) {
        expect(seq[i], greaterThan(seq[i - 1]));
      }
    });
  });

  group('나이 정밀 입력', () {
    test('만 나이 차이가 BMR 차이에 반영 (31 vs 35)', () {
      final at31 = calculateTargets(const NutritionCalculationInput(
        heightCm: 175,
        weightKg: 70,
        gender: UserGender.male,
        age: 31,
        goal: FitnessGoal.leanMassGain,
      ));
      final at35 = calculateTargets(const NutritionCalculationInput(
        heightCm: 175,
        weightKg: 70,
        gender: UserGender.male,
        age: 35,
        goal: FitnessGoal.leanMassGain,
      ));
      expect(at31.calories, greaterThan(at35.calories));
    });
  });

  group('Argument 검증', () {
    test('weightKg ≤ 0 → ArgumentError', () {
      expect(
        () => calculateTargets(const NutritionCalculationInput(
          heightCm: 170,
          weightKg: 0,
          gender: UserGender.male,
          age: 30,
          goal: FitnessGoal.leanMassGain,
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
          age: 30,
          goal: FitnessGoal.leanMassGain,
        )),
        throwsArgumentError,
      );
    });

    test('age ≤ 0 → ArgumentError', () {
      expect(
        () => calculateTargets(const NutritionCalculationInput(
          heightCm: 170,
          weightKg: 70,
          gender: UserGender.male,
          age: 0,
          goal: FitnessGoal.leanMassGain,
        )),
        throwsArgumentError,
      );
    });
  });

  group('FitnessGoalX', () {
    test('prefsKey 왕복 (4개)', () {
      for (final goal in FitnessGoal.values) {
        expect(FitnessGoalX.fromPrefsKey(goal.prefsKey), goal);
      }
    });

    test('하위호환: "lean_mass" → leanMassGain 으로 매핑', () {
      expect(FitnessGoalX.fromPrefsKey('lean_mass'), FitnessGoal.leanMassGain);
    });

    test('unknown → fallback (기본 leanMassGain)', () {
      expect(
        FitnessGoalX.fromPrefsKey('unknown'),
        FitnessGoal.leanMassGain,
      );
      expect(
        FitnessGoalX.fromPrefsKey(null, fallback: FitnessGoal.diet),
        FitnessGoal.diet,
      );
    });

    test('label 는 한글', () {
      expect(FitnessGoal.diet.label, '다이어트');
      expect(FitnessGoal.leanMassCut.label, '린매스(감량)');
      expect(FitnessGoal.leanMassGain.label, '린매스(증량)');
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

  group('ActivityLevelX · prefsKey', () {
    test('prefsKey 왕복', () {
      for (final a in ActivityLevel.values) {
        expect(ActivityLevelX.fromPrefsKey(a.prefsKey), a);
      }
    });

    test('unknown → fallback', () {
      expect(
        ActivityLevelX.fromPrefsKey('unknown'),
        ActivityLevel.moderate,
      );
    });
  });

  group('TrainingIntensityX · prefsKey', () {
    test('prefsKey 왕복', () {
      for (final x in TrainingIntensity.values) {
        expect(TrainingIntensityX.fromPrefsKey(x.prefsKey), x);
      }
    });

    test('unknown → fallback', () {
      expect(
        TrainingIntensityX.fromPrefsKey(null),
        TrainingIntensity.moderate,
      );
    });
  });
}
