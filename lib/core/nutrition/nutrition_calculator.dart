import 'dart:math' as math;

import 'nutrition_targets.dart';

export 'nutrition_targets.dart' show NutritionTargets;

/// 피트니스 목표 (4단계)
enum FitnessGoal { diet, leanMassCut, leanMassGain, bulkUp }

extension FitnessGoalX on FitnessGoal {
  String get label {
    switch (this) {
      case FitnessGoal.diet:
        return '다이어트';
      case FitnessGoal.leanMassCut:
        return '린매스(감량)';
      case FitnessGoal.leanMassGain:
        return '린매스(증량)';
      case FitnessGoal.bulkUp:
        return '벌크업';
    }
  }

  String get description {
    switch (this) {
      case FitnessGoal.diet:
        return '체중 감량 중심';
      case FitnessGoal.leanMassCut:
        return '체중 소폭 감량·근육 유지';
      case FitnessGoal.leanMassGain:
        return '근육 소폭 증가·지방 최소';
      case FitnessGoal.bulkUp:
        return '적극적 근육 증가';
    }
  }

  String get prefsKey {
    switch (this) {
      case FitnessGoal.diet:
        return 'diet';
      case FitnessGoal.leanMassCut:
        return 'lean_cut';
      case FitnessGoal.leanMassGain:
        return 'lean_gain';
      case FitnessGoal.bulkUp:
        return 'bulk_up';
    }
  }

  static FitnessGoal fromPrefsKey(
    String? key, {
    FitnessGoal fallback = FitnessGoal.leanMassGain,
  }) {
    switch (key) {
      case 'diet':
        return FitnessGoal.diet;
      case 'lean_cut':
        return FitnessGoal.leanMassCut;
      case 'lean_gain':
      case 'lean_mass': // 구버전 호환: 기존 '린매스업' → '린매스(증량)' 으로 매핑
        return FitnessGoal.leanMassGain;
      case 'bulk_up':
        return FitnessGoal.bulkUp;
      default:
        return fallback;
    }
  }
}

/// 성별 (BMR 계산용)
enum UserGender { male, female }

extension UserGenderX on UserGender {
  String get label {
    switch (this) {
      case UserGender.male:
        return '남성';
      case UserGender.female:
        return '여성';
    }
  }

  String get prefsKey {
    switch (this) {
      case UserGender.male:
        return 'male';
      case UserGender.female:
        return 'female';
    }
  }

  static UserGender fromPrefsKey(
    String? key, {
    UserGender fallback = UserGender.male,
  }) {
    switch (key) {
      case 'male':
        return UserGender.male;
      case 'female':
        return UserGender.female;
      default:
        return fallback;
    }
  }
}

/// 활동 수준 (5단계) — TDEE = BMR × multiplier
enum ActivityLevel { sedentary, light, moderate, active, veryActive }

extension ActivityLevelX on ActivityLevel {
  double get multiplier {
    switch (this) {
      case ActivityLevel.sedentary:
        return 1.2;
      case ActivityLevel.light:
        return 1.375;
      case ActivityLevel.moderate:
        return 1.55;
      case ActivityLevel.active:
        return 1.725;
      case ActivityLevel.veryActive:
        return 1.9;
    }
  }

  String get label {
    switch (this) {
      case ActivityLevel.sedentary:
        return '좌식';
      case ActivityLevel.light:
        return '가벼움';
      case ActivityLevel.moderate:
        return '보통';
      case ActivityLevel.active:
        return '활발';
      case ActivityLevel.veryActive:
        return '매우 활발';
    }
  }

  String get description {
    switch (this) {
      case ActivityLevel.sedentary:
        return '거의 운동하지 않음';
      case ActivityLevel.light:
        return '주 1~3회 가벼운 운동';
      case ActivityLevel.moderate:
        return '주 3~5회 중간 강도 운동';
      case ActivityLevel.active:
        return '주 6~7회 강도 있는 운동';
      case ActivityLevel.veryActive:
        return '매일 고강도 + 육체 노동';
    }
  }

  String get prefsKey {
    switch (this) {
      case ActivityLevel.sedentary:
        return 'sedentary';
      case ActivityLevel.light:
        return 'light';
      case ActivityLevel.moderate:
        return 'moderate';
      case ActivityLevel.active:
        return 'active';
      case ActivityLevel.veryActive:
        return 'very_active';
    }
  }

  static ActivityLevel fromPrefsKey(
    String? key, {
    ActivityLevel fallback = ActivityLevel.moderate,
  }) {
    switch (key) {
      case 'sedentary':
        return ActivityLevel.sedentary;
      case 'light':
        return ActivityLevel.light;
      case 'moderate':
        return ActivityLevel.moderate;
      case 'active':
        return ActivityLevel.active;
      case 'very_active':
        return ActivityLevel.veryActive;
      default:
        return fallback;
    }
  }
}

/// 운동 강도 (4단계) — 단백질 g/kg 결정
enum TrainingIntensity { low, moderate, high, veryHigh }

