import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/weight_record.dart';
import '../../data/repositories/weight_repository.dart';
import '../../data/repositories/sqlite_weight_repository.dart';

final weightRepositoryProvider = Provider<WeightRepository>((ref) {
  return SqliteWeightRepository();
});

final weightRecordsProvider =
    StateNotifierProvider<WeightNotifier, List<WeightRecord>>((ref) {
  final repository = ref.watch(weightRepositoryProvider);
  return WeightNotifier(repository);
});

class WeightNotifier extends StateNotifier<List<WeightRecord>> {
  final WeightRepository _repository;

  WeightNotifier(this._repository) : super([]) {
    refresh();
  }

  Future<void> refresh() async {
    state = await _repository.getAll();
  }

  Future<void> addRecord(WeightRecord record) async {
    final existing = await _repository.getByDate(record.timestamp);
    if (existing != null) {
      final saved = await _repository.update(existing.copyWith(
        weight: record.weight,
        updatedAt: DateTime.now(),
      ));
      state = _sortDesc([
        for (final r in state) r.uuid == saved.uuid ? saved : r,
      ]);
    } else {
      final saved = await _repository.add(record);
      state = _sortDesc([...state, saved]);
    }
  }

  Future<void> updateRecord(WeightRecord record) async {
    final saved = await _repository.update(record);
    state = _sortDesc([
      for (final r in state) r.uuid == saved.uuid ? saved : r,
    ]);
  }

  Future<void> deleteRecord(String uuid) async {
    await _repository.delete(uuid);
    state = state.where((r) => r.uuid != uuid).toList();
  }

  /// `getAll()` 의 정렬 규약(timestamp DESC) 을 in-memory 갱신에서도 유지.
  static List<WeightRecord> _sortDesc(List<WeightRecord> list) =>
      list..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  List<WeightRecord> getByDateRange(DateTime start, DateTime end) {
    return state
        .where((r) =>
            r.timestamp.isAfter(start.subtract(const Duration(seconds: 1))) &&
            r.timestamp.isBefore(end.add(const Duration(seconds: 1))))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }
}

/// 가장 최근 체중 기록
final latestWeightProvider = Provider<WeightRecord?>((ref) {
  final records = ref.watch(weightRecordsProvider);
  if (records.isEmpty) return null;
  // state는 timestamp DESC 순이므로 첫 번째가 가장 최근
  return records.first;
});

/// 오늘 기록된 체중 (있다면)
final todayWeightProvider = Provider<WeightRecord?>((ref) {
  final records = ref.watch(weightRecordsProvider);
  final today = DateTime.now();
  try {
    return records.firstWhere((r) =>
        r.timestamp.year == today.year &&
        r.timestamp.month == today.month &&
        r.timestamp.day == today.day);
  } catch (_) {
    return null;
  }
});

/// 차트용 데이터 필터링 (주/월/년)
enum ChartViewType { weekly, monthly, yearly }

final chartViewTypeProvider = StateProvider<ChartViewType>((ref) => ChartViewType.weekly);

final weightChartDataProvider = Provider<List<WeightRecord>>((ref) {
  final records = ref.watch(weightRecordsProvider);
  final viewType = ref.watch(chartViewTypeProvider);
  final now = DateTime.now();
  
  DateTime startDate;
  switch (viewType) {
    case ChartViewType.weekly:
      startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      break;
    case ChartViewType.monthly:
      startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
      break;
    case ChartViewType.yearly:
      startDate = DateTime(now.year, 1, 1);
      break;
  }

  return records
      .where((r) => r.timestamp.isAfter(startDate.subtract(const Duration(seconds: 1))))
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
});
