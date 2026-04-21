import '../../../../core/database/base_syncable_sqlite_repository.dart';
import '../../../../core/database/database_helper.dart';
import '../../domain/entities/weight_record.dart';
import '../repositories/weight_repository.dart';

class SqliteWeightRepository extends BaseSyncableSqliteRepository<WeightRecord>
    implements WeightRepository {
  @override
  String get tableName => 'weight_records';

  @override
  WeightRecord copyWithSync(
    WeightRecord entity, {
    String? uuid,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) =>
      entity.copyWith(
        uuid: uuid,
        updatedAt: updatedAt,
        syncStatus: syncStatus,
      );

  /// 최신 체중 1건. 온보딩·요약 화면 등에서 사용.
  @override
  Future<WeightRecord?> getLatest() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query(
      tableName,
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.deleted.value],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return fromMap(result.first);
  }

  /// 차트용 기간 조회 (start · end 는 inclusive), timestamp ASC.
  @override
  Future<List<WeightRecord>> getByDateRange(DateTime start, DateTime end) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query(
      tableName,
      where: 'timestamp >= ? AND timestamp <= ? AND sync_status != ?',
      whereArgs: [
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
        SyncStatus.deleted.value,
      ],
      orderBy: 'timestamp ASC',
    );
    return result.map(fromMap).toList();
  }

  /// 체중은 하루에 한 건만 사용하므로 단일 반환. 리스트 반환을 하는
  /// 다른 도메인의 `getByDate` 와 시그니처가 다르다.
  @override
  Future<WeightRecord?> getByDate(DateTime date) async {
    final db = await DatabaseHelper.instance.database;
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final result = await db.query(
      tableName,
      where: 'timestamp >= ? AND timestamp < ? AND sync_status != ?',
      whereArgs: [
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
        SyncStatus.deleted.value,
      ],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return fromMap(result.first);
  }

  @override
  Map<String, dynamic> toMap(WeightRecord record) {
    return {
      'uuid': record.uuid,
      'timestamp': record.timestamp.millisecondsSinceEpoch,
      'updated_at': record.updatedAt.millisecondsSinceEpoch,
      'sync_status': record.syncStatus.value,
      'weight': record.weight,
    };
  }

  @override
  WeightRecord fromMap(Map<String, dynamic> map) {
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
