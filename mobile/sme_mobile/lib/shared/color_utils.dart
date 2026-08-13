import 'package:flutter/material.dart';

/// Parses a `#RRGGBB` (or `#AARRGGBB`) hex string as returned by
/// BookingType.colorHex from the API.
Color? parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var value = hex.replaceFirst('#', '');
  if (value.length == 6) value = 'FF$value';
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}
