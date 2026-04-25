import 'package:flutter_test/flutter_test.dart';
import 'package:nacfson_health/core/ai/coach_chat_models.dart';
import 'package:nacfson_health/features/activity/domain/entities/daily_activity.dart';
import 'package:nacfson_health/features/summary/domain/entities/daily_summary.dart';

void main() {
  group('HealthContext.toPromptContext with DailyActivity', () {
    HealthContext baseCtx({DailyActivity? activity}) => HealthContext(
          date: DateTime(2026, 4, 25),
          weightKg: 70.0,
          heightM: 1.75,
          summary: DailySummary(date: DateTime(2026, 4, 25)),
          recentWeights: const [],
          activity: activity,
        );

    test('omits activity line when activity is null', () {
      final out = baseCtx().toPromptContext();
      expect(out, isNot(contains('오늘 활동:')));
      expect(out, isNot(contains('평균 심박')));
    });

    test('omits activity line when activity is empty', () {
      final out =
          baseCtx(activity: DailyActivity.empty(DateTime(2026, 4, 25)))
              .toPromptContext();
      expect(out, isNot(contains('오늘 활동:')));
    });

    test('includes activity + heart rate when populated', () {
      final activity = DailyActivity(
        date: DateTime(2026, 4, 25),
        steps: 8234,
        activeCaloriesKcal: 285.4,
        basalCaloriesKcal: 1456.7,
        averageHeartRateBpm: 78,
        restingHeartRateBpm: 62,
        maxHeartRateBpm: 156,
        fetchedAt: DateTime(2026, 4, 25, 18),
      );
      final out = baseCtx(activity: activity).toPromptContext();
      expect(out, contains('8234보'));
      expect(out, contains('활동 285kcal + 기초 1457kcal'));
      expect(out, contains('평균 심박: 78bpm'));
      expect(out, contains('안정 시 62bpm'));
    });

    test('includes only steps + calories when heart rate is missing', () {
      final activity = DailyActivity(
        date: DateTime(2026, 4, 25),
        steps: 1000,
        activeCaloriesKcal: 50,
        basalCaloriesKcal: 100,
        averageHeartRateBpm: null,
        restingHeartRateBpm: null,
        maxHeartRateBpm: null,
        fetchedAt: DateTime.now(),
      );
      final out = baseCtx(activity: activity).toPromptContext();
      expect(out, contains('1000보'));
      expect(out, isNot(contains('평균 심박')));
    });

    test('contentHash differs when activity changes', () {
      final ctxA = baseCtx();
      final ctxB = baseCtx(
        activity: DailyActivity(
          date: DateTime(2026, 4, 25),
          steps: 5000,
          activeCaloriesKcal: 200,
          basalCaloriesKcal: 1000,
          averageHeartRateBpm: 75,
          restingHeartRateBpm: null,
          maxHeartRateBpm: null,
          fetchedAt: DateTime.now(),
        ),
      );
      expect(ctxA.contentHash(), isNot(equals(ctxB.contentHash())));
    });

    test('contentHash stable when activity values are identical', () {
      final activity = DailyActivity(
        date: DateTime(2026, 4, 25),
        steps: 5000,
        activeCaloriesKcal: 200,
        basalCaloriesKcal: 1000,
        averageHeartRateBpm: 75,
        restingHeartRateBpm: null,
        maxHeartRateBpm: null,
        // fetchedAt 은 해시에 포함되지 않아야 함 (캐시 키 안정성)
        fetchedAt: DateTime(2026, 4, 25, 10),
      );
      final activity2 = DailyActivity(
        date: DateTime(2026, 4, 25),
        steps: 5000,
        activeCaloriesKcal: 200,
        basalCaloriesKcal: 1000,
        averageHeartRateBpm: 75,
        restingHeartRateBpm: null,
        maxHeartRateBpm: null,
        fetchedAt: DateTime(2026, 4, 25, 18),
      );
      expect(
        baseCtx(activity: activity).contentHash(),
        equals(baseCtx(activity: activity2).contentHash()),
      );
    });
  });
}
