import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/available_slot_model.dart';
import '../providers/booking_providers.dart';
import '../shared/date_format.dart';
import '../theme/app_theme.dart';

/// Date strip (next 14 days) + available-slot grid for a resource/booking
/// type/duration combo. Shared by the booking wizard's date step and the
/// "My Bookings" reschedule sheet so the non-trivial fetch/selection logic
/// isn't duplicated.
class DateSlotPicker extends ConsumerStatefulWidget {
  final String resourceId;
  final String bookingTypeId;
  final int durationMinutes;
  final Color accentColor;
  final void Function(DateTime date, AvailableSlot slot) onSlotSelected;
  final String? selectedSlotStartTime;

  const DateSlotPicker({
    super.key,
    required this.resourceId,
    required this.bookingTypeId,
    required this.durationMinutes,
    required this.onSlotSelected,
    this.accentColor = AppColors.primary,
    this.selectedSlotStartTime,
  });

  @override
  ConsumerState<DateSlotPicker> createState() => _DateSlotPickerState();
}

class _DateSlotPickerState extends ConsumerState<DateSlotPicker> {
  late DateTime _selectedDate;
  late final List<DateTime> _days;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _selectedDate = DateTime(today.year, today.month, today.day);
    _days = List.generate(14, (i) => _selectedDate.add(Duration(days: i)));
  }

  @override
  Widget build(BuildContext context) {
    final query = (
      resourceId: widget.resourceId,
      date: toApiDateString(_selectedDate),
      duration: widget.durationMinutes,
      bookingTypeId: widget.bookingTypeId,
    );
    final slotsAsync = ref.watch(availableSlotsProvider(query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final day = _days[i];
              final isSelected = day == _selectedDate;
              return GestureDetector(
                onTap: () => setState(() => _selectedDate = day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 56,
                  decoration: BoxDecoration(
                    color: isSelected ? widget.accentColor : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? widget.accentColor : AppColors.border,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: widget.accentColor.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        formatWeekday(day),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white70 : Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppColors.onPrimary : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        slotsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, stack) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.wifi_off_rounded, color: AppColors.danger.withValues(alpha: 0.7), size: 36),
                  const SizedBox(height: 10),
                  const Text('Could not load availability.'),
                  TextButton(
                    onPressed: () => ref.invalidate(availableSlotsProvider(query)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (result) {
            if (!result.isOpen) {
              return _EmptySlots(message: 'Closed on ${formatFullDate(_selectedDate)}.');
            }
            final available = result.slots.where((s) => s.isAvailable).toList();
            if (available.isEmpty) {
              return const _EmptySlots(message: 'No open slots on this day — try another date.');
            }
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: available.map((slot) {
                final isSelected = slot.startTime == widget.selectedSlotStartTime;
                return GestureDetector(
                  onTap: () => widget.onSlotSelected(_selectedDate, slot),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? widget.accentColor : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? widget.accentColor : AppColors.border,
                      ),
                    ),
                    child: Text(
                      formatTimeOfDay(slot.startLocal),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? AppColors.onPrimary : AppColors.textPrimary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _EmptySlots extends StatelessWidget {
  final String message;
  const _EmptySlots({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.event_busy_outlined, color: Colors.grey.shade400, size: 36),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
