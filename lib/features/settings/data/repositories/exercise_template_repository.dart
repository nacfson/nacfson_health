import '../../domain/entities/exercise_template.dart';
import '../default_exercise_templates.dart';

abstract class ExerciseTemplateRepository {
  /// 삭제된 항목 제외 전체 목록
  Future<List<ExerciseTemplate>> getAll();

  /// 새 템플릿 추가 (uuid 빈 문자열 → 자동 생성)
  Future<void> add(ExerciseTemplate template);

  /// Soft delete (sync_status = deleted)
  Future<void> delete(String uuid);

  /// 종목별 휴식 시간 오버라이드 업데이트(초).
  ///
  /// [seconds] 가 `null` 이면 오버라이드를 제거해 부위 기본값으로 되돌린다.
  /// 내부적으로 `sync_status` 를 `created` 로 표시해 다음 동기화에서 upsert 된다.
  Future<void> updateRestOverride(String uuid, int? seconds);

  /// 기본 템플릿 시드. 결정론적 UUID v5로 name UNIQUE 충돌 시 자연 dedup.
  /// 반환값은 실제 삽입된 건수.
  Future<int> seedDefaults(List<DefaultExerciseTemplateSeed> seeds);

  // ── Sync 전용 ─────────────────────────────────────────────────────────────
  Future<List<ExerciseTemplate>> getPendingSync(); // status != synced
  Future<void> markAsSynced(List<String> uuids);
  Future<void> mergeRemoteTemplates(List<ExerciseTemplate> remote); // insert-or-skip
  Future<void> hardDeleteSyncedDeleted();
  Future<void> resetAllSyncStatus(); // 스프레드시트 교체 시 전체 재업로드 초기화
}
