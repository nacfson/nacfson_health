import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/summary/presentation/providers/summary_provider.dart';
import '../../features/weight/presentation/providers/weight_provider.dart';
import '../../shared/providers/selected_date_provider.dart';
import '../../shared/providers/user_profile_provider.dart';
import 'coach_chat_models.dart';
import 'gemini_service.dart';

/// 수동 새로고침 디바운스(초).
/// 버튼 마지막 탭 후 이 시간 이내 재탭은 무시한다.
const kInsightRefreshDebounceSeconds = 60;

/// 마지막 수동 새로고침 시각 (디바운스 판정용, 세션 전용).
final insightLastRefreshAtProvider = StateProvider<DateTime?>((ref) => null);

/// 날짜 + 데이터 해시 기반 세션 캐시.
///
/// 데이터 해시가 바뀌면 자동으로 새로운 키가 되어 재호출된다.
/// Provider rebuild 로 인한 불필요한 재호출은 같은 해시 → 캐시 적중으로 방지.
final insightCacheProvider =
    StateProvider<Map<String, String>>((ref) => {});

/// 날짜 + 컨텍스트 해시 조합 키. 데이터가 달라지면 키가 달라진다.
String insightCacheKey(DateTime date, HealthContext ctx) {
  final ymd =
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  return '$ymd-${ctx.contentHash()}';
}

/// 새로고침 가능 여부 (디바운스).
///
/// true == 지금 새로고침 가능, false == 아직 [kInsightRefreshDebounceSeconds]초 미경과.
final insightCanRefreshProvider = Provider<bool>((ref) {
  final last = ref.watch(insightLastRefreshAtProvider);
  if (last == null) return true;
  final elapsed = DateTime.now().difference(last).inSeconds;
  return elapsed >= kInsightRefreshDebounceSeconds;
});

/// 오늘의 종합 건강 인사이트 (Gemini 호출, `gemini-2.5-flash-lite`).
///
/// 선택된 날짜의 요약 + 최근 7일 체중 + 사용자 키를 조합해 Gemini에 쿼리한다.
/// 동일 (날짜, 데이터 해시)는 세션 캐시에서 즉시 반환하고, 데이터가 바뀌면
/// 자동으로 새 인사이트를 생성한다. 일일 호출 제한은 없다 — 무한 재호출은
/// 해시 캐시와 UI의 60초 디바운스로 방어한다.
final healthInsightProvider = FutureProvider.autoDispose<String>((ref) async {
  final selectedDate  = ref.watch(selectedDateProvider);
  final summary       = ref.watch(dailySummaryProvider);
  final heightM       = ref.watch(heightMProvider);
  final latestWeight  = ref.watch(latestWeightProvider);
  final recentWeights = ref.watch(weightChartDataProvider);

  final ctx = HealthContext(
    date: selectedDate,
    weightKg: latestWeight?.weight,
    heightM: heightM,
    summary: summary,
    recentWeights: recentWeights,
  );

  final cacheKey = insightCacheKey(selectedDate, ctx);
  final cache = ref.read(insightCacheProvider);
  if (cache.containsKey(cacheKey)) return cache[cacheKey]!;

  final result = await GeminiService().getHealthInsight(
    weightKg: ctx.weightKg,
    heightM: ctx.heightM,
    summary: ctx.summary,
    recentWeights: ctx.recentWeights,
  );

  ref
      .read(insightCacheProvider.notifier)
      .update((s) => {...s, cacheKey: result});

  return result;
});
