import 'package:flutter_test/flutter_test.dart';
import 'package:nacfson_health/core/training/challenge_readiness.dart';

void main() {
  group('assessReadiness', () {
    test('데이터 부족 → gray (currentE1RM null)', () {
      final r = assessReadiness(const ReadinessInput(
        weeklyHistory: [null, null, null, null, null],
        recentWorkSetCount: 0,
        recentRpeAvg: null,
        recentFailureCount: 0,
      ));
      expect(r.level, ReadinessLevel.gray);
      expect(r.headline, '데이터 부족');
    });

    test('데이터 부족 → gray (non-null 1개뿐)', () {
      final r = assessReadiness(const ReadinessInput(
        weeklyHistory: [null, null, null, null, 80.0],
        recentWorkSetCount: 1,
        recentRpeAvg: null,
        recentFailureCount: 0,
      ));
      expect(r.level, ReadinessLevel.gray);
    });

    test('추세 상승 + RPE 낮음 + 충분한 볼륨 → green', () {
      final r = assessReadiness(const ReadinessInput(
        weeklyHistory: [85.0, 87.0, 88.0, 90.0, 93.0], // 2주 전 88, 현재 93 → 상승
        recentWorkSetCount: 4,
        recentRpeAvg: 7.5,
        recentFailureCount: 0,
      ));
      expect(r.level, ReadinessLevel.green);
      expect(r.headline, 'PR 도전 적절');
    });

    test('추세 평탄 → amber', () {
      final r = assessReadiness(const ReadinessInput(
        weeklyHistory: [88.0, 88.5, 88.0, 88.5, 88.0], // 2주 전 88, 현재 88 → 평탄
        recentWorkSetCount: 4,
        recentRpeAvg: 7.0,
        recentFailureCount: 0,
      ));
      expect(r.level, ReadinessLevel.amber);
      expect(r.headline, '1주 더 쌓고');
    });

    test('볼륨 부족 → amber', () {
      final r = assessReadiness(const ReadinessInput(
        weeklyHistory: [80.0, 82.0, 84.0, 86.0, 90.0], // 추세는 상승
        recentWorkSetCount: 1, // 본세트 1개만 = 부족
        recentRpeAvg: 7.0,
        recentFailureCount: 0,
      ));
      expect(r.level, ReadinessLevel.amber);
    });

    test('RPE 9.5 (높음) → red', () {
      final r = assessReadiness(const ReadinessInput(
        weeklyHistory: [85.0, 87.0, 88.0, 90.0, 93.0],
        recentWorkSetCount: 4,
        recentRpeAvg: 9.5,
        recentFailureCount: 0,
      ));
      expect(r.level, ReadinessLevel.red);
      expect(r.headline, '회복 우선');
    });

    test('추세 하락 → red', () {
      final r = assessReadiness(const ReadinessInput(
        weeklyHistory: [95.0, 94.0, 93.0, 92.0, 90.0], // 2주 전 93, 현재 90 → 하락
        recentWorkSetCount: 4,
        recentRpeAvg: 8.0,
        recentFailureCount: 0,
      ));
      expect(r.level, ReadinessLevel.red);
    });

    test('실패 세트 2회 이상 → red', () {
      final r = assessReadiness(const ReadinessInput(
        weeklyHistory: [85.0, 87.0, 88.0, 90.0, 93.0],
        recentWorkSetCount: 4,
        recentRpeAvg: 7.0,
        recentFailureCount: 2,
      ));
      expect(r.level, ReadinessLevel.red);
    });
  });
}
