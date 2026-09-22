import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/available_slot_model.dart';
import '../../models/booking_type_model.dart';
import '../../models/public_tenant_model.dart';
import '../../models/resource_model.dart';
import '../../models/subtype_dashboard_config.dart';
import '../../models/tourism_subtype.dart';
import '../../providers/api_service_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/booking_providers.dart';
import '../../registry/tourism_dashboard_registry.dart';
import '../../shared/color_utils.dart';
import '../../shared/date_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/booking_field_input.dart';
import '../../widgets/date_range_picker.dart';
import '../../widgets/date_slot_picker.dart';
import '../../widgets/route_transitions.dart';
import 'booking_success_screen.dart';

/// Unifies Slot's [AvailableSlot] and Night/DateRange/Package's picked
/// start/end dates into one shape [_ConfirmStep]/[_confirmBooking] work
/// with, so neither has to branch on booking unit internally.
typedef BookingWindow = ({DateTime startLocal, DateTime endLocal, String startIso, String endIso});

({int hour, int minute}) _parseTimeOfDay(String? value, {required int fallbackHour, required int fallbackMinute}) {
  if (value != null) {
    final parts = value.split(':');
    final h = int.tryParse(parts.elementAt(0));
    final m = parts.length > 1 ? int.tryParse(parts.elementAt(1)) : 0;
    if (h != null && m != null) return (hour: h, minute: m);
  }
  return (hour: fallbackHour, minute: fallbackMinute);
}

BookingWindow _rangeToWindow(DateTime start, DateTime end, BookingType type) {
  final config = type.config;
  if (type.bookingUnit == 'Night') {
    final checkIn = _parseTimeOfDay(config?['checkInTime'] as String?, fallbackHour: 14, fallbackMinute: 0);
    final checkOut = _parseTimeOfDay(config?['checkOutTime'] as String?, fallbackHour: 11, fallbackMinute: 0);
    final startLocal = DateTime(start.year, start.month, start.day, checkIn.hour, checkIn.minute);
    final endLocal = DateTime(end.year, end.month, end.day, checkOut.hour, checkOut.minute);
    return (startLocal: startLocal, endLocal: endLocal, startIso: startLocal.toUtc().toIso8601String(), endIso: endLocal.toUtc().toIso8601String());
  }
  final startLocal = DateTime(start.year, start.month, start.day);
  final endLocal = DateTime(end.year, end.month, end.day, 23, 59);
  return (startLocal: startLocal, endLocal: endLocal, startIso: startLocal.toUtc().toIso8601String(), endIso: endLocal.toUtc().toIso8601String());
}

class BookingFlowScreen extends ConsumerStatefulWidget {
  final PublicTenant tenant;
  final Resource resource;
  // Resolved tourism sub-type (see models/tourism_subtype.dart), null for
  // non-Tourism tenants or Tourism tenants with no sub-type set - in both
  // cases the wizard behaves exactly as before (no extra step).
  final TourismSubType? subType;

  const BookingFlowScreen({super.key, required this.tenant, required this.resource, this.subType});

  @override
  ConsumerState<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends ConsumerState<BookingFlowScreen> {
  int _step = 0;
  BookingType? _selectedType;
  DateTime? _selectedDate;
  AvailableSlot? _selectedSlot;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  int _attendeeCount = 1;
  final _notesController = TextEditingController();
  bool _submitting = false;
  bool _repeatWeekly = false;
  DateTime? _repeatUntil;
  final Map<String, dynamic> _extraFieldValues = {};

  Color get _accent => BusinessTypeVisual.of(widget.tenant.businessType).color;

  List<BookingFormField> get _extraFields =>
      widget.subType == null ? const [] : TourismDashboardRegistry.configFor(widget.subType!).bookingFormFields;

  bool get _hasExtraStep => _extraFields.isNotEmpty;

  // Step after date/time is always index 2, whether that's the extra-fields
  // step (when the sub-type has any) or confirm directly (when it doesn't).
  int get _confirmStepIndex => _hasExtraStep ? 3 : 2;

  BookingWindow? get _window {
    final type = _selectedType;
    if (type == null) return null;
    if (type.bookingUnit == 'Slot') {
      final s = _selectedSlot;
      if (s == null) return null;
      return (startLocal: s.startLocal, endLocal: s.endLocal, startIso: s.startTime, endIso: s.endTime);
    }
    if (_rangeStart == null || _rangeEnd == null) return null;
    return _rangeToWindow(_rangeStart!, _rangeEnd!, type);
  }

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
    final window = _window;
    final type = _selectedType;
    if (user == null || window == null || type == null) return;

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
          firstStartTimeIso: window.startIso,
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
        startTimeIso: window.startIso,
        endTimeIso: window.endIso,
        title: '${type.name} — ${widget.resource.name}',
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        attendeeCount: (widget.resource.capacity ?? 1) > 1 ? _attendeeCount : null,
        formData: _extraFieldValues.isEmpty ? null : jsonEncode(_extraFieldValues),
      );

