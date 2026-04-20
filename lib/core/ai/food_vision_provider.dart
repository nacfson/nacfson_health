import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/diet/domain/entities/food_analysis_result.dart';
import 'gemini_service.dart';

/// 하루 사진 음식 분석 호출 상한.
///
/// 인사이트(3회)보다 넉넉하게 잡는 이유: 사진은 매 끼니마다 쓰일 수 있어야 함.
const kFoodVisionDailyLimit = 5;

const _kFoodVisionCountKey = 'food_vision_call_count_v1';

/// sha256 해시 → 분석 결과 (앱 세션 캐시)
///
/// 같은 사진을 재분석해도 Gemini를 재호출하지 않음.
/// 리사이즈 후 바이트 해시 기반이므로 동일 세션 내 동일 파일 재선택/재시도에서 HIT.
final foodVisionCacheProvider =
    StateProvider<Map<String, FoodAnalysisResult>>((ref) => {});

/// 날짜별 사진 분석 호출 횟수 (SharedPreferences 영속).
///
/// `increment-before` 정책: 호출 직전 +1 → 네트워크 실패해도 카운트 소모.
/// 캐시 HIT은 호출이 아니므로 카운트 영향 없음.
class FoodVisionCallCountNotifier extends StateNotifier<Map<String, int>> {
  FoodVisionCallCountNotifier([Map<String, int>? initial])
      : super(initial ?? const {});

  static Future<Map<String, int>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFoodVisionCountKey);
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
      (kFoodVisionDailyLimit - countFor(dateKey))
          .clamp(0, kFoodVisionDailyLimit);

  bool canCallFor(String dateKey) =>
      countFor(dateKey) < kFoodVisionDailyLimit;

  Future<void> increment(String dateKey) async {
    final next = {...state, dateKey: (state[dateKey] ?? 0) + 1};
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFoodVisionCountKey, json.encode(next));
  }
}

final foodVisionCallCountProvider =
    StateNotifierProvider<FoodVisionCallCountNotifier, Map<String, int>>(
  (ref) => FoodVisionCallCountNotifier(),
);

/// 날짜 → 카운터 키 변환 헬퍼 (YYYYMMDD).
String foodVisionDateKey(DateTime date) =>
    '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

/// 사진 음식 분석 오케스트레이터.
///
/// 입력: `(key: sha256해시, bytes: JPEG 바이트)`.
/// 순서: 캐시 조회 → 한도 체크 → 카운트 증가 → Gemini 호출 → 캐시 저장 → 반환.
/// 한도 초과 시 `StateError('DAILY_LIMIT_REACHED')` 전파.
final foodVisionAnalysisProvider = FutureProvider.autoDispose
    .family<FoodAnalysisResult, FoodVisionRequest>((ref, req) async {
  final cache = ref.read(foodVisionCacheProvider);
  final cached = cache[req.key];
  if (cached != null) return cached;

  final dateKey = foodVisionDateKey(DateTime.now());
  final countNotifier = ref.read(foodVisionCallCountProvider.notifier);
  if (!countNotifier.canCallFor(dateKey)) {
    throw StateError('DAILY_LIMIT_REACHED');
  }

  await countNotifier.increment(dateKey);

  final result = await GeminiService().analyzeFoodImage(req.bytes);

  ref
      .read(foodVisionCacheProvider.notifier)
      .update((s) => {...s, req.key: result});

  return result;
});

/// 분석 요청 파라미터 (해시 키 + 바이트).
class FoodVisionRequest {
  final String key;
  final Uint8List bytes;

  const FoodVisionRequest({required this.key, required this.bytes});

  @override
  bool operator ==(Object other) =>
      other is FoodVisionRequest && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
