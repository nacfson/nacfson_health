import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 알림 액션 ID. Android notification의 액션 버튼 또는 iOS Live Activity의
/// AppIntents/URL scheme deep link에서 발행됩니다.
class RestNotificationAction {
  static const addFifteen = 'rest_add_15';
  static const stop = 'rest_stop';
}

typedef RestNotificationActionHandler = void Function(String actionId);

/// 휴식 타이머의 앱 외부(iOS Live Activity, Android persistent notification)
/// 표시를 담당하는 플랫폼 추상화 서비스.
///
/// Phase A에서는 NoopRestNotificationService가 모든 메서드를 no-op로 처리합니다.
/// 플랫폼별 분기는 `restNotificationServiceProvider` 정의에서 수행됩니다.
abstract class RestNotificationService {
  /// 새 휴식 타이머 위젯/알림을 표시합니다.
  /// 반환: 플랫폼별 식별자(activityId / notificationId). 미지원/실패 시 null.
  Future<String?> show({
    required int totalSeconds,
    required DateTime endAt,
    String? exerciseName,
  });

  /// 표시 중인 위젯/알림의 종료 시각/일시정지 상태를 갱신합니다.
  Future<void> update({
    required DateTime endAt,
    required bool isPaused,
  });

  /// 위젯/알림을 종료합니다.
  Future<void> end();

  /// 종료 5초 전 및 종료 시점에 로컬 알림을 예약합니다.
  /// 앱이 suspend/killed 상태여도 iOS/Android 가 시스템 레벨에서 전달합니다.
  Future<void> schedulePreAlert({required DateTime endAt});

  /// 예약된 pre-alert 와 완료 알림을 모두 취소합니다.
  Future<void> cancelPreAlert();

  /// 알림 액션 버튼 또는 Live Activity 인텐트 콜백을 등록합니다.
  /// 핸들러는 `RestNotificationAction` 상수 중 하나를 받습니다.
  set onAction(RestNotificationActionHandler? handler);
}

/// 웹/macOS/Linux/Windows 등 미지원 플랫폼용 no-op 구현.
class NoopRestNotificationService implements RestNotificationService {
  NoopRestNotificationService();

  @override
  Future<String?> show({
    required int totalSeconds,
    required DateTime endAt,
    String? exerciseName,
  }) async => null;

  @override
  Future<void> update({
    required DateTime endAt,
    required bool isPaused,
  }) async {}

  @override
  Future<void> end() async {}

  @override
  Future<void> schedulePreAlert({required DateTime endAt}) async {}

  @override
  Future<void> cancelPreAlert() async {}

  @override
  set onAction(RestNotificationActionHandler? handler) {}
}

/// 플랫폼별 분기 Provider. main.dart에서 override되어 Android/iOS 구현을 주입합니다.
/// 기본값은 web/macOS/desktop 안전을 위한 no-op.
final restNotificationServiceProvider = Provider<RestNotificationService>(
  (ref) => NoopRestNotificationService(),
);
