import 'package:uuid/uuid.dart';

import '../sync/sync_status.dart';
import 'database_helper.dart';
import 'syncable_entity.dart';

/// `timestamp` 를 가진 레코드형 SQLite 레포지토리의 공통 구현.
///
/// - exercise_records · diet_records · weight_records 가 이 base 를 사용한다.
/// - Weight 처럼 단일 반환 `getByDate` 가 필요한 경우 subclass 에서 별도 정의하고
///   [queryByDate] 헬퍼는 List 반환 버전만 제공한다.
/// - `workout_routines` 는 `timestamp` 가 없고 `mergeRemote` 의미론이 달라 제외.
abstract class BaseSyncableSqliteRepository<T extends SyncableEntity> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();

  /// SQLite 기본 SQLITE_MAX_VARIABLE_NUMBER(999) 대비 여유 마진.
  static const int _maxBindsPerQuery = 900;

  // ── Subclass 구현 훅 ──────────────────────────────────────────────────────

  String get tableName;
  Map<String, dynamic> toMap(T entity);
  T fromMap(Map<String, dynamic> map);

  /// Repository 가 sync 메타데이터(uuid/updatedAt/syncStatus) 를 갱신할 때 사용.
  /// 각 엔티티의 수동 `copyWith` 를 subclass 에서 그대로 위임한다.
  T copyWithSync(
    T entity, {
    String? uuid,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  });

  // ── 공통 구현 ────────────────────────────────────────────────────────────

  Future<List<T>> getAll() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      tableName,
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.deleted.value],
      orderBy: 'timestamp DESC',
    );
    return result.map(fromMap).toList();
  }

  /// 특정 날짜(하루) 레코드 목록을 timestamp 내림차순으로 반환.
  /// Exercise/Diet 의 public `getByDate` 는 이 헬퍼의 얇은 래퍼.
  Future<List<T>> queryByDate(DateTime date) async {
    final db = await _dbHelper.database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final result = await db.query(
      tableName,
      where: 'timestamp >= ? AND timestamp < ? AND sync_status != ?',
      whereArgs: [
        startOfDay.millisecondsSinceEpoch,
        endOfDay.millisecondsSinceEpoch,
        SyncStatus.deleted.value,
      ],
      orderBy: 'timestamp DESC',
    );
    return result.map(fromMap).toList();
  }

  Future<void> add(T record) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final newRecord = copyWithSync(
      record,
      uuid: record.uuid.isEmpty ? _uuid.v4() : record.uuid,
      updatedAt: record.timestamp.isBefore(now) ? record.timestamp : now,
      syncStatus: SyncStatus.created,
    );
    await db.insert(tableName, toMap(newRecord));
  }

  Future<void> update(T record) async {
    final db = await _dbHelper.database;
    final updated = copyWithSync(
      record,
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.modified,
    );
    await db.update(
      tableName,
      toMap(updated),
      where: 'uuid = ?',
      whereArgs: [record.uuid],
    );
  }

  Future<void> delete(String uuid) async {
    final db = await _dbHelper.database;
    await db.update(
      tableName,
      {
        'sync_status': SyncStatus.deleted.value,
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
      whereArgs: [SyncStatus.synced.value],
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
        {'sync_status': SyncStatus.synced.value},
        where: 'uuid IN (${chunk.map((_) => '?').join(',')})',
        whereArgs: chunk,
      );
    }
  }

  /// LWW (Last-Write-Wins): uuid 가 없으면 insert, 있으면 updated_at 이 더 큰 쪽으로 덮어쓴다.
  ///
  /// Insert 경로는 `add()` 를 재사용하지 않는다 — `add()` 는 `updatedAt` 을 현재 시간으로 덮고
  /// `syncStatus` 를 `created` 로 강제하므로, remote 메타데이터가 왜곡되어 다음 push 때
  /// 서버의 `updated_at` 을 과거 값으로 되돌릴 위험이 있다.
  Future<void> mergeRemoteRecords(List<T> remote) async {
    for (final remoteRecord in remote) {
      final existing = await findByUuid(remoteRecord.uuid);
      if (existing == null) {
        await _insertFromRemote(remoteRecord);
      } else {
        final remoteTime = remoteRecord.updatedAt.millisecondsSinceEpoch;
        final localTime = existing.updatedAt.millisecondsSinceEpoch;
        if (remoteTime > localTime) {
          await hardUpdate(remoteRecord);
        }
      }
    }
  }

  Future<void> _insertFromRemote(T remoteRecord) async {
    final db = await _dbHelper.database;
    final synced = copyWithSync(
      remoteRecord,
      syncStatus: SyncStatus.synced,
    );
    await db.insert(tableName, toMap(synced));
  }

  Future<void> hardDeleteSyncedDeleted() async {
    final db = await _dbHelper.database;
    await db.delete(
      tableName,
      where: 'sync_status = ?',
      whereArgs: [SyncStatus.deleted.value],
    );
  }

  Future<void> resetAllSyncStatus() async {
    final db = await _dbHelper.database;
    await db.update(
      tableName,
      {'sync_status': SyncStatus.created.value},
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.deleted.value],
    );
  }

  // ── 보조 헬퍼 (subclass 재사용 허용) ──────────────────────────────────────

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

  Future<void> hardUpdate(T record) async {
    final db = await _dbHelper.database;
    await db.update(
      tableName,
      toMap(record),
      where: 'uuid = ?',
      whereArgs: [record.uuid],
    );
  }
}