      if (!mounted) return;
      ref.invalidate(myBookingsProvider);
      Navigator.of(context).pushReplacement(slideFadeRoute(BookingSuccessScreen(
        tenantName: widget.tenant.businessName,
        resourceName: widget.resource.name,
        bookingTypeName: type.name,
        startLocal: window.startLocal,
        endLocal: window.endLocal,
        bookingUnit: type.bookingUnit,
        requiresApproval: type.requiresApproval,
        accentColor: _accent,
        bookingId: bookingId,
      )));
    } on BookingConflictException catch (e) {
      if (!mounted) return;
      if (type.bookingUnit == 'Slot' && _selectedDate != null) {
        ref.invalidate(availableSlotsProvider((
          resourceId: widget.resource.id,
          date: toApiDateString(_selectedDate!),
          duration: type.defaultDurationMinutes,
          bookingTypeId: type.id,
        )));
      } else {
        final today = DateTime.now();
        ref.invalidate(unavailableRangesProvider((
          resourceId: widget.resource.id,
          from: toApiDateString(DateTime(today.year, today.month, today.day)),
          to: toApiDateString(DateTime(today.year, today.month, today.day).add(const Duration(days: 365))),
        )));
      }
      setState(() {
        _selectedSlot = null;
        _rangeStart = null;
        _rangeEnd = null;
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
            _WizardHeader(
              step: _step,
              accent: _accent,
              onBack: _goBack,
              resourceName: widget.resource.name,
              labels: _hasExtraStep ? const ['Type', 'Date & time', 'Details', 'Confirm'] : const ['Type', 'Date & time', 'Confirm'],
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _step == 0
                    ? _TypeStep(
                        key: const ValueKey('type'),
                        tenantId: widget.tenant.id,
                        accent: _accent,
                        onSelected: (type) => setState(() {
                          _selectedType = type;
                          _step = 1;
                        }),
                      )
                    : _step == 1
                        ? _DateTimeStep(
                            key: const ValueKey('datetime'),
                            resource: widget.resource,
                            type: _selectedType!,
                            accent: _accent,
                            selectedSlotStartTime: _selectedSlot?.startTime,
                            initialRangeStart: _rangeStart,
                            initialRangeEnd: _rangeEnd,
                            onSlotSelected: (date, slot) => setState(() {
                              _selectedDate = date;
                              _selectedSlot = slot;
                              _step = 2;
                            }),
                            onRangeSelected: (start, end) => setState(() {
                              _rangeStart = start;
                              _rangeEnd = end;
                              _step = 2;
                            }),
                          )
                        : (_hasExtraStep && _step == 2)
                            ? _ExtraFieldsStep(
                                key: const ValueKey('extra'),
                                fields: _extraFields,
                                accent: _accent,
                                values: _extraFieldValues,
                                onChanged: (key, value) => setState(() => _extraFieldValues[key] = value),
                                onContinue: () => setState(() => _step = _confirmStepIndex),
                              )
                            : _ConfirmStep(
                                key: const ValueKey('confirm'),
                                tenant: widget.tenant,
                                resource: widget.resource,
                                type: _selectedType!,
                                window: _window!,
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
  final List<String> labels;

  const _WizardHeader({
    required this.step,
    required this.accent,
    required this.onBack,
    required this.resourceName,
    this.labels = const ['Type', 'Date & time', 'Confirm'],
  });

  List<String> get _labels => labels;

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
        // Add-ons are extras attached to a trip, not trips in their own
        // right, so they get their own labelled section below the tours
        // instead of sitting in the same list as "Whale Watching" - which
        // made a photo package look like something you could book alone.
        final tours = types.where((t) => !t.isAddon).toList();
        final addons = types.where((t) => t.isAddon).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            Text('What would you like to book?', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // Falls back to every type when nothing is categorised, so a
            // tenant that never set `category` sees exactly what it saw
            // before this grouping existed.
            ...(tours.isEmpty ? types : tours).map((type) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TypeCard(type: type, accent: accent, onTap: () => onSelected(type)),
                )),
            if (tours.isNotEmpty && addons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Add-ons & services', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Extras you can book alongside a trip.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              ...addons.map((type) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TypeCard(type: type, accent: accent, onTap: () => onSelected(type)),
                  )),
            ],
          ],
        );
      },
    );
  }
}

/// "LKR 7,500" - or "Free" for a published zero price, which is a real rate
/// (the complimentary 3 km transfer) and not missing data.
String? _money(num? value, String currency) {
  if (value == null) return null;
  if (value == 0) return 'Free';
  final formatted = value.round().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]},',
      );
  return '$currency $formatted';
}

/// One ticket tier, laid out like the operator's own rate card: the tier, the
/// age band it applies to, and the per-person price.
class _TicketTier extends StatelessWidget {
  final String label;
  final String? band;
  final String price;
  final Color color;

