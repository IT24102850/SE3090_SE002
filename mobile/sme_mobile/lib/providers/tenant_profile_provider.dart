import 'dart:typed_data';
import 'package:dio/dio.dart';
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

// ─────────────────────────────────────────────────────────
// Business Profile editor mutations (Admin/Manager) - mirrors
// frontend/src/api/bookingApi.ts's profile/media endpoints, same plain-
// function pattern already used throughout booking_providers.dart.
// ─────────────────────────────────────────────────────────

class TenantProfileRequestException implements Exception {
  final String message;
  TenantProfileRequestException(this.message);
}

String? _extractProfileErrorMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map) return data['message']?.toString() ?? data['title']?.toString();
  return null;
}

class UploadedImage {
  final String url;
  final String publicId;
  const UploadedImage({required this.url, required this.publicId});
}

/// POST /media/upload - the only place that ever touches Cloudinary
/// (through the backend); [bytes] comes from an XFile.readAsBytes(), which
/// is cross-platform (works on web, unlike dart:io File).
Future<UploadedImage> uploadTenantMedia(
  Dio dio, {
  required Uint8List bytes,
  required String fileName,
  required String purpose,
}) async {
  try {
    final formData = FormData.fromMap({
      'purpose': purpose,
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final response = await dio.post('/media/upload', data: formData);
    final data = response.data as Map<String, dynamic>;
    return UploadedImage(url: data['url'].toString(), publicId: data['publicId'].toString());
  } on DioException catch (e) {
    throw TenantProfileRequestException(_extractProfileErrorMessage(e) ?? 'Could not upload image.');
  }
}

Future<void> setTenantLogo(Dio dio, String tenantId, String imageUrl) async {
  try {
    await dio.put('/tenants/$tenantId/logo', data: {'imageUrl': imageUrl});
  } on DioException catch (e) {
    throw TenantProfileRequestException(_extractProfileErrorMessage(e) ?? 'Could not set logo.');
  }
}

Future<void> setTenantCoverImage(Dio dio, String tenantId, String imageUrl) async {
  try {
    await dio.put('/tenants/$tenantId/cover-image', data: {'imageUrl': imageUrl});
  } on DioException catch (e) {
    throw TenantProfileRequestException(_extractProfileErrorMessage(e) ?? 'Could not set cover image.');
  }
}

Future<List<String>> addTenantGalleryImage(Dio dio, String tenantId, String imageUrl) async {
  try {
    final response = await dio.post('/tenants/$tenantId/gallery-images', data: {'imageUrl': imageUrl});
    final data = response.data as Map<String, dynamic>;
    return (data['galleryImageUrls'] as List<dynamic>).map((e) => e.toString()).toList();
  } on DioException catch (e) {
    throw TenantProfileRequestException(_extractProfileErrorMessage(e) ?? 'Could not add photo.');
  }
}

Future<List<String>> removeTenantGalleryImage(Dio dio, String tenantId, int index) async {
  try {
    final response = await dio.delete('/tenants/$tenantId/gallery-images/$index');
    final data = response.data as Map<String, dynamic>;
    return (data['galleryImageUrls'] as List<dynamic>).map((e) => e.toString()).toList();
  } on DioException catch (e) {
    throw TenantProfileRequestException(_extractProfileErrorMessage(e) ?? 'Could not remove photo.');
  }
}

/// Rejects (backend-side) any list that isn't exactly a reordering of the
/// existing gallery - no silently dropping/injecting images.
Future<List<String>> reorderTenantGalleryImages(Dio dio, String tenantId, List<String> orderedUrls) async {
  try {
    final response = await dio.put('/tenants/$tenantId/gallery-images/reorder', data: {'orderedUrls': orderedUrls});
    final data = response.data as Map<String, dynamic>;
    return (data['galleryImageUrls'] as List<dynamic>).map((e) => e.toString()).toList();
  } on DioException catch (e) {
    throw TenantProfileRequestException(_extractProfileErrorMessage(e) ?? 'Could not reorder photos.');
  }
}

Future<void> updateTenantProfileFields(
  Dio dio,
  String tenantId, {
  String? description,
  String? shortTagline,
  List<String>? amenities,
  String? contactPhone,
  String? contactEmail,
  String? website,
  Map<String, String>? socialLinks,
  List<BusinessHourEntry>? businessHours,
}) async {
  try {
    await dio.put('/tenants/$tenantId/profile', data: {
      if (description != null) 'description': description,
      if (shortTagline != null) 'shortTagline': shortTagline,
      if (amenities != null) 'amenities': amenities,
      if (contactPhone != null) 'contactPhone': contactPhone,
      if (contactEmail != null) 'contactEmail': contactEmail,
      if (website != null) 'website': website,
      if (socialLinks != null) 'socialLinks': socialLinks,
      if (businessHours != null)
        'businessHours': businessHours
            .map((h) => {
                  'dayOfWeek': h.dayOfWeek,
                  'openTime': h.openTime,
                  'closeTime': h.closeTime,
                  'isClosed': h.isClosed,
                })
            .toList(),
    });
  } on DioException catch (e) {
    throw TenantProfileRequestException(_extractProfileErrorMessage(e) ?? 'Could not save profile.');
  }
}
