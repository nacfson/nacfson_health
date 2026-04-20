import 'package:uuid/uuid.dart';

import '../../domain/entities/exercise_record.dart';
import '../repositories/exercise_repository.dart';
import '../../../../core/database/database_helper.dart';

class SqliteExerciseRepository implements ExerciseRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  @override
  Future<List<ExerciseRecord>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'exercise_records',
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.deleted.value],
      orderBy: 'timestamp DESC',
    );
    return result.map((map) => _fromMap(map)).toList();
  }

  @override
  Future<List<ExerciseRecord>> getByDate(DateTime date) async {
    final db = await _dbHelper.database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startMs = startOfDay.millisecondsSinceEpoch;
    final endMs = endOfDay.millisecondsSinceEpoch;

    final result = await db.query(
      'exercise_records',
      where: 'timestamp >= ? AND timestamp < ? AND sync_status != ?',
      whereArgs: [startMs, endMs, SyncStatus.deleted.value],
      orderBy: 'timestamp DESC',
    );
    return result.map((map) => _fromMap(map)).toList();
  }

  @override
  Future<void> add(ExerciseRecord record) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    // uuid가 빈 문자열이면 자동 생성
    // updatedAt은 최초 생성 시 timestamp와 동일하게 설정
    final newRecord = record.copyWith(
      uuid: record.uuid.isEmpty ? _uuid.v4() : record.uuid,
      updatedAt: record.timestamp.isBefore(now) ? record.timestamp : now,
      syncStatus: SyncStatus.created,
    );
    await db.insert('exercise_records', _toMap(newRecord));
  }

  @override
  Future<void> update(ExerciseRecord record) async {
    final db = await _dbHelper.database;
    final updatedRecord = record.copyWith(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.modified,
    );
    await db.update(
      'exercise_records',
      _toMap(updatedRecord),
      where: 'uuid = ?',
      whereArgs: [record.uuid],
    );
  }

  @override
  Future<void> delete(String uuid) async {
    final db = await _dbHelper.database;
    await db.update(
      'exercise_records',
      {
        'sync_status': SyncStatus.deleted.value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  @override
  Future<List<ExerciseRecord>> getPendingSync() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'exercise_records',
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.synced.value],
    );
    return result.map((map) => _fromMap(map)).toList();
  }

  @override
  Future<void> markAsSynced(List<String> uuids) async {
    if (uuids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.update(
      'exercise_records',
      {'sync_status': SyncStatus.synced.value},
      where: 'uuid IN (${uuids.map((_) => '?').join(',')})',
      whereArgs: uuids,
    );
  }

  @override
  Future<void> mergeRemoteRecords(List<ExerciseRecord> remote) async {
    for (final remoteRecord in remote) {
      final existing = await _findByUuid(remoteRecord.uuid);

      if (existing == null) {
        // 로컬에 없음 → Insert
        await add(remoteRecord);
      } else {
        // uuid 같음 → updated_at 비교 (LWW)
        final remoteTime =
            remoteRecord.updatedAt.millisecondsSinceEpoch;
        final localTime =
            existing.updatedAt.millisecondsSinceEpoch;

        if (remoteTime > localTime) {
          // 리모트가 더 최신 → 덮어쓰기
          await _hardUpdate(remoteRecord);
        }
        // else: 로컬이 더 최신 → 무시
      }
    }
  }

  @override
  Future<void> hardDeleteSyncedDeleted() async {
    final db = await _dbHelper.database;
    await db.delete(
      'exercise_records',
      where: 'sync_status = ?',
      whereArgs: [SyncStatus.deleted.value],
    );
  }

  @override
  Future<void> resetAllSyncStatus() async {
    final db = await _dbHelper.database;
    await db.update(
      'exercise_records',
      {'sync_status': SyncStatus.created.value},
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.deleted.value],
    );
  }

  Future<ExerciseRecord?> _findByUuid(String uuid) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'exercise_records',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return _fromMap(result.first);
  }

  Future<void> _hardUpdate(ExerciseRecord record) async {
    final db = await _dbHelper.database;
    await db.update(
      'exercise_records',
      _toMap(record),
      where: 'uuid = ?',
      whereArgs: [record.uuid],
    );
  }

  Map<String, dynamic> _toMap(ExerciseRecord record) {
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

  ExerciseRecord _fromMap(Map<String, dynamic> map) {
    return ExerciseRecord(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
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
