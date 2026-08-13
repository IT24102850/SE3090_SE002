import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/available_slot_model.dart';
import '../../models/booking_type_model.dart';
import '../../models/public_tenant_model.dart';
import '../../models/resource_model.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/booking_providers.dart';
import '../../shared/color_utils.dart';
import '../../shared/date_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/date_slot_picker.dart';
import '../../widgets/route_transitions.dart';
import 'booking_success_screen.dart';

class BookingFlowScreen extends ConsumerStatefulWidget {
  final PublicTenant tenant;
  final Resource resource;

  const BookingFlowScreen({super.key, required this.tenant, required this.resource});

  @override
  ConsumerState<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends ConsumerState<BookingFlowScreen> {
  int _step = 0;
  BookingType? _selectedType;
  DateTime? _selectedDate;
  AvailableSlot? _selectedSlot;
  int _attendeeCount = 1;
  final _notesController = TextEditingController();
  bool _submitting = false;
  bool _repeatWeekly = false;
  DateTime? _repeatUntil;

  Color get _accent => BusinessTypeVisual.of(widget.tenant.businessType).color;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step -= 1);
    }
  }

  Future<void> _confirmBooking() async {
    final user = ref.read(authProvider).user;
    final slot = _selectedSlot;
    final type = _selectedType;
    if (user == null || slot == null || type == null) return;

    if (_repeatWeekly && _repeatUntil == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick an end date for the recurring series.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final dio = ref.read(apiServiceProvider);
    try {
      if (_repeatWeekly) {
        final result = await createRecurringBooking(
          dio,
          tenantId: widget.tenant.id,
          resourceId: widget.resource.id,
          bookingTypeId: type.id,
          bookedBy: user.id,
          firstStartTimeIso: slot.startTime,
          durationMinutes: type.defaultDurationMinutes,
          endDate: toApiDateString(_repeatUntil!),
          title: '${type.name} — ${widget.resource.name}',
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        );

        if (!mounted) return;
        ref.invalidate(myBookingsProvider);
        final message = result.requiresApproval
            ? 'This recurring series affects ${result.totalRequested} bookings and requires approval from ${widget.tenant.businessName}.'
            : 'Recurring series created: ${result.created} of ${result.totalRequested} booking(s).';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }

      final bookingId = await createBooking(
        dio,
        tenantId: widget.tenant.id,
        resourceId: widget.resource.id,
        bookingTypeId: type.id,
        bookedBy: user.id,
        startTimeIso: slot.startTime,
        endTimeIso: slot.endTime,
        title: '${type.name} — ${widget.resource.name}',
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        attendeeCount: (widget.resource.capacity ?? 1) > 1 ? _attendeeCount : null,
      );

      if (!mounted) return;
      ref.invalidate(myBookingsProvider);
      Navigator.of(context).pushReplacement(slideFadeRoute(BookingSuccessScreen(
        tenantName: widget.tenant.businessName,
        resourceName: widget.resource.name,
        bookingTypeName: type.name,
        startLocal: slot.startLocal,
        endLocal: slot.endLocal,
        requiresApproval: type.requiresApproval,
        accentColor: _accent,
        bookingId: bookingId,
      )));
    } on BookingConflictException catch (e) {
      if (!mounted) return;
      final query = (
        resourceId: widget.resource.id,
        date: toApiDateString(_selectedDate!),
        duration: type.defaultDurationMinutes,
        bookingTypeId: type.id,
      );
      ref.invalidate(availableSlotsProvider(query));
      setState(() {
        _selectedSlot = null;
        _step = 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } on BookingRequestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _WizardHeader(step: _step, accent: _accent, onBack: _goBack, resourceName: widget.resource.name),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (_step) {
                  0 => _TypeStep(
                      key: const ValueKey('type'),
                      tenantId: widget.tenant.id,
                      accent: _accent,
                      onSelected: (type) => setState(() {
                        _selectedType = type;
                        _step = 1;
                      }),
                    ),
                  1 => _DateTimeStep(
                      key: const ValueKey('datetime'),
                      resource: widget.resource,
                      type: _selectedType!,
                      accent: _accent,
                      selectedSlotStartTime: _selectedSlot?.startTime,
                      onSelected: (date, slot) => setState(() {
                        _selectedDate = date;
                        _selectedSlot = slot;
                        _step = 2;
                      }),
                    ),
                  _ => _ConfirmStep(
                      key: const ValueKey('confirm'),
                      tenant: widget.tenant,
                      resource: widget.resource,
                      type: _selectedType!,
                      slot: _selectedSlot!,
                      accent: _accent,
                      notesController: _notesController,
                      attendeeCount: _attendeeCount,
                      onAttendeeChanged: (v) => setState(() => _attendeeCount = v),
                      repeatWeekly: _repeatWeekly,
                      onRepeatWeeklyChanged: (v) => setState(() => _repeatWeekly = v),
                      repeatUntil: _repeatUntil,
                      onRepeatUntilChanged: (v) => setState(() => _repeatUntil = v),
                      submitting: _submitting,
                      onConfirm: _confirmBooking,
                    ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WizardHeader extends StatelessWidget {
  final int step;
  final Color accent;
  final VoidCallback onBack;
  final String resourceName;

  const _WizardHeader({required this.step, required this.accent, required this.onBack, required this.resourceName});

  static const _labels = ['Type', 'Date & time', 'Confirm'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
              Expanded(
                child: Text(
                  resourceName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: List.generate(_labels.length * 2 - 1, (i) {
                if (i.isOdd) {
                  final segmentDone = (i ~/ 2) < step;
                  return Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: segmentDone ? accent : AppColors.border,
                    ),
                  );
                }
                final idx = i ~/ 2;
                final isDone = idx < step;
                final isCurrent = idx == step;
                return Column(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDone || isCurrent ? accent : Colors.white,
                        border: Border.all(color: isDone || isCurrent ? accent : AppColors.border),
                      ),
                      child: isDone
                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                          : Text('${idx + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isCurrent ? Colors.white : Colors.grey.shade500)),
                    ),
                    const SizedBox(height: 4),
                    Text(_labels[idx], style: TextStyle(fontSize: 10, color: isCurrent ? accent : Colors.grey.shade500, fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500)),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeStep extends ConsumerWidget {
  final String tenantId;
  final Color accent;
  final void Function(BookingType) onSelected;

  const _TypeStep({super.key, required this.tenantId, required this.accent, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(bookingTypesProvider(tenantId));

    return typesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load booking types.'),
            TextButton(onPressed: () => ref.invalidate(bookingTypesProvider(tenantId)), child: const Text('Retry')),
          ],
        ),
      ),
      data: (types) {
        if (types.isEmpty) {
          return const Center(child: Text('No bookable services available.'));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            Text('What would you like to book?', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...types.map((type) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TypeCard(type: type, accent: accent, onTap: () => onSelected(type)),
                )),
          ],
        );
      },
    );
  }
}

class _TypeCard extends StatelessWidget {
  final BookingType type;
  final Color accent;
  final VoidCallback onTap;

  const _TypeCard({required this.type, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(type.colorHex) ?? accent;
    return Container(
      decoration: GlassStyle.elevatedCard(),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(width: 8, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text('${type.defaultDurationMinutes} min', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        if (type.requiresApproval) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                            child: const Text('Needs approval', style: TextStyle(fontSize: 10, color: AppColors.amber, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateTimeStep extends StatelessWidget {
  final Resource resource;
  final BookingType type;
  final Color accent;
  final String? selectedSlotStartTime;
  final void Function(DateTime date, AvailableSlot slot) onSelected;

  const _DateTimeStep({
    super.key,
    required this.resource,
    required this.type,
    required this.accent,
    required this.selectedSlotStartTime,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Text('Pick a date & time', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        DateSlotPicker(
          resourceId: resource.id,
          bookingTypeId: type.id,
          durationMinutes: type.defaultDurationMinutes,
          accentColor: accent,
          selectedSlotStartTime: selectedSlotStartTime,
          onSlotSelected: onSelected,
        ),
      ],
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  final PublicTenant tenant;
  final Resource resource;
  final BookingType type;
  final AvailableSlot slot;
  final Color accent;
  final TextEditingController notesController;
  final int attendeeCount;
  final ValueChanged<int> onAttendeeChanged;
  final bool repeatWeekly;
  final ValueChanged<bool> onRepeatWeeklyChanged;
  final DateTime? repeatUntil;
  final ValueChanged<DateTime> onRepeatUntilChanged;
  final bool submitting;
  final VoidCallback onConfirm;

  const _ConfirmStep({
    super.key,
    required this.tenant,
    required this.resource,
    required this.type,
    required this.slot,
    required this.accent,
    required this.notesController,
    required this.attendeeCount,
    required this.onAttendeeChanged,
    required this.repeatWeekly,
    required this.onRepeatWeeklyChanged,
    required this.repeatUntil,
    required this.onRepeatUntilChanged,
    required this.submitting,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final start = slot.startLocal;
    final end = slot.endLocal;
    final price = resource.hourlyRate == null
        ? null
        : resource.hourlyRate! * (end.difference(start).inMinutes / 60);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Text('Confirm your booking', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(gradient: AppColors.heroGradientFor(accent), borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tenant.businessName, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('${resource.name} · ${type.name}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
              const Divider(color: Colors.white24, height: 28),
              _SummaryRow(icon: Icons.calendar_today_outlined, label: formatFullDate(start)),
              const SizedBox(height: 8),
              _SummaryRow(icon: Icons.access_time_rounded, label: '${formatTimeOfDay(start)} – ${formatTimeOfDay(end)}'),
              if (price != null) ...[
                const SizedBox(height: 8),
                _SummaryRow(icon: Icons.payments_outlined, label: 'LKR ${price.toStringAsFixed(0)}'),
              ],
            ],
          ),
        ),
        if (type.requiresApproval) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.amber, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('This booking type requires approval from the business before it is confirmed.', style: TextStyle(fontSize: 12.5))),
              ],
            ),
          ),
        ],
        if ((resource.capacity ?? 1) > 1) ...[
          const SizedBox(height: 20),
          Text('Attendees', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              _StepperButton(icon: Icons.remove, onTap: attendeeCount > 1 ? () => onAttendeeChanged(attendeeCount - 1) : null),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('$attendeeCount', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              _StepperButton(
                icon: Icons.add,
                onTap: attendeeCount < resource.capacity! ? () => onAttendeeChanged(attendeeCount + 1) : null,
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Text('Notes (optional)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        TextField(
          controller: notesController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Anything the business should know?',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: repeatWeekly,
          onChanged: onRepeatWeeklyChanged,
          activeColor: accent,
          title: const Text('Repeat weekly', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: const Text('e.g. weekly physiotherapy sessions', style: TextStyle(fontSize: 12)),
        ),
        if (repeatWeekly) ...[
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: repeatUntil ?? slot.startLocal.add(const Duration(days: 28)),
                firstDate: slot.startLocal,
                lastDate: slot.startLocal.add(const Duration(days: 365)),
              );
              if (picked != null) onRepeatUntilChanged(picked);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Repeat until',
                prefixIcon: const Icon(Icons.event_repeat_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(repeatUntil == null ? 'Select a date' : formatFullDate(repeatUntil!)),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: submitting ? null : onConfirm,
            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: submitting
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(repeatWeekly ? 'Confirm Series' : 'Confirm Booking', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SummaryRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? Colors.grey.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 18, color: onTap == null ? Colors.grey.shade400 : AppColors.ink),
      ),
    );
  }
}
