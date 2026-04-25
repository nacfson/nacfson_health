import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/exercise_record.dart' show SyncStatus;
import '../../domain/entities/routine_item.dart';
import '../../domain/entities/workout_routine.dart';
import 'workout_routine_repository.dart';

class SqliteWorkoutRoutineRepository implements WorkoutRoutineRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  @override
  Future<List<WorkoutRoutine>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'workout_routines',
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.deleted.value],
      orderBy: 'updated_at DESC',
    );
    return result.map(_fromMap).toList();
  }

  @override
  Future<void> add(WorkoutRoutine routine) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final record = routine.copyWith(
      uuid: routine.uuid.isEmpty ? _uuid.v4() : routine.uuid,
      createdAt: routine.createdAt,
      updatedAt: now,
      syncStatus: SyncStatus.created,
    );
    await db.insert('workout_routines', _toMap(record));
  }

  @override
  Future<void> update(WorkoutRoutine routine) async {
    final db = await _dbHelper.database;
    final updated = routine.copyWith(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.modified,
    );
    await db.update(
      'workout_routines',
      _toMap(updated),
      where: 'uuid = ?',
      whereArgs: [routine.uuid],
    );
  }

  @override
  Future<void> delete(String uuid) async {
    final db = await _dbHelper.database;
    await db.update(
      'workout_routines',
      {
        'sync_status': SyncStatus.deleted.value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  @override
  Future<List<WorkoutRoutine>> getPendingSync() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'workout_routines',
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.synced.value],
    );
    return result.map(_fromMap).toList();
  }

  @override
  Future<void> markAsSynced(List<String> uuids) async {
    if (uuids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.update(
      'workout_routines',
      {'sync_status': SyncStatus.synced.value},
      where: 'uuid IN (${uuids.map((_) => '?').join(',')})',
      whereArgs: uuids,
    );
  }

  @override
  Future<void> mergeRemoteRoutines(List<WorkoutRoutine> remote) async {
    if (remote.isEmpty) return;
    final localByUuid =
        await _findExistingByUuids(remote.map((r) => r.uuid).toList());
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final r in remote) {
        final existing = localByUuid[r.uuid];
        if (existing == null) {
          await txn.insert(
            'workout_routines',
            _toMap(r.copyWith(syncStatus: SyncStatus.synced)),
          );
        } else if (r.updatedAt.isAfter(existing.updatedAt)) {
          await txn.update(
            'workout_routines',
            _toMap(r.copyWith(syncStatus: SyncStatus.synced)),
            where: 'uuid = ?',
            whereArgs: [r.uuid],
          );
        }
      }
    });
  }

  /// SQLite SQLITE_MAX_VARIABLE_NUMBER(999) 대비 여유 마진.
  static const int _maxBindsPerQuery = 900;

  Future<Map<String, WorkoutRoutine>> _findExistingByUuids(
      List<String> uuids) async {
    if (uuids.isEmpty) return const {};
    final db = await _dbHelper.database;
    final result = <String, WorkoutRoutine>{};
    for (var i = 0; i < uuids.length; i += _maxBindsPerQuery) {
      final end = i + _maxBindsPerQuery;
      final chunk = uuids.sublist(i, end > uuids.length ? uuids.length : end);
      final rows = await db.query(
        'workout_routines',
        where: 'uuid IN (${chunk.map((_) => '?').join(',')})',
        whereArgs: chunk,
      );
      for (final row in rows) {
        final routine = _fromMap(row);
        result[routine.uuid] = routine;
      }
    }
    return result;
  }

  @override
  Future<void> hardDeleteSyncedDeleted() async {
    final db = await _dbHelper.database;
    await db.delete(
      'workout_routines',
      where: 'sync_status = ?',
      whereArgs: [SyncStatus.deleted.value],
    );
  }

  @override
  Future<void> resetAllSyncStatus() async {
    final db = await _dbHelper.database;
    await db.update(
      'workout_routines',
      {'sync_status': SyncStatus.created.value},
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.deleted.value],
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Map<String, dynamic> _toMap(WorkoutRoutine r) => {
        'uuid': r.uuid,
        'name': r.name,
        'items_json': jsonEncode(r.items.map((i) => i.toJson()).toList()),
        'created_at': r.createdAt.millisecondsSinceEpoch,
        'updated_at': r.updatedAt.millisecondsSinceEpoch,
        'sync_status': r.syncStatus.value,
      };

  WorkoutRoutine _fromMap(Map<String, dynamic> map) {
    final decoded = jsonDecode(map['items_json'] as String) as List;
    final items = decoded
        .map((e) => RoutineItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return WorkoutRoutine(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      name: map['name'] as String,
      items: items,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      syncStatus: SyncStatus.fromInt(map['sync_status'] as int),
    );
  }
}
