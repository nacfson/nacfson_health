/// 하루치 활동 데이터 집계 엔티티.
///
/// Apple Health(HealthKit) 또는 Android Health Connect 에서 읽어 와 메모리에
/// 보관하는 임시 객체. Supabase 동기화 대상이 아니며 `SyncableEntity` 를
/// 구현하지 않는다 (HealthKit/HC 가 source of truth).
class DailyActivity {
  /// 데이터가 가리키는 날짜의 자정 (local time).
  final DateTime date;

  /// 걸음 수 (없으면 0).
  final int steps;

  /// 활동(능동) 소모 칼로리 합. 없으면 0.
  final double activeCaloriesKcal;

  /// 기초대사 소모 칼로리 합. 없으면 0.
  final double basalCaloriesKcal;

  /// 하루 동안 측정된 HEART_RATE 샘플의 산술 평균. 샘플 0개면 null.
  final int? averageHeartRateBpm;

  /// 안정 시 심박수 (별도 타입, 하루 1회 OS 자동 산출). 없으면 null.
  final int? restingHeartRateBpm;

  /// 하루 동안 측정된 HEART_RATE 샘플 최댓값. 샘플 0개면 null.
  final int? maxHeartRateBpm;

  /// 이 객체가 만들어진 시각 (캐시 디버깅용).
  final DateTime fetchedAt;

  const DailyActivity({
    required this.date,
    required this.steps,
    required this.activeCaloriesKcal,
    required this.basalCaloriesKcal,
    required this.averageHeartRateBpm,
    required this.restingHeartRateBpm,
    required this.maxHeartRateBpm,
    required this.fetchedAt,
  });

  /// 활동 + 기초 = 일일 총 소모 칼로리 (kcal).
  double get totalCaloriesKcal => activeCaloriesKcal + basalCaloriesKcal;

  /// 어떤 의미 있는 데이터도 없는 경우. 권한 거부 또는 데이터 부재 케이스.
  bool get isEmpty =>
      steps == 0 &&
      activeCaloriesKcal == 0 &&
      basalCaloriesKcal == 0 &&
      averageHeartRateBpm == null &&
      restingHeartRateBpm == null;

  /// 빈 활동 데이터 (권한 거부 또는 데이터 없음).
  factory DailyActivity.empty(DateTime date) => DailyActivity(
        date: DateTime(date.year, date.month, date.day),
        steps: 0,
        activeCaloriesKcal: 0,
        basalCaloriesKcal: 0,
        averageHeartRateBpm: null,
        restingHeartRateBpm: null,
        maxHeartRateBpm: null,
        fetchedAt: DateTime.now(),
      );
}
