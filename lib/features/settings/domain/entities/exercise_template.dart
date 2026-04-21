import '../../../../core/database/syncable_entity.dart';
import '../../../../core/sync/sync_status.dart';

export '../../../../core/sync/sync_status.dart' show TemplateSyncStatus;

class ExerciseTemplate implements TemplateSyncableEntity {
  final int? id; // LOCAL ONLY — 시트 연동 시 사용 금지
  @override
  final String uuid; // 글로벌 PK (UUID v4)
  final String name; // 템플릿 이름 (unique)
  final String exerciseType; // v5 신규: 운동 유형 (가슴/등/팔/하체/어깨/코어)
  @override
  final DateTime updatedAt;
  @override
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
