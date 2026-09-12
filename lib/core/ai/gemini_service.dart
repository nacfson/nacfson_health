import 'dart:typed_data';

import '../../features/activity/domain/entities/daily_activity.dart';
import '../../features/diet/domain/entities/food_analysis_result.dart';
import '../../features/summary/domain/entities/daily_summary.dart';
import '../../features/weight/domain/entities/weight_record.dart';
import '../training/challenge_readiness.dart';
import 'coach_chat_models.dart';

/// Gated AI surface — UI remains, but no Gemini keys or network calls.
class GeminiService {
  static const unavailableMessage =
      'AI 기능은 현재 사용할 수 없습니다. 곧 다시 제공될 예정입니다.';

  GeminiService();

  Future<String> getHealthInsight({
    required double? weightKg,
    required double heightM,
    required DailySummary? summary,
    required List<WeightRecord> recentWeights,
    DailyActivity? activity,
  }) async {
    return unavailableMessage;
  }

  Future<FoodAnalysisResult> analyzeFoodImage(Uint8List jpegBytes) async {
    throw StateError('AI_UNAVAILABLE');
  }

  Future<CoachReply> coachChat({
    required String userMessage,
    required List<ChatMessage> history,
    required HealthContext healthContext,
  }) async {
    return const CoachReply(answer: unavailableMessage, followUps: []);
  }

  Future<String> getOneRMCoachNote({
    required String exerciseName,
    required double currentE1RM,
    required double? deltaKg,
    required ReadinessLevel readiness,
  }) async {
    return unavailableMessage;
  }
}
