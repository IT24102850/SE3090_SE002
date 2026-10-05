import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/booking_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ui/ui.dart';
import '../owner/owner_widgets.dart';

/// FR-B7: staff scans a patient's booking QR (shown on their booking
/// confirmation / "My Bookings") and checks them in on arrival.
class CheckInScannerScreen extends ConsumerStatefulWidget {
  const CheckInScannerScreen({super.key});

  @override
  ConsumerState<CheckInScannerScreen> createState() =>
      _CheckInScannerScreenState();
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
      final api = ref.read(apiServiceProvider);
      await checkInBooking(api, bookingId);
      Map<String, dynamic>? booking;
      String? businessType;
      try {
        final bookingResponse = await api.get('/bookings/$bookingId');
        booking = Map<String, dynamic>.from(
            bookingResponse.data as Map<String, dynamic>);
        businessType = _stringValue(
          booking,
          'tenantBusinessType',
          'businessType',
        );
        final tenantId = booking['tenantId']?.toString();
        if ((businessType == null || businessType.isEmpty) &&
            tenantId != null &&
            tenantId.isNotEmpty) {
          final profileResponse = await api.get('/tenants/$tenantId/profile');
          businessType =
              (profileResponse.data as Map<String, dynamic>)['businessType']
                  ?.toString();
        }
      } on DioException {
        // Check-in already succeeded; details are supplementary.
      }
      ref.invalidate(myScheduleProvider);
      if (mounted) {
        setState(() {
          _processing = false;
        });
        AppSnackBar.success(context, 'Patient checked in.');
        if (booking != null) {
          await _showCheckInDetails(booking, businessType);
        }
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

  Future<void> _showCheckInDetails(
      Map<String, dynamic> booking, String? businessType) async {
    final normalizedBusinessType = (businessType ?? '').trim();
    final labels = _labelsForBusiness(normalizedBusinessType);
    final customer = _stringValue(booking, 'customerName') ??
        _stringValue(booking, 'title') ??
        'Guest';
    final bookingType =
        _stringValue(booking, 'bookingTypeName') ?? labels.service;
    final resource = _stringValue(booking, 'resourceName');
    final start = _stringValue(booking, 'startTime');
    final status = (booking['status'] ?? 'CheckedIn').toString();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${labels.person} checked in'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow(labels.person, customer),
            _detailRow('Business type',
                normalizedBusinessType.isEmpty ? 'Business' : normalizedBusinessType),
            _detailRow('Service', bookingType),
            if (resource != null && resource.isNotEmpty)
              _detailRow(labels.location, resource),
            if (start != null && start.isNotEmpty)
              _detailRow(labels.time, start),
            _detailRow('Status', status),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String? _stringValue(Map<String, dynamic> values, String primary,
      [String? fallback]) {
    final value = values[primary]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'null') return value;
    if (fallback == null) return null;
    final fallbackValue = values[fallback]?.toString().trim();
    return fallbackValue != null &&
            fallbackValue.isNotEmpty &&
            fallbackValue != 'null'
        ? fallbackValue
        : null;
  }

  _CheckInLabels _labelsForBusiness(String businessType) {
    switch (businessType.toLowerCase()) {
      case 'clinic':
        return const _CheckInLabels('Patient', 'Appointment', 'Room', 'Time');
      case 'gym':
        return const _CheckInLabels('Member', 'Session', 'Trainer', 'Time');
      case 'school':
        return const _CheckInLabels('Student', 'Class', 'Teacher', 'Time');
      case 'restaurant':
        return const _CheckInLabels('Guest', 'Reservation', 'Table', 'Time');
      case 'tourism':
        return const _CheckInLabels('Guest', 'Activity', 'Departure', 'Time');
      default:
        return const _CheckInLabels('Customer', 'Service', 'Resource', 'Time');
    }
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RichText(
          text: TextSpan(
            style: AppTextStyles.body,
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // The camera preview *is* this screen's background — the app gradient
    // would be entirely hidden behind it — so the theme shows up in the glass
    // chrome and the cyan reticle instead.
    return OwnerScaffold(
      title: 'Scan to check in',
      preferBackButton: true,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Positioned(
            top: 8,
            left: 8,
            child: Builder(
              builder: (buttonContext) => SafeArea(
                child: Material(
                  color: AppColors.overlaySurface.withValues(alpha: 0.9),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.iconPrimary,
                    onPressed: () {
                      if (Navigator.of(buttonContext).canPop()) {
                        Navigator.of(buttonContext).pop();
                      } else {
                        Scaffold.of(buttonContext).openDrawer();
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.cyan, width: 3),
                borderRadius: BorderRadius.circular(AppRadii.card),
                boxShadow: const [
                  BoxShadow(
                      color: AppColors.buttonGlow,
                      blurRadius: 24,
                      spreadRadius: 2),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
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

class _CheckInLabels {
  final String person;
  final String service;
  final String location;
  final String time;

  const _CheckInLabels(this.person, this.service, this.location, this.time);
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
