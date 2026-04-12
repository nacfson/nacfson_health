import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;

class GoogleAuthService {
  final GoogleSignIn _signIn = GoogleSignIn(
    // iOS OAuth 클라이언트 ID — URL Scheme(REVERSED_CLIENT_ID)과 쌍으로 동작합니다.
    clientId: '410327801063-iujf05260o95fjdhv3au63kvjnrt0nmj.apps.googleusercontent.com',
    scopes: [
      sheets.SheetsApi.spreadsheetsScope,
      'https://www.googleapis.com/auth/drive.file',
    ],
  );

  GoogleSignInAccount? _currentAccount;
  auth.AccessCredentials? _credentials;

  GoogleSignInAccount? get currentAccount => _currentAccount;
  bool get isSignedIn => _currentAccount != null && _credentials != null;

  Future<GoogleSignInAccount?> signIn() async {
    debugPrint('[GoogleAuthService] ========== signIn() 시작 ==========');
    try {
      debugPrint('[GoogleAuthService] GoogleSignIn.signIn() 호출 중...');
      _currentAccount = await _signIn.signIn();
      debugPrint('[GoogleAuthService] GoogleSignIn.signIn() 응답: $_currentAccount');
    } on Exception catch (e) {
      debugPrint('[GoogleAuthService] GoogleSignIn.signIn() 예외 발생: $e');
      throw GoogleSignInException.networkError();
    }

    if (_currentAccount == null) {
      debugPrint('[GoogleAuthService] 사용자가 로그인을 취소함');
      // 사용자가 직접 취소한 경우 — 오류 아님
      return null;
    }

    debugPrint('[GoogleAuthService] _createCredentials() 호출 중...');
    await _createCredentials();
    debugPrint('[GoogleAuthService] signIn() 성공: $_currentAccount');
    return _currentAccount;
  }

  Future<void> _createCredentials() async {
    debugPrint('[GoogleAuthService] _createCredentials() 시작');
    final authentication = await _currentAccount!.authentication;
    debugPrint('[GoogleAuthService] 인증 정보 획득: $authentication');
    final accessToken = authentication.accessToken;
    debugPrint('[GoogleAuthService] accessToken: ${accessToken != null ? '있음' : '없음'}');

    if (accessToken == null) {
      debugPrint('[GoogleAuthService] accessToken 없음 - 예외 발생');
      throw GoogleSignInException.noToken();
    }
    debugPrint('[GoogleAuthService] _createCredentials() 완료');

    _credentials = auth.AccessCredentials(
      auth.AccessToken(
        'Bearer',
        accessToken,
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      null, // refreshToken
      [sheets.SheetsApi.spreadsheetsScope, 'https://www.googleapis.com/auth/drive.file'],
    );
  }

  Future<auth.AuthClient> get authClient async {
    if (_credentials == null) {
      throw Exception('Not authenticated');
    }
    return auth.authenticatedClient(http.Client(), _credentials!);
  }

  Future<String> createSpreadsheet(String title) async {
    final client = await authClient;
    final driveApi = drive.DriveApi(client);

    final spreadsheet = await driveApi.files.create(
      drive.File()
        ..name = title
        ..mimeType = 'application/vnd.google-apps.spreadsheet',
    );

    return spreadsheet.id!;
  }

  Future<sheets.SheetsApi> createSheetsApi() async {
    final client = await authClient;
    return sheets.SheetsApi(client);
  }

  Future<void> signOut() async {
    await _signIn.signOut();
    _currentAccount = null;
    _credentials = null;
  }

  Future<void> shareSpreadsheet(String spreadsheetId) async {
    final client = await authClient;
    final driveApi = drive.DriveApi(client);

    await driveApi.permissions.create(
      drive.Permission()
        ..type = 'user'
        ..role = 'writer'
        ..emailAddress = _currentAccount?.email,
      spreadsheetId,
    );
  }
}

/// Google 로그인 관련 오류를 사람이 읽기 좋은 메시지로 표현합니다.
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
