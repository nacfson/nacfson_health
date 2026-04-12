import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/daily_summary.dart';
import '../../../exercise/presentation/providers/exercise_provider.dart';
import '../../../diet/presentation/providers/diet_provider.dart';

final dailySummaryProvider = Provider<DailySummary>((ref) {
  final exercises = ref.watch(exerciseRecordsProvider);
  final diets = ref.watch(dietRecordsProvider);
  final now = DateTime.now();

  final todayExercises = exercises.where((e) =>
    e.timestamp.year == now.year &&
    e.timestamp.month == now.month &&
    e.timestamp.day == now.day
  ).toList();

  final todayDiets = diets.where((d) =>
    d.timestamp.year == now.year &&
    d.timestamp.month == now.month &&
    d.timestamp.day == now.day
  ).toList();

  final totalCalories = todayDiets.fold(0, (sum, d) => sum + d.totalCalories);
  final targetCalories = 1800;

  CalorieResult result;
  if (totalCalories >= targetCalories) {
    result = CalorieResult.achieved;
  } else if (totalCalories > targetCalories) {
    result = CalorieResult.exceeded;
  } else {
    result = CalorieResult.under;
  }

  final totalCarbs = todayDiets.fold(0.0, (sum, d) => sum + d.carbs);
  final totalProtein = todayDiets.fold(0.0, (sum, d) => sum + d.protein);
  final totalFat = todayDiets.fold(0.0, (sum, d) => sum + d.fat);

  final dietNutrition = DietNutrition(
    consumedCalories: totalCalories,
    targetCalories: targetCalories,
    macroStatus: {
      'carbs': MacroInfo(consumed: totalCarbs, target: 250, percentage: totalCarbs / 250 * 100),
      'protein': MacroInfo(consumed: totalProtein, target: 150, percentage: totalProtein / 150 * 100),
      'fat': MacroInfo(consumed: totalFat, target: 60, percentage: totalFat / 60 * 100),
    },
    calorieResult: result,
  );

  final totalVolume = todayExercises.fold(0.0, (sum, e) => sum + e.volume);
  final avgRpe = todayExercises.isEmpty
      ? 0.0
      : todayExercises.fold(0.0, (sum, e) => sum + e.rpe) / todayExercises.length;

  final targetedMuscles = todayExercises
      .map((e) => e.exerciseType)
      .toSet()
      .toList();

  final workoutPerformance = WorkoutPerformance(
    isWorkoutDay: todayExercises.isNotEmpty,
    targetedMuscles: targetedMuscles,
    totalVolume: totalVolume,
    averageRpe: avgRpe,
  );

  return DailySummary(
    date: now,
    dietNutrition: dietNutrition,
    workoutPerformance: workoutPerformance,
  );
});