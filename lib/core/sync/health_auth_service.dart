import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_env.dart';
import 'health_api_client.dart';

/// Opaque session holder for ProcessManager Auth.
class AuthAccount {
  final String id;
  final String email;

  const AuthAccount({required this.id, required this.email});
}

enum AuthChangeEvent { signedIn, signedOut, tokenRefreshed, initialSession }

class AuthState {
  final AuthChangeEvent event;
  final AuthAccount? account;

  const AuthState(this.event, this.account);
}

/// Browser / deep-link login against auth.nacfson.cloud; stores opaque Bearer.
class HealthAuthService {
  static const _tokenKey = 'health_auth_session_token';
  static const _userIdKey = 'health_auth_user_id';
  static const _emailKey = 'health_auth_user_email';

  final FlutterSecureStorage _storage;
  final HealthApiClient _api;
  final AppLinks _appLinks;
  final StreamController<AuthState> _controller =
      StreamController<AuthState>.broadcast();

  AuthAccount? _account;
  String? _token;
  StreamSubscription<Uri>? _linkSub;
  bool _initialized = false;

  HealthAuthService({
    FlutterSecureStorage? storage,
    HealthApiClient? api,
    AppLinks? appLinks,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _api = api ?? HealthApiClient(),
        _appLinks = appLinks ?? AppLinks();

  AuthAccount? get currentAccount => _account;
  bool get isSignedIn => _account != null && (_token?.isNotEmpty ?? false);
  String? get accessToken => _token;

  Stream<AuthState> get onAuthStateChange => _controller.stream;

  Future<AuthAccount?> restoreSession() async {
    if (!_initialized) {
      await _bootstrap();
    }
    return _account;
  }

  Future<void> _bootstrap() async {
    _initialized = true;
    _token = await _storage.read(key: _tokenKey);
    final id = await _storage.read(key: _userIdKey);
    final email = await _storage.read(key: _emailKey);
    if (_token != null && _token!.isNotEmpty && id != null && email != null) {
      _account = AuthAccount(id: id, email: email);
      _api.setBearerToken(_token);
      _controller.add(AuthState(AuthChangeEvent.initialSession, _account));
      try {
        final me = await _api.getMe();
        _account = AuthAccount(id: me.userId, email: me.email);
        await _persistAccount(_account!);
      } catch (_) {}
    }
    _linkSub ??= _appLinks.uriLinkStream.listen(_handleIncomingUri);
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await _handleIncomingUri(initial);
      }
    } catch (_) {}
  }

  Future<void> signIn() async {
    await restoreSession();
    final redirect = Uri.parse(AppEnv.authRedirectUrl);
    final authUri = Uri.parse(AppEnv.centralAuthUrl).replace(
      path: '/login',
      queryParameters: {'rd': redirect.toString()},
    );
    final launched = await launchUrl(
      authUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw const HealthAuthException(
        '브라우저를 열 수 없습니다. 기본 브라우저 앱이 설치되어 있는지 확인해 주세요.',
      );
    }
  }

  Future<void> completeFromRedirect(Uri uri) => _handleIncomingUri(uri);

  Future<void> _handleIncomingUri(Uri uri) async {
    final token = _extractToken(uri);
    if (token == null || token.isEmpty) return;
    await _acceptToken(token);
  }

  String? _extractToken(Uri uri) {
    final qp = uri.queryParameters['token'];
    if (qp != null && qp.isNotEmpty) return qp;
    final frag = uri.fragment;
    if (frag.isEmpty) return null;
    final queryPart = frag.contains('?') ? frag.split('?').last : frag;
    return Uri.splitQueryString(queryPart)['token'];
  }

  Future<void> _acceptToken(String token) async {
    _api.setBearerToken(token);
    try {
      final me = await _api.getMe();
      _token = token;
      _account = AuthAccount(id: me.userId, email: me.email);
      await _storage.write(key: _tokenKey, value: token);
      await _persistAccount(_account!);
      _controller.add(AuthState(AuthChangeEvent.signedIn, _account));
    } catch (e) {
      _api.setBearerToken(null);
      debugPrint('[HealthAuthService] token accept failed: $e');
      throw const HealthAuthException('인증 토큰을 확인하지 못했습니다. 다시 시도해 주세요.');
    }
  }

  Future<void> _persistAccount(AuthAccount account) async {
    await _storage.write(key: _userIdKey, value: account.id);
    await _storage.write(key: _emailKey, value: account.email);
  }

  Future<void> signOut() async {
    final token = _token;
    try {
      if (token != null && token.isNotEmpty) {
        await _api.logout();
      }
    } catch (_) {}
    _token = null;
    _account = null;
    _api.setBearerToken(null);
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _emailKey);
    _controller.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  void dispose() {
    _linkSub?.cancel();
    _controller.close();
  }
}

class HealthAuthException implements Exception {
  final String message;
  const HealthAuthException(this.message);

  @override
  String toString() => message;
}

HealthAuthService? _sharedAuth;

HealthAuthService sharedHealthAuth() {
  return _sharedAuth ??= HealthAuthService();
}

@visibleForTesting
void debugResetSharedHealthAuth() {
  _sharedAuth = null;
}

/// Compatibility alias while settings UI still says "Google".
typedef GoogleAuthService = HealthAuthService;
typedef GoogleSignInException = HealthAuthException;
