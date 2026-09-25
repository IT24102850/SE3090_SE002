import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/booking_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ui/ui.dart';

/// FR-B7: staff scans a patient's booking QR (shown on their booking
/// confirmation / "My Bookings") and checks them in on arrival.
class CheckInScannerScreen extends ConsumerStatefulWidget {
  const CheckInScannerScreen({super.key});

  @override
  ConsumerState<CheckInScannerScreen> createState() => _CheckInScannerScreenState();
}

class _CheckInScannerScreenState extends ConsumerState<CheckInScannerScreen> {
  final _controller = MobileScannerController();
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final bookingId = capture.barcodes.firstOrNull?.rawValue;
    if (bookingId == null || bookingId.isEmpty) return;

    setState(() => _processing = true);
    await _controller.stop();

    try {
      await checkInBooking(ref.read(apiServiceProvider), bookingId);
      ref.invalidate(myScheduleProvider);
      if (mounted) {
        AppSnackBar.success(context, 'Patient checked in.');
      }
    } on BookingRequestException catch (e) {
      if (mounted) {
        AppSnackBar.error(context, e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
        await _controller.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The camera preview *is* this screen's background — the app gradient
    // would be entirely hidden behind it — so the theme shows up in the glass
    // chrome and the cyan reticle instead.
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: 'Scan to check in'),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.cyan, width: 3),
                borderRadius: BorderRadius.circular(AppRadii.card),
                boxShadow: const [
                  BoxShadow(color: AppColors.buttonGlow, blurRadius: 24, spreadRadius: 2),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Column(
              children: [
                if (_processing)
                  const AppLoader()
                else
                  // A dark pill behind the caption: over a live camera feed
                  // plain white text is unreadable on a bright scene.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.overlaySurface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Text(
                      'Point the camera at the patient\'s booking QR code',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
