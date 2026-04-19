import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'rest_notification_service.dart';

/// Android persistent notification (chronometer + 액션 버튼) 구현체.
///
/// 알림 채널: `rest_timer_channel`. importance/priority `low`로 설정하여
/// 카운트다운이 사용자를 방해하지 않게 합니다(소리/고우선 헤드업 알림 X).
class RestNotificationServiceAndroid implements RestNotificationService {
  RestNotificationServiceAndroid() {
    _initialize();
  }

  static const _notificationId = 9001;
  static const _channelId = 'rest_timer_channel';
  static const _channelName = '휴식 타이머';
  static const _channelDescription = '운동 세트 사이 휴식 카운트다운';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  RestNotificationActionHandler? _actionHandler;
  bool _initialized = false;
  String? _activeExerciseName;

  Future<void> _initialize() async {
    if (_initialized) return;
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onResponse,
    );
    _initialized = true;
  }

  void _onResponse(NotificationResponse response) {
    final actionId = response.actionId;
    if (actionId == null) return;
    _actionHandler?.call(actionId);
  }

  Future<bool> _ensurePermission() async {
    // Android 13+ POST_NOTIFICATIONS 런타임 권한 요청.
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    final result = await Permission.notification.request();
    return result.isGranted;
  }

  AndroidNotificationDetails _details({
    required DateTime endAt,
    required bool isPaused,
    String? exerciseName,
  }) {
    return AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      when: endAt.millisecondsSinceEpoch,
      usesChronometer: !isPaused,
      chronometerCountDown: true,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      category: AndroidNotificationCategory.stopwatch,
      visibility: NotificationVisibility.public,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          RestNotificationAction.addFifteen,
          '+15초',
          showsUserInterface: false,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          RestNotificationAction.stop,
          '정지',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );
  }

  @override
  Future<String?> show({
    required int totalSeconds,
    required DateTime endAt,
    String? exerciseName,
  }) async {
    await _initialize();
    final granted = await _ensurePermission();
    if (!granted) return null;

    final details = NotificationDetails(
      android: _details(
        endAt: endAt,
        isPaused: false,
        exerciseName: exerciseName,
      ),
    );

    _activeExerciseName = exerciseName?.isNotEmpty == true ? exerciseName : null;
    await _plugin.show(
      _notificationId,
      _titleText(),
      _bodyText(false),
      details,
    );
    return _notificationId.toString();
  }

  @override
  Future<void> update({
    required DateTime endAt,
    required bool isPaused,
  }) async {
    if (!_initialized) return;
    final details = NotificationDetails(
      android: _details(endAt: endAt, isPaused: isPaused),
    );
    await _plugin.show(
      _notificationId,
      _titleText(),
      _bodyText(isPaused),
      details,
    );
  }

  @override
  Future<void> end() async {
    if (!_initialized) return;
    await _plugin.cancel(_notificationId);
    _activeExerciseName = null;
  }

  @override
  set onAction(RestNotificationActionHandler? handler) {
    _actionHandler = handler;
  }

  String _bodyText(bool paused) =>
      paused ? '일시정지 중' : '세트 사이 휴식 카운트다운';

  String _titleText() => _activeExerciseName ?? '휴식 중';
}
