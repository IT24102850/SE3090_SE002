import 'package:flutter/material.dart';
import '../models/subtype_dashboard_config.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'ui/ui.dart';

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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(field.label),
            DropdownButtonFormField<String>(
              value: value as String?,
              // The menu is a popup, not part of the field, so it needs its
              // own dark fill — otherwise it opens as a white Material sheet.
              dropdownColor: AppColors.overlaySurface,
              borderRadius: BorderRadius.circular(AppRadii.control),
              style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
              icon: const Icon(Icons.expand_more_rounded, color: AppColors.iconSecondary),
              items: (field.options ?? const [])
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: onChanged,
            ),
          ],
        );

      case BookingFieldType.numberStepper:
        final count = (value as int?) ?? 1;
        return Row(
          children: [
            Expanded(child: Text(field.label, style: AppTextStyles.subtitle.copyWith(fontSize: 14))),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              color: AppColors.cyan,
              disabledColor: AppColors.iconDisabled,
              onPressed: count > 1 ? () => onChanged(count - 1) : null,
            ),
            Text('$count', style: AppTextStyles.title),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              color: AppColors.cyan,
              onPressed: () => onChanged(count + 1),
            ),
          ],
        );

      case BookingFieldType.checkbox:
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: (value as bool?) ?? false,
          onChanged: (v) => onChanged(v ?? false),
          activeColor: AppColors.cyan,
          checkColor: AppColors.onPrimary,
          title: Text(field.label, style: AppTextStyles.subtitle.copyWith(fontSize: 14)),
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
          activeColor: AppColors.cyan,
          checkColor: AppColors.onPrimary,
          title: Text(field.label, style: AppTextStyles.subtitle.copyWith(fontSize: 14)),
          subtitle: Text(
            'You\'ll be asked to show this on arrival',
            style: AppTextStyles.caption.copyWith(fontSize: 11.5),
          ),
        );

      case BookingFieldType.textArea:
        return NeonInputField(
          label: field.label,
          initialValue: value as String?,
          maxLines: 3,
          onChanged: onChanged,
        );
    }
  }
}
