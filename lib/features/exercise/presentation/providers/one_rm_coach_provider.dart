import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/ai/gemini_service.dart';
import '../../../../core/training/challenge_readiness.dart';
import '../../data/repositories/sqlite_pr_repository.dart';
import '../../domain/entities/pr_summary.dart';
import '../../domain/repositories/pr_repository.dart';
import 'exercise_provider.dart'
    show
        exerciseRecordsProvider,
        todayExerciseCardsProvider,
        selectedDateExerciseGroupedProvider;

/// PR Repository 인스턴스.
final prRepositoryProvider = Provider<PrRepository>((ref) {
  return SqlitePrRepository();
});

/// 1RM 코치 칩에 노출할 종목 후보 (최근 90일 볼륨 상위 8개).
/// `exerciseRecordsProvider` 변경(세트 추가/삭제) 시 무효화.
///
/// **lifecycle**: autoDispose. 1RM 코치 풀스크린이 닫히면 즉시 dispose.
/// 다른 탭에서 운동 세트가 추가되어도 invalidate 가 이 Provider 까지 전파되지
/// 않는다 (이미 dispose 됨). 다음 풀스크린 진입 시 새로 쿼리.
final topExerciseNamesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);
  return repo.getTopExerciseNames();
});

/// 종목의 최근 work/drop 세트 1개. 입력값 자동 초기화 용도.
///
/// **lifecycle**: family.autoDispose. 풀스크린 닫히거나 종목이 변경돼
/// 다른 인스턴스가 활성화되면 listener 0 → 즉시 dispose.
/// `exerciseRecordsProvider` 변경(세트 추가/삭제) 시 자동 invalidate.
///
/// `prSummaryProvider` 와 달리 keepAlive 없음 — 입력 초기화는 칩 클릭 시
/// 1회만 실행되므로 캐시 가치가 적음.
final latestWorkSetProvider = FutureProvider.family
    .autoDispose<({double weight, int reps})?, String>((ref, exerciseName) async {
  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);
  return repo.getLatestWorkSet(exerciseName);
});

/// 카드 e1RM 칩 표시 대상 종목명 — 오늘 카드(편집 모드) ∪ 선택 날짜 그룹(과거 모드).
/// e1RM 은 날짜 무관 전역 지표이므로 과거 카드에도 동일 칩 노출.
///
/// **lifecycle**: Provider (캐시). 두 의존 Provider 변경 시 자동 invalidate.
final visibleExerciseNamesProvider = Provider<Set<String>>((ref) {
  final today =
      ref.watch(todayExerciseCardsProvider).map((c) => c.exerciseName);
  final past = ref
      .watch(selectedDateExerciseGroupedProvider)
      .values
      .expand((m) => m.keys);
  return {...today, ...past};
});

/// 카드 e1RM 칩 배치 조회. exerciseRecordsProvider 변경 시 자동 invalidate.
///
/// **lifecycle**: autoDispose. 운동 탭이 떠 있는 동안만 유지. 카드 스크롤로 일부
/// 카드가 viewport 를 벗어나도 동일 Provider 인스턴스 — re-query 없음.
/// 세트 추가/삭제 시 자동 재계산 (단일 batch SQL 1회).
final batchExerciseE1RMProvider = FutureProvider.autoDispose<
    Map<String, ({double? current, double? fourWeeksAgo})>>((ref) async {
  ref.watch(exerciseRecordsProvider);
  final names = ref.watch(visibleExerciseNamesProvider).toList();
  if (names.isEmpty) return const {};
  final repo = ref.watch(prRepositoryProvider);
  return repo.getBatchE1RM(names);
});

/// 1RM 코치 풀스크린에서 현재 선택된 종목명.
/// 진입 시 query param 또는 [topExerciseNamesProvider] 의 첫 항목으로 초기화.
final selectedCoachExerciseProvider = StateProvider<String?>((ref) => null);

/// 빠른 추정 카드의 입력 중량(kg).
final coachInputWeightProvider = StateProvider<double>((ref) => 80.0);

/// 빠른 추정 카드의 입력 횟수.
final coachInputRepsProvider = StateProvider<int>((ref) => 5);

