import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/diet_record.dart';
import '../../data/repositories/diet_repository.dart';
import '../../data/repositories/sqlite_diet_repository.dart';

final dietRepositoryProvider = Provider<DietRepository>((ref) {
  return SqliteDietRepository();
});

final dietRecordsProvider = StateNotifierProvider<DietNotifier, List<DietRecord>>((ref) {
  final repository = ref.watch(dietRepositoryProvider);
  return DietNotifier(repository);
});

class DietNotifier extends StateNotifier<List<DietRecord>> {
  final DietRepository _repository;

  DietNotifier(this._repository) : super([]) {
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    state = await _repository.getAll();
  }

  Future<void> addRecord(DietRecord record) async {
    await _repository.add(record);
    state = await _repository.getAll();
  }

  Future<void> updateRecord(DietRecord record) async {
    await _repository.update(record);
    state = await _repository.getAll();
  }

  Future<void> deleteRecord(String id) async {
    await _repository.delete(id);
    state = await _repository.getAll();
  }

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