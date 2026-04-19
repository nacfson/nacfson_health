import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/selected_date_provider.dart';
import '../../domain/entities/exercise_record.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/sqlite_exercise_repository.dart';

// Web 환경용 메모리 기반 Repository (임시 구현)
class _MemoryExerciseRepository implements ExerciseRepository {
  final List<ExerciseRecord> _records = [];

  @override
  Future<List<ExerciseRecord>> getAll() async => List.from(_records);

  @override
  Future<ExerciseRecord?> getById(String id) async =>
      _records.cast<ExerciseRecord?>().firstWhere(
            (r) => r?.uuid == id,
            orElse: () => null,
          );

  @override
  Future<List<ExerciseRecord>> getByDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return _records
        .where((r) =>
            r.timestamp.isAfter(startOfDay) && r.timestamp.isBefore(endOfDay))
        .toList();
  }

  @override
  Future<void> add(ExerciseRecord record) async => _records.add(record);

  @override
  Future<void> update(ExerciseRecord record) async {
    final index = _records.indexWhere((r) => r.uuid == record.uuid);
    if (index != -1) _records[index] = record;
  }

  @override
  Future<void> delete(String id) async =>
      _records.removeWhere((r) => r.uuid == id);

  @override
  Future<void> deleteAll() async => _records.clear();

  @override
  Future<int> sync(List<ExerciseRecord> records) async {
    _records.clear();
    _records.addAll(records);
    return records.length;
  }

  @override
  Future<List<ExerciseRecord>> getPendingSync() async =>
      _records.where((r) => r.syncStatus != 0).toList();

  @override
  Future<void> markAsSynced(List<String> uuids) async {
    for (final uuid in uuids) {
      final index = _records.indexWhere((r) => r.uuid == uuid);
      if (index != -1) {
        final record = _records[index];
        _records[index] = record.copyWith(syncStatus: SyncStatus.synced);
      }
    }
  }

  @override
  Future<void> mergeRemoteRecords(List<ExerciseRecord> remote) async {
    for (final remoteRecord in remote) {
      final index = _records.indexWhere((r) => r.uuid == remoteRecord.uuid);
      if (index == -1) {
        _records.add(remoteRecord);
      } else if (remoteRecord.updatedAt.isAfter(_records[index].updatedAt)) {
        _records[index] = remoteRecord;
      }
    }
  }

  @override
  Future<void> hardDeleteSyncedDeleted() async {
    _records.removeWhere((r) => r.syncStatus == SyncStatus.deleted);
  }

  @override
  Future<void> resetAllSyncStatus() async {
    for (int i = 0; i < _records.length; i++) {
      _records[i] = _records[i].copyWith(syncStatus: SyncStatus.created);
    }
  }
}

final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  if (kIsWeb) {
    return _MemoryExerciseRepository();
  }
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

