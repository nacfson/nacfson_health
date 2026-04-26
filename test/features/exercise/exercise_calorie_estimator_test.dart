import 'package:flutter_test/flutter_test.dart';
import 'package:nacfson_health/features/exercise/domain/entities/exercise_record.dart';
import 'package:nacfson_health/features/exercise/domain/exercise_calorie_estimator.dart';

ExerciseRecord _record({
  required String exerciseType,
  required double weight,
  required int reps,
  SetType setType = SetType.work,
}) {
  final now = DateTime(2026, 4, 26, 10);
  return ExerciseRecord(
    timestamp: now,
    updatedAt: now,
    exerciseType: exerciseType,
    exerciseName: 'test',
    currentSet: 1,
    weight: weight,
    reps: reps,
    rpe: 7.0,
    setType: setType,
  );
}

void main() {
  group('estimateExerciseCalories', () {
    test('returns 0 for empty input', () {
      expect(estimateExerciseCalories(const []), 0.0);
    });

    test('하체 100kg × 8회 work 1세트 → 8.0 kcal', () {
      // 100 × 8 × 0.01 × 1.0 (하체 계수) = 8.0
      final r = _record(exerciseType: '하체', weight: 100, reps: 8);
      expect(estimateExerciseCalories([r]), closeTo(8.0, 1e-6));
    });

    test('warmup 세트는 제외', () {
      final r = _record(
        exerciseType: '하체',
        weight: 100,
        reps: 8,
        setType: SetType.warmup,
      );
      expect(estimateExerciseCalories([r]), 0.0);
    });

    test('failure 세트는 제외', () {
      final r = _record(
        exerciseType: '하체',
        weight: 100,
        reps: 8,
        setType: SetType.failure,
      );
      expect(estimateExerciseCalories([r]), 0.0);
    });

    test('drop 세트는 포함', () {
      // drop 세트도 countsTowardVolume == true
      final r = _record(
        exerciseType: '하체',
        weight: 80,
        reps: 10,
        setType: SetType.drop,
      );
      // 80 × 10 × 0.01 × 1.0 = 8.0
      expect(estimateExerciseCalories([r]), closeTo(8.0, 1e-6));
    });

    test('유산소는 부위계수 0 → 0 kcal', () {
      final r = _record(exerciseType: '유산소', weight: 50, reps: 10);
      expect(estimateExerciseCalories([r]), 0.0);
    });

    test('부위별 계수가 차등 적용된다', () {
      // 같은 볼륨(100kg × 10회 = 1000kg)에 부위별 계수 적용
      // 하체 1.00 → 10.0, 어깨 0.60 → 6.0, 코어 0.50 → 5.0
      final lower = _record(exerciseType: '하체', weight: 100, reps: 10);
      final shoulder = _record(exerciseType: '어깨', weight: 100, reps: 10);
      final core = _record(exerciseType: '코어', weight: 100, reps: 10);

      expect(estimateExerciseCalories([lower]), closeTo(10.0, 1e-6));
      expect(estimateExerciseCalories([shoulder]), closeTo(6.0, 1e-6));
      expect(estimateExerciseCalories([core]), closeTo(5.0, 1e-6));
    });

    test('알 수 없는 부위는 기타 폴백 계수(0.7) 적용', () {
      // 100 × 10 × 0.01 × 0.7 = 7.0
      final r = _record(exerciseType: '존재하지않는부위', weight: 100, reps: 10);
      expect(estimateExerciseCalories([r]), closeTo(7.0, 1e-6));
    });

    test('맨몸/유산소 weight=0 은 자연스럽게 0 kcal', () {
      final r = _record(exerciseType: '가슴', weight: 0, reps: 20);
      expect(estimateExerciseCalories([r]), 0.0);
    });

    test('여러 세트 합산', () {
      // 스쿼트 100kg × 8회 × 5세트 work
      final records = List.generate(
        5,
        (_) => _record(exerciseType: '하체', weight: 100, reps: 8),
      );
      // 5 × 8.0 = 40.0
      expect(estimateExerciseCalories(records), closeTo(40.0, 1e-6));
    });

    test('warmup + work 섞여있을 때 work 만 반영', () {
      final records = [
        _record(
          exerciseType: '하체',
          weight: 60,
          reps: 10,
          setType: SetType.warmup,
        ), // 제외
        _record(exerciseType: '하체', weight: 100, reps: 8), // 8.0
        _record(exerciseType: '하체', weight: 100, reps: 8), // 8.0
      ];
      expect(estimateExerciseCalories(records), closeTo(16.0, 1e-6));
    });
  });
}
