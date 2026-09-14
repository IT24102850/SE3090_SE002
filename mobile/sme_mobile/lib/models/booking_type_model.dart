import 'dart:convert';

class BookingType {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String colorHex;
  final String status;
  final int defaultDurationMinutes;
  final bool requiresApproval;
  final int? maxParticipants;
  final int bufferMinutesBefore;
  final int bufferMinutesAfter;

  /// "Slot" (fixed-duration time slot, the original/default shape) | "Night"
  /// (check-in/check-out) | "DateRange" (multi-day) | "Package" (multi-day
  /// itinerary). Defaults to "Slot" so existing/older API responses without
  /// this field keep working exactly as before.
  final String bookingUnit;
  final String? configJson;

  const BookingType({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    required this.colorHex,
    required this.status,
    required this.defaultDurationMinutes,
    required this.requiresApproval,
    this.maxParticipants,
    required this.bufferMinutesBefore,
    required this.bufferMinutesAfter,
    this.bookingUnit = 'Slot',
    this.configJson,
  });

  /// Lazily-parsed config bag (capacity, weatherDependent, minNights,
  /// checkInTime/checkOutTime, itinerary, ...) - null if not set or invalid.
  Map<String, dynamic>? get config {
    if (configJson == null || configJson!.isEmpty) return null;
    try {
      return jsonDecode(configJson!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// What kind of product this is - `tour`, `package` or `addon` - from
  /// ConfigJson's `category` key. Defaults to `tour` when the key is absent
  /// or unrecognised, so every product written before the convention existed
  /// still shows up as something bookable rather than vanishing into the
  /// add-ons list. Mirrors the web registry's getProductCategory().
  String get category {
    final raw = config?['category'];
    return (raw == 'tour' || raw == 'package' || raw == 'addon') ? raw as String : 'tour';
  }

  /// True for extras attached to a booking rather than booked on their own.
  bool get isAddon => category == 'addon';

  /// The operator's own emoji for this product, where their site uses one.
  String? get icon {
    final raw = config?['icon'];
    return (raw is String && raw.isNotEmpty) ? raw : null;
  }

  Map<String, dynamic>? get _pricing {
    final raw = config?['pricing'];
    return raw is Map<String, dynamic> ? raw : null;
  }

  String get currency => _pricing?['currency']?.toString() ?? 'LKR';

  /// Per-head prices. Null means "no such rate exists" - which is not the
  /// same as free, so the UI omits a null rate and prints 0 as "Free".
  num? get adultPrice => _pricing?['adult'] as num?;
  num? get childPrice => _pricing?['child'] as num?;

  /// Age bands the operator publishes with each rate, e.g. adult 12 and up.
  /// Null when they publish no age split, which plenty of products do not -
  /// the UI omits the band rather than inventing one.
  int? get adultFromAge {
    final raw = config?['agePolicy'];
    return raw is Map<String, dynamic> ? (raw['adultFromAge'] as num?)?.toInt() : null;
  }

  int? get childUnderAge {
    final raw = config?['agePolicy'];
    return raw is Map<String, dynamic> ? (raw['childUnderAge'] as num?)?.toInt() : null;
  }

  /// What this product includes, per ConfigJson `includes`.
  List<String> get includes {
    final raw = config?['includes'];
    return raw is List ? raw.whereType<String>().toList() : const [];
  }

  factory BookingType.fromJson(Map<String, dynamic> json) {
    return BookingType(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      description: json['description']?.toString(),
      colorHex: json['colorHex']?.toString() ?? '#3B82F6',
      status: json['status']?.toString() ?? 'Active',
      defaultDurationMinutes: (json['defaultDurationMinutes'] as num?)?.toInt() ?? 60,
      requiresApproval: json['requiresApproval'] as bool? ?? false,
      maxParticipants: json['maxParticipants'] == null ? null : (json['maxParticipants'] as num).toInt(),
      bufferMinutesBefore: (json['bufferMinutesBefore'] as num?)?.toInt() ?? 0,
      bufferMinutesAfter: (json['bufferMinutesAfter'] as num?)?.toInt() ?? 0,
      bookingUnit: json['bookingUnit']?.toString() ?? 'Slot',
      configJson: json['configJson']?.toString(),
    );
  }
}
