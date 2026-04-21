import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../../features/diet/domain/entities/food_analysis_result.dart';
import '../../features/summary/domain/entities/daily_summary.dart';
import '../../features/weight/domain/entities/weight_record.dart';
import 'coach_chat_models.dart';

/// Gemini AI 건강 인사이트 + 음식 사진 분석 + 코치 챗봇 서비스.
///
/// - 텍스트 인사이트: gemini-2.5-flash-lite (저비용, 자동 생성 카드)
/// - 음식 Vision 분석: gemini-2.5-flash (Vision 안정 지원 + JSON 모드)
/// - 코치 챗봇: gemini-2.5-flash (JSON 응답 — answer + follow_ups)
class GeminiService {
  late final GenerativeModel _model;
  late final GenerativeModel _visionModel;
  late final GenerativeModel _chatModel;

  GeminiService() {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    _model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: apiKey,
    );
    _visionModel = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.2,
        // 복합 플레이트(여러 items) 에서 1024 로는 잘림 — 실측 후 상향.
        maxOutputTokens: 4096,
      ),
    );
    _chatModel = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.4,
        maxOutputTokens: 1024,
      ),
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

  /// 음식 사진을 분석해 영양성분을 추정합니다.
  ///
  /// [jpegBytes]는 사전 리사이즈된 JPEG(권장 1024px, q=85).
  /// 내부적으로 `responseMimeType: application/json`을 강제해 파싱 실패율을
  /// 최소화합니다. 응답이 JSON이 아니거나 스키마가 어긋나면
  /// [FormatException]을 던집니다.
  Future<FoodAnalysisResult> analyzeFoodImage(Uint8List jpegBytes) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty || apiKey == 'your_gemini_api_key_here') {
      throw StateError('GEMINI_API_KEY_MISSING');
    }

    try {
      final response = await _visionModel.generateContent([
        Content.multi([
          TextPart(_buildFoodVisionPrompt()),
          DataPart('image/jpeg', jpegBytes),
        ]),
      ]);
      final text = response.text?.trim() ?? '';
      if (text.isEmpty) {
        throw const FormatException('빈 응답');
      }
      return _parseFoodAnalysisJson(text);
    } catch (e, st) {
      debugPrint('[GeminiService.vision] ${e.runtimeType}: $e');
      debugPrint('[GeminiService.vision] stack: $st');
      rethrow;
    }
  }

  String _buildFoodVisionPrompt() {
    return '''당신은 한국어 영양 분석 전문가입니다. 첨부된 음식 사진을 분석하여
아래 JSON 스키마에 맞는 응답만 출력하세요. 설명/마크다운/코드블록 없이 JSON만.

규칙:
1. 단일 음식이면 최상위 필드에, 여러 음식이면 모두 인식 후 합산값을 최상위에 넣고 items 배열에 개별 항목 포함.
2. estimatedGrams는 사진 속 1인분 실제 섭취량 추정치 (그릇 크기·국물량·고명 종합).
3. 영양성분은 100g 기준이 아닌 estimatedGrams 기준 총량.
4. 한국 음식명은 한국어로, 외국 음식은 한글 표기.
5. 음식이 아니거나 불확실하면 isFood=false, 나머지는 0/빈 문자열.
6. confidence는 0.0~1.0 사이 실수.

스키마:
{
  "isFood": boolean,
  "foodName": string,
  "estimatedGrams": integer,
  "calories": integer,
  "carbs": number,
  "protein": number,
  "fat": number,
  "confidence": number,
  "notes": string,
  "items": [
    {
      "foodName": string,
      "estimatedGrams": integer,
      "calories": integer,
      "carbs": number,
      "protein": number,
      "fat": number
    }
  ]
}

items가 비어 있어도 됩니다(단일 음식 또는 isFood=false인 경우).''';
  }

  /// 코치 챗봇 단일 턴.
  ///
  /// 매 호출마다 최신 건강 데이터([healthContext])를 시스템 프롬프트에 재주입한다.
  /// [history]는 세션 메모리 기반이며 마지막 6턴(3 user + 3 assistant)만 전달한다.
  /// 응답은 JSON {"answer": ..., "follow_ups": [...]} 스키마.
  /// 파싱 실패 시 raw 텍스트를 answer로 반환하고 follow_ups는 빈 배열.
  Future<CoachReply> coachChat({
    required String userMessage,
    required List<ChatMessage> history,
    required HealthContext healthContext,
  }) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty || apiKey == 'your_gemini_api_key_here') {
      throw StateError('GEMINI_API_KEY_MISSING');
    }

    // 최근 6턴만 컨텍스트로 전달 (토큰 절약)
    final trimmed = history.length > 6
        ? history.sublist(history.length - 6)
        : history;

    final contents = <Content>[
      Content.text(_buildCoachSystemInstruction(healthContext)),
      for (final m in trimmed)
        m.role == ChatRole.user
            ? Content.text('[사용자] ${m.content}')
            : Content.model([TextPart(m.content)]),
      Content.text('[사용자] $userMessage'),
    ];

    try {
      final response = await _chatModel.generateContent(contents);
      final text = response.text?.trim() ?? '';
      if (text.isEmpty) {
        return const CoachReply(
            answer: '응답이 비어 있어요. 잠시 후 다시 시도해주세요.', followUps: []);
      }
      return _parseCoachReply(text);
    } catch (e, st) {
      debugPrint('[GeminiService.coach] ${e.runtimeType}: $e');
      debugPrint('[GeminiService.coach] stack: $st');
      rethrow;
    }
  }

  String _buildCoachSystemInstruction(HealthContext ctx) {
    return '''당신은 한국어 건강 코치입니다. 따뜻하고 구체적인 조언을 제공하세요.
${ctx.toPromptContext()}

규칙:
1. 답변은 한국어, 200자 이내, 친근한 코치 말투.
2. 사용자 데이터에 근거해 구체적인 수치/예시 포함.
3. follow_ups는 사용자가 다음에 궁금해할 만한 짧은 질문 3개 (각 25자 이내).
4. 응답은 반드시 아래 JSON 스키마만 출력 (마크다운/코드블록 없이):
{"answer": "...", "follow_ups": ["...", "...", "..."]}
''';
  }

  CoachReply _parseCoachReply(String text) {
    try {
      final decoded = json.decode(text);
      if (decoded is Map<String, dynamic>) {
        final answer = (decoded['answer'] as String?)?.trim() ?? '';
        final rawFollowUps = decoded['follow_ups'];
        final followUps = rawFollowUps is List
            ? rawFollowUps
                .whereType<String>()
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .take(3)
                .toList()
            : <String>[];
        if (answer.isNotEmpty) {
          return CoachReply(answer: answer, followUps: followUps);
        }
      }
      return CoachReply(answer: text, followUps: const []);
    } catch (_) {
      // JSON 파싱 실패 시 raw 텍스트를 answer로 fallback
      return CoachReply(answer: text, followUps: const []);
    }
  }

  FoodAnalysisResult _parseFoodAnalysisJson(String text) {
    try {
      final decoded = json.decode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON 루트가 객체가 아님');
      }
      return FoodAnalysisResult.fromJson(decoded);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('음식 분석 JSON 파싱 실패: $e');
    }
  }
}
