import 'package:flutter/material.dart';
import '../models/subtype_dashboard_config.dart';

/// Renders ONE input for a [BookingFormField], dispatching on
/// [BookingFieldType]. Shared by every tourism sub-type's extra-fields step
/// in the booking wizard - adding a 12th sub-type never needs a new widget
/// here, only a new registry entry.
class BookingFieldInput extends StatelessWidget {
  final BookingFormField field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  const BookingFieldInput({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    switch (field.type) {
      case BookingFieldType.dropdown:
        return DropdownButtonFormField<String>(
          value: value as String?,
          decoration: InputDecoration(labelText: field.label, border: const OutlineInputBorder()),
          items: (field.options ?? const []).map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: onChanged,
        );

      case BookingFieldType.numberStepper:
        final count = (value as int?) ?? 1;
        return Row(
          children: [
            Expanded(child: Text(field.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: count > 1 ? () => onChanged(count - 1) : null,
            ),
            Text('$count', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => onChanged(count + 1),
            ),
          ],
        );

      case BookingFieldType.checkbox:
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: (value as bool?) ?? false,
          onChanged: (v) => onChanged(v ?? false),
          title: Text(field.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        );

      case BookingFieldType.fileUpload:
        // No document-storage backend exists yet - this deliberately stops
        // short of a real upload pipeline (multipart + cloud storage) and
        // just records that the customer confirmed they have the document,
        // to be checked in person/on arrival.
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: (value as bool?) ?? false,
          onChanged: (v) => onChanged(v ?? false),
          title: Text(field.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: const Text('You\'ll be asked to show this on arrival', style: TextStyle(fontSize: 11.5)),
        );

      case BookingFieldType.textArea:
        return TextFormField(
          initialValue: value as String?,
          maxLines: 3,
          decoration: InputDecoration(labelText: field.label, border: const OutlineInputBorder()),
          onChanged: onChanged,
        );
    }
  }
}
