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
      const legacyRoleClaim =
          'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/role';
      final rawRolesCandidates = [
        payload['role'],
        payload['Role'],
        payload['roles'],
        payload['Roles'],
        payload[roleClaim],
        payload[legacyRoleClaim],
      ];

      final roleValues = <String>[];
      for (final rawRoles in rawRolesCandidates) {
        if (rawRoles == null) continue;

        if (rawRoles is List) {
          for (final value in rawRoles) {
            if (value is String) {
              roleValues.add(value);
            } else if (value is Map && value['value'] is String) {
              roleValues.add(value['value'] as String);
            }
          }
        } else if (rawRoles is String) {
          roleValues.add(rawRoles);
        } else if (rawRoles is Map) {
          for (final value in rawRoles.values) {
            if (value is String) {
              roleValues.add(value);
            } else if (value is List) {
              for (final item in value) {
                if (item is String) roleValues.add(item);
              }
            }
          }
        }
      }

      final resolvedRoles = <AppRole>[];
      for (final value in roleValues) {
        for (final part in value
           .split(RegExp(r'[|,]'))
           .map((role) => role.trim())
           .where((role) => role.isNotEmpty)) {
          final parsedRole = AppRoleLabel.fromClaim(part);
          if (parsedRole != null && !resolvedRoles.contains(parsedRole)) {
           resolvedRoles.add(parsedRole);
          }
        }
      }

      return AuthSession(
        token: token,
        roles: resolvedRoles,
        tenantId: payload['tenant_id'] as String?,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