/// 오늘 운동 기록 - exerciseType별 및 exerciseName별 이중 그룹핑
final todayExerciseGroupedProvider =
    Provider<Map<String, Map<String, List<ExerciseRecord>>>>((ref) {
  final records = ref.watch(todayExerciseRecordsProvider);
  const typeOrder = ['가슴', '등', '하체', '어깨', '팔', '코어', '유산소', '기타'];
  final Map<String, Map<String, List<ExerciseRecord>>> grouped = {};

  for (final type in typeOrder) {
    final typeRecords = records.where((r) => r.exerciseType == type).toList();
    if (typeRecords.isNotEmpty) {
      final Map<String, List<ExerciseRecord>> nameGrouped = {};
      // 최신순으로 정렬된 기록을 이름별로 묶음
      for (final r in typeRecords) {
        nameGrouped.putIfAbsent(r.exerciseName, () => []).add(r);
      }
      // 세트 번호 순서(또는 시간 순서)로 다시 정렬하고 싶다면 여기서 수행
      for (final name in nameGrouped.keys) {
        nameGrouped[name]!.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
      grouped[type] = nameGrouped;
    }
  }
  return grouped;
});

/// 오늘 총 볼륨 합계 (kg)
final todayTotalVolumeProvider = Provider<double>((ref) {
  return ref
      .watch(todayExerciseRecordsProvider)
      .fold(0.0, (sum, r) => sum + r.volume);
});

// ─────────────────────────────────────────────────────────────────────────────
// 선택 날짜 기반 Provider (Observer 패턴 — selectedDateProvider 변경 시 자동 갱신)
// ─────────────────────────────────────────────────────────────────────────────

/// 선택 날짜의 운동 기록 목록 - 최신순
final selectedDateExerciseRecordsProvider = Provider<List<ExerciseRecord>>((ref) {
  final all = ref.watch(exerciseRecordsProvider);
  final date = ref.watch(selectedDateProvider);
  return all
      .where((r) =>
          r.timestamp.year == date.year &&
          r.timestamp.month == date.month &&
          r.timestamp.day == date.day)
      .toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
});

/// 선택 날짜 운동 기록 — exerciseType별 및 exerciseName별 이중 그룹핑
final selectedDateExerciseGroupedProvider =
    Provider<Map<String, Map<String, List<ExerciseRecord>>>>((ref) {
  final records = ref.watch(selectedDateExerciseRecordsProvider);
  const typeOrder = ['가슴', '등', '하체', '어깨', '팔', '코어', '유산소', '기타'];
  final Map<String, Map<String, List<ExerciseRecord>>> grouped = {};

  for (final type in typeOrder) {
    final typeRecords = records.where((r) => r.exerciseType == type).toList();
    if (typeRecords.isNotEmpty) {
      final Map<String, List<ExerciseRecord>> nameGrouped = {};
      for (final r in typeRecords) {
        nameGrouped.putIfAbsent(r.exerciseName, () => []).add(r);
      }
      for (final name in nameGrouped.keys) {
        nameGrouped[name]!.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
      grouped[type] = nameGrouped;
    }
  }
  return grouped;
});

/// 선택 날짜의 총 볼륨 합계 (kg)
final selectedDateTotalVolumeProvider = Provider<double>((ref) {
  return ref
      .watch(selectedDateExerciseRecordsProvider)
      .fold(0.0, (sum, r) => sum + r.volume);
});

// ─────────────────────────────────────────────────────────────────────────────
// 볼륨 추세 차트 데이터 (Strategy 패턴 — ChartViewType으로 기간 전략 전환)
// ─────────────────────────────────────────────────────────────────────────────

/// 차트 뷰 타입 (체중 차트와 동일 패턴 재사용)
enum ExerciseChartViewType { weekly, monthly }

final exerciseChartViewTypeProvider =
    StateProvider<ExerciseChartViewType>((ref) => ExerciseChartViewType.weekly);

/// 볼륨 추세 데이터: 일별 (날짜, 총볼륨) 리스트
final volumeTrendDataProvider =
    Provider<List<({DateTime date, double volume})>>((ref) {
  final all = ref.watch(exerciseRecordsProvider);
  final viewType = ref.watch(exerciseChartViewTypeProvider);
  final now = DateTime.now();

  // Strategy 패턴: 뷰 타입에 따라 시작 날짜 결정
  final int daysBack = switch (viewType) {
    ExerciseChartViewType.weekly => 6,
    ExerciseChartViewType.monthly => 29,
  };
  final startDate = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: daysBack));

  // 날짜 범위 내 기록만 필터링
  final filtered = all.where((r) =>
      r.timestamp.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
      r.syncStatus != SyncStatus.deleted);

  // 일별 볼륨 집계 (메모리 효율: Map으로 한 번만 순회)
  final Map<String, double> dailyVolume = {};
  for (final r in filtered) {
    final key = '${r.timestamp.year}-${r.timestamp.month}-${r.timestamp.day}';
    dailyVolume[key] = (dailyVolume[key] ?? 0) + r.volume;
  }

  // 전체 기간의 날짜를 생성하여 빈 날짜도 포함 (차트 연속성 보장)
  final List<({DateTime date, double volume})> result = [];
  for (int i = 0; i <= daysBack; i++) {
    final date = startDate.add(Duration(days: i));
    final key = '${date.year}-${date.month}-${date.day}';
    result.add((date: date, volume: dailyVolume[key] ?? 0));
  }

  return result;
});