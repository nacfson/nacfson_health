import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/summary/presentation/providers/summary_provider.dart';
import '../../features/weight/presentation/providers/weight_provider.dart';
import '../../shared/providers/selected_date_provider.dart';
import '../../shared/providers/user_profile_provider.dart';
import 'coach_chat_models.dart';
import 'gemini_service.dart';

/// 코치 챗봇 일일 호출 한도 (메시지 기준).
const kCoachChatDailyLimit = 30;

const _kCoachChatCountKey = 'coach_chat_count_v1';

String coachChatDateKey(DateTime date) =>
    '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

/// 날짜별 챗 호출 횟수 (SharedPreferences 영속, 자정 리셋은 키 변경으로 자동).
class CoachChatCallCountNotifier extends StateNotifier<Map<String, int>> {
  CoachChatCallCountNotifier([Map<String, int>? initial])
      : super(initial ?? const {}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCoachChatCountKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final loaded = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      // 레이스 방어: 비동기 로드 완료 전에 increment() 가 먼저 실행되어
      // 이미 메모리에 카운트가 쌓였을 수 있다. 같은 키는 메모리 값이 우선.
      state = {...loaded, ...state};
    } catch (_) {
      // 손상된 캐시는 비워두고 새로 시작
    }
  }

  int countFor(String dateKey) => state[dateKey] ?? 0;

  int remainingFor(String dateKey) =>
      (kCoachChatDailyLimit - countFor(dateKey))
          .clamp(0, kCoachChatDailyLimit);

  bool canCallFor(String dateKey) =>
      countFor(dateKey) < kCoachChatDailyLimit;

  Future<void> increment(String dateKey) async {
    final next = {...state, dateKey: (state[dateKey] ?? 0) + 1};
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCoachChatCountKey, json.encode(next));
  }
}

final coachChatCallCountProvider =
    StateNotifierProvider<CoachChatCallCountNotifier, Map<String, int>>(
  (ref) => CoachChatCallCountNotifier(),
);

// ─────────────────────────────────────────────────────────────────────────────
// 챗 상태 & Notifier
// ─────────────────────────────────────────────────────────────────────────────

class CoachChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;

  const CoachChatState({
    required this.messages,
    required this.isLoading,
    required this.error,
  });

  const CoachChatState.initial()
      : messages = const [],
        isLoading = false,
        error = null;

  CoachChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    Object? error = _sentinel,
  }) {
    return CoachChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  static const _sentinel = Object();
}

class CoachChatNotifier extends StateNotifier<CoachChatState> {
  CoachChatNotifier(this._ref) : super(const CoachChatState.initial());

  final Ref _ref;

  Future<void> send(String userMessage) async {
    final trimmed = userMessage.trim();
    if (trimmed.isEmpty || state.isLoading) return;

    final dateKey = coachChatDateKey(DateTime.now());
    final counter = _ref.read(coachChatCallCountProvider.notifier);
    if (!counter.canCallFor(dateKey)) {
      state = state.copyWith(error: 'CHAT_DAILY_LIMIT_REACHED');
      return;
    }

    // 새 사용자 메시지를 추가하기 *전* 의 history. coachChat() 내부에서
    // userMessage 를 별도로 append 하므로, 여기에서는 직전 히스토리만 전달.
    final priorHistory = state.messages;
    final userMsg = ChatMessage(
      role: ChatRole.user,
      content: trimmed,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      error: null,
    );

    // 호출 전 카운트 증가 (네트워크 실패 시에도 소모 — Food Vision 정책과 동일)
    await counter.increment(dateKey);

    try {
      final ctx = _buildHealthContext();
      final reply = await GeminiService().coachChat(
        userMessage: trimmed,
        history: priorHistory,
        healthContext: ctx,
      );
      final assistantMsg = ChatMessage(
        role: ChatRole.assistant,
        content: reply.answer,
        createdAt: DateTime.now(),
        followUps: reply.followUps,
      );
      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        isLoading: false,
      );
    } catch (e, st) {
      debugPrint('[CoachChatNotifier] $e\n$st');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void clearError() {
    if (state.error != null) {
      state = state.copyWith(error: null);
    }
  }

  HealthContext _buildHealthContext() {
    final summary = _ref.read(dailySummaryProvider);
    final heightM = _ref.read(heightMProvider);
    final latestWeight = _ref.read(latestWeightProvider);
    final recentWeights = _ref.read(weightChartDataProvider);
    final selectedDate = _ref.read(selectedDateProvider);
    return HealthContext(
      date: selectedDate,
      weightKg: latestWeight?.weight,
      heightM: heightM,
      summary: summary,
      recentWeights: recentWeights,
    );
  }
}

/// 모달 시트가 닫히면 자동 폐기(autoDispose) → 세션 히스토리 휘발.
final coachChatProvider =
    StateNotifierProvider.autoDispose<CoachChatNotifier, CoachChatState>(
  (ref) => CoachChatNotifier(ref),
);
