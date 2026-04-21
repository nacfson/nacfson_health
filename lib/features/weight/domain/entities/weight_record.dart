import '../../../../core/database/syncable_entity.dart';
import '../../../../core/sync/sync_status.dart';

export '../../../../core/sync/sync_status.dart' show SyncStatus;

class WeightRecord implements SyncableEntity {
  final int? id; // LOCAL ONLY
  @override
  final String uuid; // 글로벌 PK (UUID v4)
  @override
  final DateTime timestamp;
  @override
  final DateTime updatedAt;
  @override
  final SyncStatus syncStatus;
  final double weight;

  const WeightRecord({
    this.id,
    this.uuid = '',
    required this.timestamp,
    required this.updatedAt,
    this.syncStatus = SyncStatus.created,
    required this.weight,
  });

  WeightRecord copyWith({
    int? id,
    String? uuid,
    DateTime? timestamp,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    double? weight,
  }) {
    return WeightRecord(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      timestamp: timestamp ?? this.timestamp,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      weight: weight ?? this.weight,
    );
  }
}
