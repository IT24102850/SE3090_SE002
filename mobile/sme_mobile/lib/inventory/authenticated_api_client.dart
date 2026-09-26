import 'dart:convert';

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../services/api_service.dart';

/// Compatibility gateway for the inventory screens.
///
/// The inventory feature originally used a standalone `package:http` client.
/// It now delegates to the app's shared Dio instance, which owns JWT
/// attachment and expiry handling.
class AuthenticatedApiClient {
  AuthenticatedApiClient({Dio? dio}) : _dio = dio ?? ApiService.dio;

  final Dio _dio;

  Future<InventoryApiResponse> get(String path) async {
    return _send(() => _dio.get(_normalize(path)));
  }

  Future<InventoryApiResponse> post(String path, {Object? body}) async {
    return _send(() => _dio.post(_normalize(path), data: body));
  }

  Future<InventoryApiResponse> put(String path, {Object? body}) async {
    return _send(() => _dio.put(_normalize(path), data: body));
  }

  Future<String> uploadMaintenancePhoto(
      Uint8List bytes, String fileName) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      'purpose': 'maintenance',
    });
    final response = await _dio.post(
      _normalize('/api/media/upload'),
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    final data = response.data;
    if (data is Map &&
        data['url'] is String &&
        (data['url'] as String).isNotEmpty) {
      return data['url'] as String;
    }
    throw const FormatException('The image service returned no photo URL.');
  }

  Future<InventoryApiResponse> _send(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final response = await request();
      return InventoryApiResponse(
        response.statusCode ?? 0,
        _body(response.data),
      );
    } on DioException catch (error) {
      final response = error.response;
      if (response == null) rethrow;
      return InventoryApiResponse(
        response.statusCode ?? 0,
        _body(response.data),
      );
    }
  }

  String _normalize(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return normalized.startsWith('/api/')
        ? normalized.substring(4)
        : normalized == '/api'
            ? '/'
            : normalized;
  }

  String _body(Object? data) => data is String ? data : jsonEncode(data ?? {});
}

class InventoryApiResponse {
  const InventoryApiResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
