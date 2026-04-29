import 'package:flutter_test/flutter_test.dart';
import 'package:nacfson_health/core/training/one_rm_formula.dart';

void main() {
  // 표준 테스트 입력: 80kg × 5회.
  // 기대값은 각 공식의 표준 정의에서 직접 계산한 값.

  group('EpleySpec', () {
    test('Epley (k=1/30) — 80kg × 5회 ≈ 93.33kg', () {
      final spec = EpleySpec(k: 1 / 30);
      expect(spec.calculate(80, 5), closeTo(93.333, 0.01));
    });

    test('O\'Conner (k=0.025) — 80kg × 5회 = 90.0kg', () {
      final spec = EpleySpec(k: 0.025);
      expect(spec.calculate(80, 5), closeTo(90.0, 0.01));
    });

    test('reps=1 일 때 weight 그대로', () {
      final spec = EpleySpec(k: 1 / 30);
      expect(spec.calculate(100, 1), 100);
    });

    test('reps<=0 일 때 0', () {
      final spec = EpleySpec(k: 1 / 30);
      expect(spec.calculate(100, 0), 0);
    });
  });

  group('LinearSpec', () {
    test('Brzycki (a=1.0278, b=0.0278) — 80kg × 5회 ≈ 90.07kg', () {
      final spec = LinearSpec(a: 1.0278, b: 0.0278);
      // 80 / (1.0278 - 0.0278*5) = 80 / 0.8888 ≈ 90.0090
      expect(spec.calculate(80, 5), closeTo(90.01, 0.05));
    });

    test('Lander (a=1.013, b=0.0267123) — 80kg × 5회 ≈ 91.0kg', () {
      final spec = LinearSpec(a: 1.013, b: 0.0267123);
      // 80 / (1.013 - 0.0267123*5) = 80 / 0.879 ≈ 91.0
      expect(spec.calculate(80, 5), closeTo(90.99, 0.1));
    });

    test('분모가 0 이하면 weight 반환 (안전 fallback)', () {
      final spec = LinearSpec(a: 1.0, b: 0.5);
      // reps=3 → 1.0 - 1.5 = -0.5 → fallback
      expect(spec.calculate(80, 3), 80);
    });
  });

  group('ExponentialSpec', () {
    test('Mayhew (a=100, b=52.2, c=41.9, k=-0.055) — 80kg × 5회 ≈ 92.6kg', () {
      final spec = ExponentialSpec(a: 100, b: 52.2, c: 41.9, k: -0.055);
      // 100*80 / (52.2 + 41.9*exp(-0.275)) = 8000 / (52.2 + 41.9*0.7596) ≈ 8000 / 84.03 ≈ 95.2
      expect(spec.calculate(80, 5), closeTo(95.2, 0.5));
    });

    test('Wathen (a=100, b=48.8, c=53.8, k=-0.075) — 80kg × 5회 ≈ 91.5kg', () {
      final spec = ExponentialSpec(a: 100, b: 48.8, c: 53.8, k: -0.075);
      // 100*80 / (48.8 + 53.8*exp(-0.375)) = 8000 / (48.8 + 53.8*0.6873) ≈ 8000 / 85.78 ≈ 93.3
      expect(spec.calculate(80, 5), closeTo(93.3, 0.5));
    });

    test('reps=1 → weight 그대로', () {
      final spec = ExponentialSpec(a: 100, b: 52.2, c: 41.9, k: -0.055);
      expect(spec.calculate(100, 1), 100);
    });
  });

  group('PolynomialSpec', () {
    test('Lombardi (p=0.10) — 80kg × 5회 ≈ 138.9kg... wait', () {
      // 80 * 5^0.10 = 80 * 1.1746 ≈ 93.97
      final spec = PolynomialSpec(p: 0.10);
      expect(spec.calculate(80, 5), closeTo(93.97, 0.1));
    });
  });

  group('parse()', () {
    test('epley type 파싱', () {
      final spec = OneRMFormulaSpec.parse('epley', {'k': 0.0333});
      expect(spec, isA<EpleySpec>());
      expect((spec as EpleySpec).k, 0.0333);
    });

    test('linear type 파싱', () {
      final spec = OneRMFormulaSpec.parse('linear', {'a': 1.0278, 'b': 0.0278});
      expect(spec, isA<LinearSpec>());
    });

    test('exponential type 파싱', () {
      final spec = OneRMFormulaSpec.parse('exponential', {
        'a': 100,
        'b': 52.2,
        'c': 41.9,
        'k': -0.055,
      });
      expect(spec, isA<ExponentialSpec>());
    });

    test('polynomial type 파싱', () {
      final spec = OneRMFormulaSpec.parse('polynomial', {'p': 0.10});
      expect(spec, isA<PolynomialSpec>());
    });

    test('알 수 없는 type → null', () {
      final spec = OneRMFormulaSpec.parse('unknown', {'k': 0.0333});
      expect(spec, isNull);
    });

    test('필수 키 누락 → null', () {
      final spec = OneRMFormulaSpec.parse('exponential', {'a': 100, 'b': 52.2});
      expect(spec, isNull);
    });

    test('JSON 정수도 double 로 파싱', () {
      final spec = OneRMFormulaSpec.parse('exponential', {
        'a': 100, // int
        'b': 52, // int
        'c': 42, // int
        'k': -0.055,
      });
      expect(spec, isA<ExponentialSpec>());
    });
  });

  group('calculateE1RMWithFormula', () {
    test('null spec → null 반환', () {
      expect(calculateE1RMWithFormula(null, 80, 5), isNull);
    });

    test('reps<=0 → null', () {
      final spec = EpleySpec(k: 1 / 30);
      expect(calculateE1RMWithFormula(spec, 80, 0), isNull);
    });

    test('weight<=0 → null', () {
      final spec = EpleySpec(k: 1 / 30);
      expect(calculateE1RMWithFormula(spec, 0, 5), isNull);
    });

    test('정상 입력 → spec.calculate 결과', () {
      final spec = EpleySpec(k: 1 / 30);
      final result = calculateE1RMWithFormula(spec, 80, 5);
      expect(result, closeTo(93.333, 0.01));
    });
  });
}
