import '../../domain/entities/weight_record.dart';

abstract class WeightRepository {
  Future<List<WeightRecord>> getAll();
  Future<WeightRecord?> getLatest();
  Future<List<WeightRecord>> getByDateRange(DateTime start, DateTime end);
  Future<WeightRecord?> getByDate(DateTime date);
  Future<void> add(WeightRecord record);
  Future<void> update(WeightRecord record);
  Future<void> delete(String uuid);

  // Sync 관련 메서드
  Future<List<WeightRecord>> getPendingSync();
  Future<void> markAsSynced(List<String> uuids);
  Future<void> mergeRemoteRecords(List<WeightRecord> remote);
  Future<void> hardDeleteSyncedDeleted();
  Future<void> resetAllSyncStatus();
}
