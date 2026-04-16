enum SyncStatus {
  synced(0), // 시트와 동일
  created(1), // Insert 필요
  modified(2), // Update 필요
  deleted(3); // Soft Delete

  final int value;
  const SyncStatus(this.value);

  static SyncStatus fromInt(int v) =>
      SyncStatus.values.firstWhere((e) => e.value == v);
}

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
