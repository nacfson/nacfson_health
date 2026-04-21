import '../../../../core/database/base_template_syncable_sqlite_repository.dart';
import '../../domain/entities/food_template.dart';
import 'food_template_repository.dart';

class SqliteFoodTemplateRepository
    extends BaseTemplateSyncableSqliteRepository<FoodTemplate>
    implements FoodTemplateRepository {
  @override
  String get tableName => 'food_templates';

  @override
  FoodTemplate copyWithSync(
    FoodTemplate entity, {
    String? uuid,
    TemplateSyncStatus? syncStatus,
  }) =>
      entity.copyWith(uuid: uuid, syncStatus: syncStatus);

  @override
  Map<String, dynamic> toMap(FoodTemplate t) => {
        'uuid': t.uuid,
        'name': t.name,
        'calories': t.calories,
        'carbs': t.carbs,
        'protein': t.protein,
        'fat': t.fat,
        'updated_at': t.updatedAt.millisecondsSinceEpoch,
        'sync_status': t.syncStatus.value,
      };

  @override
  FoodTemplate fromMap(Map<String, dynamic> map) => FoodTemplate(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        name: map['name'] as String,
        calories: map['calories'] as int,
        carbs: (map['carbs'] as num).toDouble(),
        protein: (map['protein'] as num).toDouble(),
        fat: (map['fat'] as num).toDouble(),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
        syncStatus: TemplateSyncStatus.fromInt(map['sync_status'] as int),
      );
}
