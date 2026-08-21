import 'package:flutter/foundation.dart';

@immutable
class PublicTenant {
  final String id;
  final String businessName;
  final String businessType;
  final String? subType;
  final String? logoUrl;

  const PublicTenant({
    required this.id,
    required this.businessName,
    required this.businessType,
    this.subType,
    this.logoUrl,
  });

  // GET /api/tenant/public returns { id, name, businessType, subType, logoUrl }
  // — note the field is `name`, not `businessName`.
  factory PublicTenant.fromJson(Map<String, dynamic> json) {
    return PublicTenant(
      id: json['id'] as String,
      businessName: json['name'] as String,
      businessType: json['businessType'] as String,
      subType: json['subType'] as String?,
      logoUrl: json['logoUrl'] as String?,
    );
  }
}
