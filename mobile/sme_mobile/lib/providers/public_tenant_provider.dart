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

/// Real, publicly bookable offerings for a business. This uses the anonymous
/// catalog endpoint rather than authenticated branch/resource administration
/// endpoints, so visitors can preview actual businesses before signing in.
final publicBusinessCatalogProvider =
    FutureProvider.family<PublicBusinessCatalog, String>((ref, tenantId) async {
  final dio = ref.watch(apiServiceProvider);
  final response = await dio.get('/public/booking/$tenantId/catalog');
  return PublicBusinessCatalog.fromJson(response.data as Map<String, dynamic>);
});

class PublicBusinessCatalog {
  const PublicBusinessCatalog({
    required this.resources,
    required this.departures,
    required this.bookingTypes,
  });

  final List<PublicCatalogResource> resources;
  final List<PublicCatalogDeparture> departures;
  final List<PublicCatalogBookingType> bookingTypes;

  factory PublicBusinessCatalog.fromJson(Map<String, dynamic> json) =>
      PublicBusinessCatalog(
        resources: (json['resources'] as List<dynamic>? ?? [])
            .map((item) => PublicCatalogResource.fromJson(
                item as Map<String, dynamic>))
            .toList(),
        departures: (json['departures'] as List<dynamic>? ?? [])
            .map((item) => PublicCatalogDeparture.fromJson(
                item as Map<String, dynamic>))
            .toList(),
        bookingTypes: (json['bookingTypes'] as List<dynamic>? ?? [])
            .map((item) => PublicCatalogBookingType.fromJson(
                item as Map<String, dynamic>))
            .toList(),
      );
}

class PublicCatalogResource {
  const PublicCatalogResource({
    required this.id,
    required this.name,
    required this.category,
    this.description,
  });

  final String id;
  final String name;
  final String category;
  final String? description;

  factory PublicCatalogResource.fromJson(Map<String, dynamic> json) =>
      PublicCatalogResource(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Service',
        category: json['category']?.toString() ?? '',
        description: json['description']?.toString(),
      );
}

class PublicCatalogDeparture {
  const PublicCatalogDeparture({
    required this.name,
    required this.startTime,
    this.bookingTypeName,
    this.seatsRemaining,
  });

  final String name;
  final DateTime? startTime;
  final String? bookingTypeName;
  final int? seatsRemaining;

  factory PublicCatalogDeparture.fromJson(Map<String, dynamic> json) =>
      PublicCatalogDeparture(
        name: json['vesselName']?.toString() ?? 'Experience',
        startTime: DateTime.tryParse(
            json['scheduledDeparture']?.toString() ?? ''),
        bookingTypeName: json['bookingTypeName']?.toString(),
        seatsRemaining: (json['seatsRemaining'] as num?)?.toInt(),
      );
}

class PublicCatalogBookingType {
  const PublicCatalogBookingType({required this.name, this.description});

  final String name;
  final String? description;

  factory PublicCatalogBookingType.fromJson(Map<String, dynamic> json) =>
      PublicCatalogBookingType(
        name: json['name']?.toString() ?? 'Service',
        description: json['description']?.toString(),
      );
}
