// modified(2) 없음 — 템플릿은 생성/삭제만 지원
enum TemplateSyncStatus {
  synced(0),
  created(1),
  deleted(3);

  final int value;
  const TemplateSyncStatus(this.value);

  static TemplateSyncStatus fromInt(int v) =>
      TemplateSyncStatus.values.firstWhere((e) => e.value == v);
}

class ExerciseTemplate {
  final int? id; // LOCAL ONLY — 시트 연동 시 사용 금지
  final String uuid; // 글로벌 PK (UUID v4)
  final String name; // 템플릿 이름 (unique)
  final String exerciseType; // v5 신규: 운동 유형 (가슴/등/팔/하체/어깨/코어)
  final DateTime updatedAt;
  final TemplateSyncStatus syncStatus;

  const ExerciseTemplate({
    this.id,
    required this.uuid,
    required this.name,
    this.exerciseType = '',
    required this.updatedAt,
    this.syncStatus = TemplateSyncStatus.created,
  });

  ExerciseTemplate copyWith({
    int? id,
    String? uuid,
    String? name,
    String? exerciseType,
    DateTime? updatedAt,
    TemplateSyncStatus? syncStatus,
  }) =>
      ExerciseTemplate(
        id: id ?? this.id,
        uuid: uuid ?? this.uuid,
        name: name ?? this.name,
        exerciseType: exerciseType ?? this.exerciseType,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}
