import '../../../../core/database/syncable_entity.dart';
import '../../../../core/sync/sync_status.dart';

export '../../../../core/sync/sync_status.dart' show TemplateSyncStatus;

class FoodTemplate implements TemplateSyncableEntity {
  final int? id; // LOCAL ONLY — 시트 연동 시 사용 금지
  @override
  final String uuid; // 글로벌 PK (UUID v4)
  final String name; // 음식 이름 (unique)
  final int calories; // kcal
  final double carbs; // 탄수화물 g
  final double protein; // 단백질 g
  final double fat; // 지방 g
  @override
  final DateTime updatedAt;
  @override
  final TemplateSyncStatus syncStatus;

  const FoodTemplate({
    this.id,
    required this.uuid,
    required this.name,
    required this.calories,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.updatedAt,
    this.syncStatus = TemplateSyncStatus.created,
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
    TemplateSyncStatus? syncStatus,
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
