import 'package:uuid/uuid.dart';

import '../../domain/entities/diet_record.dart';
import '../repositories/diet_repository.dart';
import '../../../../core/database/database_helper.dart';

class SqliteDietRepository implements DietRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  @override
  Future<List<DietRecord>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'diet_records',
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.deleted.value],
      orderBy: 'timestamp DESC',
    );
    return result.map((map) => _fromMap(map)).toList();
  }

  @override
  Future<List<DietRecord>> getByDate(DateTime date) async {
    final db = await _dbHelper.database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startMs = startOfDay.millisecondsSinceEpoch;
    final endMs = endOfDay.millisecondsSinceEpoch;

    final result = await db.query(
      'diet_records',
      where: 'timestamp >= ? AND timestamp < ? AND sync_status != ?',
      whereArgs: [startMs, endMs, SyncStatus.deleted.value],
      orderBy: 'timestamp DESC',
    );
    return result.map((map) => _fromMap(map)).toList();
  }

  @override
  Future<void> add(DietRecord record) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    // uuid가 빈 문자열이면 자동 생성
    // updatedAt은 최초 생성 시 timestamp와 동일하게 설정
    final newRecord = record.copyWith(
      uuid: record.uuid.isEmpty ? _uuid.v4() : record.uuid,
      updatedAt: record.timestamp.isBefore(now) ? record.timestamp : now,
      syncStatus: SyncStatus.created,
    );
    await db.insert('diet_records', _toMap(newRecord));
  }

  @override
  Future<void> update(DietRecord record) async {
    final db = await _dbHelper.database;
    final updatedRecord = record.copyWith(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.modified,
    );
    await db.update(
      'diet_records',
      _toMap(updatedRecord),
      where: 'uuid = ?',
      whereArgs: [record.uuid],
    );
  }

  @override
  Future<void> delete(String uuid) async {
    final db = await _dbHelper.database;
    await db.update(
      'diet_records',
      {
        'sync_status': SyncStatus.deleted.value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  @override
  Future<List<DietRecord>> getPendingSync() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'diet_records',
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
      'diet_records',
      {'sync_status': SyncStatus.synced.value},
      where: 'uuid IN (${uuids.map((_) => '?').join(',')})',
      whereArgs: uuids,
    );
  }

  @override
  Future<void> mergeRemoteRecords(List<DietRecord> remote) async {
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
      'diet_records',
      where: 'sync_status = ?',
      whereArgs: [SyncStatus.deleted.value],
    );
  }

  @override
  Future<void> resetAllSyncStatus() async {
    final db = await _dbHelper.database;
    await db.update(
      'diet_records',
      {'sync_status': SyncStatus.created.value},
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.deleted.value],
    );
  }

  Future<DietRecord?> _findByUuid(String uuid) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'diet_records',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return _fromMap(result.first);
  }

  Future<void> _hardUpdate(DietRecord record) async {
    final db = await _dbHelper.database;
    await db.update(
      'diet_records',
      _toMap(record),
      where: 'uuid = ?',
      whereArgs: [record.uuid],
    );
  }

  Map<String, dynamic> _toMap(DietRecord record) {
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

  DietRecord _fromMap(Map<String, dynamic> map) {
    return DietRecord(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
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
