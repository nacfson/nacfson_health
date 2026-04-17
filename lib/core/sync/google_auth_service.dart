import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;

/// Google 네이티브 SDK의 인증 헤더를 가로채서 API 요청에 동적으로 주입하는 클라이언트입니다.
/// 이를 통해 Token 1시간 만료 제한을 우회하고, SDK가 알아서 갱신한 토큰을 매번 사용하게 됩니다.
/// (Decorator 패턴 적용)
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

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

  GoogleSignInAccount? get currentAccount => _currentAccount;
  bool get isSignedIn => _currentAccount != null;

  /// 앱 초기 구동 시 보안 저장소(Keychain/Keystore)에서 세션을 안전하게 복구합니다.
  Future<GoogleSignInAccount?> restoreSession() async {
    debugPrint('[GoogleAuthService] ========== restoreSession() 시작 ==========');
    try {
      _currentAccount = await _signIn.signInSilently();
      debugPrint('[GoogleAuthService] signInSilently 결과: ${_currentAccount?.email}');
      return _currentAccount;
    } catch (e) {
      debugPrint('[GoogleAuthService] signInSilently 예외 발생: $e');
      return null;
    }
  }

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
      return null;
    }

    debugPrint('[GoogleAuthService] signIn() 성공: $_currentAccount');
    return _currentAccount;
  }

  Future<http.Client> get authClient async {
    if (_currentAccount == null) {
      throw Exception('Not authenticated');
    }
    
    debugPrint('[GoogleAuthService] 동적 authHeaders 확보 중...');
    final headers = await _currentAccount!.authHeaders;
    if (headers.isEmpty) {
       throw GoogleSignInException.noToken();
    }
    
    return _GoogleAuthClient(headers);
  }

  Future<String> createSpreadsheet(String title) async {
    final client = await authClient;
    final sheetsApi = sheets.SheetsApi(client);

    final spreadsheet = await sheetsApi.spreadsheets.create(
      sheets.Spreadsheet()
        ..properties = (sheets.SpreadsheetProperties()..title = title)
        ..sheets = [
          sheets.Sheet()
            ..properties =
                (sheets.SheetProperties()..title = 'exercise_records'),
          sheets.Sheet()
            ..properties = (sheets.SheetProperties()..title = 'diet_records'),
          sheets.Sheet()
            ..properties =
                (sheets.SheetProperties()..title = 'exercise_templates'),
          sheets.Sheet()
            ..properties =
                (sheets.SheetProperties()..title = 'food_templates'),
          sheets.Sheet()
            ..properties =
                (sheets.SheetProperties()..title = 'weight_records'),
        ],
    );

    return spreadsheet.spreadsheetId!;
  }

  Future<sheets.SheetsApi> createSheetsApi() async {
    final client = await authClient;
    return sheets.SheetsApi(client);
  }

  Future<void> signOut() async {
    await _signIn.signOut();
    _currentAccount = null;
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
