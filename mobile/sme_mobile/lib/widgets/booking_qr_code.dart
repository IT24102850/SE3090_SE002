import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_theme.dart';

/// FR-B7: encodes the raw booking ID — the staff check-in scanner
/// (screens/staff/check_in_scanner_screen.dart) reads this value verbatim
/// and calls PUT /bookings/{id}/checkin with it.
class BookingQrCode extends StatelessWidget {
  final String bookingId;
  final double size;

  const BookingQrCode({super.key, required this.bookingId, this.size = 180});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: QrImageView(
        data: bookingId,
        size: size,
        backgroundColor: Colors.white,
      ),
    );
  }
}
