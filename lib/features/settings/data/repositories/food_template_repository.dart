import '../../domain/entities/food_template.dart';

abstract class FoodTemplateRepository {
  /// 삭제된 항목 제외 전체 목록
  Future<List<FoodTemplate>> getAll();

  /// 새 템플릿 추가 (uuid 빈 문자열 → 자동 생성)
  Future<void> add(FoodTemplate template);

  /// Soft delete (sync_status = deleted)
  Future<void> delete(String uuid);

  // ── Sync 전용 ─────────────────────────────────────────
  Future<List<FoodTemplate>> getPendingSync(); // status != synced
  Future<void> markAsSynced(List<String> uuids);
  Future<void> mergeRemoteTemplates(List<FoodTemplate> remote); // insert-or-skip
  Future<void> hardDeleteSyncedDeleted();
  Future<void> resetAllSyncStatus(); // 스프레드시트 교체 시
}
