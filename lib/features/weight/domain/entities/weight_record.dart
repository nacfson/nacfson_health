import '../../../../core/sync/sync_status.dart';

export '../../../../core/sync/sync_status.dart' show SyncStatus;

class WeightRecord {
  final int? id; // LOCAL ONLY
  final String uuid; // 글로벌 PK (UUID v4)
  final DateTime timestamp;
  final DateTime updatedAt;
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
