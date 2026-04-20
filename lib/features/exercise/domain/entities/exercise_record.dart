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

/// 세트 타입 — 볼륨/PR 집계 시 `work`(기본)와 `drop`을 포함하고 웜업/실패는 제외한다.
/// 드롭세트는 본세트와 함께 집계에 포함(근성장 기여).
enum SetType {
  warmup('warmup'),
  work('work'),
  drop('drop'),
  failure('failure');

  final String value;
  const SetType(this.value);

  static SetType fromString(String? v) {
    if (v == null) return SetType.work;
    return SetType.values.firstWhere(
      (e) => e.value == v,
      orElse: () => SetType.work,
    );
  }
}

class ExerciseRecord {
  final int? id; // LOCAL ONLY - 시트 연동 시 사용 금지
  final String uuid; // 글로벌 PK (UUID v4), 빈 문자열이면 Repository에서 자동 생성
  final DateTime timestamp;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final String exerciseType;
  final String exerciseName;
  final int currentSet;
  final double weight;
  final int reps;
  final double rpe;
  final SetType setType;

  const ExerciseRecord({
    this.id,
    this.uuid = '', // 빈 문자열이면 Repository에서 UUID v4 자동 생성
    required this.timestamp,
    required this.updatedAt,
    this.syncStatus = SyncStatus.created,
    required this.exerciseType,
    required this.exerciseName,
    required this.currentSet,
    required this.weight,
    required this.reps,
    required this.rpe,
    this.setType = SetType.work,
  });

  double get volume => weight * reps;

  /// 볼륨 집계 포함 여부 (웜업/실패는 제외).
  bool get countsTowardVolume =>
      setType == SetType.work || setType == SetType.drop;

  ExerciseRecord copyWith({
    int? id,
    String? uuid,
    DateTime? timestamp,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    String? exerciseType,
    String? exerciseName,
    int? currentSet,
    double? weight,
    int? reps,
    double? rpe,
    SetType? setType,
  }) {
    return ExerciseRecord(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      timestamp: timestamp ?? this.timestamp,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      exerciseType: exerciseType ?? this.exerciseType,
      exerciseName: exerciseName ?? this.exerciseName,
      currentSet: currentSet ?? this.currentSet,
      weight: weight ?? this.weight,
      reps: reps ?? this.reps,
      rpe: rpe ?? this.rpe,
      setType: setType ?? this.setType,
    );
  }
}
