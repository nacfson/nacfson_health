import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/daily_summary.dart';
import '../../../exercise/presentation/providers/exercise_provider.dart';
import '../../../diet/presentation/providers/diet_provider.dart';
import '../../../../core/sync/sync_state.dart';

final dailySummaryProvider = Provider<DailySummary>((ref) {
  final exercises = ref.watch(exerciseRecordsProvider);
  final diets = ref.watch(dietRecordsProvider);
  final targets = ref.watch(nutritionTargetsProvider);
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
  final targetCalories = targets.calories;

  CalorieResult result;
  if (totalCalories >= targetCalories * 1.05) {
    result = CalorieResult.exceeded;
  } else if (totalCalories >= targetCalories * 0.90) {
    result = CalorieResult.achieved;
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
      'carbs': MacroInfo(
        consumed: totalCarbs,
        target: targets.carbs,
        percentage: targets.carbs > 0 ? totalCarbs / targets.carbs * 100 : 0,
      ),
      'protein': MacroInfo(
        consumed: totalProtein,
        target: targets.protein,
        percentage: targets.protein > 0 ? totalProtein / targets.protein * 100 : 0,
      ),
      'fat': MacroInfo(
        consumed: totalFat,
        target: targets.fat,
        percentage: targets.fat > 0 ? totalFat / targets.fat * 100 : 0,
      ),
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
