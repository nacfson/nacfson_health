import '../../../../core/database/base_syncable_sqlite_repository.dart';
import '../../../../core/database/database_helper.dart';
import '../../domain/entities/exercise_record.dart';
import '../repositories/exercise_repository.dart';

class SqliteExerciseRepository
    extends BaseSyncableSqliteRepository<ExerciseRecord>
    implements ExerciseRepository {
  @override
  String get tableName => 'exercise_records';

  @override
  Future<List<ExerciseRecord>> getByDate(DateTime date) => queryByDate(date);

  @override
  Future<int> deleteByExerciseNameOnDate(
      String exerciseName, DateTime date) async {
    final db = await DatabaseHelper.instance.database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return db.update(
      tableName,
      {
        'sync_status': SyncStatus.deleted.value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where:
          'exercise_name = ? AND timestamp >= ? AND timestamp < ? AND sync_status != ?',
      whereArgs: [
        exerciseName,
        startOfDay.millisecondsSinceEpoch,
        endOfDay.millisecondsSinceEpoch,
        SyncStatus.deleted.value,
      ],
    );
  }

  @override
  ExerciseRecord copyWithSync(
    ExerciseRecord entity, {
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
  Map<String, dynamic> toMap(ExerciseRecord record) {
    return {
      'uuid': record.uuid,
      'timestamp': record.timestamp.millisecondsSinceEpoch,
      'updated_at': record.updatedAt.millisecondsSinceEpoch,
      'sync_status': record.syncStatus.value,
      'exercise_type': record.exerciseType,
      'exercise_name': record.exerciseName,
      'current_set': record.currentSet,
      'weight': record.weight,
      'reps': record.reps,
      'rpe': record.rpe,
      'set_type': record.setType.value,
    };
  }

  @override
  ExerciseRecord fromMap(Map<String, dynamic> map) {
    return ExerciseRecord(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      syncStatus: SyncStatus.fromInt(map['sync_status'] as int),
      exerciseType: map['exercise_type'] as String,
      exerciseName: map['exercise_name'] as String,
      currentSet: map['current_set'] as int,
      weight: (map['weight'] as num).toDouble(),
      reps: map['reps'] as int,
      rpe: (map['rpe'] as num).toDouble(),
      setType: SetType.fromString(map['set_type'] as String?),
    );
  }
}
