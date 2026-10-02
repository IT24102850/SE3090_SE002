import 'package:dio/dio.dart';

import '../models/managed_user_model.dart';

/// User administration (api/users) — the mobile twin of the web app's
/// Users & Access screen. Every route here is Admin-only on the server; the
/// screen is hidden from other roles so the refusal is never the first thing
/// a manager learns about it.
class AccessRepository {
  final Dio _dio;
  const AccessRepository(this._dio);

  static List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) from) {
    final raw = data is Map<String, dynamic> ? (data['items'] as List<dynamic>? ?? const []) : data;
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(from).toList(growable: false);
  }

  Future<List<ManagedUser>> users() async =>
      _list((await _dio.get('/users')).data, ManagedUser.fromJson);

  /// People who registered themselves and cannot sign in yet.
  Future<List<ManagedUser>> pending() async =>
      _list((await _dio.get('/users/pending')).data, ManagedUser.fromJson);

  Future<List<AccessBranch>> branches() async =>
      _list((await _dio.get('/users/branches')).data, AccessBranch.fromJson);

  Future<void> create({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String role,
    String? branchId,
  }) =>
      _dio.post('/users', data: {
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role,
        'branchId': (branchId == null || branchId.isEmpty) ? null : branchId,
      });

  /// Lets someone in, with the role and branch they will have.
  Future<void> approve(ManagedUser user, {required String role, required String branchId}) =>
      _dio.put('/users/${user.id}/approve', data: {'role': role, 'branchId': branchId});

  /// The server takes the whole user on a PUT, so unchanged fields are sent
  /// back as they were. `password: null` means "leave the password alone" —
  /// omitting it would be read as a change.
  Future<void> update(ManagedUser user, {String? role, String? branchId}) =>
      _dio.put('/users/${user.id}', data: {
        'fullName': user.fullName,
        'phone': user.phone,
        'role': role ?? user.role,
        'branchId': branchId ?? user.branchId,
        'password': null,
      });

  Future<void> remove(String id) => _dio.delete('/users/$id');
}

/// Turns a failed call into something an Admin can act on.
String accessErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    if (error.response?.statusCode == 403) {
      return 'Only an Admin can manage users.';
    }
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (data is Map && data['title'] is String) return data['title'] as String;
  }
  return fallback;
}
