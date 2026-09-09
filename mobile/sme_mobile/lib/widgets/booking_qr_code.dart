import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_colors.dart';

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
        // Stays white against the dark theme on purpose: scanners need the
        // quiet zone and the light/dark contrast the spec assumes. Inverting
        // it to match the palette would cost reliable scanning.
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.row),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: const [
          BoxShadow(color: AppColors.buttonGlow, blurRadius: 24, spreadRadius: -6),
        ],
      ),
      child: QrImageView(
        data: bookingId,
        size: size,
        backgroundColor: Colors.white,
      ),
    );
  }
}
