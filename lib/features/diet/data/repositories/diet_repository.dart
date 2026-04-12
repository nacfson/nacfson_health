import '../../domain/entities/diet_record.dart';

abstract class DietRepository {
  Future<List<DietRecord>> getAll();
  Future<List<DietRecord>> getByDate(DateTime date);
  Future<void> add(DietRecord record);
  Future<void> update(DietRecord record);
  Future<void> delete(String uuid);

  // Sync 관련 메서드
  Future<List<DietRecord>> getPendingSync();
  Future<void> markAsSynced(List<String> uuids);
  Future<void> mergeRemoteRecords(List<DietRecord> remote);
  Future<void> hardDeleteSyncedDeleted();
  Future<void> resetAllSyncStatus(); // 스프레드시트 교체 시 전체 재동기화 초기화
}
