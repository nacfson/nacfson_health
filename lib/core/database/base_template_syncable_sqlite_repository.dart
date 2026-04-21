import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../sync/sync_status.dart';
import 'database_helper.dart';
import 'syncable_entity.dart';

/// 템플릿(운동 템플릿·음식 템플릿) 전용 SQLite 레포지토리 공통 구현.
///
/// - 생성/삭제만 지원하며 `update` 연산이 없다 → `TemplateSyncStatus` 사용.
/// - `name` UNIQUE 제약이 있어 insert 는 `ConflictAlgorithm.ignore` 로 수행.
/// - 원격 병합은 insert-or-skip (LWW 아님).
abstract class BaseTemplateSyncableSqliteRepository<
    T extends TemplateSyncableEntity> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  // ── Subclass 구현 훅 ──────────────────────────────────────────────────────

  String get tableName;
  Map<String, dynamic> toMap(T entity);
  T fromMap(Map<String, dynamic> map);

  T copyWithSync(
    T entity, {
    String? uuid,
    TemplateSyncStatus? syncStatus,
  });

  // ── 공통 구현 ────────────────────────────────────────────────────────────

  Future<List<T>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      tableName,
      where: 'sync_status != ?',
      whereArgs: [TemplateSyncStatus.deleted.value],
      orderBy: 'updated_at ASC',
    );
    return result.map(fromMap).toList();
  }

  Future<void> add(T template) async {
    final db = await _dbHelper.database;
    final record = copyWithSync(
      template,
      uuid: template.uuid.isEmpty ? _uuid.v4() : template.uuid,
      syncStatus: TemplateSyncStatus.created,
    );
    await db.insert(
      tableName,
      toMap(record),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> delete(String uuid) async {
    final db = await _dbHelper.database;
    await db.update(
      tableName,
      {
        'sync_status': TemplateSyncStatus.deleted.value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<List<T>> getPendingSync() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      tableName,
      where: 'sync_status != ?',
      whereArgs: [TemplateSyncStatus.synced.value],
    );
    return result.map(fromMap).toList();
  }

  Future<void> markAsSynced(List<String> uuids) async {
    if (uuids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.update(
      tableName,
      {'sync_status': TemplateSyncStatus.synced.value},
      where: 'uuid IN (${uuids.map((_) => '?').join(',')})',
      whereArgs: uuids,
    );
  }

  /// insert-or-skip: 로컬에 없는 것만 synced 상태로 삽입. 이미 있으면 무시.
  Future<void> mergeRemoteTemplates(List<T> remote) async {
    for (final t in remote) {
      final existing = await findByUuid(t.uuid);
      if (existing == null) {
        final db = await _dbHelper.database;
        await db.insert(
          tableName,
          toMap(copyWithSync(t, syncStatus: TemplateSyncStatus.synced)),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  Future<void> hardDeleteSyncedDeleted() async {
    final db = await _dbHelper.database;
    await db.delete(
      tableName,
      where: 'sync_status = ?',
      whereArgs: [TemplateSyncStatus.deleted.value],
    );
  }

  Future<void> resetAllSyncStatus() async {
    final db = await _dbHelper.database;
    await db.update(
      tableName,
      {'sync_status': TemplateSyncStatus.created.value},
      where: 'sync_status != ?',
      whereArgs: [TemplateSyncStatus.deleted.value],
    );
  }

  // ── 보조 헬퍼 ───────────────────────────────────────────────────────────

  Future<T?> findByUuid(String uuid) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      tableName,
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return fromMap(result.first);
  }
}
