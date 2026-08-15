/// Shared, business-type-agnostic Business Profile shell - identical shape
/// for a clinic, a restaurant, or a dive center. Nothing here is Tourism/
/// sub-type-specific; that content lives entirely in BookingType.
class BusinessHourEntry {
  final String dayOfWeek; // "Monday".."Sunday"
  final String? openTime; // "HH:mm"
  final String? closeTime;
  final bool isClosed;

  const BusinessHourEntry({
    required this.dayOfWeek,
    this.openTime,
    this.closeTime,
    required this.isClosed,
  });

  factory BusinessHourEntry.fromJson(Map<String, dynamic> json) => BusinessHourEntry(
        dayOfWeek: json['dayOfWeek']?.toString() ?? '',
        openTime: json['openTime']?.toString(),
        closeTime: json['closeTime']?.toString(),
        isClosed: json['isClosed'] == true,
      );
}

class TenantProfile {
  final String tenantId;
  final String name;
  final String businessType;
  final String? logoUrl;
  final String? coverImageUrl;
  final List<String> galleryImageUrls;
  final String? description;
  final String? shortTagline;
  final List<String> amenities;
  final String? contactPhone;
  final String? contactEmail;
  final String? website;
  final Map<String, String> socialLinks;
  final List<BusinessHourEntry> businessHours;
  final double? averageRating;
  final int reviewCount;
  final String? address;

  const TenantProfile({
    required this.tenantId,
    required this.name,
    required this.businessType,
    this.logoUrl,
    this.coverImageUrl,
    required this.galleryImageUrls,
    this.description,
    this.shortTagline,
    required this.amenities,
    this.contactPhone,
    this.contactEmail,
    this.website,
    required this.socialLinks,
    required this.businessHours,
    this.averageRating,
    required this.reviewCount,
    this.address,
  });

  factory TenantProfile.fromJson(Map<String, dynamic> json) => TenantProfile(
        tenantId: json['tenantId'].toString(),
        name: json['name']?.toString() ?? '',
        businessType: json['businessType']?.toString() ?? '',
        logoUrl: json['logoUrl']?.toString(),
        coverImageUrl: json['coverImageUrl']?.toString(),
        galleryImageUrls: (json['galleryImageUrls'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        description: json['description']?.toString(),
        shortTagline: json['shortTagline']?.toString(),
        amenities: (json['amenities'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        contactPhone: json['contactPhone']?.toString(),
        contactEmail: json['contactEmail']?.toString(),
        website: json['website']?.toString(),
        socialLinks: (json['socialLinks'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, v.toString())),
        businessHours: (json['businessHours'] as List<dynamic>? ?? [])
            .map((e) => BusinessHourEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        averageRating: (json['averageRating'] as num?)?.toDouble(),
        reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
        address: json['address']?.toString(),
      );

  /// Compares [now]'s weekday/time-of-day against today's businessHours row.
  /// Returns false (not "open") if there's no row for today, the day is
  /// marked closed, or either time is missing/malformed.
  bool isOpenNow(DateTime now) {
    final todayName = _dayName(now.weekday);
    BusinessHourEntry? today;
    for (final h in businessHours) {
      if (h.dayOfWeek == todayName) {
        today = h;
        break;
      }
    }
    if (today == null || today.isClosed || today.openTime == null || today.closeTime == null) return false;

    final nowMinutes = now.hour * 60 + now.minute;
    final open = _parseMinutes(today.openTime!);
    final close = _parseMinutes(today.closeTime!);
    if (open == null || close == null) return false;
    return nowMinutes >= open && nowMinutes < close;
  }

  /// Today's BusinessHourEntry, or null if none is configured for today.
  BusinessHourEntry? todaysHours(DateTime now) {
    final todayName = _dayName(now.weekday);
    for (final h in businessHours) {
      if (h.dayOfWeek == todayName) return h;
    }
    return null;
  }

  static int? _parseMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static String _dayName(int weekday) {
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return names[(weekday - 1).clamp(0, 6)];
  }
}
