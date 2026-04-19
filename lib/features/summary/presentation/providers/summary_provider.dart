import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/daily_summary.dart';
import '../../../exercise/presentation/providers/exercise_provider.dart';
import '../../../diet/presentation/providers/diet_provider.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../shared/providers/selected_date_provider.dart';

final dailySummaryProvider = Provider<DailySummary>((ref) {
  final exercises = ref.watch(exerciseRecordsProvider);
  final diets = ref.watch(dietRecordsProvider);
  final targets = ref.watch(nutritionTargetsProvider);
  final date = ref.watch(selectedDateProvider); // Observer 패턴: 날짜 변경 시 자동 갱신

  final dateExercises = exercises.where((e) =>
    e.timestamp.year == date.year &&
    e.timestamp.month == date.month &&
    e.timestamp.day == date.day
  ).toList();

  final dateDiets = diets.where((d) =>
    d.timestamp.year == date.year &&
    d.timestamp.month == date.month &&
    d.timestamp.day == date.day
  ).toList();

  final totalCalories = dateDiets.fold(0, (sum, d) => sum + d.totalCalories);
  final targetCalories = targets.calories;

  CalorieResult result;
  if (totalCalories >= targetCalories * 1.05) {
    result = CalorieResult.exceeded;
  } else if (totalCalories >= targetCalories * 0.90) {
    result = CalorieResult.achieved;
  } else {
    result = CalorieResult.under;
  }

  final totalCarbs = dateDiets.fold(0.0, (sum, d) => sum + d.carbs);
  final totalProtein = dateDiets.fold(0.0, (sum, d) => sum + d.protein);
  final totalFat = dateDiets.fold(0.0, (sum, d) => sum + d.fat);

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

  final totalVolume = dateExercises.fold(0.0, (sum, e) => sum + e.volume);
  final avgRpe = dateExercises.isEmpty
      ? 0.0
      : dateExercises.fold(0.0, (sum, e) => sum + e.rpe) / dateExercises.length;

  final targetedMuscles = dateExercises
      .map((e) => e.exerciseType)
      .toSet()
      .toList();

  final workoutPerformance = WorkoutPerformance(
    isWorkoutDay: dateExercises.isNotEmpty,
    targetedMuscles: targetedMuscles,
    totalVolume: totalVolume,
    averageRpe: avgRpe,
  );

  return DailySummary(
    date: date,
    dietNutrition: dietNutrition,
    workoutPerformance: workoutPerformance,
  );
});

