import 'package:nacfson_health/features/exercise/data/repositories/exercise_repository.dart';
import 'package:nacfson_health/features/exercise/domain/entities/exercise_record.dart';
import 'package:uuid/uuid.dart';

/// 인메모리 Exercise Repository — SQLite 없이 단위 테스트 가능
class FakeExerciseRepository implements ExerciseRepository {
  final List<ExerciseRecord> _store = [];
  final Uuid _uuid = const Uuid();

  @override
  Future<List<ExerciseRecord>> getAll() async {
    return _store
        .where((r) => r.syncStatus != SyncStatus.deleted)
        .toList();
  }

  @override
  Future<List<ExerciseRecord>> getByDate(DateTime date) async {
    return _store.where((r) {
      return r.syncStatus != SyncStatus.deleted &&
          r.timestamp.year == date.year &&
          r.timestamp.month == date.month &&
          r.timestamp.day == date.day;
    }).toList();
  }

  @override
  Future<void> add(ExerciseRecord record) async {
    _store.add(record.copyWith(
      uuid: record.uuid.isEmpty ? _uuid.v4() : record.uuid,
      syncStatus: SyncStatus.created,
    ));
  }

  @override
  Future<void> update(ExerciseRecord record) async {
    final idx = _store.indexWhere((r) => r.uuid == record.uuid);
    if (idx != -1) {
      _store[idx] = record.copyWith(
        updatedAt: DateTime.now(),
        syncStatus: SyncStatus.modified,
      );
    }
  }

  @override
  Future<void> delete(String uuid) async {
    final idx = _store.indexWhere((r) => r.uuid == uuid);
    if (idx != -1) {
      _store[idx] = _store[idx].copyWith(syncStatus: SyncStatus.deleted);
    }
  }

  @override
  Future<int> deleteByExerciseNameOnDate(
      String exerciseName, DateTime date) async {
    int count = 0;
    for (int i = 0; i < _store.length; i++) {
      final r = _store[i];
      final sameDay = r.timestamp.year == date.year &&
          r.timestamp.month == date.month &&
          r.timestamp.day == date.day;
      if (r.exerciseName == exerciseName &&
          sameDay &&
          r.syncStatus != SyncStatus.deleted) {
        _store[i] = r.copyWith(
          syncStatus: SyncStatus.deleted,
          updatedAt: DateTime.now(),
        );
        count++;
      }
    }
    return count;
  }

  @override
  Future<List<ExerciseRecord>> getPendingSync() async {
    return _store.where((r) => r.syncStatus != SyncStatus.synced).toList();
  }

  @override
  Future<void> markAsSynced(List<String> uuids) async {
    for (final uuid in uuids) {
      final idx = _store.indexWhere((r) => r.uuid == uuid);
      if (idx != -1) {
        _store[idx] = _store[idx].copyWith(syncStatus: SyncStatus.synced);
      }
    }
  }

  @override
  Future<void> mergeRemoteRecords(List<ExerciseRecord> remote) async {
    for (final remoteRecord in remote) {
      final idx = _store.indexWhere((r) => r.uuid == remoteRecord.uuid);
      if (idx == -1) {
        await add(remoteRecord);
      } else if (remoteRecord.updatedAt.isAfter(_store[idx].updatedAt)) {
        _store[idx] = remoteRecord;
      }
    }
  }

  @override
  Future<void> hardDeleteSyncedDeleted() async {
    _store.removeWhere((r) => r.syncStatus == SyncStatus.deleted);
  }

  @override
  Future<void> resetAllSyncStatus() async {
    for (int i = 0; i < _store.length; i++) {
      if (_store[i].syncStatus != SyncStatus.deleted) {
        _store[i] = _store[i].copyWith(syncStatus: SyncStatus.created);
      }
    }
  }

  // 테스트 편의 메서드
  void seed(List<ExerciseRecord> records) => _store.addAll(records);
  void clear() => _store.clear();
  int get count => _store.length;
}
