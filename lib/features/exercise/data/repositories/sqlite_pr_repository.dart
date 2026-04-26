import 'dart:math' as math;

import '../../../../core/database/database_helper.dart';
import '../../../../core/sync/sync_status.dart';
import '../../../../core/training/one_rm_calculator.dart';
import '../../domain/entities/pr_summary.dart';
import '../../domain/repositories/pr_repository.dart';

/// sqflite 기반 PR Repository.
/// `exercise_records` 테이블에서 종목·주차별 max e1RM + 최근 강도 통계를 집계.
///
/// 컬럼명 (database_helper.dart 의 CREATE TABLE 기준):
///   exercise_name TEXT, weight REAL, reps INT, rpe REAL,
///   set_type TEXT ('work'|'warmup'|'drop'|'failure'),
///   timestamp INT (msSinceEpoch), sync_status INT
class SqlitePrRepository implements PrRepository {
  static const _msPerWeek = 7 * 24 * 60 * 60 * 1000;
  static const _msPerDay = 24 * 60 * 60 * 1000;

  @override
  Future<PrSummary> getPrSummary(String exerciseName, {int weeks = 5}) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final since = nowMs - weeks * _msPerWeek;
    final since14 = nowMs - 14 * _msPerDay;

    // 1) 5주치 work/drop 세트 — e1RM 추세 + 최근 7일 강도 통계
    final rows = await db.query(
      'exercise_records',
      columns: const [
        'weight',
        'reps',
        'rpe',
        'set_type',
        'timestamp',
        'exercise_type',
      ],
      where:
          'exercise_name = ? AND timestamp >= ? AND set_type IN (?, ?) AND sync_status != ?',
      whereArgs: [
        exerciseName,
        since,
        'work',
        'drop',
        SyncStatus.deleted.value,
      ],
      orderBy: 'timestamp DESC',
    );

    final weekly = List<double?>.filled(weeks, null);
    int recentWork = 0;
    double rpeSum = 0;
    int rpeN = 0;
    final since7 = nowMs - 7 * _msPerDay;
    // orderBy DESC 이므로 첫 row 의 type 이 가장 최근. 이후 row 는 무시.
    String? exerciseType;

    for (final r in rows) {
      exerciseType ??= r['exercise_type'] as String?;
      final w = (r['weight'] as num).toDouble();
      final reps = r['reps'] as int;
      final ts = r['timestamp'] as int;
      final setType = r['set_type'] as String;
      final rpe = (r['rpe'] as num?)?.toDouble();

      final e1 = calculateE1RM(w, reps);
      final weekIdx = ((nowMs - ts) / _msPerWeek).floor();
      if (weekIdx >= 0 && weekIdx < weeks) {
        final slot = weeks - 1 - weekIdx;
        final prev = weekly[slot];
        weekly[slot] = (prev == null) ? e1 : math.max(prev, e1);
      }

      if (ts >= since7 && setType == 'work') recentWork++;
      // RPE 컬럼은 NOT NULL 이지만 0.0 으로 기본값일 수 있어 양수만 평균에 포함
      if (ts >= since7 && rpe != null && rpe > 0) {
        rpeSum += rpe;
        rpeN++;
      }
    }

    // 2) 최근 14일 failure 세트 카운트 (별도 쿼리)
    final failRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM exercise_records '
      'WHERE exercise_name = ? AND timestamp >= ? '
      "AND set_type = 'failure' AND sync_status != ?",
      [exerciseName, since14, SyncStatus.deleted.value],
    );
    final recentFailure = (failRows.first['c'] as int?) ?? 0;

    // 5주치 안에 한 번도 종목이 없으면(데이터 부족 케이스), 추가 lookup 으로 type 보강
    if (exerciseType == null) {
      final typeRows = await db.query(
        'exercise_records',
        columns: const ['exercise_type'],
        where: 'exercise_name = ? AND sync_status != ?',
        whereArgs: [exerciseName, SyncStatus.deleted.value],
        orderBy: 'timestamp DESC',
        limit: 1,
      );
      if (typeRows.isNotEmpty) {
        exerciseType = typeRows.first['exercise_type'] as String?;
      }
    }

    return PrSummary(
      exerciseName: exerciseName,
      exerciseType: exerciseType,
      currentE1RM: weekly.last,
      fourWeeksAgoE1RM: weekly.first,
      weeklyHistory: weekly,
      recentWorkSetCount: recentWork,
      recentRpeAvg: rpeN > 0 ? rpeSum / rpeN : null,
      recentFailureCount: recentFailure,
      lastUpdated: now,
    );
  }

  @override
  Future<List<PrSummary>> getTopPrs({int limit = 3}) async {
    // 후보 풀을 충분히 넓혀야(볼륨 상위 ≠ e1RM 상위) 실제 PR 상위가 누락되지 않음.
    // 볼륨 상위만 보면 고볼륨/저강도 종목(예: 컬)에 가려 스쿼트·벤치·데드 같은 PR 종목이 빠질 수 있음.
    final poolSize = (limit * 5).clamp(10, 20);
    final names = await getTopExerciseNames(limit: poolSize);
    final summaries = <PrSummary>[];
    for (final name in names) {
      summaries.add(await getPrSummary(name));
    }
    // currentE1RM 내림차순 정렬 (null 후순위)
    summaries.sort((a, b) {
      final av = a.currentE1RM ?? -1;
      final bv = b.currentE1RM ?? -1;
      return bv.compareTo(av);
    });
    return summaries.take(limit).toList();
  }

  @override
  Future<List<String>> getTopExerciseNames({int limit = 8}) async {
    final db = await DatabaseHelper.instance.database;
    final since90 = DateTime.now().millisecondsSinceEpoch - 90 * _msPerDay;
    // 최근 90일 work/drop 세트 총 볼륨 상위 종목명
    final rows = await db.rawQuery(
      'SELECT exercise_name, SUM(weight * reps) AS vol '
      'FROM exercise_records '
      'WHERE timestamp >= ? AND set_type IN (?, ?) AND sync_status != ? '
      'GROUP BY exercise_name '
      'ORDER BY vol DESC '
      'LIMIT ?',
      [since90, 'work', 'drop', SyncStatus.deleted.value, limit],
    );
    return rows.map((r) => r['exercise_name'] as String).toList();
  }
}
