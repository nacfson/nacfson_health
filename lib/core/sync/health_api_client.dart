import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_env.dart';

class HealthMe {
  final String userId;
  final String email;
  const HealthMe({required this.userId, required this.email});
}

/// Thin HTTPS client for health-web Go API (Bearer auth).
class HealthApiClient {
  HealthApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        _baseUrl = (baseUrl ?? AppEnv.healthApiBaseUrl).replaceAll(RegExp(r'/$'), '');

  final http.Client _http;
  final String _baseUrl;
  String? _bearer;

  void setBearerToken(String? token) {
    _bearer = (token == null || token.isEmpty) ? null : token;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalized').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool jsonBody = false}) {
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (jsonBody) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }
    if (_bearer != null) {
      headers['Authorization'] = 'Bearer $_bearer';
    }
    return headers;
  }

  Future<HealthMe> getMe() async {
    final resp = await _http.get(_uri('/api/me'), headers: _headers());
    _ensureOk(resp);
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return HealthMe(
      userId: map['user_id'] as String,
      email: map['email'] as String,
    );
  }

  Future<void> logout() async {
    final resp = await _http.post(_uri('/api/logout'), headers: _headers());
    if (resp.statusCode == 401) return;
    _ensureOk(resp, allowNoContent: true);
  }

  Future<void> pushSync(String resource, List<Map<String, dynamic>> items) async {
    final resp = await _http.post(
      _uri('/api/v1/sync/$resource'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'items': items}),
    );
    _ensureOk(resp);
  }

  Future<List<Map<String, dynamic>>> pullSync(
    String resource, {
    DateTime? since,
  }) async {
    final query = <String, String>{};
    if (since != null) {
      query['since'] = since.toUtc().toIso8601String();
    }
    final resp = await _http.get(
      _uri('/api/v1/sync/$resource', query.isEmpty ? null : query),
      headers: _headers(),
    );
    _ensureOk(resp);
    final list = jsonDecode(resp.body) as List<dynamic>;
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<Map<String, dynamic>> fetchMasterBundle() async {
    final resp = await _http.get(
      _uri('/api/v1/master/bundle'),
      headers: _headers(),
    );
    _ensureOk(resp);
    return (jsonDecode(resp.body) as Map).cast<String, dynamic>();
  }

  void _ensureOk(http.Response resp, {bool allowNoContent = false}) {
    if (allowNoContent && resp.statusCode == 204) return;
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw HealthApiException(resp.statusCode, resp.body);
  }
}

class HealthApiException implements Exception {
  final int statusCode;
  final String body;
  const HealthApiException(this.statusCode, this.body);

  @override
  String toString() => 'HealthApiException($statusCode): $body';
}
