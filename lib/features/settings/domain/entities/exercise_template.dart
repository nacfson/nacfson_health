import '../../../../core/database/syncable_entity.dart';
import '../../../../core/sync/sync_status.dart';

export '../../../../core/sync/sync_status.dart' show TemplateSyncStatus;

/// copyWith 의 nullable 필드(`restSecondsOverride`) 에서
/// "값 그대로 두기" 와 "null 로 초기화" 를 구분하기 위한 sentinel.
const Object _restOverrideSentinel = Object();

class ExerciseTemplate implements TemplateSyncableEntity {
  final int? id; // LOCAL ONLY — 시트 연동 시 사용 금지
  @override
  final String uuid; // 글로벌 PK (UUID v4)
  final String name; // 템플릿 이름 (unique)
  final String exerciseType; // v5 신규: 운동 유형 (가슴/등/팔/하체/어깨/코어)

  /// 종목별 휴식 시간 오버라이드(초). null 이면 부위 기본값을 사용한다.
  /// 유효 범위는 `kMinRestSeconds` ~ `kMaxRestSeconds` (60 ~ 300).
  final int? restSecondsOverride;

  @override
  final DateTime updatedAt;
  @override
  final TemplateSyncStatus syncStatus;

  const ExerciseTemplate({
    this.id,
    required this.uuid,
    required this.name,
    this.exerciseType = '',
    this.restSecondsOverride,
    required this.updatedAt,
    this.syncStatus = TemplateSyncStatus.created,
  });

  ExerciseTemplate copyWith({
    int? id,
    String? uuid,
    String? name,
    String? exerciseType,
    Object? restSecondsOverride = _restOverrideSentinel,
    DateTime? updatedAt,
    TemplateSyncStatus? syncStatus,
  }) =>
      ExerciseTemplate(
        id: id ?? this.id,
        uuid: uuid ?? this.uuid,
        name: name ?? this.name,
        exerciseType: exerciseType ?? this.exerciseType,
        restSecondsOverride: identical(restSecondsOverride, _restOverrideSentinel)
            ? this.restSecondsOverride
            : restSecondsOverride as int?,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}
