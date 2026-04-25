import 'package:flutter_test/flutter_test.dart';
import 'package:nacfson_health/features/activity/domain/entities/daily_activity.dart';

void main() {
  group('DailyActivity', () {
    test('totalCaloriesKcal sums active + basal', () {
      final a = DailyActivity(
        date: DateTime(2026, 4, 25),
        steps: 5000,
        activeCaloriesKcal: 320.5,
        basalCaloriesKcal: 1450.2,
        averageHeartRateBpm: 75,
        restingHeartRateBpm: 60,
        maxHeartRateBpm: 140,
        fetchedAt: DateTime(2026, 4, 25, 12),
      );
      expect(a.totalCaloriesKcal, closeTo(1770.7, 0.01));
    });

    test('isEmpty true when all metrics are zero/null', () {
      final a = DailyActivity.empty(DateTime(2026, 4, 25));
      expect(a.isEmpty, isTrue);
      expect(a.totalCaloriesKcal, 0);
      expect(a.steps, 0);
      expect(a.averageHeartRateBpm, isNull);
    });

    test('isEmpty false when any metric is populated', () {
      final withSteps = DailyActivity(
        date: DateTime(2026, 4, 25),
        steps: 1,
        activeCaloriesKcal: 0,
        basalCaloriesKcal: 0,
        averageHeartRateBpm: null,
        restingHeartRateBpm: null,
        maxHeartRateBpm: null,
        fetchedAt: DateTime.now(),
      );
      expect(withSteps.isEmpty, isFalse);

      final withResting = DailyActivity(
        date: DateTime(2026, 4, 25),
        steps: 0,
        activeCaloriesKcal: 0,
        basalCaloriesKcal: 0,
        averageHeartRateBpm: null,
        restingHeartRateBpm: 62,
        maxHeartRateBpm: null,
        fetchedAt: DateTime.now(),
      );
      expect(withResting.isEmpty, isFalse);
    });

    test('empty factory normalizes date to midnight', () {
      final a = DailyActivity.empty(DateTime(2026, 4, 25, 14, 30, 45));
      expect(a.date, DateTime(2026, 4, 25));
    });
  });
}
