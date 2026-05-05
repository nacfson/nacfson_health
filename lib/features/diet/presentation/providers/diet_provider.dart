import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/selected_date_provider.dart';
import '../../domain/entities/diet_record.dart';
import '../../data/repositories/diet_repository.dart';
import '../../data/repositories/sqlite_diet_repository.dart';

final dietRepositoryProvider = Provider<DietRepository>((ref) {
  return SqliteDietRepository();
});

/// 식단 기록 SQLite 초기 로드 상태 (StateNotifier state 와 분리하여 노출).
final dietRecordsInitialLoadingProvider = StateProvider<bool>((ref) => true);

final dietRecordsProvider = StateNotifierProvider<DietNotifier, List<DietRecord>>((ref) {
  final repository = ref.watch(dietRepositoryProvider);
  return DietNotifier(repository, ref);
});

class DietNotifier extends StateNotifier<List<DietRecord>> {
  final DietRepository _repository;
  final Ref _ref;

  /// SnackBar Undo 가 가능한 5초 동안 메모리에서만 제거된 레코드.
  /// 5초 경과 시 [_pendingDeleteTimers] 가 실제 DB delete 를 호출하고 비움.
  final Map<String, DietRecord> _pendingDeletes = {};
  final Map<String, Timer> _pendingDeleteTimers = {};

  static const _undoWindow = Duration(seconds: 5);

  DietNotifier(this._repository, this._ref) : super([]) {
    _loadRecords();
  }

  @override
  void dispose() {
    for (final t in _pendingDeleteTimers.values) {
      t.cancel();
    }
    _pendingDeleteTimers.clear();
    _pendingDeletes.clear();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    state = await _repository.getAll();
    if (mounted) {
      _ref.read(dietRecordsInitialLoadingProvider.notifier).state = false;
    }
  }

  /// 동기화 완료 후 DB에서 최신 상태를 다시 로드합니다.
  Future<void> refresh() => _loadRecords();

  Future<void> addRecord(DietRecord record) async {
    final saved = await _repository.add(record);
    state = _sortDesc([...state, saved]);
  }

  Future<void> updateRecord(DietRecord record) async {
    final saved = await _repository.update(record);
    state = _sortDesc([
      for (final r in state) r.uuid == saved.uuid ? saved : r,
    ]);
  }

  Future<void> deleteRecord(String id) async {
    await _repository.delete(id);
    state = state.where((r) => r.uuid != id).toList();
  }

  /// 메모리에서만 즉시 제거하고 5초 안에 [restoreSoftDelete] 호출 시 복원 가능.
  /// 5초 후 자동으로 실제 DB delete 호출. UI 는 SnackBar action="되돌리기" 를 함께 노출한다.
  void softDelete(String id) {
    final target = state.firstWhere(
      (r) => r.uuid == id,
      orElse: () => throw StateError('record not found: $id'),
    );
    _pendingDeletes[id] = target;
    state = state.where((r) => r.uuid != id).toList();
    _pendingDeleteTimers[id]?.cancel();
    _pendingDeleteTimers[id] = Timer(_undoWindow, () {
      _commitOne(id);
    });
  }

  /// 사용자가 "되돌리기" 를 누른 경우. timer 취소 후 state 에 다시 삽입.
  void restoreSoftDelete(String id) {
    final pending = _pendingDeletes.remove(id);
    _pendingDeleteTimers.remove(id)?.cancel();
    if (pending == null) return;
    state = _sortDesc([...state, pending]);
  }

  /// 동기화 진입점에서 호출. 모든 pending 을 즉시 commit 하여 sync 누락 방지.
  Future<void> commitAllPending() async {
    final ids = _pendingDeletes.keys.toList();
    for (final id in ids) {
      _pendingDeleteTimers.remove(id)?.cancel();
      await _commitOne(id);
    }
  }

  Future<void> _commitOne(String id) async {
    if (!_pendingDeletes.containsKey(id)) return;
    _pendingDeletes.remove(id);
    _pendingDeleteTimers.remove(id);
    try {
      await _repository.delete(id);
    } catch (_) {
      // 삭제 실패 시 다음 sync 가 정정. 사용자 액션은 이미 끝남.
    }
  }

  /// `getAll()` 의 정렬 규약(timestamp DESC) 을 in-memory 갱신에서도 유지.
  static List<DietRecord> _sortDesc(List<DietRecord> list) =>
      list..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  List<DietRecord> getByDate(DateTime date) {
    return state.where((r) =>
      r.timestamp.year == date.year &&
      r.timestamp.month == date.month &&
      r.timestamp.day == date.day
    ).toList();
  }
}

/// 오늘(00:00~23:59) 식단 기록 목록 - 최신순
final todayDietRecordsProvider = Provider<List<DietRecord>>((ref) {
  final all = ref.watch(dietRecordsProvider);
  final today = DateTime.now();
  return all
      .where((r) =>
          r.timestamp.year == today.year &&
          r.timestamp.month == today.month &&
          r.timestamp.day == today.day)
      .toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
});

