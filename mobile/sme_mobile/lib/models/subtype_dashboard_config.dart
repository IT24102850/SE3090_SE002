import 'package:flutter/material.dart';
import 'tourism_subtype.dart';

/// One extra field the booking form must collect for a given sub-type,
/// e.g. certification level for diving, meal plan for accommodation.
class BookingFormField {
  final String key;            // matches a key inside BookingType.ConfigJson
  final String label;          // shown to the customer
  final BookingFieldType type;
  final List<String>? options; // for dropdown/choice fields

  const BookingFormField({
    required this.key,
    required this.label,
    required this.type,
    this.options,
  });
}

enum BookingFieldType { dropdown, numberStepper, checkbox, fileUpload, textArea }

/// One field shown on a resource card, e.g. "Capacity: 8" or "Bed count: 3".
class ResourceCardField {
  final String key;     // matches a field on the Resource / metadata response
  final IconData icon;
  final String labelTemplate; // e.g. "{value} divers max"

  const ResourceCardField({
    required this.key,
    required this.icon,
    required this.labelTemplate,
  });
}

/// The full "look and feel" definition for one tourism sub-type.
/// This is the ONLY thing that differs between a dive-center dashboard and
/// a homestay dashboard - the rendering widget itself is shared.
class SubtypeDashboardConfig {
  final TourismSubType subType;
  final BookingUnit bookingUnit;
  final String resourceTermSingular;  // "Dive Trip", "Room", "Safari Drive"
  final String resourceTermPlural;    // "Dive Trips", "Rooms", "Safari Drives"
  final String heroActionLabel;       // "Choose your dive trip"
  final IconData icon;
  final Color themeColor;
  final List<ResourceCardField> cardFields;
  final List<BookingFormField> bookingFormFields;
  final bool showWeatherBadge;        // dive/safari/whale-watching = true, homestay = false

  const SubtypeDashboardConfig({
    required this.subType,
    required this.bookingUnit,
    required this.resourceTermSingular,
    required this.resourceTermPlural,
    required this.heroActionLabel,
    required this.icon,
    required this.themeColor,
    required this.cardFields,
    required this.bookingFormFields,
    this.showWeatherBadge = false,
  });
}
