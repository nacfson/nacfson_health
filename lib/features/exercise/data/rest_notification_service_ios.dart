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
class RestNotificationServiceIOS implements RestNotificationService {
  RestNotificationServiceIOS({String? appGroupId})
      : _appGroupId = appGroupId ?? _defaultAppGroupId {
    _liveActivities.init(
      appGroupId: _appGroupId,
      requireNotificationPermission: false,
    );
  }

  static const _defaultAppGroupId = 'group.com.nacfson.nacfsonHealth';

  final LiveActivities _liveActivities = LiveActivities();
  final String _appGroupId;
  final _uuid = const Uuid();
  String? _activityId;
  // ignore: unused_field
  RestNotificationActionHandler? _actionHandler;

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
      return id;
    } catch (_) {
      // ActivityKit 미지원(<iOS 16.1) 또는 사용자 미허용 시 조용히 무시
      _activityId = null;
      return null;
    }
  }

  @override
  Future<void> update({
    required DateTime endAt,
    required bool isPaused,
  }) async {
    final id = _activityId;
    if (id == null) return;
    final data = <String, dynamic>{
      'endAtMs': endAt.millisecondsSinceEpoch.toDouble(),
      'isPaused': isPaused,
    };
    try {
      await _liveActivities.updateActivity(id, data);
    } catch (_) {}
  }

  @override
  Future<void> end() async {
    final id = _activityId;
    if (id == null) return;
    try {
      await _liveActivities.endActivity(id);
    } catch (_) {}
    _activityId = null;
  }
}
