import '../../domain/entities/exercise_record.dart';

abstract class ExerciseRepository {
  Future<List<ExerciseRecord>> getAll();
  Future<List<ExerciseRecord>> getByDate(DateTime date);
  Future<ExerciseRecord> add(ExerciseRecord record);
  Future<ExerciseRecord> update(ExerciseRecord record);
  Future<void> delete(String uuid);

  /// 선택된 날짜의 특정 운동명 레코드를 모두 soft delete 한다.
  /// 반환값: 실제로 상태가 변경된 레코드 수.
  Future<int> deleteByExerciseNameOnDate(String exerciseName, DateTime date);

  // Sync 관련 메서드
  Future<List<ExerciseRecord>> getPendingSync();
  Future<void> markAsSynced(List<String> uuids);
  Future<void> mergeRemoteRecords(List<ExerciseRecord> remote);
  Future<void> hardDeleteSyncedDeleted();
  Future<void> resetAllSyncStatus(); // 스프레드시트 교체 시 전체 재동기화 초기화
}
