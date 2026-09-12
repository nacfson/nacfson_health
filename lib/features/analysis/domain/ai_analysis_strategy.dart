import '../../../core/ai/gemini_service.dart';

abstract class AiAnalysisStrategy {
  Future<String> analyze(String promptData);
  void dispose();
}

/// Legacy strategy — gated with the rest of Gemini during the owned-backend cutover.
class GeminiAnalysisStrategy implements AiAnalysisStrategy {
  GeminiAnalysisStrategy();

  @override
  Future<String> analyze(String promptData) async {
    return GeminiService.unavailableMessage;
  }

  @override
  void dispose() {}
}
