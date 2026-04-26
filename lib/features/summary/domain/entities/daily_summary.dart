enum CalorieResult { achieved, exceeded, under }

class MacroInfo {
  final double consumed;
  final double target;
  final double percentage;

  const MacroInfo({
    required this.consumed,
    required this.target,
    required this.percentage,
  });
}

class DietNutrition {
  final int consumedCalories;
  final int targetCalories;
  final Map<String, MacroInfo> macroStatus;
  final CalorieResult calorieResult;

  const DietNutrition({
    required this.consumedCalories,
    required this.targetCalories,
    required this.macroStatus,
    required this.calorieResult,
  });
}

class WorkoutPerformance {
  final bool isWorkoutDay;
  final List<String> targetedMuscles;
  final double totalVolume;
  final double averageRpe;

  /// 볼륨 기반 운동 칼로리 추정치 (kcal). 부위계수 적용, ±40% 추정치.
  /// HealthKit / Health Connect 의 활동 칼로리와는 분리하여 표시한다 (합산 X).
  final double estimatedCalories;

  const WorkoutPerformance({
    required this.isWorkoutDay,
    required this.targetedMuscles,
    required this.totalVolume,
    required this.averageRpe,
    required this.estimatedCalories,
  });
}

class DailySummary {
  final DateTime date;
  final DietNutrition? dietNutrition;
  final WorkoutPerformance? workoutPerformance;

  const DailySummary({
    required this.date,
    this.dietNutrition,
    this.workoutPerformance,
  });
}