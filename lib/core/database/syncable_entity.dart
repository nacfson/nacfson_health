import '../sync/sync_status.dart';

/// 레코드(운동·식단·체중) 공용 필드 계약.
///
/// `BaseSyncableSqliteRepository<T>` 가 이 계약을 통해 `getByDate` 나
/// LWW 충돌 해결을 구현한다.
abstract class SyncableEntity {
  String get uuid;
  DateTime get timestamp;
  DateTime get updatedAt;
  SyncStatus get syncStatus;
}

/// 템플릿(운동 템플릿·음식 템플릿) 공용 필드 계약.
///
/// 템플릿은 `timestamp` 가 없고 `updated_at` 만으로 정렬한다.
abstract class TemplateSyncableEntity {
  String get uuid;
  DateTime get updatedAt;
  TemplateSyncStatus get syncStatus;
}
