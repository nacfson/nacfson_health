import 'package:flutter_test/flutter_test.dart';
import 'package:nacfson_health/core/nutrition/atwater_calculator.dart';

void main() {
  group('kcalFromMacros (Atwater 4/4/9)', () {
    test('zero macros → 0 kcal', () {
      expect(kcalFromMacros(0, 0, 0), 0);
    });

    test('integer macros → exact sum', () {
      // 탄 30 * 4 = 120, 단 20 * 4 = 80, 지 5 * 9 = 45 → 245
      expect(kcalFromMacros(30, 20, 5), 245);
    });

    test('protein-only', () {
      expect(kcalFromMacros(0, 25, 0), 100);
    });

    test('fat-only', () {
      expect(kcalFromMacros(0, 0, 10), 90);
    });

    test('decimal macros are rounded half-up', () {
      // 1.5*4 + 1.5*4 + 1.5*9 = 6 + 6 + 13.5 = 25.5 → 26
      expect(kcalFromMacros(1.5, 1.5, 1.5), 26);
    });

    test('typical meal', () {
      // 탄 60, 단 30, 지 15 → 240 + 120 + 135 = 495
      expect(kcalFromMacros(60, 30, 15), 495);
    });

    test('NaN input → 0 (defensive guard)', () {
      expect(kcalFromMacros(double.nan, 0, 0), 0);
      expect(kcalFromMacros(0, double.nan, 0), 0);
      expect(kcalFromMacros(0, 0, double.nan), 0);
    });

    test('Infinity input → 0 (defensive guard)', () {
      expect(kcalFromMacros(double.infinity, 0, 0), 0);
      expect(kcalFromMacros(0, double.negativeInfinity, 0), 0);
    });

    test('negative input → 0 (defensive guard)', () {
      expect(kcalFromMacros(-1, 0, 0), 0);
      expect(kcalFromMacros(0, 0, -0.1), 0);
    });
  });
}
