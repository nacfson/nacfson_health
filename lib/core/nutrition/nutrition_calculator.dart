import 'dart:math' as math;

import '../sync/sync_state.dart' show NutritionTargets;

/// 피트니스 목표
enum FitnessGoal { diet, leanMass, bulkUp }

extension FitnessGoalX on FitnessGoal {
  String get label {
    switch (this) {
      case FitnessGoal.diet:
        return '다이어트';
      case FitnessGoal.leanMass:
        return '린매스업';
      case FitnessGoal.bulkUp:
        return '벌크업';
    }
  }

  String get prefsKey {
    switch (this) {
      case FitnessGoal.diet:
        return 'diet';
      case FitnessGoal.leanMass:
        return 'lean_mass';
      case FitnessGoal.bulkUp:
        return 'bulk_up';
    }
  }

  static FitnessGoal fromPrefsKey(
    String? key, {
    FitnessGoal fallback = FitnessGoal.leanMass,
  }) {
    switch (key) {
      case 'diet':
        return FitnessGoal.diet;
      case 'lean_mass':
        return FitnessGoal.leanMass;
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

/// 나이대 (BMR 계산용 — 중앙값 연령 사용)
enum AgeGroup { twenties, thirties, forties, fiftiesPlus }

extension AgeGroupX on AgeGroup {
  String get label {
    switch (this) {
      case AgeGroup.twenties:
        return '20대';
      case AgeGroup.thirties:
        return '30대';
      case AgeGroup.forties:
        return '40대';
      case AgeGroup.fiftiesPlus:
        return '50대 이상';
    }
  }

  String get prefsKey {
    switch (this) {
      case AgeGroup.twenties:
        return '20s';
      case AgeGroup.thirties:
        return '30s';
      case AgeGroup.forties:
        return '40s';
      case AgeGroup.fiftiesPlus:
        return '50s+';
    }
  }

  int get midpointAge {
    switch (this) {
      case AgeGroup.twenties:
        return 25;
      case AgeGroup.thirties:
        return 35;
      case AgeGroup.forties:
        return 45;
      case AgeGroup.fiftiesPlus:
        return 55;
    }
  }

  static AgeGroup fromPrefsKey(
    String? key, {
    AgeGroup fallback = AgeGroup.thirties,
  }) {
    switch (key) {
      case '20s':
        return AgeGroup.twenties;
      case '30s':
        return AgeGroup.thirties;
      case '40s':
        return AgeGroup.forties;
      case '50s+':
        return AgeGroup.fiftiesPlus;
      default:
        return fallback;
    }
  }
}

class NutritionCalculationInput {
  final double heightCm;
  final double weightKg;
  final UserGender gender;
  final AgeGroup ageGroup;
  final FitnessGoal goal;

  const NutritionCalculationInput({
    required this.heightCm,
    required this.weightKg,
    required this.gender,
    required this.ageGroup,
    required this.goal,
  });
}

/// 활동계수 (중간 활동, 1.55)
const double _activityFactor = 1.55;

/// Mifflin-St Jeor 공식 기반 BMR (kcal/day)
double _calculateBmr({
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
    case FitnessGoal.leanMass:
      return tdee + 200;
    case FitnessGoal.bulkUp:
      return tdee + 400;
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

  final bmr = _calculateBmr(
    weightKg: input.weightKg,
    heightCm: input.heightCm,
    age: input.ageGroup.midpointAge,
    gender: input.gender,
  );
  final tdee = bmr * _activityFactor;
  final targetKcal = _applyGoalAdjustment(
    tdee: tdee,
    weightKg: input.weightKg,
    goal: input.goal,
  );

  // 칼로리: 10 단위 반올림
  final kcalRounded = (targetKcal / 10).round() * 10;

  // 단백질: 체중 × 1.8 g/kg
  final proteinG = input.weightKg * 1.8;

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
