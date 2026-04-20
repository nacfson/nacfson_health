import '../../domain/entities/workout_routine.dart';

abstract class WorkoutRoutineRepository {
  /// 삭제된 항목 제외 전체 목록 (최신 수정 순)
  Future<List<WorkoutRoutine>> getAll();

  /// 새 프리셋 추가 (uuid 빈 문자열 → 자동 생성)
  Future<void> add(WorkoutRoutine routine);

  /// 이름/항목 수정
  Future<void> update(WorkoutRoutine routine);

  /// Soft delete (sync_status = deleted)
  Future<void> delete(String uuid);

  // ── Sync 전용 ─────────────────────────────────────────────────────────────
  Future<List<WorkoutRoutine>> getPendingSync(); // status != synced
  Future<void> markAsSynced(List<String> uuids);
  Future<void> mergeRemoteRoutines(List<WorkoutRoutine> remote); // LWW
  Future<void> hardDeleteSyncedDeleted();
  Future<void> resetAllSyncStatus();
}