extension TrainingIntensityX on TrainingIntensity {
  double get proteinGPerKg {
    switch (this) {
      case TrainingIntensity.low:
        return 1.8;
      case TrainingIntensity.moderate:
        return 2.0;
      case TrainingIntensity.high:
        return 2.2;
      case TrainingIntensity.veryHigh:
        return 2.4;
    }
  }

  String get label {
    switch (this) {
      case TrainingIntensity.low:
        return '낮음';
      case TrainingIntensity.moderate:
        return '보통';
      case TrainingIntensity.high:
        return '높음';
      case TrainingIntensity.veryHigh:
        return '매우 높음';
    }
  }

  String get description {
    switch (this) {
      case TrainingIntensity.low:
        return '가벼운 유산소 위주';
      case TrainingIntensity.moderate:
        return '중간 강도 근력 운동';
      case TrainingIntensity.high:
        return '주 4회 이상 근력 훈련';
      case TrainingIntensity.veryHigh:
        return '고강도 웨이트 트레이닝';
    }
  }

  String get prefsKey {
    switch (this) {
      case TrainingIntensity.low:
        return 'low';
      case TrainingIntensity.moderate:
        return 'moderate';
      case TrainingIntensity.high:
        return 'high';
      case TrainingIntensity.veryHigh:
        return 'very_high';
    }
  }

  static TrainingIntensity fromPrefsKey(
    String? key, {
    TrainingIntensity fallback = TrainingIntensity.moderate,
  }) {
    switch (key) {
      case 'low':
        return TrainingIntensity.low;
      case 'moderate':
        return TrainingIntensity.moderate;
      case 'high':
        return TrainingIntensity.high;
      case 'very_high':
        return TrainingIntensity.veryHigh;
      default:
        return fallback;
    }
  }
}

class NutritionCalculationInput {
  final double heightCm;
  final double weightKg;
  final UserGender gender;
  final int age;
  final FitnessGoal goal;
  final ActivityLevel activityLevel;
  final TrainingIntensity intensity;

  const NutritionCalculationInput({
    required this.heightCm,
    required this.weightKg,
    required this.gender,
    required this.age,
    required this.goal,
    this.activityLevel = ActivityLevel.moderate,
    this.intensity = TrainingIntensity.moderate,
  });
}

/// Mifflin-St Jeor 공식 기반 BMR (kcal/day).
///
/// `calculateTargets()` 의 내부 단계이자, UI 가 별도로 BMR 만 표시하고 싶을 때
/// (예: 활동 카드의 "기초대사량 NNNkcal/일" 보조 라인) 직접 호출하는 진입점.
double computeBmr({
  required double weightKg,
  required double heightCm,
  required int age,
  required UserGender gender,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return gender == UserGender.male ? base + 5 : base - 161;
}

/// 목표별 kcal 보정 (TDEE 기준) + 다이어트 하한 적용
double _applyGoalAdjustment({
  required double tdee,
  required double weightKg,
  required FitnessGoal goal,
}) {
  switch (goal) {
    case FitnessGoal.diet:
      final adjusted = tdee - 500;
      final floor = math.max(1200.0, weightKg * 22);
      return math.max(floor, adjusted);
    case FitnessGoal.leanMassCut:
      return tdee - 200;
    case FitnessGoal.leanMassGain:
      return tdee + 200;
    case FitnessGoal.bulkUp:
      return tdee + 500;
  }
}

/// 주어진 입력 기준 목표 영양 성분 계산
NutritionTargets calculateTargets(NutritionCalculationInput input) {
  if (input.weightKg <= 0) {
    throw ArgumentError.value(input.weightKg, 'weightKg', '0보다 커야 합니다');
  }
  if (input.heightCm <= 0) {
    throw ArgumentError.value(input.heightCm, 'heightCm', '0보다 커야 합니다');
  }
  if (input.age <= 0) {
    throw ArgumentError.value(input.age, 'age', '0보다 커야 합니다');
  }

  final bmr = computeBmr(
    weightKg: input.weightKg,
    heightCm: input.heightCm,
    age: input.age,
    gender: input.gender,
  );
  final tdee = bmr * input.activityLevel.multiplier;
  final targetKcal = _applyGoalAdjustment(
    tdee: tdee,
    weightKg: input.weightKg,
    goal: input.goal,
  );

  // 칼로리: 10 단위 반올림
  final kcalRounded = (targetKcal / 10).round() * 10;

  // 단백질: 체중 × 강도별 g/kg
  final proteinG = input.weightKg * input.intensity.proteinGPerKg;

  // 지방: 총 칼로리의 22.5%
  final fatG = kcalRounded * 0.225 / 9;

  // 탄수: 나머지 (음수는 0으로 clamp)
  final remainingKcal = kcalRounded - proteinG * 4 - fatG * 9;
  final carbsG = math.max(0.0, remainingKcal / 4);

  return NutritionTargets(
    calories: kcalRounded,
    carbs: carbsG.roundToDouble(),
    protein: proteinG.roundToDouble(),
    fat: fatG.roundToDouble(),
  );
}
