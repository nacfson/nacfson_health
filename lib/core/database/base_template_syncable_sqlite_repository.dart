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

  /// SQLite 기본 SQLITE_MAX_VARIABLE_NUMBER(999) 대비 여유 마진.
  static const int _maxBindsPerQuery = 900;

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
    for (var i = 0; i < uuids.length; i += _maxBindsPerQuery) {
      final end = i + _maxBindsPerQuery;
      final chunk = uuids.sublist(i, end > uuids.length ? uuids.length : end);
      await db.update(
        tableName,
        {'sync_status': TemplateSyncStatus.synced.value},
        where: 'uuid IN (${chunk.map((_) => '?').join(',')})',
        whereArgs: chunk,
      );
    }
  }

  /// insert-or-skip: 로컬에 없는 것만 synced 상태로 삽입. 이미 있으면 무시.
  ///
  /// 원격 목록이 클 때 `findByUuid` 를 건건이 호출하면 N+1 패턴이므로
  /// 기존 UUID 를 한 번(혹은 청크 단위)에 조회해 Set 으로 만들고, 트랜잭션 안에서 insert 한다.
  Future<void> mergeRemoteTemplates(List<T> remote) async {
    if (remote.isEmpty) return;
    final existingUuids =
        await _findExistingUuids(remote.map((t) => t.uuid).toList());
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final t in remote) {
        if (existingUuids.contains(t.uuid)) continue;
        await txn.insert(
          tableName,
          toMap(copyWithSync(t, syncStatus: TemplateSyncStatus.synced)),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<Set<String>> _findExistingUuids(List<String> uuids) async {
    if (uuids.isEmpty) return const <String>{};
    final db = await _dbHelper.database;
    final result = <String>{};
    for (var i = 0; i < uuids.length; i += _maxBindsPerQuery) {
      final end = i + _maxBindsPerQuery;
      final chunk = uuids.sublist(i, end > uuids.length ? uuids.length : end);
      final rows = await db.query(
        tableName,
        columns: const ['uuid'],
        where: 'uuid IN (${chunk.map((_) => '?').join(',')})',
        whereArgs: chunk,
      );
      for (final row in rows) {
        final uuid = row['uuid'] as String?;
        if (uuid != null) result.add(uuid);
      }
    }
    return result;
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
