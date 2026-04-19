import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GoogleAuthService {
  SupabaseClient get _client => Supabase.instance.client;

  User? get currentAccount => _client.auth.currentUser;
  bool get isSignedIn => _client.auth.currentUser != null;

  // Supabase는 initialize 시 자동으로 세션을 복구하므로 별도 처리 불필요
  Future<User?> restoreSession() async {
    return _client.auth.currentUser;
  }

  Future<void> signIn() async {
    try {
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'io.supabase.nacfson://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw GoogleSignInException(
          '브라우저를 열 수 없습니다. 기본 브라우저 앱이 설치되어 있는지 확인해 주세요.',
        );
      }
    } on AuthException catch (e) {
      debugPrint('[GoogleAuthService] Supabase AuthException: ${e.message}');
      throw GoogleSignInException('Supabase 인증 오류: ${e.message}');
    } catch (e) {
      debugPrint('[GoogleAuthService] signIn 예외: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}

class GoogleSignInException implements Exception {
  final String message;

  const GoogleSignInException(this.message);

  factory GoogleSignInException.networkError() => const GoogleSignInException(
        '네트워크 오류가 발생했습니다. 인터넷 연결을 확인해 주세요.',
      );

  factory GoogleSignInException.noToken() => const GoogleSignInException(
        '인증 토큰을 가져오지 못했습니다. 다시 시도해 주세요.',
      );

  @override
  String toString() => message;
}
