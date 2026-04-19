import '../../domain/entities/exercise_record.dart';

abstract class ExerciseRepository {
  Future<List<ExerciseRecord>> getAll();
  Future<List<ExerciseRecord>> getByDate(DateTime date);
  Future<void> add(ExerciseRecord record);
  Future<void> update(ExerciseRecord record);
  Future<void> delete(String uuid);

  // Sync 관련 메서드
  Future<List<ExerciseRecord>> getPendingSync();
  Future<void> markAsSynced(List<String> uuids);
  Future<void> mergeRemoteRecords(List<ExerciseRecord> remote);
  Future<void> hardDeleteSyncedDeleted();
  Future<void> resetAllSyncStatus(); // 스프레드시트 교체 시 전체 재동기화 초기화
}
