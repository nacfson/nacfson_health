import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/selected_date_provider.dart';
import '../../domain/entities/exercise_record.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/sqlite_exercise_repository.dart';
import 'routine_planner_provider.dart';

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

  /// 같은 운동명·같은 날짜의 마지막 세트 다음 번호로 자동 부여하여 추가한다.
  /// 휴식 타이머 시작은 호출자(UI)가 별도로 책임진다.
  Future<void> addSetAutoNumber({
    required String exerciseType,
    required String exerciseName,
    required double weight,
    required int reps,
    required double rpe,
    SetType setType = SetType.work,
    DateTime? when,
  }) async {
    final now = when ?? DateTime.now();
    final maxSet = state
        .where((r) =>
            r.exerciseName == exerciseName &&
            r.timestamp.year == now.year &&
            r.timestamp.month == now.month &&
            r.timestamp.day == now.day)
        .fold<int>(0, (m, r) => r.currentSet > m ? r.currentSet : m);
    final record = ExerciseRecord(
      timestamp: now,
      updatedAt: now,
      exerciseType: exerciseType,
      exerciseName: exerciseName,
      currentSet: maxSet + 1,
      weight: weight,
      reps: reps,
      rpe: rpe,
      setType: setType,
    );
    await _repository.add(record);
    state = await _repository.getAll();
  }

  /// 세트를 삭제한 뒤 같은 운동명·같은 날짜 세트들의 currentSet을
  /// timestamp 순으로 1..N 재부여한다.
  Future<void> deleteSetAndRenumber(String uuid) async {
    final target = state.firstWhere(
      (r) => r.uuid == uuid,
      orElse: () => throw StateError('record not found'),
    );
    await _repository.delete(uuid);

    final remaining = (await _repository.getAll())
        .where((r) =>
            r.exerciseName == target.exerciseName &&
            r.timestamp.year == target.timestamp.year &&
            r.timestamp.month == target.timestamp.month &&
            r.timestamp.day == target.timestamp.day)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (var i = 0; i < remaining.length; i++) {
      final r = remaining[i];
      final desired = i + 1;
      if (r.currentSet != desired) {
        await _repository.update(r.copyWith(currentSet: desired));
      }
    }
    state = await _repository.getAll();
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

/// 오늘 총 볼륨 합계 (kg) — 본세트/드롭세트만 집계(웜업/실패 제외).
final todayTotalVolumeProvider = Provider<double>((ref) {
  return ref
      .watch(todayExerciseRecordsProvider)
      .where((r) => r.countsTowardVolume)
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

/// 선택 날짜의 총 볼륨 합계 (kg) — 본세트/드롭세트만 집계(웜업/실패 제외).
final selectedDateTotalVolumeProvider = Provider<double>((ref) {
  return ref
      .watch(selectedDateExerciseRecordsProvider)
      .where((r) => r.countsTowardVolume)
      .fold(0.0, (sum, r) => sum + r.volume);
});

// ─────────────────────────────────────────────────────────────────────────────
// 오늘 루틴 + 기록 통합 카드 데이터
// ─────────────────────────────────────────────────────────────────────────────

class ExerciseCardData {
  final String exerciseType;
  final String exerciseName;
  final List<ExerciseRecord> records; // 세트 timestamp 오름차순
  const ExerciseCardData({
    required this.exerciseType,
    required this.exerciseName,
    required this.records,
  });
}

/// 오늘 루틴(계획)과 오늘 기록을 union 한 카드 리스트.
/// - 계획 순서가 우선
/// - 기록만 있고 계획에 없는 운동은 뒤에 timestamp 순으로 append
final todayExerciseCardsProvider =
    Provider<List<ExerciseCardData>>((ref) {
  final routine = ref.watch(routinePlannerProvider);
  final records = ref.watch(todayExerciseRecordsProvider);

  final byName = <String, List<ExerciseRecord>>{};
  for (final r in records) {
    byName.putIfAbsent(r.exerciseName, () => []).add(r);
  }
  for (final list in byName.values) {
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  final cards = <ExerciseCardData>[];
  final seen = <String>{};
  for (final item in routine) {
    seen.add(item.exerciseName);
    cards.add(ExerciseCardData(
      exerciseType: item.exerciseType,
      exerciseName: item.exerciseName,
      records: byName[item.exerciseName] ?? const [],
    ));
  }

  // 기록만 있고 계획에 없는 운동들 — 첫 timestamp 순서대로 뒤에 붙임
  final extras = byName.entries
      .where((e) => !seen.contains(e.key))
      .toList()
    ..sort((a, b) =>
        a.value.first.timestamp.compareTo(b.value.first.timestamp));
  for (final entry in extras) {
    cards.add(ExerciseCardData(
      exerciseType: entry.value.first.exerciseType,
      exerciseName: entry.key,
      records: entry.value,
    ));
  }
  return cards;
});

/// 같은 운동명의 오늘 가장 최근 세트(있다면) — 인라인 입력 프리필용.
final latestSetOfTodayProvider =
    Provider.family<ExerciseRecord?, String>((ref, exerciseName) {
  final today = ref.watch(todayExerciseRecordsProvider);
  final match = today.where((r) => r.exerciseName == exerciseName).toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return match.isEmpty ? null : match.first;
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

  // 날짜 범위 내 기록만 필터링 (웜업/실패는 볼륨 집계 제외)
  final filtered = all.where((r) =>
      r.timestamp.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
      r.syncStatus != SyncStatus.deleted &&
      r.countsTowardVolume);

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

// ─────────────────────────────────────────────────────────────────────────────
// 종목별 진행 차트 (A2) — 운동 1개에 대해 최고 무게 / e1RM / 세션 볼륨 시계열
// ─────────────────────────────────────────────────────────────────────────────

enum ProgressionMetric { topWeight, e1rm, sessionVolume }

enum ProgressionPeriod { m1, m3, m6 }

extension ProgressionPeriodDays on ProgressionPeriod {
  int get days => switch (this) {
        ProgressionPeriod.m1 => 30,
        ProgressionPeriod.m3 => 90,
        ProgressionPeriod.m6 => 180,
      };

  String get label => switch (this) {
        ProgressionPeriod.m1 => '1개월',
        ProgressionPeriod.m3 => '3개월',
        ProgressionPeriod.m6 => '6개월',
      };
}

extension ProgressionMetricLabel on ProgressionMetric {
  String get label => switch (this) {
        ProgressionMetric.topWeight => '최고 무게',
        ProgressionMetric.e1rm => 'e1RM',
        ProgressionMetric.sessionVolume => '세션 볼륨',
      };

  String get unit => switch (this) {
        ProgressionMetric.topWeight => 'kg',
        ProgressionMetric.e1rm => 'kg',
        ProgressionMetric.sessionVolume => 'kg',
      };
}

final progressionMetricProvider =
    StateProvider<ProgressionMetric>((_) => ProgressionMetric.topWeight);

final progressionPeriodProvider =
    StateProvider<ProgressionPeriod>((_) => ProgressionPeriod.m3);

/// Epley 1RM 추정치. reps ≤ 10 인 세트만 대상(고반복은 편향).
double _epleyE1rm(double weight, int reps) {
  if (reps < 1 || reps > 10) return 0;
  return weight * (1 + reps / 30.0);
}

class ProgressionSessionPoint {
  final DateTime date;
  final double value; // 메트릭 값
  final double topWeight;
  final int topReps;
  final double avgRpe;
  final int setCount;

  const ProgressionSessionPoint({
    required this.date,
    required this.value,
    required this.topWeight,
    required this.topReps,
    required this.avgRpe,
    required this.setCount,
  });
}

/// 종목명 별 진행 데이터. 본세트/드롭세트만 포함(웜업/실패 제외).
/// 빈 날짜는 포함하지 않음(세션이 있는 날짜만 점으로 반환).
final exerciseProgressionDataProvider = Provider.family<
    List<ProgressionSessionPoint>, String>((ref, exerciseName) {
  final all = ref.watch(exerciseRecordsProvider);
  final metric = ref.watch(progressionMetricProvider);
  final period = ref.watch(progressionPeriodProvider);
  final now = DateTime.now();
  final cutoff = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: period.days));

  final relevant = all.where((r) =>
      r.exerciseName == exerciseName &&
      r.syncStatus != SyncStatus.deleted &&
      r.countsTowardVolume &&
      r.timestamp.isAfter(cutoff.subtract(const Duration(seconds: 1))));

  // 날짜별 그룹핑 (midnight)
  final Map<DateTime, List<ExerciseRecord>> byDay = {};
  for (final r in relevant) {
    final key = DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day);
    byDay.putIfAbsent(key, () => []).add(r);
  }

  final points = <ProgressionSessionPoint>[];
  for (final entry in byDay.entries) {
    final sets = entry.value;
    final topSet = sets.reduce((a, b) => a.weight >= b.weight ? a : b);
    final maxE1rm = sets
        .map((s) => _epleyE1rm(s.weight, s.reps))
        .fold<double>(0, (a, b) => a > b ? a : b);
    final sessionVolume = sets.fold<double>(0, (s, r) => s + r.volume);
    final avgRpe = sets.map((s) => s.rpe).fold<double>(0, (a, b) => a + b) /
        sets.length;
    final value = switch (metric) {
      ProgressionMetric.topWeight => topSet.weight,
      ProgressionMetric.e1rm => maxE1rm,
      ProgressionMetric.sessionVolume => sessionVolume,
    };
    points.add(ProgressionSessionPoint(
      date: entry.key,
      value: value,
      topWeight: topSet.weight,
      topReps: topSet.reps,
      avgRpe: avgRpe,
      setCount: sets.length,
    ));
  }
  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
});

class ProgressionSummary {
  final double maxWeight;
  final int maxWeightReps;
  final int sessionCount;
  final double avgRpe;

  const ProgressionSummary({
    required this.maxWeight,
    required this.maxWeightReps,
    required this.sessionCount,
    required this.avgRpe,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 운동 달력 히트맵 (D1) — 최근 91일 일별 본세트 볼륨 맵
// ─────────────────────────────────────────────────────────────────────────────

/// 최근 13주(월요일 기준) 일별 본세트 볼륨. key: midnight DateTime, value: 총 볼륨(kg).
/// 볼륨 0인 날짜는 맵에 포함되지 않는다 (호출자가 기본값 0으로 처리).
/// 시작점은 `WorkoutHeatmapCard` 의 그리드 시작(mondayOfThisWeek - 7*12)과 동일하게 계산한다.
final heatmapDataProvider = Provider<Map<DateTime, double>>((ref) {
  final all = ref.watch(exerciseRecordsProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final mondayOfThisWeek =
      today.subtract(Duration(days: today.weekday - 1));
  final start = mondayOfThisWeek.subtract(const Duration(days: 7 * 12));
  final map = <DateTime, double>{};
  for (final r in all) {
    if (r.syncStatus == SyncStatus.deleted) continue;
    if (!r.countsTowardVolume) continue; // 웜업/실패 제외
    if (r.timestamp.isBefore(start)) continue;
    final key =
        DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day);
    map[key] = (map[key] ?? 0) + r.volume;
  }
  return map;
});

/// 종목별 요약 카드 데이터 (기간 내 최고 기록 / 세션 수 / 평균 RPE).
final exerciseProgressionSummaryProvider =
    Provider.family<ProgressionSummary, String>((ref, exerciseName) {
  final points = ref.watch(exerciseProgressionDataProvider(exerciseName));
  if (points.isEmpty) {
    return const ProgressionSummary(
      maxWeight: 0,
      maxWeightReps: 0,
      sessionCount: 0,
      avgRpe: 0,
    );
  }
  final topPoint = points.reduce((a, b) => a.topWeight >= b.topWeight ? a : b);
  final avgRpe =
      points.map((p) => p.avgRpe).fold<double>(0, (a, b) => a + b) /
          points.length;
  return ProgressionSummary(
    maxWeight: topPoint.topWeight,
    maxWeightReps: topPoint.topReps,
    sessionCount: points.length,
    avgRpe: avgRpe,
  );
});