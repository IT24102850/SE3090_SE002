import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/booking_providers.dart';
import '../../theme/app_theme.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patient checked in.'), backgroundColor: AppColors.success),
        );
      }
    } on BookingRequestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan to check in'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 3),
                borderRadius: BorderRadius.circular(20),
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
                  const CircularProgressIndicator(color: Colors.white)
                else
                  const Text(
                    'Point the camera at the patient\'s booking QR code',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13),
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
