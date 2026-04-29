import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/ai/gemini_service.dart';
import '../../../../core/training/challenge_readiness.dart';
import '../../../../core/training/one_rm_formula.dart';
import '../../data/legacy_korean_mapping.dart';
import '../../data/repositories/sqlite_pr_repository.dart';
import '../../domain/entities/pr_summary.dart';
import '../../domain/repositories/pr_repository.dart';
import 'exercise_provider.dart' show exerciseRecordsProvider;
import 'master_data_provider.dart';

/// PR Repository 인스턴스.
final prRepositoryProvider = Provider<PrRepository>((ref) {
  return SqlitePrRepository();
});

/// 1RM 코치 칩에 노출할 종목 후보 (최근 90일 볼륨 상위 8개).
/// `exerciseRecordsProvider` 변경(세트 추가/삭제) 시 무효화.
///
/// v12: Supabase 에 1RM 공식이 등록된 종목만 노출. 미등록 종목은 자동 제외.
/// 결과 String 은 사용자가 마지막으로 본 한글/영문 이름(legacy snapshot) — UI 측에서
/// `exerciseDisplayNameProvider` 로 다시 매핑하면 현재 locale 의 표시명을 얻는다.
///
/// **lifecycle**: autoDispose. 1RM 코치 풀스크린이 닫히면 즉시 dispose.
final topExerciseNamesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);

  // v12: master data + 공식 등록 종목만 통과
  try {
    final formulaMap = await ref.watch(oneRMFormulaSpecMapProvider.future);
    if (formulaMap.isNotEmpty) {
      final registered = await repo.getTopRegisteredExercises(
        registeredExerciseKeys: formulaMap.keys.toSet(),
      );
      return registered
          .map((e) => e.legacyDisplayName ?? e.exerciseKey)
          .toList();
    }
  } catch (_) {
    // master data fetch 실패 시 legacy 동작 (전체 종목)
  }
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
///
/// v12: master data 가 로드돼 있으면 종목별 권위 공식(Mayhew/Wathen/Brzycki/...)
/// 사용. 미등록 종목은 Epley fallback (점진적 호환).
final prSummaryProvider = FutureProvider.family
    .autoDispose<PrSummary, String>((ref, exerciseName) async {
  // 빠른 칩 전환 / 화면 짧은 잠시 떠남에서 재쿼리 회귀 방지
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 30), link.close);
  ref.onDispose(timer.cancel);

  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);

  // v12: 종목명 → exercise_key → formula spec 조회.
  // 매핑 실패 시 spec=null → repository 가 Epley fallback.
  OneRMFormulaSpec? formulaSpec;
  try {
    final exerciseKey = legacyKoreanToExerciseKey(exerciseName);
    if (exerciseKey != null) {
      final formulaMap = await ref.watch(oneRMFormulaSpecMapProvider.future);
      formulaSpec = formulaMap[exerciseKey];
    }
  } catch (_) {
    // master data 로드 실패 → Epley fallback
  }

  return repo.getPrSummary(exerciseName, formulaSpec: formulaSpec);
});

/// 선택된 종목의 1RM 공식 spec. UI 의 빠른 추정 (live e1RM) 계산에 사용.
/// 종목 미등록이면 null → UI 가 Epley fallback 또는 칩 비표시.
final selectedExerciseFormulaProvider =
    FutureProvider.autoDispose<OneRMFormulaSpec?>((ref) async {
  final selected = ref.watch(selectedCoachExerciseProvider);
  if (selected == null) return null;
  final exerciseKey = legacyKoreanToExerciseKey(selected);
  if (exerciseKey == null) return null;
  try {
    final formulaMap = await ref.watch(oneRMFormulaSpecMapProvider.future);
    return formulaMap[exerciseKey];
  } catch (_) {
    return null;
  }
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
