import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/selected_date_provider.dart';
import '../../data/repositories/daily_routine_repository.dart';
import '../../domain/entities/daily_routine.dart';
import '../../domain/entities/routine_item.dart';

class _MemoryDailyRoutineRepository implements DailyRoutineRepository {
  final Map<String, DailyRoutine> _store = {};

  @override
  Future<DailyRoutine?> getByDate(DateTime date) async =>
      _store[DailyRoutine.formatDate(date)];

  @override
  Future<void> upsert(DailyRoutine routine) async {
    _store[DailyRoutine.formatDate(routine.date)] = routine;
  }

  @override
  Future<void> deleteByDate(DateTime date) async {
    _store.remove(DailyRoutine.formatDate(date));
  }
}

final dailyRoutineRepositoryProvider =
    Provider<DailyRoutineRepository>((ref) {
  if (kIsWeb) return _MemoryDailyRoutineRepository();
  return SqliteDailyRoutineRepository();
});

/// 오늘(또는 선택된 날짜의 오늘) 루틴 항목 리스트를 관리한다.
/// 선택 날짜가 변경되면 해당 일자의 루틴을 다시 로드한다.
final routinePlannerProvider =
    StateNotifierProvider<RoutinePlannerNotifier, List<RoutineItem>>((ref) {
  final repo = ref.watch(dailyRoutineRepositoryProvider);
  final date = ref.watch(selectedDateProvider);
  return RoutinePlannerNotifier(repo, date);
});

class RoutinePlannerNotifier extends StateNotifier<List<RoutineItem>> {
  final DailyRoutineRepository _repository;
  final DateTime _date;

  RoutinePlannerNotifier(this._repository, this._date) : super(const []) {
    _load();
  }

  Future<void> _load() async {
    final routine = await _repository.getByDate(_date);
    state = routine?.items ?? const [];
  }

  Future<void> _persist(List<RoutineItem> items) async {
    state = List.unmodifiable(items);
    await _repository.upsert(DailyRoutine(
      date: _date,
      items: state,
      updatedAt: DateTime.now(),
    ));
  }

  /// 같은 이름의 운동이 이미 있으면 무시한다.
  Future<void> addItem(RoutineItem item) async {
    if (state.any((i) => i.exerciseName == item.exerciseName)) return;
    await _persist([...state, item]);
  }

  Future<void> removeByName(String exerciseName) async {
    await _persist(state.where((i) => i.exerciseName != exerciseName).toList());
  }

  Future<void> replaceAll(List<RoutineItem> items) async {
    final dedup = <String, RoutineItem>{};
    for (final i in items) {
      dedup.putIfAbsent(i.exerciseName, () => i);
    }
    await _persist(dedup.values.toList());
  }

  /// 기존 항목은 유지하고, 중복되지 않는 항목만 뒤에 추가한다.
  Future<void> appendMany(List<RoutineItem> items) async {
    final existing = state.map((i) => i.exerciseName).toSet();
    final merged = [...state];
    for (final i in items) {
      if (existing.add(i.exerciseName)) merged.add(i);
    }
    await _persist(merged);
  }

  Future<void> clear() async {
    await _persist(const []);
  }
}
