import 'body_part_calorie_coefficients.dart';
import 'entities/exercise_record.dart';

/// 운동 볼륨 기반 칼로리 추정 (Scott 2011 단순 모델).
///
/// 공식: `kcal = Σ(weight × reps × kKcalPerKgVolume × 부위계수)`
///
/// - warmup / failure 세트는 제외 (`countsTowardVolume == true` 만 합산).
/// - 부위계수가 0 인 유산소·미분류는 자연스럽게 0 으로 떨어짐.
/// - 정확도 ±40% 추정치 — UI 노출 시 "추정치" 라벨링 권장.
double estimateExerciseCalories(Iterable<ExerciseRecord> records) {
  double total = 0.0;
  for (final r in records) {
    if (!r.countsTowardVolume) continue;
    total += r.volume * kKcalPerKgVolume * calorieCoefficientFor(r.exerciseType);
  }
  return total;
}
