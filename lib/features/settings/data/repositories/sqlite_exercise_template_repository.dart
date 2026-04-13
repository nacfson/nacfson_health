import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/exercise_template.dart';
import 'exercise_template_repository.dart';

class SqliteExerciseTemplateRepository implements ExerciseTemplateRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  @override
  Future<List<ExerciseTemplate>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'exercise_templates',
      where: 'sync_status != ?',
      whereArgs: [TemplateSyncStatus.deleted.value],
      orderBy: 'updated_at ASC',
    );
    return result.map(_fromMap).toList();
  }

  @override
  Future<void> add(ExerciseTemplate template) async {
    final db = await _dbHelper.database;
    final record = template.copyWith(
      uuid: template.uuid.isEmpty ? _uuid.v4() : template.uuid,
      syncStatus: TemplateSyncStatus.created,
    );
    await db.insert(
      'exercise_templates',
      _toMap(record),
      conflictAlgorithm: ConflictAlgorithm.ignore, // name UNIQUE 충돌 시 무시
    );
  }

  @override
  Future<void> delete(String uuid) async {
    final db = await _dbHelper.database;
    await db.update(
      'exercise_templates',
      {
        'sync_status': TemplateSyncStatus.deleted.value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  @override
  Future<List<ExerciseTemplate>> getPendingSync() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'exercise_templates',
      where: 'sync_status != ?',
      whereArgs: [TemplateSyncStatus.synced.value],
    );
    return result.map(_fromMap).toList();
  }

  @override
  Future<void> markAsSynced(List<String> uuids) async {
    if (uuids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.update(
      'exercise_templates',
      {'sync_status': TemplateSyncStatus.synced.value},
      where: 'uuid IN (${uuids.map((_) => '?').join(',')})',
      whereArgs: uuids,
    );
  }

  @override
  Future<void> mergeRemoteTemplates(List<ExerciseTemplate> remote) async {
    // 수정 연산 없음 — 로컬에 없는 것만 insert, 이미 있으면 skip
    for (final t in remote) {
      final existing = await _findByUuid(t.uuid);
      if (existing == null) {
        final db = await _dbHelper.database;
        await db.insert(
          'exercise_templates',
          _toMap(t.copyWith(syncStatus: TemplateSyncStatus.synced)),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      // 이미 있으면 무시 (수정 연산 없음)
    }
  }

  @override
  Future<void> hardDeleteSyncedDeleted() async {
    final db = await _dbHelper.database;
    await db.delete(
      'exercise_templates',
      where: 'sync_status = ?',
      whereArgs: [TemplateSyncStatus.deleted.value],
    );
  }

  @override
  Future<void> resetAllSyncStatus() async {
    final db = await _dbHelper.database;
    await db.update(
      'exercise_templates',
      {'sync_status': TemplateSyncStatus.created.value},
      where: 'sync_status != ?',
      whereArgs: [TemplateSyncStatus.deleted.value],
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<ExerciseTemplate?> _findByUuid(String uuid) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'exercise_templates',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return _fromMap(result.first);
  }

  Map<String, dynamic> _toMap(ExerciseTemplate t) => {
        'uuid': t.uuid,
        'name': t.name,
        'updated_at': t.updatedAt.millisecondsSinceEpoch,
        'sync_status': t.syncStatus.value,
      };

  ExerciseTemplate _fromMap(Map<String, dynamic> map) => ExerciseTemplate(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        name: map['name'] as String,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
        syncStatus: TemplateSyncStatus.fromInt(map['sync_status'] as int),
      );
}
