import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';
import 'package:uuid/uuid.dart';

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
/// 진단 로그: `[LiveActivity]` 접두사로 Xcode 콘솔에 출력됩니다.
/// Live Activity가 뜨지 않을 때 Xcode 콘솔에서 필터링하여 원인 확인 가능:
///   `log stream --predicate 'eventMessage contains "[LiveActivity]"'`
class RestNotificationServiceIOS implements RestNotificationService {
  RestNotificationServiceIOS({String? appGroupId})
      : _appGroupId = appGroupId ?? _defaultAppGroupId {
    _initFuture = _initialize();
  }

  static const _defaultAppGroupId = 'group.com.nacfson.nacfsonHealth';

  final LiveActivities _liveActivities = LiveActivities();
  final String _appGroupId;
  final _uuid = const Uuid();

  /// init() 은 MethodChannel 핸드쉐이크를 포함하므로 반드시 `show/update/end` 호출 전에
  /// await 되어야 한다. 생성자에서 버려진 Future를 await 하지 않고 `createActivity` 를
  /// 호출하면 첫 Activity가 silently fail 할 수 있다.
  late final Future<void> _initFuture;

  String? _activityId;
  // ignore: unused_field
  RestNotificationActionHandler? _actionHandler;

  Future<void> _initialize() async {
    try {
      await _liveActivities.init(
        appGroupId: _appGroupId,
        requireNotificationPermission: false,
      );
      // 이전 세션이 휴식 중 강제 종료되면 _activityId 는 사라지지만 iOS는 Activity 를
      // 유지한다. 새 실행에서 중복으로 보이지 않도록 정리.
      final stale = await _liveActivities.getAllActivitiesIds();
      for (final id in stale) {
        try {
          await _liveActivities.endActivity(id);
        } catch (e, s) {
          debugPrint('[LiveActivity] cleanup id=$id failed: $e\n$s');
        }
      }
      debugPrint('[LiveActivity] init OK, cleaned ${stale.length} stale');
    } catch (e, s) {
      debugPrint('[LiveActivity] init FAILED: $e\n$s');
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

    try {
      final enabled = await _liveActivities.areActivitiesEnabled();
      if (!enabled) {
        debugPrint(
          '[LiveActivity] disabled by user (Settings > $_appGroupId > Live Activities)',
        );
        return null;
      }
    } catch (e, s) {
      debugPrint('[LiveActivity] areActivitiesEnabled FAILED: $e\n$s');
      return null;
    }

    final id = _uuid.v4();
    final data = <String, dynamic>{
      'endAtMs': endAt.millisecondsSinceEpoch.toDouble(),
      'isPaused': false,
      'totalSeconds': totalSeconds,
      'exerciseName': exerciseName ?? '',
    };

    try {
      await _liveActivities.createActivity(id, data);
      _activityId = id;
      debugPrint(
        '[LiveActivity] created id=$id name="${exerciseName ?? ''}" endAt=$endAt',
      );
      return id;
    } catch (e, s) {
      debugPrint('[LiveActivity] createActivity FAILED: $e\n$s');
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
    if (id == null) return;
    final data = <String, dynamic>{
      'endAtMs': endAt.millisecondsSinceEpoch.toDouble(),
      'isPaused': isPaused,
    };
    try {
      await _liveActivities.updateActivity(id, data);
    } catch (e, s) {
      debugPrint('[LiveActivity] updateActivity id=$id FAILED: $e\n$s');
    }
  }

  @override
  Future<void> end() async {
    await _initFuture;
    final id = _activityId;
    if (id == null) return;
    try {
      await _liveActivities.endActivity(id);
    } catch (e, s) {
      debugPrint('[LiveActivity] endActivity id=$id FAILED: $e\n$s');
    }
    _activityId = null;
  }
}
