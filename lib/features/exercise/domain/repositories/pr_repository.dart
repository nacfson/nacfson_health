import '../entities/pr_summary.dart';

/// 종목별 PR 추세/강도 통계 조회.
abstract class PrRepository {
  /// 특정 종목의 [weeks] 주치 PR 요약. 데이터가 전혀 없어도 null-필드로 채워 반환.
  Future<PrSummary> getPrSummary(String exerciseName, {int weeks = 5});

  /// 최근 90일 work/drop 세트가 있던 종목 중 e1RM 상위 [limit] 개.
  Future<List<PrSummary>> getTopPrs({int limit = 3});

  /// 최근 90일 work/drop 세트 총 볼륨 상위 [limit] 종목 이름.
  /// 1RM 코치 종목 칩 후보 목록.
  Future<List<String>> getTopExerciseNames({int limit = 8});

  /// 종목의 가장 최근 work/drop 세트의 (weight, reps). 없으면 null.
  /// warmup / failure 는 제외 — 1RM 코치 입력 초기값 용도.
  Future<({double weight, int reps})?> getLatestWorkSet(String exerciseName);
}