/// 오늘 식단 기록 - mealType별 그룹핑 (시간대 순서 고정)
final todayDietGroupedProvider =
    Provider<Map<String, List<DietRecord>>>((ref) {
  final records = ref.watch(todayDietRecordsProvider);
  const mealOrder = ['아침', '점심', '저녁', '간식'];
  final Map<String, List<DietRecord>> grouped = {};
  for (final meal in mealOrder) {
    final list = records.where((r) => r.mealType == meal).toList();
    if (list.isNotEmpty) grouped[meal] = list;
  }
  return grouped;
});

/// 오늘 칼로리 / 매크로 합계
final todayDietSummaryProvider =
    Provider<({int kcal, double carbs, double protein, double fat})>((ref) {
  final records = ref.watch(todayDietRecordsProvider);
  return (
    kcal: records.fold(0, (s, r) => s + r.totalCalories),
    carbs: records.fold(0.0, (s, r) => s + r.carbs),
    protein: records.fold(0.0, (s, r) => s + r.protein),
    fat: records.fold(0.0, (s, r) => s + r.fat),
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// 선택 날짜 기반 Provider (Observer 패턴 — selectedDateProvider 변경 시 자동 갱신)
// ─────────────────────────────────────────────────────────────────────────────

/// 선택 날짜의 식단 기록 목록 - 최신순
final selectedDateDietRecordsProvider = Provider<List<DietRecord>>((ref) {
  final all = ref.watch(dietRecordsProvider);
  final date = ref.watch(selectedDateProvider);
  return all
      .where((r) =>
          r.timestamp.year == date.year &&
          r.timestamp.month == date.month &&
          r.timestamp.day == date.day)
      .toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
});

/// 선택 날짜 식단 기록 — mealType별 그룹핑 (시간대 순서 고정)
final selectedDateDietGroupedProvider =
    Provider<Map<String, List<DietRecord>>>((ref) {
  final records = ref.watch(selectedDateDietRecordsProvider);
  const mealOrder = ['아침', '점심', '저녁', '간식'];
  final Map<String, List<DietRecord>> grouped = {};
  for (final meal in mealOrder) {
    final list = records.where((r) => r.mealType == meal).toList();
    if (list.isNotEmpty) grouped[meal] = list;
  }
  return grouped;
});

/// 선택 날짜의 칼로리 / 매크로 합계
final selectedDateDietSummaryProvider =
    Provider<({int kcal, double carbs, double protein, double fat})>((ref) {
  final records = ref.watch(selectedDateDietRecordsProvider);
  return (
    kcal: records.fold(0, (s, r) => s + r.totalCalories),
    carbs: records.fold(0.0, (s, r) => s + r.carbs),
    protein: records.fold(0.0, (s, r) => s + r.protein),
    fat: records.fold(0.0, (s, r) => s + r.fat),
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// 최근 고유 음식 (입력 단축 — 시트 상단 "최근 식사에서 다시 추가" 섹션에서 사용)
// ─────────────────────────────────────────────────────────────────────────────

/// 최근 7일 내 고유 음식(foodName) 기록 — 같은 이름은 가장 최근 것만 남김, 최대 10개
final recentUniqueDietRecordsProvider = Provider<List<DietRecord>>((ref) {
  final all = ref.watch(dietRecordsProvider);
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  final sorted = all
      .where((r) =>
          r.syncStatus != SyncStatus.deleted &&
          r.timestamp.isAfter(cutoff))
      .toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  final seen = <String>{};
  final result = <DietRecord>[];
  for (final r in sorted) {
    final key = r.foodName.trim();
    if (key.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    result.add(r);
    if (result.length >= 10) break;
  }
  return result;
});

// ─────────────────────────────────────────────────────────────────────────────
// 칼로리 추세 차트 데이터 (Strategy 패턴 — ChartViewType으로 기간 전략 전환)
// ─────────────────────────────────────────────────────────────────────────────

enum DietChartViewType { weekly, monthly }

final dietChartViewTypeProvider =
    StateProvider<DietChartViewType>((ref) => DietChartViewType.weekly);

/// 칼로리 추세 데이터: 일별 (날짜, 칼로리) 리스트
final calorieTrendDataProvider =
    Provider<List<({DateTime date, int calories})>>((ref) {
  final all = ref.watch(dietRecordsProvider);
  final viewType = ref.watch(dietChartViewTypeProvider);
  final now = DateTime.now();

  final int daysBack = switch (viewType) {
    DietChartViewType.weekly => 6,
    DietChartViewType.monthly => 29,
  };
  final startDate = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: daysBack));

  final filtered = all.where((r) =>
      r.timestamp.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
      r.syncStatus != SyncStatus.deleted);

  // 일별 칼로리 집계
  final Map<String, int> dailyCalories = {};
  for (final r in filtered) {
    final key = '${r.timestamp.year}-${r.timestamp.month}-${r.timestamp.day}';
    dailyCalories[key] = (dailyCalories[key] ?? 0) + r.totalCalories;
  }

  final List<({DateTime date, int calories})> result = [];
  for (int i = 0; i <= daysBack; i++) {
    final date = startDate.add(Duration(days: i));
    final key = '${date.year}-${date.month}-${date.day}';
    result.add((date: date, calories: dailyCalories[key] ?? 0));
  }

  return result;
});