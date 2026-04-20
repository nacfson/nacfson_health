/// Gemini Vision이 반환한 음식 분석 결과.
///
/// 모든 영양성분(칼로리·탄단지)은 [estimatedGrams] 기준의 실제 섭취량입니다.
/// 100g 기준 환산값이 아닙니다.
class FoodAnalysisResult {
  final bool isFood;
  final String foodName;
  final int estimatedGrams;
  final int calories;
  final double carbs;
  final double protein;
  final double fat;
  final double confidence;
  final String? notes;
  final List<FoodAnalysisItem> items;

  const FoodAnalysisResult({
    required this.isFood,
    required this.foodName,
    required this.estimatedGrams,
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.confidence,
    this.notes,
    this.items = const [],
  });

  bool get isMultiItem => items.length > 1;

  FoodAnalysisResult copyWith({
    bool? isFood,
    String? foodName,
    int? estimatedGrams,
    int? calories,
    double? carbs,
    double? protein,
    double? fat,
    double? confidence,
    String? notes,
    List<FoodAnalysisItem>? items,
  }) {
    return FoodAnalysisResult(
      isFood: isFood ?? this.isFood,
      foodName: foodName ?? this.foodName,
      estimatedGrams: estimatedGrams ?? this.estimatedGrams,
      calories: calories ?? this.calories,
      carbs: carbs ?? this.carbs,
      protein: protein ?? this.protein,
      fat: fat ?? this.fat,
      confidence: confidence ?? this.confidence,
      notes: notes ?? this.notes,
      items: items ?? this.items,
    );
  }

  /// 중량 변경 시 영양성분을 비례 환산해 반환합니다.
  ///
  /// 예: 350g → 700g이면 모든 매크로가 2배.
  FoodAnalysisResult scaleTo(int newGrams) {
    if (estimatedGrams <= 0 || newGrams <= 0) {
      return copyWith(estimatedGrams: newGrams);
    }
    final r = newGrams / estimatedGrams;
    return copyWith(
      estimatedGrams: newGrams,
      calories: (calories * r).round(),
      carbs: carbs * r,
      protein: protein * r,
      fat: fat * r,
    );
  }

  factory FoodAnalysisResult.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    final rawItems = json['items'];
    final items = <FoodAnalysisItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map<String, dynamic>) {
          items.add(FoodAnalysisItem.fromJson(e));
        }
      }
    }

    return FoodAnalysisResult(
      isFood: json['isFood'] == true,
      foodName: (json['foodName'] ?? '').toString(),
      estimatedGrams: asInt(json['estimatedGrams']),
      calories: asInt(json['calories']),
      carbs: asDouble(json['carbs']),
      protein: asDouble(json['protein']),
      fat: asDouble(json['fat']),
      confidence: asDouble(json['confidence']).clamp(0.0, 1.0),
      notes: (json['notes'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['notes'] as String).trim(),
      items: items,
    );
  }

  static const empty = FoodAnalysisResult(
    isFood: false,
    foodName: '',
    estimatedGrams: 0,
    calories: 0,
    carbs: 0,
    protein: 0,
    fat: 0,
    confidence: 0,
  );
}

class FoodAnalysisItem {
  final String foodName;
  final int estimatedGrams;
  final int calories;
  final double carbs;
  final double protein;
  final double fat;

  const FoodAnalysisItem({
    required this.foodName,
    required this.estimatedGrams,
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
  });

  factory FoodAnalysisItem.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
    int asInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    return FoodAnalysisItem(
      foodName: (json['foodName'] ?? '').toString(),
      estimatedGrams: asInt(json['estimatedGrams']),
      calories: asInt(json['calories']),
      carbs: asDouble(json['carbs']),
      protein: asDouble(json['protein']),
      fat: asDouble(json['fat']),
    );
  }
}
