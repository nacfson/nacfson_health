import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/sqlite_workout_routine_repository.dart';
import '../../data/repositories/workout_routine_repository.dart';
import '../../domain/entities/exercise_record.dart' show SyncStatus;
import '../../domain/entities/routine_item.dart';
import '../../domain/entities/workout_routine.dart';

class _MemoryWorkoutRoutineRepository implements WorkoutRoutineRepository {
  final List<WorkoutRoutine> _items = [];
  final Uuid _uuid = const Uuid();

  @override
  Future<List<WorkoutRoutine>> getAll() async {
    return _items
        .where((r) => r.syncStatus != SyncStatus.deleted)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<void> add(WorkoutRoutine routine) async {
    final id = _items.length + 1;
    _items.add(routine.copyWith(
      id: id,
      uuid: routine.uuid.isEmpty ? _uuid.v4() : routine.uuid,
    ));
  }

  @override
  Future<void> update(WorkoutRoutine routine) async {
    final i = _items.indexWhere((r) => r.uuid == routine.uuid);
    if (i != -1) {
      _items[i] = routine.copyWith(
        updatedAt: DateTime.now(),
        syncStatus: SyncStatus.modified,
      );
    }
  }

  @override
  Future<void> delete(String uuid) async {
    final i = _items.indexWhere((r) => r.uuid == uuid);
    if (i != -1) {
      _items[i] = _items[i].copyWith(syncStatus: SyncStatus.deleted);
    }
  }

  @override
  Future<List<WorkoutRoutine>> getPendingSync() async =>
      _items.where((r) => r.syncStatus != SyncStatus.synced).toList();

  @override
  Future<void> markAsSynced(List<String> uuids) async {
    for (final u in uuids) {
      final i = _items.indexWhere((r) => r.uuid == u);
      if (i != -1) _items[i] = _items[i].copyWith(syncStatus: SyncStatus.synced);
    }
  }

  @override
  Future<void> mergeRemoteRoutines(List<WorkoutRoutine> remote) async {
    for (final r in remote) {
      final i = _items.indexWhere((e) => e.uuid == r.uuid);
      if (i == -1) {
        _items.add(r.copyWith(syncStatus: SyncStatus.synced));
      } else if (r.updatedAt.isAfter(_items[i].updatedAt)) {
        _items[i] = r.copyWith(syncStatus: SyncStatus.synced);
      }
    }
  }

  @override
  Future<void> hardDeleteSyncedDeleted() async {
    _items.removeWhere((r) => r.syncStatus == SyncStatus.deleted);
  }

  @override
  Future<void> resetAllSyncStatus() async {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].syncStatus != SyncStatus.deleted) {
        _items[i] = _items[i].copyWith(syncStatus: SyncStatus.created);
      }
    }
  }
}

final workoutRoutineRepositoryProvider =
    Provider<WorkoutRoutineRepository>((ref) {
  if (kIsWeb) return _MemoryWorkoutRoutineRepository();
  return SqliteWorkoutRoutineRepository();
});

final workoutRoutinesProvider =
    StateNotifierProvider<WorkoutRoutineNotifier, List<WorkoutRoutine>>((ref) {
  return WorkoutRoutineNotifier(ref.watch(workoutRoutineRepositoryProvider));
});

class WorkoutRoutineNotifier extends StateNotifier<List<WorkoutRoutine>> {
  final WorkoutRoutineRepository _repository;

  WorkoutRoutineNotifier(this._repository) : super([]) {
    _load();
  }

  Future<void> _load() async {
    state = await _repository.getAll();
  }

  Future<void> refresh() => _load();

  Future<void> savePreset(String name, List<RoutineItem> items) async {
    if (items.isEmpty) return;
    final now = DateTime.now();
    await _repository.add(WorkoutRoutine(
      name: name.trim(),
      items: List.unmodifiable(items),
      createdAt: now,
      updatedAt: now,
    ));
    await _load();
  }

  Future<void> renamePreset(String uuid, String newName) async {
    final target = state.firstWhere((r) => r.uuid == uuid);
    await _repository.update(target.copyWith(name: newName.trim()));
    await _load();
  }

  Future<void> deletePreset(String uuid) async {
    await _repository.delete(uuid);
    await _load();
  }
}
