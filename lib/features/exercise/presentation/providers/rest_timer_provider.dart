import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/sync_preferences.dart';
import '../../../../core/sync/sync_state.dart';
import '../../data/rest_notification_service.dart';

/// 휴식 타이머의 권위 있는 상태.
///
/// 백그라운드 복귀 정확성을 위해 매초 감산이 아닌
/// `endAt - DateTime.now()`로 남은 시간을 계산합니다.
class RestTimerState {
  final bool isActive;
  final bool isPaused;
  final int totalSeconds;
  final int remainingSeconds;

  /// 타이머 종료 예정 시각. 일시정지 중에도 재개 시 복원에 사용됩니다.
  final DateTime? endAt;

  /// 일시정지 시점에 보관되는 남은 초. 재개 시 endAt 재계산에 사용됩니다.
  final int? pausedRemaining;

  /// Phase B/C에서 네이티브 위젯과의 매핑에 사용되는 식별자.
  final String? activityId;

  /// 운동 종목명(선택). Live Activity 라벨에 사용됩니다.
  final String? exerciseName;

  const RestTimerState({
    this.isActive = false,
    this.isPaused = false,
    this.totalSeconds = 0,
    this.remainingSeconds = 0,
    this.endAt,
    this.pausedRemaining,
    this.activityId,
    this.exerciseName,
  });

  RestTimerState copyWith({
    bool? isActive,
    bool? isPaused,
    int? totalSeconds,
    int? remainingSeconds,
    DateTime? endAt,
    int? pausedRemaining,
    String? activityId,
    String? exerciseName,
    bool clearEndAt = false,
    bool clearPausedRemaining = false,
    bool clearActivityId = false,
    bool clearExerciseName = false,
  }) {
    return RestTimerState(
      isActive: isActive ?? this.isActive,
      isPaused: isPaused ?? this.isPaused,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      endAt: clearEndAt ? null : (endAt ?? this.endAt),
      pausedRemaining: clearPausedRemaining
          ? null
          : (pausedRemaining ?? this.pausedRemaining),
      activityId: clearActivityId ? null : (activityId ?? this.activityId),
      exerciseName: clearExerciseName
          ? null
          : (exerciseName ?? this.exerciseName),
    );
  }
}

