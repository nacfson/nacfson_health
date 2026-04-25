import '../../domain/entities/daily_activity.dart';
import '../sources/health_data_source.dart';

/// 활동 데이터 도메인 진입점.
///
/// 의도적으로 [HealthDataSource] 와 거의 동일한 메서드 셋을 갖되, 도메인 레이어
/// 에서 외부 SDK 타입(`Health`, `HealthDataType`) 을 노출하지 않는다.
abstract class ActivityRepository {
  Future<ActivityAuthStatus> checkAvailability();
  Future<ActivityAuthStatus> requestAuthorization();
  Future<DailyActivity> getDailyActivity(DateTime date);
}

class HealthActivityRepository implements ActivityRepository {
  final HealthDataSource _source;

  HealthActivityRepository(this._source);

  @override
  Future<ActivityAuthStatus> checkAvailability() => _source.checkAvailability();

  @override
  Future<ActivityAuthStatus> requestAuthorization() =>
      _source.requestAuthorization();

  @override
  Future<DailyActivity> getDailyActivity(DateTime date) =>
      _source.getDailyActivity(date);
}
