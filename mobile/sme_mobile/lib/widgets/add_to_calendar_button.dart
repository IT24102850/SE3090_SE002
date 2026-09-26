import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';

/// "Add to calendar" — pulls the booking's .ics from the API and hands it to
/// the system share sheet, from where the guest can open it in Google
/// Calendar, Apple Calendar or anything else installed.
///
/// A file rather than a Google Calendar integration: no API key, no OAuth
/// consent screen and no rate limit, and it works with whichever calendar the
/// guest actually uses. The event carries a two-hour alarm their own device
/// raises, so the reminder still arrives when our push and SMS do not.
///
/// Shared straight from memory with XFile.fromData - the same pattern the
/// receipt screen already uses - so there is no temp file to write or clean up
/// and no extra package to justify.
class AddToCalendarButton extends StatefulWidget {
  final String bookingId;
  final String label;

  const AddToCalendarButton({super.key, required this.bookingId, this.label = 'Add to calendar'});

  @override
  State<AddToCalendarButton> createState() => _AddToCalendarButtonState();
}

class _AddToCalendarButtonState extends State<AddToCalendarButton> {
  bool _busy = false;

  Future<void> _addToCalendar() async {
    setState(() => _busy = true);
    try {
      final response = await ApiService.dio.get<List<int>>(
        '/bookings/${widget.bookingId}/calendar.ics',
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = Uint8List.fromList(response.data ?? const []);
      if (bytes.isEmpty) throw StateError('empty calendar file');

      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: 'booking-${widget.bookingId}.ics',
            // text/calendar is what makes Android and iOS offer the calendar
            // apps rather than a text editor.
            mimeType: 'text/calendar',
          ),
        ],
        subject: 'Add booking to calendar',
      ));
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not build the calendar file.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _busy ? null : _addToCalendar,
      icon: _busy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.event_available_outlined, size: 18),
      label: Text(widget.label, style: AppTextStyles.caption.copyWith(color: AppColors.cyan)),
      style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
    );
  }
}
