import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_session.dart';
import 'authenticated_api_client.dart';
import 'secure_token_store.dart';

class AuthRepository {
  AuthRepository({required String apiBaseUrl, SecureTokenStore? tokenStore})
      : _apiBaseUrl = apiBaseUrl.replaceFirst(RegExp(r'/$'), ''),
        _tokenStore = tokenStore ?? SecureTokenStore();

  final String _apiBaseUrl;
  final SecureTokenStore _tokenStore;

  Future<AuthSession?> restoreSession() async {
    final token = await _tokenStore.read();
    final session = token == null ? null : AuthSession.fromToken(token);
    if (session == null && token != null) await _tokenStore.clear();
    return session;
  }

  Future<AuthSession> login(String email, String password) async {
    final endpoint = Uri.parse('$_apiBaseUrl/api/auth/login');
    try {
      final response = await http
          .post(
            endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> body;
      try {
        final decoded =
            jsonDecode(response.body.isEmpty ? '{}' : response.body);
        body = decoded is Map<String, dynamic> ? decoded : const {};
      } on FormatException {
        throw AuthException(
            'The service returned an invalid response (${response.statusCode}).');
      }

      final token = body['accessToken'] ?? body['token'];
      final session = token is String ? AuthSession.fromToken(token) : null;
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          session == null) {
        final message = body['message'] ?? body['title'];
        throw AuthException(message is String
            ? message
            : 'Login failed. Check your credentials and try again.');
      }
      await _tokenStore.write(token);
      return session;
    } on AuthException {
      rethrow;
    } on http.ClientException catch (error) {
      throw AuthException(
          'Cannot reach $endpoint. Check that the API is running and accessible. '
          '${error.message}');
    } on TimeoutException {
      throw AuthException(
          'The API did not respond within 15 seconds: $endpoint');
    } catch (error) {
      throw AuthException('Cannot reach the API at $endpoint. '
          'For Android Emulator use 10.0.2.2; for a physical device use '
          'your computer LAN IP. $error');
    }
  }

  Future<void> logout() => _tokenStore.clear();

  /// Creates the shared authenticated client used by inventory feature screens.
  AuthenticatedApiClient authenticatedClient(AuthSession session) =>
      AuthenticatedApiClient(
          apiBaseUrl: _apiBaseUrl, accessToken: session.token);
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
}