class RestTimerNotifier extends StateNotifier<RestTimerState>
    with WidgetsBindingObserver {
  RestTimerNotifier(this._notifications) : super(const RestTimerState()) {
    _notifications.onAction = (actionId) {
      switch (actionId) {
        case RestNotificationAction.addFifteen:
          addSeconds(15);
          break;
        case RestNotificationAction.stop:
          stop();
          break;
      }
    };
    WidgetsBinding.instance.addObserver(this);
  }

  // ignore: avoid_renaming_method_parameters — StateNotifier.state 와 이름 충돌 회피.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed) return;
    if (!state.isActive || state.isPaused) return;
    final endAt = state.endAt;
    if (endAt == null) return;
    // 백그라운드에서 Timer.periodic 이 멎은 동안 타이머가 종료됐으면 즉시 정리.
    if (endAt.isBefore(DateTime.now())) {
      stop();
    }
  }

  final RestNotificationService _notifications;

  Timer? _ticker;
  bool _firedFiveSecondHaptic = false;

  static const int _minSeconds = 5;
  static const int _maxSeconds = 600;

  Future<void> start(int seconds, {String? exerciseName}) async {
    final clamped = seconds.clamp(_minSeconds, _maxSeconds);
    _ticker?.cancel();
    _firedFiveSecondHaptic = false;

    // 이전에 활성 타이머가 있었다면 네이티브 위젯/알림을 정리한 뒤 새 위젯을 띄운다.
    if (state.isActive) {
      await _notifications.end();
    }

    final endAt = DateTime.now().add(Duration(seconds: clamped));

    final activityId = await _notifications.show(
      totalSeconds: clamped,
      endAt: endAt,
      exerciseName: exerciseName,
    );

    state = RestTimerState(
      isActive: true,
      isPaused: false,
      totalSeconds: clamped,
      remainingSeconds: clamped,
      endAt: endAt,
      activityId: activityId,
      exerciseName: exerciseName,
    );

    await _notifications.schedulePreAlert(endAt: endAt);
    _startTicker();
  }

  Future<void> addSeconds(int delta) async {
    if (!state.isActive) return;

    if (state.isPaused) {
      final newRemaining =
          ((state.pausedRemaining ?? state.remainingSeconds) + delta)
              .clamp(_minSeconds, _maxSeconds);
      if (newRemaining > 5) _firedFiveSecondHaptic = false;
      final displayEnd = DateTime.now().add(Duration(seconds: newRemaining));
      state = state.copyWith(
        pausedRemaining: newRemaining,
        remainingSeconds: newRemaining,
        totalSeconds: newRemaining > state.totalSeconds
            ? newRemaining
            : state.totalSeconds,
      );
      await _notifications.update(endAt: displayEnd, isPaused: true);
      return;
    }

    final currentEnd = state.endAt;
    if (currentEnd == null) return;
    final newEnd = currentEnd.add(Duration(seconds: delta));
    final remaining = newEnd
        .difference(DateTime.now())
        .inSeconds
        .clamp(_minSeconds, _maxSeconds);
    final newTotal =
        remaining > state.totalSeconds ? remaining : state.totalSeconds;
    final actualEnd = DateTime.now().add(Duration(seconds: remaining));

    if (remaining > 5) _firedFiveSecondHaptic = false;

    state = state.copyWith(
      endAt: actualEnd,
      remainingSeconds: remaining,
      totalSeconds: newTotal,
    );

    await _notifications.update(endAt: actualEnd, isPaused: false);
    await _notifications.schedulePreAlert(endAt: actualEnd);
  }

  Future<void> togglePause() async {
    if (!state.isActive) return;

    if (state.isPaused) {
      final remaining = state.pausedRemaining ?? state.remainingSeconds;
      final newEnd = DateTime.now().add(Duration(seconds: remaining));
      state = state.copyWith(
        isPaused: false,
        endAt: newEnd,
        remainingSeconds: remaining,
        clearPausedRemaining: true,
      );
      _startTicker();
      await _notifications.update(endAt: newEnd, isPaused: false);
      await _notifications.schedulePreAlert(endAt: newEnd);
    } else {
      _ticker?.cancel();
      final remaining = state.remainingSeconds;
      state = state.copyWith(
        isPaused: true,
        pausedRemaining: remaining,
      );
      await _notifications.update(
        endAt: state.endAt ?? DateTime.now(),
        isPaused: true,
      );
      await _notifications.cancelPreAlert();
    }
  }

  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;
    state = const RestTimerState();
    await _notifications.cancelPreAlert();
    await _notifications.end();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (!state.isActive || state.isPaused) return;
    final endAt = state.endAt;
    if (endAt == null) return;

    final remaining = endAt.difference(DateTime.now()).inSeconds;

    if (remaining <= 5 && remaining > 0 && !_firedFiveSecondHaptic) {
      _firedFiveSecondHaptic = true;
      HapticFeedback.mediumImpact();
    }

    if (remaining <= 0) {
      HapticFeedback.heavyImpact();
      _ticker?.cancel();
      _ticker = null;
      state = const RestTimerState();
      _notifications.end();
      return;
    }

    state = state.copyWith(remainingSeconds: remaining);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }
}

final restTimerProvider =
    StateNotifierProvider<RestTimerNotifier, RestTimerState>(
  (ref) => RestTimerNotifier(ref.watch(restNotificationServiceProvider)),
);

/// 글로벌 기본 휴식 시간(초). SharedPreferences에 영속됩니다.
final defaultRestSecondsProvider = StateNotifierProvider<
    DefaultRestSecondsNotifier, int>((ref) {
  return DefaultRestSecondsNotifier(ref.read(syncPreferencesProvider));
});

class DefaultRestSecondsNotifier extends StateNotifier<int> {
  DefaultRestSecondsNotifier(this._prefs) : super(_prefs.defaultRestSeconds);

  final SyncPreferences _prefs;

  Future<void> set(int seconds) async {
    await _prefs.setDefaultRestSeconds(seconds);
    state = seconds;
  }
}
