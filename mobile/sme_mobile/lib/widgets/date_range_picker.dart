import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/booking_providers.dart';
import '../shared/date_format.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';
import 'ui/ui.dart';

/// Start/end date picker for Night/DateRange/Package booking types (see
/// docs/tourism-business-template.md) - the counterpart to [DateSlotPicker]
/// for bookings that aren't a fixed-duration time slot. Greys out dates
/// already booked on this resource via [unavailableRangesProvider], and
/// enforces `minNights`/`minDays` from the booking type's config.
class DateRangePicker extends ConsumerStatefulWidget {
  final String resourceId;
  final String bookingUnit;
  final Map<String, dynamic>? config;
  final Color accentColor;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final void Function(DateTime start, DateTime end) onRangeSelected;

  const DateRangePicker({
    super.key,
    required this.resourceId,
    required this.bookingUnit,
    required this.onRangeSelected,
    this.config,
    this.accentColor = AppColors.cyan,
    this.initialStart,
    this.initialEnd,
  });

  @override
  ConsumerState<DateRangePicker> createState() => _DateRangePickerState();
}

class _DateRangePickerState extends ConsumerState<DateRangePicker> {
  DateTime? _start;
  DateTime? _end;

  bool get _isNight => widget.bookingUnit == 'Night';
  bool get _isPackage => widget.bookingUnit == 'Package';

  int get _minUnits {
    final key = _isNight ? 'minNights' : 'minDays';
    final v = widget.config?[key];
    return v is num ? v.toInt() : 1;
  }

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final windowFrom = DateTime(today.year, today.month, today.day);
    final windowTo = windowFrom.add(const Duration(days: 365));
    final query = (
      resourceId: widget.resourceId,
      from: toApiDateString(windowFrom),
      to: toApiDateString(windowTo),
    );
    final rangesAsync = ref.watch(unavailableRangesProvider(query));

    return rangesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: AppLoader(),
      ),
      error: (err, stack) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.wifi_off_rounded, color: AppColors.danger, size: 36),
              const SizedBox(height: 10),
              Text('Could not load availability.', style: AppTextStyles.bodyMuted),
              TextButton(
                onPressed: () => ref.invalidate(unavailableRangesProvider(query)),
                child: Text('Retry', style: AppTextStyles.body.copyWith(color: AppColors.cyan)),
              ),
            ],
          ),
        ),
      ),
      data: (ranges) {
        bool isTaken(DateTime day) {
          final dayStart = DateTime(day.year, day.month, day.day);
          final dayEnd = dayStart.add(const Duration(days: 1));
          return ranges.any((r) => r.overlaps(dayStart, dayEnd));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isPackage && widget.config?['itinerary'] is List) ...[
              _ItineraryPreview(items: (widget.config!['itinerary'] as List).cast<Map<String, dynamic>>()),
              const SizedBox(height: 20),
            ],
            _DatePickerField(
              label: _isNight ? 'Check-in' : 'Start date',
              value: _start,
              accent: widget.accentColor,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _start ?? windowFrom,
                  firstDate: windowFrom,
                  lastDate: windowTo,
                  selectableDayPredicate: (d) => !isTaken(d),
                );
                if (picked == null) return;
                setState(() {
                  _start = picked;
                  final minEnd = picked.add(Duration(days: _minUnits));
                  if (_end == null || !_end!.isAfter(picked) || _end!.isBefore(minEnd)) {
                    _end = null;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            _DatePickerField(
              label: _isNight ? 'Check-out' : 'End date',
              value: _end,
              accent: widget.accentColor,
              enabled: _start != null,
              onTap: () async {
                final start = _start!;
                final firstEnd = start.add(Duration(days: _minUnits));
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _end ?? firstEnd,
                  firstDate: firstEnd,
                  lastDate: windowTo,
                  // Block any end date that would make [start, end) overlap
                  // an existing booking on this resource.
                  selectableDayPredicate: (d) => !ranges.any((r) => r.start.isBefore(d) && r.end.isAfter(start)),
                );
                if (picked == null) return;
                setState(() => _end = picked);
              },
            ),
            if (_minUnits > 1) ...[
              const SizedBox(height: 8),
              Text('Minimum $_minUnits ${_isNight ? "nights" : "days"}', style: AppTextStyles.caption),
            ],
            if (_start != null && _end != null) ...[
              const SizedBox(height: 16),
              NeonButton(
                label: 'Continue · ${formatDateRangeSummary(_start!, _end!, nights: _isNight)}',
                onPressed: () => widget.onRangeSelected(_start!, _end!),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final Color accent;
  final VoidCallback onTap;
  final bool enabled;

  const _DatePickerField({required this.label, required this.value, required this.accent, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTextStyles.label),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadii.control),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(
                color: enabled ? AppColors.inputBorder : AppColors.hairline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 20,
                  color: enabled ? AppColors.iconSecondary : AppColors.iconDisabled,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value == null ? 'Select a date' : formatFullDate(value!),
                    style: value == null
                        ? AppTextStyles.body.copyWith(color: AppColors.textMuted)
                        : AppTextStyles.body.copyWith(color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ItineraryPreview extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _ItineraryPreview({required this.items});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Itinerary'),
          ...items.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.only(right: 10, top: 1),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.cyan),
                      child: Text(
                        '${i['day'] ?? ''}',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.onPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text('${i['title'] ?? ''}', style: AppTextStyles.body.copyWith(fontSize: 13)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