  const _TicketTier({required this.label, required this.band, required this.price, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(price, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          if (band != null) ...[
            const SizedBox(height: 1),
            Text(band!, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ],
        ],
      ),
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
    final currency = type.currency;
    final adult = _money(type.adultPrice, currency);
    // A null child rate means this product has no child tier at all, which is
    // not the same as free - the tier is omitted rather than shown at zero.
    final child = _money(type.childPrice, currency);

    return Container(
      decoration: GlassStyle.elevatedCard(),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 40,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type.icon == null ? type.name : '${type.icon} ${type.name}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        if (type.description != null && type.description!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            type.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3),
                          ),
                        ],
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(Icons.schedule, size: 13, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text('${type.defaultDurationMinutes} min',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            if (type.requiresApproval) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.amber.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Needs approval',
                                    style: TextStyle(fontSize: 10, color: AppColors.amber, fontWeight: FontWeight.w700)),
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

              // The rate card: one tile per ticket tier the operator publishes.
              if (adult != null || child != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (adult != null)
                      Expanded(
                        child: _TicketTier(
                          label: 'ADULT',
                          band: type.adultFromAge == null ? null : 'Above ${type.adultFromAge} years',
                          price: adult,
                          color: color,
                        ),
                      ),
                    if (adult != null && child != null) const SizedBox(width: 8),
                    if (child != null)
                      Expanded(
                        child: _TicketTier(
                          label: 'CHILD',
                          band: type.childUnderAge == null ? null : 'Below ${type.childUnderAge} years',
                          price: child,
                          color: color,
                        ),
                      ),
                  ],
                ),
              ],

              // What every ticket includes - the same list the operator prints
              // under each tier on their own booking page.
              if (type.includes.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...type.includes.map((inc) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.add, size: 12, color: color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(inc,
                                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, height: 1.3)),
                          ),
                        ],
                      ),
                    )),
              ],
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
  final DateTime? initialRangeStart;
  final DateTime? initialRangeEnd;
  final void Function(DateTime date, AvailableSlot slot) onSlotSelected;
  final void Function(DateTime start, DateTime end) onRangeSelected;

  const _DateTimeStep({
    super.key,
    required this.resource,
    required this.type,
    required this.accent,
    required this.selectedSlotStartTime,
    required this.initialRangeStart,
    required this.initialRangeEnd,
    required this.onSlotSelected,
    required this.onRangeSelected,
  });

  static const _titles = {
    'Slot': 'Pick a date & time',
    'Night': 'Pick your stay dates',
    'DateRange': 'Pick your rental dates',
    'Package': 'Pick your tour dates',
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Text(_titles[type.bookingUnit] ?? _titles['Slot']!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        if (type.bookingUnit == 'Slot')
          DateSlotPicker(
            resourceId: resource.id,
            bookingTypeId: type.id,
            durationMinutes: type.defaultDurationMinutes,
            accentColor: accent,
            selectedSlotStartTime: selectedSlotStartTime,
            onSlotSelected: onSlotSelected,
          )
        else
          DateRangePicker(
            resourceId: resource.id,
            bookingUnit: type.bookingUnit,
            config: type.config,
            accentColor: accent,
            initialStart: initialRangeStart,
            initialEnd: initialRangeEnd,
            onRangeSelected: onRangeSelected,
          ),
      ],
    );
  }
}

/// One shared step (not one screen per sub-type) collecting the tourism
/// sub-type's extra fields via [BookingFieldInput] - inserted between
/// date/time and confirm only when the registry has fields for this
/// business's sub-type (see TourismDashboardRegistry).
class _ExtraFieldsStep extends StatelessWidget {
  final List<BookingFormField> fields;
  final Color accent;
  final Map<String, dynamic> values;
  final void Function(String key, dynamic value) onChanged;
  final VoidCallback onContinue;

  const _ExtraFieldsStep({
    super.key,
    required this.fields,
    required this.accent,
    required this.values,
    required this.onChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Text('A few more details', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ...fields.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: BookingFieldInput(
                field: f,
                value: values[f.key],
                onChanged: (v) => onChanged(f.key, v),
              ),
            )),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: onContinue,
            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  final PublicTenant tenant;
  final Resource resource;
  final BookingType type;
  final BookingWindow window;
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
    required this.window,
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
    final start = window.startLocal;
    final end = window.endLocal;
    final isSlot = type.bookingUnit == 'Slot';
    final unitCount = isSlot ? null : DateTime(end.year, end.month, end.day).difference(DateTime(start.year, start.month, start.day)).inDays;
    final price = resource.hourlyRate == null
        ? null
        : resource.hourlyRate! * (isSlot ? (end.difference(start).inMinutes / 60) : unitCount!);

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
              if (isSlot) ...[
                _SummaryRow(icon: Icons.calendar_today_outlined, label: formatFullDate(start)),
                const SizedBox(height: 8),
                _SummaryRow(icon: Icons.access_time_rounded, label: '${formatTimeOfDay(start)} – ${formatTimeOfDay(end)}'),
              ] else
                _SummaryRow(
                  icon: Icons.calendar_today_outlined,
                  label: formatDateRangeSummary(start, end, nights: type.bookingUnit == 'Night'),
                ),
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
        if (isSlot) ...[
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
                  initialDate: repeatUntil ?? start.add(const Duration(days: 28)),
                  firstDate: start,
                  lastDate: start.add(const Duration(days: 365)),
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
        child: Icon(icon, size: 18, color: onTap == null ? AppColors.textMuted : AppColors.textPrimary),
      ),
    );
  }
}
