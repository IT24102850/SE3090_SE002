import 'dart:convert';

import 'package:http/http.dart' as http;

/// Shared HTTP gateway for every authenticated inventory feature.
///
/// Construct it from the current [AuthSession] and use it for inventory,
/// supplier, purchase-order, and analytics requests. It ensures the JWT is
/// consistently sent without exposing credentials to widget code.
class AuthenticatedApiClient {
  AuthenticatedApiClient({
    required String apiBaseUrl,
    required String accessToken,
    http.Client? client,
  })  : _apiBaseUrl = apiBaseUrl.replaceFirst(RegExp(r'/$'), ''),
        _accessToken = accessToken,
        _client = client ?? http.Client();

  final String _apiBaseUrl;
  final String _accessToken;
  final http.Client _client;

  Future<http.Response> get(String path) =>
      _client.get(_uri(path), headers: _headers);

  Future<http.Response> post(String path, {Object? body}) => _client.post(
        _uri(path),
        headers: _headers,
        body: body == null ? null : jsonEncode(body),
      );

  void close() => _client.close();

  Uri _uri(String path) =>
      Uri.parse('$_apiBaseUrl/${path.replaceFirst(RegExp(r'^/'), '')}');

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_accessToken',
      };
}
