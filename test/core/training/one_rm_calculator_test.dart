import 'package:flutter_test/flutter_test.dart';
import 'package:nacfson_health/core/training/one_rm_calculator.dart';

void main() {
  group('calculateE1RM (Epley)', () {
    test('1회는 weight 그대로', () {
      expect(calculateE1RM(100, 1), 100.0);
    });

    test('80kg × 5회 → 약 93.33', () {
      // 80 × (1 + 5/30) = 80 × 1.1667 = 93.333…
      expect(calculateE1RM(80, 5), closeTo(93.333, 0.01));
    });

    test('60kg × 10회 → 약 80', () {
      // 60 × (1 + 10/30) = 80
      expect(calculateE1RM(60, 10), closeTo(80.0, 0.01));
    });

    test('reps 0 또는 음수 → 0 (방어)', () {
      expect(calculateE1RM(100, 0), 0);
      expect(calculateE1RM(100, -1), 0);
    });
  });

  group('inputConfidencePercent', () {
    test('reps 5 이하 → 96', () {
      expect(inputConfidencePercent(1), 96);
      expect(inputConfidencePercent(5), 96);
    });
    test('reps 6~8 → 92', () {
      expect(inputConfidencePercent(6), 92);
      expect(inputConfidencePercent(8), 92);
    });
    test('reps 9~12 → 85', () {
      expect(inputConfidencePercent(9), 85);
      expect(inputConfidencePercent(12), 85);
    });
    test('reps 13 이상 → 72', () {
      expect(inputConfidencePercent(13), 72);
      expect(inputConfidencePercent(20), 72);
    });
  });

  group('confidenceBand', () {
    test('각 구간별 안내 문구', () {
      expect(confidenceBand(3), contains('정확도 높음'));
      expect(confidenceBand(7), contains('표준 추정'));
      expect(confidenceBand(10), contains('약간의 오차'));
      expect(confidenceBand(15), contains('정확도 낮음'));
    });
  });

  group('weightForPercentage (2.5kg 단위 반올림)', () {
    test('100kg × 100% = 100kg', () {
      expect(weightForPercentage(100, 100), 100.0);
    });
    test('100kg × 80% = 80kg', () {
      expect(weightForPercentage(100, 80), 80.0);
    });
    test('100kg × 87.5% 비율 → 87.5kg (87.5 정확히 나옴)', () {
      // 100 × 87/100 = 87 → 2.5 단위 반올림 → 87.5
      expect(weightForPercentage(100, 87), 87.5);
    });
    test('93kg × 95% = 88.35 → 87.5kg (가장 가까운 2.5 배수)', () {
      // 93 × 0.95 = 88.35 → /2.5 = 35.34 → round 35 → 87.5
      expect(weightForPercentage(93, 95), 87.5);
    });
  });
}
