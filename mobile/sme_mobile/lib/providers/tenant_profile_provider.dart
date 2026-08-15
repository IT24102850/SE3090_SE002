import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tenant_profile_model.dart';
import 'api_service_provider.dart';

/// GET /tenants/{id}/profile - anonymous, matching how tenant browsing
/// already works (TenantPublicController has no auth requirement either).
final tenantProfileProvider = FutureProvider.family<TenantProfile, String>((ref, tenantId) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/tenants/$tenantId/profile');
  return TenantProfile.fromJson(response.data as Map<String, dynamic>);
});
