/// 영양 목표 (kcal · 탄수 g · 단백질 g · 지방 g)를 담는 경량 DTO.
///
/// 순수 데이터 타입 — sync 레이어나 Riverpod에 의존하지 않습니다.
/// 계산기(`nutrition_calculator.dart`)와 상태 노티파이어(`sync_state.dart`)가
/// 모두 이 파일을 import 해서 결합도를 최소화합니다.
class NutritionTargets {
  final int calories;
  final double carbs;
  final double protein;
  final double fat;

  const NutritionTargets({
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
  });

  NutritionTargets copyWith({
    int? calories,
    double? carbs,
    double? protein,
    double? fat,
  }) =>
      NutritionTargets(
        calories: calories ?? this.calories,
        carbs: carbs ?? this.carbs,
        protein: protein ?? this.protein,
        fat: fat ?? this.fat,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NutritionTargets &&
        other.calories == calories &&
        other.carbs == carbs &&
        other.protein == protein &&
        other.fat == fat;
  }

  @override
  int get hashCode => Object.hash(calories, carbs, protein, fat);

  @override
  String toString() =>
      'NutritionTargets(calories: $calories, carbs: $carbs, '
      'protein: $protein, fat: $fat)';
}
