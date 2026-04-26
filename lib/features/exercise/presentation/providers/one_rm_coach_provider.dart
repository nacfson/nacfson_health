import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/ai/gemini_service.dart';
import '../../../../core/training/challenge_readiness.dart';
import '../../data/repositories/sqlite_pr_repository.dart';
import '../../domain/entities/pr_summary.dart';
import '../../domain/repositories/pr_repository.dart';
import 'exercise_provider.dart' show exerciseRecordsProvider;

/// PR Repository 인스턴스.
final prRepositoryProvider = Provider<PrRepository>((ref) {
  return SqlitePrRepository();
});

/// 1RM 코치 칩에 노출할 종목 후보 (최근 90일 볼륨 상위 8개).
/// `exerciseRecordsProvider` 변경(세트 추가/삭제) 시 무효화.
final topExerciseNamesProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);
  return repo.getTopExerciseNames();
});

/// 1RM 코치 풀스크린에서 현재 선택된 종목명.
/// 진입 시 query param 또는 [topExerciseNamesProvider] 의 첫 항목으로 초기화.
final selectedCoachExerciseProvider = StateProvider<String?>((ref) => null);

/// 빠른 추정 카드의 입력 중량(kg).
final coachInputWeightProvider = StateProvider<double>((ref) => 80.0);

/// 빠른 추정 카드의 입력 횟수.
final coachInputRepsProvider = StateProvider<int>((ref) => 5);

/// 선택된 종목의 PR 요약 (FutureProvider.family).
final prSummaryProvider =
    FutureProvider.family<PrSummary, String>((ref, exerciseName) async {
  ref.watch(exerciseRecordsProvider);
  final repo = ref.watch(prRepositoryProvider);
  return repo.getPrSummary(exerciseName);
});

/// 요약 탭 RecentPrCard 용 — 상위 3개 PR.
final topPrsProvider = FutureProvider<List<PrSummary>>((ref) async {
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
final oneRmCoachNoteProvider =
    FutureProvider.family<String, CoachNoteRequest>((ref, req) async {
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
