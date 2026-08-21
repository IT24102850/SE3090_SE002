import 'dart:convert';

class Resource {
  final String id;
  final String tenantId;
  final String? branchId;
  final String name;
  final String? code;
  final String category;
  final String status;
  final String? description;
  final int? capacity;
  final double? hourlyRate;
  final String? specialty;
  final String? customAttributes;

  const Resource({
    required this.id,
    required this.tenantId,
    this.branchId,
    required this.name,
    this.code,
    required this.category,
    required this.status,
    this.description,
    this.capacity,
    this.hourlyRate,
    this.specialty,
    this.customAttributes,
  });

  /// Lazily-parsed custom attributes (rating, depth, bedCount, transmission,
  /// ...) - null if not set or invalid JSON. Used by tourism sub-type
  /// dashboard cards (see registry/tourism_dashboard_registry.dart).
  Map<String, dynamic>? get attributes {
    if (customAttributes == null || customAttributes!.isEmpty) return null;
    try {
      return jsonDecode(customAttributes!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      id: json['id'].toString(),
      tenantId: json['tenantId'].toString(),
      branchId: json['branchId']?.toString(),
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString(),
      category: json['category']?.toString() ?? 'Other',
      status: json['status']?.toString() ?? 'Available',
      description: json['description']?.toString(),
      capacity: json['capacity'] == null ? null : (json['capacity'] as num).toInt(),
      hourlyRate: json['hourlyRate'] == null ? null : (json['hourlyRate'] as num).toDouble(),
      specialty: json['specialty']?.toString(),
      customAttributes: json['customAttributes']?.toString(),
    );
  }
}