/// 선택된 종목의 PR 요약 (FutureProvider.family).
///
/// **lifecycle**: family.autoDispose + keepAlive 30초 윈도우.
/// - 칩 A→B→A 빠른 전환 시 30초 안의 재선택은 캐시 히트 (DB 쿼리 0).
/// - 30초 경과 + listener 0 이면 dispose. 재진입 시 새 쿼리.
/// - `exerciseRecordsProvider` 변경 시에는 keepAlive 와 무관하게 invalidate.
final prSummaryProvider = FutureProvider.family
    .autoDispose<PrSummary, String>((ref, exerciseName) async {
  // 빠른 칩 전환 / 화면 짧은 잠시 떠남에서 재쿼리 회귀 방지
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 30), link.close);
  ref.onDispose(timer.cancel);

  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);
  return repo.getPrSummary(exerciseName);
});

/// 요약 탭 RecentPrCard 용 — 상위 3개 PR.
///
/// **lifecycle**: autoDispose. 현재 BottomNavShell 가 화면을 메모리에 유지하므로
/// 실질 효과는 미미하지만, BottomNav 정책 변경 / `ref.invalidate` 호출 시
/// 다음 read 까지 결과 폐기를 보장하기 위해 명시적으로 autoDispose 로 둔다.
final topPrsProvider =
    FutureProvider.autoDispose<List<PrSummary>>((ref) async {
  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);
  return repo.getTopPrs();
});

/// Gemini 코치 노트 요청 파라미터.
class CoachNoteRequest {
  final String exerciseName;
  final double currentE1RM;
  final double? deltaKg;
  final ReadinessLevel readiness;
  final double lastSetWeight;
  final int lastSetReps;

  const CoachNoteRequest({
    required this.exerciseName,
    required this.currentE1RM,
    required this.deltaKg,
    required this.readiness,
    required this.lastSetWeight,
    required this.lastSetReps,
  });

  String get cacheKey {
    final today = DateTime.now();
    final ymd =
        '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    return 'oneRmNote_${exerciseName}_${readiness.name}_$ymd';
  }

  @override
  bool operator ==(Object other) =>
      other is CoachNoteRequest &&
      other.exerciseName == exerciseName &&
      other.readiness == readiness;

  @override
  int get hashCode => Object.hash(exerciseName, readiness);
}

/// Gemini 1RM 코치 노트. 종목 + 신호등 + 날짜 별로 SharedPreferences 캐시.
/// 동일 일자 내 같은 종목/신호등이면 캐시 히트.
///
/// **lifecycle**: family.autoDispose. CoachNoteCard 가 unmount 되거나
/// 종목/신호등이 바뀌면 listener 0 → dispose. SharedPreferences 캐시는 영속이므로
/// 다음 진입 시 같은 날짜·종목·신호등이면 즉시 캐시 히트 (Gemini 호출 X).
final oneRmCoachNoteProvider = FutureProvider.family
    .autoDispose<String, CoachNoteRequest>((ref, req) async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString(req.cacheKey);
  if (cached != null && cached.isNotEmpty) return cached;

  try {
    final note = await GeminiService().getOneRMCoachNote(
      exerciseName: req.exerciseName,
      currentE1RM: req.currentE1RM,
      deltaKg: req.deltaKg,
      readiness: req.readiness,
      lastSetWeight: req.lastSetWeight,
      lastSetReps: req.lastSetReps,
    );
    if (note.isNotEmpty) {
      await prefs.setString(req.cacheKey, note);
    }
    return note;
  } catch (e) {
    debugPrint('[oneRmCoachNoteProvider] $e');
    // 실패 시 신호등별 정적 fallback
    return switch (req.readiness) {
      ReadinessLevel.green =>
        '추세가 좋아요. 가벼운 1RM 시도를 권장드립니다.',
      ReadinessLevel.amber =>
        '본세트를 2~3회 더 쌓고 다음 주 도전을 추천드려요.',
      ReadinessLevel.red =>
        '최근 강도가 높았어요. 회복 우선으로 가는 게 좋겠어요.',
      ReadinessLevel.gray =>
        '같은 종목으로 본세트를 몇 회 더 쌓아 주세요.',
    };
  }
});
