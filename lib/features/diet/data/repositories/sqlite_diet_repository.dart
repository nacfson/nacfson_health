import '../../../../core/database/base_syncable_sqlite_repository.dart';
import '../../domain/entities/diet_record.dart';
import '../repositories/diet_repository.dart';

class SqliteDietRepository extends BaseSyncableSqliteRepository<DietRecord>
    implements DietRepository {
  @override
  String get tableName => 'diet_records';

  @override
  Future<List<DietRecord>> getByDate(DateTime date) => queryByDate(date);

  @override
  DietRecord copyWithSync(
    DietRecord entity, {
    String? uuid,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) =>
      entity.copyWith(
        uuid: uuid,
        updatedAt: updatedAt,
        syncStatus: syncStatus,
      );

  @override
  Map<String, dynamic> toMap(DietRecord record) {
    return {
      'uuid': record.uuid,
      'timestamp': record.timestamp.millisecondsSinceEpoch,
      'updated_at': record.updatedAt.millisecondsSinceEpoch,
      'sync_status': record.syncStatus.value,
      'meal_type': record.mealType,
      'food_name': record.foodName,
      'total_calories': record.totalCalories,
      'carbs': record.carbs,
      'protein': record.protein,
      'fat': record.fat,
      'satisfaction': record.satisfaction,
      'memo': record.memo,
    };
  }

  @override
  DietRecord fromMap(Map<String, dynamic> map) {
    return DietRecord(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      syncStatus: SyncStatus.fromInt(map['sync_status'] as int),
      mealType: map['meal_type'] as String,
      foodName: map['food_name'] as String,
      totalCalories: map['total_calories'] as int,
      carbs: (map['carbs'] as num).toDouble(),
      protein: (map['protein'] as num).toDouble(),
      fat: (map['fat'] as num).toDouble(),
      satisfaction: map['satisfaction'] as int,
      memo: map['memo'] as String?,
    );
  }
}
