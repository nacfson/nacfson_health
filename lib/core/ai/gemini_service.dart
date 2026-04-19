import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../../features/summary/domain/entities/daily_summary.dart';
import '../../features/weight/domain/entities/weight_record.dart';

/// Gemini AI 건강 인사이트 서비스
///
/// 체중·식단·운동 데이터를 종합해 한국어 건강 조언을 생성합니다.
class GeminiService {
  late final GenerativeModel _model;

  GeminiService() {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    _model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: apiKey,
    );
  }

  /// 종합 건강 인사이트 생성
  Future<String> getHealthInsight({
    required double? weightKg,
    required double heightM,
    required DailySummary? summary,
    required List<WeightRecord> recentWeights,
  }) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty || apiKey == 'your_gemini_api_key_here') {
      return 'Gemini API 키를 설정 화면(.env)에 입력해주세요.';
    }

    final prompt = _buildPrompt(
      weightKg: weightKg,
      heightM: heightM,
      summary: summary,
      recentWeights: recentWeights,
    );

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text?.trim() ?? '인사이트를 가져올 수 없습니다.';
    } catch (e, st) {
      debugPrint('[GeminiService] ${e.runtimeType}: $e');
      debugPrint('[GeminiService] stack: $st');
      rethrow;
    }
  }

  String _buildPrompt({
    required double? weightKg,
    required double heightM,
    required DailySummary? summary,
    required List<WeightRecord> recentWeights,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('당신은 전문 건강 코치입니다. 아래 건강 데이터를 분석하여 간결하고 실용적인 한국어 조언을 제공해주세요.');
    buffer.writeln('응답은 150자 이내로, 긍정적이고 구체적으로 작성해주세요.\n');

    // 체중 & BMI
    if (weightKg != null) {
      final bmi = weightKg / (heightM * heightM);
      buffer.writeln('【체중 정보】');
      buffer.writeln('• 현재 체중: ${weightKg.toStringAsFixed(1)}kg');
      buffer.writeln('• 신장: ${(heightM * 100).toStringAsFixed(0)}cm');
      buffer.writeln('• BMI: ${bmi.toStringAsFixed(1)} (${_bmiCategory(bmi)})');
    }

    // 최근 체중 변화 (최대 7일)
    if (recentWeights.length >= 2) {
      final oldest = recentWeights.first.weight;
      final newest = recentWeights.last.weight;
      final diff = newest - oldest;
      final sign = diff >= 0 ? '+' : '';
      buffer.writeln('• 최근 ${recentWeights.length}일 체중 변화: $sign${diff.toStringAsFixed(1)}kg');
    }

    // 식단 정보
    final diet = summary?.dietNutrition;
    if (diet != null) {
      buffer.writeln('\n【오늘 식단】');
      buffer.writeln('• 칼로리: ${diet.consumedCalories}/${diet.targetCalories}kcal');
      final carbs = diet.macroStatus['carbs'];
      final protein = diet.macroStatus['protein'];
      final fat = diet.macroStatus['fat'];
      if (carbs != null) buffer.writeln('• 탄수화물: ${carbs.consumed.toStringAsFixed(0)}/${carbs.target.toStringAsFixed(0)}g');
      if (protein != null) buffer.writeln('• 단백질: ${protein.consumed.toStringAsFixed(0)}/${protein.target.toStringAsFixed(0)}g');
      if (fat != null) buffer.writeln('• 지방: ${fat.consumed.toStringAsFixed(0)}/${fat.target.toStringAsFixed(0)}g');
    }

    // 운동 정보
    final workout = summary?.workoutPerformance;
    if (workout != null && workout.isWorkoutDay) {
      buffer.writeln('\n【오늘 운동】');
      buffer.writeln('• 운동 부위: ${workout.targetedMuscles.join(', ')}');
      buffer.writeln('• 총 볼륨: ${workout.totalVolume.toStringAsFixed(0)}kg');
      if (workout.averageRpe > 0) {
        buffer.writeln('• 평균 RPE: ${workout.averageRpe.toStringAsFixed(1)}');
      }
    } else {
      buffer.writeln('\n• 오늘 운동 없음');
    }

    buffer.writeln('\n위 데이터를 바탕으로 오늘의 건강 상태와 개선 포인트를 150자 이내로 알려주세요.');

    return buffer.toString();
  }

  String _bmiCategory(double bmi) {
    if (bmi < 18.5) return '저체중';
    if (bmi < 23.0) return '정상';
    if (bmi < 25.0) return '과체중';
    return '비만';
  }
}
