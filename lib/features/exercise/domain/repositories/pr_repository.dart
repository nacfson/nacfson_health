import '../../../../core/training/one_rm_formula.dart';
import '../entities/pr_summary.dart';

/// 종목별 PR 추세/강도 통계 조회.
abstract class PrRepository {
  /// 특정 종목의 [weeks] 주치 PR 요약. 데이터가 전혀 없어도 null-필드로 채워 반환.
  ///
  /// [formulaSpec] 가 주어지면 해당 공식으로 e1RM 을 계산. null 이면 기본
  /// Epley 공식 사용 (legacy fallback). v12 부터는 항상 formulaSpec 을 전달하길 권장.
  Future<PrSummary> getPrSummary(
    String exerciseName, {
    int weeks = 5,
    OneRMFormulaSpec? formulaSpec,
  });

  /// 최근 90일 work/drop 세트가 있던 종목 중 e1RM 상위 [limit] 개.
  Future<List<PrSummary>> getTopPrs({int limit = 3});

  /// 최근 90일 work/drop 세트 총 볼륨 상위 [limit] 종목 이름.
  /// 1RM 코치 종목 칩 후보 목록.
  Future<List<String>> getTopExerciseNames({int limit = 8});

  /// `getTopExerciseNames` 와 같지만 [registeredExerciseKeys] 안에 있는
  /// `exercise_key` 인 기록만 반환. 1RM 공식이 등록된 종목만 노출하기 위해 사용.
  ///
  /// exercise_records 의 `exercise_key` 가 NULL 인 기록(legacy/사용자 커스텀)은
  /// 자동 제외된다.
  Future<List<RegisteredExercise>> getTopRegisteredExercises({
    required Set<String> registeredExerciseKeys,
    int limit = 8,
  });

  /// 종목의 가장 최근 work/drop 세트의 (weight, reps). 없으면 null.
  /// warmup / failure 는 제외 — 1RM 코치 입력 초기값 용도.
  Future<({double weight, int reps})?> getLatestWorkSet(String exerciseName);

  /// `exercise_key` 기준으로 가장 최근 work/drop 세트 1개. 없으면 null.
  Future<({double weight, int reps})?> getLatestWorkSetByKey(String exerciseKey);
}

/// `getTopRegisteredExercises` 결과 — exercise_key + 사용자가 마지막으로
/// 본 한글/영문 이름 (historical snapshot). UI 측에서 현재 locale 의 번역으로
/// 다시 매핑할 때 fallback 으로 사용.
class RegisteredExercise {
  final String exerciseKey;
  final String? legacyDisplayName;
  const RegisteredExercise({
    required this.exerciseKey,
    required this.legacyDisplayName,
  });
}
