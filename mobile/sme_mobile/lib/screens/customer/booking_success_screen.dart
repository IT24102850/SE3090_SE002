import 'package:flutter/material.dart';
import '../../shared/date_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/booking_qr_code.dart';
import '../../widgets/route_transitions.dart';
import 'my_bookings_screen.dart';

class BookingSuccessScreen extends StatefulWidget {
  final String tenantName;
  final String resourceName;
  final String bookingTypeName;
  final DateTime startLocal;
  final DateTime endLocal;
  final String bookingUnit;
  final bool requiresApproval;
  final Color accentColor;
  final String bookingId;

  const BookingSuccessScreen({
    super.key,
    required this.tenantName,
    required this.resourceName,
    required this.bookingTypeName,
    required this.startLocal,
    required this.endLocal,
    this.bookingUnit = 'Slot',
    required this.requiresApproval,
    required this.accentColor,
    required this.bookingId,
  });

  @override
  State<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends State<BookingSuccessScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: AppColors.success, size: 52),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.requiresApproval ? 'Booking requested!' : 'Booking confirmed!',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                widget.requiresApproval
                    ? '${widget.tenantName} will confirm your booking shortly.'
                    : 'You\'re all set with ${widget.tenantName}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
              ),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: GlassStyle.elevatedCard(radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${widget.resourceName} · ${widget.bookingTypeName}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    if (widget.bookingUnit == 'Slot') ...[
                      _Row(icon: Icons.calendar_today_outlined, label: formatFullDate(widget.startLocal), accent: widget.accentColor),
                      const SizedBox(height: 8),
                      _Row(
                        icon: Icons.access_time_rounded,
                        label: '${formatTimeOfDay(widget.startLocal)} – ${formatTimeOfDay(widget.endLocal)}',
                        accent: widget.accentColor,
                      ),
                    ] else
                      _Row(
                        icon: Icons.calendar_today_outlined,
                        label: formatDateRangeSummary(widget.startLocal, widget.endLocal, nights: widget.bookingUnit == 'Night'),
                        accent: widget.accentColor,
                      ),
                    const SizedBox(height: 8),
                    _Row(icon: Icons.confirmation_number_outlined, label: 'Ref: ${widget.bookingId.substring(0, 8).toUpperCase()}', accent: widget.accentColor),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              BookingQrCode(bookingId: widget.bookingId, size: 140),
              const SizedBox(height: 8),
              Text(
                'Show this at reception to check in',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    slideFadeRoute(const MyBookingsScreen()),
                    (route) => route.isFirst,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('View My Bookings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  const _Row({required this.icon, required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      ],
    );
  }
}
