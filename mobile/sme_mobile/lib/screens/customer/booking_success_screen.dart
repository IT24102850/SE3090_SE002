import 'package:flutter/material.dart';
import '../../shared/date_format.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/booking_qr_code.dart';
import '../../widgets/ui/ui.dart';
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
    return AppBackgroundScaffold(
      showParticles: true,
      child: SafeArea(
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
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.5), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: AppColors.success.withValues(alpha: 0.25), blurRadius: 28, spreadRadius: -4),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded, color: AppColors.success, size: 52),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.requiresApproval ? 'Booking requested!' : 'Booking confirmed!',
                style: AppTextStyles.headlineSmall.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 8),
              Text(
                widget.requiresApproval
                    ? '${widget.tenantName} will confirm your booking shortly.'
                    : 'You\'re all set with ${widget.tenantName}.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMuted.copyWith(fontSize: 13.5),
              ),
              const SizedBox(height: 28),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${widget.resourceName} · ${widget.bookingTypeName}', style: AppTextStyles.subtitle),
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
                style: AppTextStyles.caption.copyWith(fontSize: 11.5),
              ),
              const Spacer(),
              NeonButton(
                label: 'View My Bookings',
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  slideFadeRoute(const MyBookingsScreen()),
                  (route) => route.isFirst,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: Text('Done', style: AppTextStyles.body.copyWith(color: AppColors.cyan)),
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
        Expanded(child: Text(label, style: AppTextStyles.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600))),
      ],
    );
  }
}
