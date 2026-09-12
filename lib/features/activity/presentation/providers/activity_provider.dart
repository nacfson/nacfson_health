import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/selected_date_provider.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/sources/health_data_source.dart';
import '../../domain/entities/daily_activity.dart';

/// HealthDataSource 싱글톤 — HealthKit / Health Connect 는 cutover 동안 게이트.
final healthDataSourceProvider = Provider<HealthDataSource>((ref) {
  return const GatedHealthDataSource();
});

/// ActivityRepository 싱글톤.
final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  final source = ref.watch(healthDataSourceProvider);
  return HealthActivityRepository(source);
});

/// 활동 데이터 권한/가용성 상태.
///
/// UI 가 권한 카드 vs 활동 카드 노출을 결정하기 위해 사용.
final activityAuthStatusProvider =
    FutureProvider.autoDispose<ActivityAuthStatus>((ref) async {
  ref.keepAlive();
  final repo = ref.watch(activityRepositoryProvider);
  return repo.checkAvailability();
});

/// 선택된 날짜의 활동 데이터.
///
/// 권한이 없으면 [DailyActivity.empty] 를 반환한다 (UI 에서 카드 자체 숨김 결정).
/// 캐시는 Riverpod autoDispose + keepAlive 로 자연 무효화되며, 외부에서 명시적
/// 무효화는 [ref.invalidate] 로 호출 (앱 resume / pull-to-refresh).
final dailyActivityProvider =
    FutureProvider.autoDispose<DailyActivity?>((ref) async {
  ref.keepAlive();

  final repo = ref.watch(activityRepositoryProvider);
  final auth = await ref.watch(activityAuthStatusProvider.future);

  if (auth != ActivityAuthStatus.authorized) {
    return null;
  }

  final date = ref.watch(selectedDateProvider);
  return repo.getDailyActivity(date);
});

/// 권한 요청을 트리거하는 헬퍼.
///
/// 호출 후 [activityAuthStatusProvider] 와 [dailyActivityProvider] 를 invalidate
/// 하여 UI 가 갱신되도록 한다.
Future<ActivityAuthStatus> requestActivityAuthorization(WidgetRef ref) async {
  final repo = ref.read(activityRepositoryProvider);
  final result = await repo.requestAuthorization();
  ref.invalidate(activityAuthStatusProvider);
  ref.invalidate(dailyActivityProvider);
  return result;
}
