import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/exercise_record.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/sqlite_exercise_repository.dart';

final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  return SqliteExerciseRepository();
});

final exerciseRecordsProvider = StateNotifierProvider<ExerciseNotifier, List<ExerciseRecord>>((ref) {
  final repository = ref.watch(exerciseRepositoryProvider);
  return ExerciseNotifier(repository);
});

class ExerciseNotifier extends StateNotifier<List<ExerciseRecord>> {
  final ExerciseRepository _repository;

  ExerciseNotifier(this._repository) : super([]) {
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    state = await _repository.getAll();
  }

  /// 동기화 완료 후 DB에서 최신 상태를 다시 로드합니다.
  Future<void> refresh() => _loadRecords();

  Future<void> addRecord(ExerciseRecord record) async {
    await _repository.add(record);
    state = await _repository.getAll();
  }

  Future<void> updateRecord(ExerciseRecord record) async {
    await _repository.update(record);
    state = await _repository.getAll();
  }

  Future<void> deleteRecord(String id) async {
    await _repository.delete(id);
    state = await _repository.getAll();
  }

  List<ExerciseRecord> getByDate(DateTime date) {
    return state.where((r) =>
      r.timestamp.year == date.year &&
      r.timestamp.month == date.month &&
      r.timestamp.day == date.day
    ).toList();
  }
}

/// 오늘(00:00~23:59) 운동 기록 목록 - 최신순
final todayExerciseRecordsProvider = Provider<List<ExerciseRecord>>((ref) {
  final all = ref.watch(exerciseRecordsProvider);
  final today = DateTime.now();
  return all
      .where((r) =>
          r.timestamp.year == today.year &&
          r.timestamp.month == today.month &&
          r.timestamp.day == today.day)
      .toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
});

/// 오늘 운동 기록 - exerciseType별 그룹핑 (표시 순서 고정)
final todayExerciseGroupedProvider =
    Provider<Map<String, List<ExerciseRecord>>>((ref) {
  final records = ref.watch(todayExerciseRecordsProvider);
  const typeOrder = ['가슴', '등', '하체', '어깨', '팔', '코어', '유산소', '기타'];
  final Map<String, List<ExerciseRecord>> grouped = {};
  for (final type in typeOrder) {
    final list = records.where((r) => r.exerciseType == type).toList();
    if (list.isNotEmpty) grouped[type] = list;
  }
  return grouped;
});

/// 오늘 총 볼륨 합계 (kg)
final todayTotalVolumeProvider = Provider<double>((ref) {
  return ref
      .watch(todayExerciseRecordsProvider)
      .fold(0.0, (sum, r) => sum + r.volume);
});