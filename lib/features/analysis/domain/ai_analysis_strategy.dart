import 'package:google_generative_ai/google_generative_ai.dart';

import '../../../core/config/app_env.dart';

abstract class AiAnalysisStrategy {
  Future<String> analyze(String promptData);
  void dispose();
}

class GeminiAnalysisStrategy implements AiAnalysisStrategy {
  final GenerativeModel _model;

  GeminiAnalysisStrategy()
      : _model = GenerativeModel(
          model: 'gemini-1.5-flash',
          apiKey: AppEnv.geminiApiKey,
        );

  @override
  Future<String> analyze(String promptData) async {
    try {
      final prompt = [
        Content.text('당신은 전문 퍼스널 트레이너이자 영양사입니다. 사용자의 데이터를 보고 오늘 하루에 대한 친근하고 짧은 한 줄 조언을 해주세요.\n\n$promptData')
      ];
      final response = await _model.generateContent(prompt);
      return response.text ?? '분석 결과를 불러오지 못했습니다.';
    } catch (e) {
      throw Exception('Gemini 분석 실패: $e');
    }
  }

  @override
  void dispose() {
    // Gemini SDK는 별도의 명시적인 HTTP Client close를 노출하지 않지만,
    // Strategy 인터페이스 유지를 위해 남겨둡니다.
  }
}
