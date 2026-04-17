import 'package:uuid/uuid.dart';

import '../../domain/entities/weight_record.dart';
import '../repositories/weight_repository.dart';
import '../../../../core/database/database_helper.dart';

class SqliteWeightRepository implements WeightRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  @override
  Future<List<WeightRecord>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'weight_records',
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.deleted.value],
      orderBy: 'timestamp DESC',
    );
    return result.map((map) => _fromMap(map)).toList();
  }

  @override
  Future<WeightRecord?> getLatest() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'weight_records',
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.deleted.value],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return _fromMap(result.first);
  }

  @override
  Future<List<WeightRecord>> getByDateRange(DateTime start, DateTime end) async {
    final db = await _dbHelper.database;
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;

    final result = await db.query(
      'weight_records',
      where: 'timestamp >= ? AND timestamp <= ? AND sync_status != ?',
      whereArgs: [startMs, endMs, SyncStatus.deleted.value],
      orderBy: 'timestamp ASC',
    );
    return result.map((map) => _fromMap(map)).toList();
  }

  @override
  Future<void> add(WeightRecord record) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final newRecord = record.copyWith(
      uuid: record.uuid.isEmpty ? _uuid.v4() : record.uuid,
      updatedAt: record.timestamp.isBefore(now) ? record.timestamp : now,
      syncStatus: SyncStatus.created,
    );
    await db.insert('weight_records', _toMap(newRecord));
  }

  @override
  Future<void> update(WeightRecord record) async {
    final db = await _dbHelper.database;
    final updatedRecord = record.copyWith(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.modified,
    );
    await db.update(
      'weight_records',
      _toMap(updatedRecord),
      where: 'uuid = ?',
      whereArgs: [record.uuid],
    );
  }

  @override
  Future<void> delete(String uuid) async {
    final db = await _dbHelper.database;
    await db.update(
      'weight_records',
      {
        'sync_status': SyncStatus.deleted.value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  @override
  Future<List<WeightRecord>> getPendingSync() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'weight_records',
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
      'weight_records',
      {'sync_status': SyncStatus.synced.value},
      where: 'uuid IN (${uuids.map((_) => '?').join(',')})',
      whereArgs: uuids,
    );
  }

  @override
  Future<void> mergeRemoteRecords(List<WeightRecord> remote) async {
    for (final remoteRecord in remote) {
      final existing = await _findByUuid(remoteRecord.uuid);

      if (existing == null) {
        await add(remoteRecord);
      } else {
        final remoteTime = remoteRecord.updatedAt.millisecondsSinceEpoch;
        final localTime = existing.updatedAt.millisecondsSinceEpoch;

        if (remoteTime > localTime) {
          await _hardUpdate(remoteRecord);
        }
      }
    }
  }

  @override
  Future<void> hardDeleteSyncedDeleted() async {
    final db = await _dbHelper.database;
    await db.delete(
      'weight_records',
      where: 'sync_status = ?',
      whereArgs: [SyncStatus.deleted.value],
    );
  }

  @override
  Future<void> resetAllSyncStatus() async {
    final db = await _dbHelper.database;
    await db.update(
      'weight_records',
      {'sync_status': SyncStatus.created.value},
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.deleted.value],
    );
  }

  Future<WeightRecord?> _findByUuid(String uuid) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'weight_records',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return _fromMap(result.first);
  }

  Future<void> _hardUpdate(WeightRecord record) async {
    final db = await _dbHelper.database;
    await db.update(
      'weight_records',
      _toMap(record),
      where: 'uuid = ?',
      whereArgs: [record.uuid],
    );
  }

  Map<String, dynamic> _toMap(WeightRecord record) {
    return {
      'uuid': record.uuid,
      'timestamp': record.timestamp.millisecondsSinceEpoch,
      'updated_at': record.updatedAt.millisecondsSinceEpoch,
      'sync_status': record.syncStatus.value,
      'weight': record.weight,
    };
  }

  WeightRecord _fromMap(Map<String, dynamic> map) {
    return WeightRecord(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      syncStatus: SyncStatus.fromInt(map['sync_status'] as int),
      weight: (map['weight'] as num).toDouble(),
    );
  }
}
