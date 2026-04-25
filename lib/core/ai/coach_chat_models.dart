import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../features/activity/domain/entities/daily_activity.dart';
import '../../features/summary/domain/entities/daily_summary.dart';
import '../../features/weight/domain/entities/weight_record.dart';

enum ChatRole { user, assistant }

class ChatMessage {
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final List<String> followUps;

  const ChatMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.followUps = const [],
  });
}

class CoachReply {
  final String answer;
  final List<String> followUps;

  const CoachReply({required this.answer, required this.followUps});
}

/// 매 챗 호출마다 Gemini System Instruction에 주입되는 사용자 건강 스냅샷.
class HealthContext {
  final DateTime date;
  final double? weightKg;
  final double heightM;
  final DailySummary? summary;
  final List<WeightRecord> recentWeights;

  /// Apple Health / Health Connect 에서 읽어 온 일일 활동 요약. 권한 미허용 또는
  /// 데이터 없음이면 null. null 이면 프롬프트에서 "활동 데이터 없음" 으로 표기.
  final DailyActivity? activity;

  const HealthContext({
    required this.date,
    required this.weightKg,
    required this.heightM,
    required this.summary,
    required this.recentWeights,
    this.activity,
  });

  double? get bmi {
    final w = weightKg;
    if (w == null || heightM <= 0) return null;
    return w / (heightM * heightM);
  }

  /// 컨텍스트 요약 문자열 (Gemini 프롬프트 주입용).
  String toPromptContext() {
    final buffer = StringBuffer();
    buffer.writeln('【사용자 건강 데이터】');
    if (weightKg != null) {
      buffer.writeln('- 체중: ${weightKg!.toStringAsFixed(1)}kg');
      final b = bmi;
      if (b != null) buffer.writeln('- BMI: ${b.toStringAsFixed(1)}');
    }
    if (recentWeights.length >= 2) {
      final delta =
          recentWeights.last.weight - recentWeights.first.weight;
      final sign = delta >= 0 ? '+' : '';
      buffer.writeln(
          '- 최근 ${recentWeights.length}일 체중 변화: $sign${delta.toStringAsFixed(1)}kg');
    }
    final diet = summary?.dietNutrition;
    if (diet != null) {
      buffer.writeln(
          '- 오늘 칼로리: ${diet.consumedCalories}/${diet.targetCalories}kcal');
      final p = diet.macroStatus['protein'];
      final c = diet.macroStatus['carbs'];
      final f = diet.macroStatus['fat'];
      if (p != null) {
        buffer.writeln(
            '- 단백질: ${p.consumed.toStringAsFixed(0)}/${p.target.toStringAsFixed(0)}g');
      }
      if (c != null) {
        buffer.writeln(
            '- 탄수화물: ${c.consumed.toStringAsFixed(0)}/${c.target.toStringAsFixed(0)}g');
      }
      if (f != null) {
        buffer.writeln(
            '- 지방: ${f.consumed.toStringAsFixed(0)}/${f.target.toStringAsFixed(0)}g');
      }
    }
    final workout = summary?.workoutPerformance;
    if (workout != null && workout.isWorkoutDay) {
      buffer.writeln(
          '- 오늘 운동 부위: ${workout.targetedMuscles.join(", ")}');
      buffer.writeln('- 총 볼륨: ${workout.totalVolume.toStringAsFixed(0)}kg');
      if (workout.averageRpe > 0) {
        buffer.writeln('- 평균 RPE: ${workout.averageRpe.toStringAsFixed(1)}');
      }
    } else {
      buffer.writeln('- 오늘 운동: 기록 없음');
    }
    final a = activity;
    if (a != null && !a.isEmpty) {
      buffer.writeln(
        '- 오늘 활동: ${a.steps}보, 활동 ${a.activeCaloriesKcal.round()}kcal + 기초 ${a.basalCaloriesKcal.round()}kcal 소모',
      );
      if (a.averageHeartRateBpm != null) {
        buffer.writeln(
          '- 평균 심박: ${a.averageHeartRateBpm}bpm'
          '${a.restingHeartRateBpm != null ? " (안정 시 ${a.restingHeartRateBpm}bpm)" : ""}',
        );
      }
    }
    return buffer.toString();
  }

  /// 캐시 키용 short hash — 핵심 수치가 바뀌면 값이 바뀌도록.
  ///
  /// Dart `hashCode` 는 플랫폼별 비결정성과 충돌 가능성이 있어 캐시 키로
  /// 부적절하다. 충돌 내성을 확보하기 위해 sha256 의 앞 8 hex 자리를 사용.
  String contentHash() {
    final diet = summary?.dietNutrition;
    final workout = summary?.workoutPerformance;
    final parts = <String>[
      weightKg?.toStringAsFixed(2) ?? '-',
      heightM.toStringAsFixed(2),
      diet?.consumedCalories.toString() ?? '-',
      diet?.macroStatus['protein']?.consumed.toStringAsFixed(0) ?? '-',
      diet?.macroStatus['carbs']?.consumed.toStringAsFixed(0) ?? '-',
      diet?.macroStatus['fat']?.consumed.toStringAsFixed(0) ?? '-',
      workout?.totalVolume.toStringAsFixed(0) ?? '-',
      workout?.averageRpe.toStringAsFixed(1) ?? '-',
      (workout?.targetedMuscles.join('|')) ?? '-',
      recentWeights.length.toString(),
      recentWeights.isNotEmpty
          ? recentWeights.last.weight.toStringAsFixed(1)
          : '-',
      // 활동 데이터: 핵심 수치가 바뀌면 캐시 키도 바뀌어 새 인사이트 생성.
      activity?.steps.toString() ?? '-',
      activity?.activeCaloriesKcal.toStringAsFixed(0) ?? '-',
      activity?.basalCaloriesKcal.toStringAsFixed(0) ?? '-',
      activity?.averageHeartRateBpm?.toString() ?? '-',
      activity?.restingHeartRateBpm?.toString() ?? '-',
    ];
    final digest = sha256.convert(utf8.encode(parts.join(':')));
    return digest.toString().substring(0, 8);
  }
}

enum PromptCategory {
  diet,
  macro,
  workout,
  weight,
  routine,
  motivation,
  timebased,
}

/// 추천 칩 타입. navigation은 Gemini 호출 없이 다른 화면으로 이동.
enum SuggestedPromptKind { ai, navigation }

class SuggestedPrompt {
  final String id;
  final String label;
  final String fullPrompt;
  final PromptCategory category;
  final SuggestedPromptKind kind;

  const SuggestedPrompt({
    required this.id,
    required this.label,
    required this.fullPrompt,
    required this.category,
    this.kind = SuggestedPromptKind.ai,
  });
}
