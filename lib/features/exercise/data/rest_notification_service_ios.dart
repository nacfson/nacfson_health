import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'rest_notification_service.dart';

/// iOS Live Activity (Dynamic Island + Lock Screen) 구현체.
///
/// Xcode에서 다음 단계가 사전에 완료되어 있어야 합니다:
/// 1. Widget Extension 타겟 추가 ("Include Live Activity" 체크)
/// 2. `ios/RestActivityWidget/*.swift` 두 파일을 위 타겟에 멤버십 추가
/// 3. App Group capability 추가 (Runner + Widget Extension 둘 다 동일 그룹)
/// 4. Podfile platform iOS 16.1 / Info.plist `NSSupportsLiveActivities=true`
///
/// 자세한 절차는 `docs/build-debug.md` 참조.
///
/// 본 구현체는 ActivityKit 호출 일체를 자체 `RestActivityBridge` (Swift, MethodChannel
/// `nacfson/rest_activity`) 로 위임한다. ContentState 에 타이머 데이터(endAtMs/isPaused/
/// exerciseName/totalSeconds)가 직접 들어가므로 매 update 마다 ActivityKit 이 위젯
/// rebuild 를 즉시 trigger 한다.
///
/// 진단 로그: `[LiveActivity]` 접두사로 Xcode 콘솔에 출력됩니다.
/// Live Activity가 뜨지 않을 때 Xcode 콘솔에서 필터링하여 원인 확인 가능:
///   `log stream --predicate 'eventMessage contains "[LiveActivity]"'`
class RestNotificationServiceIOS implements RestNotificationService {
  RestNotificationServiceIOS() {
    _initFuture = _initialize();
  }

  static const _bridgeChannel = MethodChannel('nacfson/rest_activity');
  static const _preAlertId = 9101;

  /// 실제 타이머 종료 후 iOS 가 위젯을 자동 dismiss 하기까지의 grace. 이 간격 안에
  /// 위젯은 "휴식 완료" 상태로 남음. 사용자가 +15초 연타해서 newEndAt 이 초기
  /// dismiss 시각을 초과하면 위젯이 카운트다운 도중 사라질 수 있으므로
  /// `update()` 시에도 재스케줄을 시도.
  static const _dismissGrace = Duration(seconds: 15);

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// init() 은 MethodChannel 핸드쉐이크 + 잔여 Activity cleanup 을 포함하므로
  /// 반드시 `show/update/end` 호출 전에 await 되어야 한다.
  late final Future<void> _initFuture;

  String? _activityId;
  bool _notificationsInitialized = false;
  bool _permissionRequested = false;
  // ignore: unused_field
  RestNotificationActionHandler? _actionHandler;

  Future<void> _initialize() async {
    try {
      // 이전 세션이 휴식 중 강제 종료되면 _activityId 는 사라지지만 iOS는 Activity 를
      // 유지한다. 새 실행에서 중복으로 보이지 않도록 정리.
      await _bridgeChannel.invokeMethod('endAll');
      debugPrint('[LiveActivity] init OK (endAll requested)');
    } catch (e, s) {
      debugPrint('[LiveActivity] init FAILED: $e\n$s');
    }
  }

  Future<void> _ensureNotificationsInit() async {
    if (_notificationsInitialized) return;
    tz.initializeTimeZones();
    const settings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _notifications.initialize(settings);
    _notificationsInitialized = true;
  }

