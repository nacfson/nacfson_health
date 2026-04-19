// modified(2) 없음 — 템플릿은 생성/삭제만 지원
enum FoodTemplateSyncStatus {
  synced(0),
  created(1),
  deleted(3);

  final int value;
  const FoodTemplateSyncStatus(this.value);

  static FoodTemplateSyncStatus fromInt(int v) =>
      FoodTemplateSyncStatus.values.firstWhere((e) => e.value == v);
}

class FoodTemplate {
  final int? id; // LOCAL ONLY — 시트 연동 시 사용 금지
  final String uuid; // 글로벌 PK (UUID v4)
  final String name; // 음식 이름 (unique)
  final int calories; // kcal
  final double carbs; // 탄수화물 g
  final double protein; // 단백질 g
  final double fat; // 지방 g
  final DateTime updatedAt;
  final FoodTemplateSyncStatus syncStatus;

  const FoodTemplate({
    this.id,
    required this.uuid,
    required this.name,
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.updatedAt,
    this.syncStatus = FoodTemplateSyncStatus.created,
  });

  FoodTemplate copyWith({
    int? id,
    String? uuid,
    String? name,
    int? calories,
    double? carbs,
    double? protein,
    double? fat,
    DateTime? updatedAt,
    FoodTemplateSyncStatus? syncStatus,
  }) =>
      FoodTemplate(
        id: id ?? this.id,
        uuid: uuid ?? this.uuid,
        name: name ?? this.name,
        calories: calories ?? this.calories,
        carbs: carbs ?? this.carbs,
        protein: protein ?? this.protein,
        fat: fat ?? this.fat,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}
