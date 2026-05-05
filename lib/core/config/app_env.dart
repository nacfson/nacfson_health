/// 빌드 시점에 주입되는 환경 변수 단일 진입점.
///
/// `--dart-define-from-file=.env` 또는 `--dart-define=KEY=VALUE` 로 전달된 값을
/// 컴파일 타임에 상수로 박는다. asset(`.env`) 로 번들에 포함하던 이전 방식은
/// IPA/APK 디컴파일 시 평문 노출 위험이 있어 폐기됨.
class AppEnv {
  const AppEnv._();

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY');
}
