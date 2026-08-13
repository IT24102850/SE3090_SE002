import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/public_tenant_model.dart';
import 'api_service_provider.dart';

final publicTenantsProvider = FutureProvider<List<PublicTenant>>((ref) async {
  final dio = ref.watch(apiServiceProvider);

  final response = await dio.get('/tenant/public');
  final List<dynamic> data = response.data as List<dynamic>;
  return data
      .map((json) => PublicTenant.fromJson(json as Map<String, dynamic>))
      .toList();
});