  Future<bool> _ensurePermission() async {
    await _ensureNotificationsInit();
    final ios = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios == null) return false;
    if (_permissionRequested) return true;
    _permissionRequested = true;
    final granted = await ios.requestPermissions(alert: true, sound: true);
    return granted ?? false;
  }

  Future<void> _scheduleDismissBridge({
    required String activityId,
    required DateTime dismissAt,
  }) async {
    try {
      await _bridgeChannel.invokeMethod('scheduleDismiss', <String, Object>{
        'activityId': activityId,
        'dismissAtMs': dismissAt.millisecondsSinceEpoch.toDouble(),
      });
    } catch (e, s) {
      // 브리지 미등록 또는 ActivityKit 조회 실패. 위젯 자체의 "완료" 폴백으로 보완.
      debugPrint('[LiveActivity] scheduleDismissBridge FAILED: $e\n$s');
    }
  }

  @override
  set onAction(RestNotificationActionHandler? handler) {
    // 현재는 등록만 받아두고 디스패치는 미구현. iOS Live Activity의 액션은
    // App Intents 또는 URL scheme deep link로 받아야 하며, 후속 백로그에서 처리.
    _actionHandler = handler;
  }

  @override
  Future<String?> show({
    required int totalSeconds,
    required DateTime endAt,
    String? exerciseName,
  }) async {
    await _initFuture;

    bool enabled = false;
    try {
      enabled = await _bridgeChannel.invokeMethod<bool>('areEnabled') ?? false;
    } catch (e, s) {
      debugPrint('[LiveActivity] areEnabled FAILED: $e\n$s');
      return null;
    }
    if (!enabled) {
      debugPrint(
        '[LiveActivity] disabled by user (Settings > Live Activities)',
      );
      return null;
    }

    try {
      final returnedId = await _bridgeChannel.invokeMethod<String>(
        'start',
        <String, Object>{
          'totalSeconds': totalSeconds,
          'endAtMs': endAt.millisecondsSinceEpoch.toDouble(),
          'exerciseName': exerciseName ?? '',
        },
      );
      if (returnedId == null) {
        debugPrint('[LiveActivity] start returned null (request failed)');
        _activityId = null;
        return null;
      }
      _activityId = returnedId;
      debugPrint(
        '[LiveActivity] created id=$_activityId name="${exerciseName ?? ''}" endAt=$endAt',
      );
      await _scheduleDismissBridge(
        activityId: returnedId,
        dismissAt: endAt.add(_dismissGrace),
      );
      return returnedId;
    } catch (e, s) {
      debugPrint('[LiveActivity] start FAILED: $e\n$s');
      _activityId = null;
      return null;
    }
  }

  @override
  Future<void> update({
    required DateTime endAt,
    required bool isPaused,
  }) async {
    await _initFuture;
    final id = _activityId;
    debugPrint(
      '[LiveActivity] update called id=$id endAt=$endAt paused=$isPaused',
    );
    if (id == null) return;
    try {
      await _bridgeChannel.invokeMethod('update', <String, Object>{
        'activityId': id,
        'endAtMs': endAt.millisecondsSinceEpoch.toDouble(),
        'isPaused': isPaused,
      });
      debugPrint('[LiveActivity] update id=$id OK');
    } catch (e, s) {
      debugPrint('[LiveActivity] update id=$id FAILED: $e\n$s');
    }
    // +15 연타 등으로 새 endAt 이 초기 dismiss 시각을 넘길 수 있으니 재스케줄.
    // 일시정지 상태에선 endAt 이 display 용이라 dismiss 를 밀지 않음.
    if (!isPaused) {
      await _scheduleDismissBridge(
        activityId: id,
        dismissAt: endAt.add(_dismissGrace),
      );
    }
  }

  @override
  Future<void> end() async {
    await _initFuture;
    final id = _activityId;
    if (id == null) return;
    try {
      await _bridgeChannel.invokeMethod('endActivity', <String, Object>{
        'activityId': id,
      });
    } catch (e, s) {
      debugPrint('[LiveActivity] endActivity id=$id FAILED: $e\n$s');
    }
    _activityId = null;
  }

  @override
  Future<void> schedulePreAlert({required DateTime endAt}) async {
    final granted = await _ensurePermission();
    if (!granted) return;

    // 기존 예약 정리 후 재예약하여 +15초 연타 race 방지.
    await cancelPreAlert();

    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    final now = DateTime.now();
    final preAt = endAt.subtract(const Duration(seconds: 5));
    if (preAt.isAfter(now)) {
      try {
        await _notifications.zonedSchedule(
          _preAlertId,
          '휴식 5초 남음',
          '곧 다음 세트를 시작합니다',
          tz.TZDateTime.from(preAt, tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e, s) {
        debugPrint('[LiveActivity] schedulePreAlert 5s FAILED: $e\n$s');
      }
    }
  }

  @override
  Future<void> cancelPreAlert() async {
    if (!_notificationsInitialized) return;
    await _notifications.cancel(_preAlertId);
  }
}
