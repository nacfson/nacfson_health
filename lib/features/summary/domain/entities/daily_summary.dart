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

  const WorkoutPerformance({
    required this.isWorkoutDay,
    required this.targetedMuscles,
    required this.totalVolume,
    required this.averageRpe,
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