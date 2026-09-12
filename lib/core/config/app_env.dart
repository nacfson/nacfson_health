/// 빌드 시점에 주입되는 환경 변수 단일 진입점.
///
/// `--dart-define-from-file=.env` 또는 `--dart-define=KEY=VALUE` 로 전달된 값을
/// 컴파일 타임에 상수로 박는다.
class AppEnv {
  const AppEnv._();

  /// health-web Go API origin (no trailing slash), e.g. https://health.nacfson.cloud
  static const String healthApiBaseUrl = String.fromEnvironment(
    'HEALTH_API_BASE_URL',
    defaultValue: 'https://health.nacfson.cloud',
  );

  /// ProcessManager / central Auth origin for browser login.
  static const String centralAuthUrl = String.fromEnvironment(
    'CENTRAL_AUTH_URL',
    defaultValue: 'https://auth.nacfson.cloud',
  );

  /// Native OAuth / magic-link return URL (must be allow-listed on Auth).
  static const String authRedirectUrl = String.fromEnvironment(
    'AUTH_REDIRECT_URL',
    defaultValue: 'nacfsonhealth://login-callback',
  );
}
