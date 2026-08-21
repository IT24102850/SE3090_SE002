import 'dart:convert';

import 'app_role.dart';

class AuthSession {
  AuthSession({required this.token, required this.roles, this.tenantId});

  final String token;
  final List<AppRole> roles;
  final String? tenantId;

  bool hasAnyRole(Iterable<AppRole> allowedRoles) =>
      roles.any(allowedRoles.contains);

  static AuthSession? fromToken(String token) {
    try {
      final segments = token.split('.');
      if (segments.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      ) as Map<String, dynamic>;

      final expiry = payload['exp'];
      if (expiry is num &&
          DateTime.now().isAfter(
              DateTime.fromMillisecondsSinceEpoch(expiry.toInt() * 1000))) {
        return null;
      }

      const roleClaim =
          'http://schemas.microsoft.com/ws/2008/06/identity/claims/role';
      final rawRoles = payload['role'] ?? payload[roleClaim];
      final roleValues = rawRoles is List
          ? rawRoles.whereType<String>()
          : rawRoles is String
              ? [rawRoles]
              : <String>[];
      final roles =
          roleValues.map(AppRoleLabel.fromClaim).whereType<AppRole>().toList();
      return AuthSession(
          token: token,
          roles: roles,
          tenantId: payload['tenant_id'] as String?);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
