import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/exercise_template.dart';
import '../../../settings/presentation/providers/exercise_template_provider.dart';
import '../../data/rest_notification_service.dart';
import '../../domain/body_part_rest_defaults.dart';

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
  RestTimerNotifier(this._ref, this._notifications)
      : super(const RestTimerState()) {
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
    // 활성 타이머 종목의 휴식 시간 override 가 변경되면 endAt 을 즉시 재계산해
    // 외부 위젯(Live Activity / 알림)을 동기화한다.
    _ref.listen<List<ExerciseTemplate>>(
      exerciseTemplatesProvider,
      _onTemplatesChanged,
      fireImmediately: false,
    );
  }

  final Ref _ref;

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
    // 빠른 start→stop→start 반복이나 네이티브 응답 지연 시 stale Live Activity
    // 가 잔존하지 않도록, end() 실패는 무시하고 새 show() 로 진행한다.
    if (state.isActive) {
      try {
        await _notifications.end();
      } catch (e) {
        debugPrint('rest timer 이전 알림 정리 실패: $e');
      }
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
      await _notifications.update(
        endAt: displayEnd,
        isPaused: true,
        totalSeconds: state.totalSeconds,
      );
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

    await _notifications.update(
      endAt: actualEnd,
      isPaused: false,
      totalSeconds: newTotal,
    );
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
      await _notifications.update(
        endAt: newEnd,
        isPaused: false,
        totalSeconds: state.totalSeconds,
      );
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
        totalSeconds: state.totalSeconds,
      );
      await _notifications.cancelPreAlert();
    }
  }

  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;
    state = const RestTimerState();
    try {
      await _notifications.cancelPreAlert();
    } catch (e) {
      debugPrint('rest timer pre-alert 취소 실패: $e');
    }
    try {
      await _notifications.end();
    } catch (e) {
      // 네이티브 정리 실패해도 state 는 비웠으므로 다음 start() 가 자체 정리.
      debugPrint('rest timer end 실패: $e');
    }
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

  /// 템플릿 리스트 변경 → 활성 타이머의 종목 override 가 바뀌었는지 검사.
  /// 일치 + 값 변화 시 endAt 을 즉시 재계산해 native 위젯/알림에 push.
  void _onTemplatesChanged(
    List<ExerciseTemplate>? prev,
    List<ExerciseTemplate> next,
  ) {
    if (!state.isActive) return;
    final activeName = state.exerciseName;
    if (activeName == null) return;

    final updated = _findByName(next, activeName);
    if (updated == null) return;
    final newRest = resolveRestSeconds(updated);
    if (newRest == null) return; // 유산소로 전환 — 활성 타이머는 그대로 유지.

    final prevTemplate = prev == null ? null : _findByName(prev, activeName);
    final oldRest =
        prevTemplate == null ? null : resolveRestSeconds(prevTemplate);
    if (oldRest == newRest) return;

    unawaited(_applyNewRestSeconds(newRest));
  }

  static ExerciseTemplate? _findByName(
    List<ExerciseTemplate> templates,
    String name,
  ) {
    final matches = templates.where((t) => t.name == name);
    return matches.isEmpty ? null : matches.first;
  }

  /// 활성 타이머의 totalSeconds 와 endAt 을 새 휴식 시간 기준으로 재산출.
  /// 경과 시간이 새 값을 이미 넘었으면 1초 보장 후 _onTick 에서 자연 종료.
  Future<void> _applyNewRestSeconds(int newRest) async {
    final clamped = newRest.clamp(_minSeconds, _maxSeconds);

    if (state.isPaused) {
      final displayEnd = DateTime.now().add(Duration(seconds: clamped));
      state = state.copyWith(
        totalSeconds: clamped,
        pausedRemaining: clamped,
        remainingSeconds: clamped,
      );
      if (clamped > 5) _firedFiveSecondHaptic = false;
      await _notifications.update(
        endAt: displayEnd,
        isPaused: true,
        totalSeconds: clamped,
      );
      return;
    }

    final elapsed = state.totalSeconds - state.remainingSeconds;
    final newRemaining = math.max(1, clamped - elapsed);
    final newEndAt = DateTime.now().add(Duration(seconds: newRemaining));

    if (newRemaining > 5) _firedFiveSecondHaptic = false;

    state = state.copyWith(
      endAt: newEndAt,
      remainingSeconds: newRemaining,
      totalSeconds: clamped,
    );

    await _notifications.update(
      endAt: newEndAt,
      isPaused: false,
      totalSeconds: clamped,
    );
    await _notifications.schedulePreAlert(endAt: newEndAt);
  }
}

final restTimerProvider =
    StateNotifierProvider<RestTimerNotifier, RestTimerState>(
  (ref) => RestTimerNotifier(ref, ref.watch(restNotificationServiceProvider)),
);
