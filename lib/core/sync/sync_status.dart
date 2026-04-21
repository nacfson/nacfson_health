/// 레코드(운동/식단/체중/루틴/프로필) 공용 동기화 상태.
///
/// DB 의 `sync_status` 컬럼에 저장되는 정수값(0/1/2/3) 과 1:1 매핑된다.
/// - `synced(0)`: 서버와 동일
/// - `created(1)`: Push 로 Insert 필요
/// - `modified(2)`: Push 로 Update 필요
/// - `deleted(3)`: Soft delete — Push 후 Hard delete
enum SyncStatus {
  synced(0),
  created(1),
  modified(2),
  deleted(3);

  final int value;
  const SyncStatus(this.value);

  static SyncStatus fromInt(int v) =>
      SyncStatus.values.firstWhere((e) => e.value == v);
}

/// 템플릿(운동 템플릿·음식 템플릿) 전용 동기화 상태.
///
/// 템플릿은 생성/삭제만 지원하므로 `modified(2)` 는 없다.
/// `SyncStatus` 와 정수값을 공유하여 DB 데이터 하위 호환을 유지한다.
enum TemplateSyncStatus {
  synced(0),
  created(1),
  deleted(3);

  final int value;
  const TemplateSyncStatus(this.value);

  static TemplateSyncStatus fromInt(int v) =>
      TemplateSyncStatus.values.firstWhere((e) => e.value == v);
}
