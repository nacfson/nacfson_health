import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/summary/presentation/providers/summary_provider.dart';
import '../../features/weight/presentation/providers/weight_provider.dart';
import '../../shared/providers/selected_date_provider.dart';
import '../../shared/providers/user_profile_provider.dart';
import 'gemini_service.dart';

/// 날짜별 AI 인사이트 캐시 (앱 세션 내 유지)
///
/// 같은 날 요약 탭을 반복 방문해도 Gemini API를 재호출하지 않음.
/// refresh 아이콘 탭 시 해당 날짜 캐시를 삭제 후 invalidate.
final insightCacheProvider =
    StateProvider<Map<String, String>>((ref) => {});

/// 날짜 → 캐시 키 변환 헬퍼
String insightCacheKey(DateTime date) =>
    '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

/// 하루 AI 인사이트 호출 상한
const kInsightDailyLimit = 3;

const _kInsightCountKey = 'insight_call_count_v1';

/// 날짜별 Gemini 호출 횟수 (SharedPreferences 영속)
///
/// 호출 직전 증가(increment-before) → 네트워크 실패 시에도 카운트 소모.
/// 의도: API 비용 방어 우선. 사용자는 내일 다시 이용하거나 캐시 응답을 활용.
class InsightCallCountNotifier extends StateNotifier<Map<String, int>> {
  InsightCallCountNotifier([Map<String, int>? initial])
      : super(initial ?? const {});

  static Future<Map<String, int>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kInsightCountKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  int countFor(String dateKey) => state[dateKey] ?? 0;

  int remainingFor(String dateKey) =>
      (kInsightDailyLimit - countFor(dateKey)).clamp(0, kInsightDailyLimit);

  bool canCallFor(String dateKey) => countFor(dateKey) < kInsightDailyLimit;

  Future<void> increment(String dateKey) async {
    final next = {...state, dateKey: (state[dateKey] ?? 0) + 1};
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInsightCountKey, json.encode(next));
  }
}

final insightCallCountProvider =
    StateNotifierProvider<InsightCallCountNotifier, Map<String, int>>(
  (ref) => InsightCallCountNotifier(),
);

/// 오늘의 종합 건강 인사이트 (Gemini API 호출)
///
/// 선택된 날짜의 요약 + 최근 7일 체중 + 사용자 키를 조합해
/// Gemini에 쿼리하고 한국어 텍스트 응답을 반환합니다.
/// 동일 날짜는 캐시에서 즉시 반환하고, 하루 호출 상한(3회)을 초과하면
/// StateError('DAILY_LIMIT_REACHED')를 던집니다.
final healthInsightProvider = FutureProvider.autoDispose<String>((ref) async {
  final selectedDate  = ref.watch(selectedDateProvider);
  final summary       = ref.watch(dailySummaryProvider);
  final heightM       = ref.watch(heightMProvider);
  final latestWeight  = ref.watch(latestWeightProvider);
  final recentWeights = ref.watch(weightChartDataProvider); // 주간 (기본값)

  final cacheKey = insightCacheKey(selectedDate);
  final cache = ref.read(insightCacheProvider);
  if (cache.containsKey(cacheKey)) return cache[cacheKey]!;

  // 하루 호출 상한 체크 (캐시 미스 경로에서만 검사)
  final countNotifier = ref.read(insightCallCountProvider.notifier);
  if (!countNotifier.canCallFor(cacheKey)) {
    throw StateError('DAILY_LIMIT_REACHED');
  }

  // 호출 직전 증가 (실패해도 카운트 소모)
  await countNotifier.increment(cacheKey);

  final result = await GeminiService().getHealthInsight(
    weightKg: latestWeight?.weight,
    heightM: heightM,
    summary: summary,
    recentWeights: recentWeights,
  );

  // 캐시 저장
  ref
      .read(insightCacheProvider.notifier)
      .update((s) => {...s, cacheKey: result});

  return result;
});
