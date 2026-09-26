import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/booking_model.dart';
import '../../../models/owner_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../shared/color_utils.dart';
import '../../../shared/date_format.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';
import 'booking_detail_sheet.dart';
import 'scheduling_kit.dart';

/// The booking desk.
///
/// Built around the day, not the database. A manager opening this on a phone
/// wants three answers in the first second — is today busy, is anything
/// broken, and what is happening right now — so the hero, the conflict
/// banner and the timeline's now-line answer exactly those, in that order,
/// before any list appears.
///
/// Row actions live in a detail sheet rather than on every card. Nine equal
/// buttons per booking is a wall; one obvious next step with the rest a tap
/// away is a decision.
class BookingManagerScreen extends ConsumerStatefulWidget {
  const BookingManagerScreen({super.key});

  @override
  ConsumerState<BookingManagerScreen> createState() => _BookingManagerScreenState();
}

enum _View { timeline, list }

class _BookingManagerScreenState extends ConsumerState<BookingManagerScreen> {
  DateTime _day = DateTime.now();
  DateTime _weekAnchor = DateTime.now().subtract(Duration(days: DateTime.now().weekday % 7));
  _View _view = _View.timeline;
  String _status = '';
  String _search = '';
  bool _searching = false;

  static DateTime _key(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(ownerBookingsProvider);
    final conflicts = ref.watch(ownerConflictsProvider).valueOrNull ?? const <ConflictPair>[];
    final types = ref.watch(ownerBookingTypesProvider).valueOrNull ?? const [];
    // The service's own colour, so a card on the timeline is recognisable
    // before its text is read.
    final colorOf = {for (final t in types) t.id: parseHexColor(t.colorHex) ?? AppColors.cyan};

    return OwnerScaffold(
      title: 'Booking Manager',
      subtitle: 'The diary',
      actions: [
        IconButton(
          tooltip: _searching ? 'Close search' : 'Search',
          icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) _search = '';
          }),
        ),
        IconButton(
          tooltip: 'Jump to a date',
          icon: const Icon(Icons.calendar_month_rounded),
          onPressed: _pickDate,
        ),
      ],
      body: bookingsAsync.when(
        loading: () => const ScheduleSkeleton(),
        error: (error, _) => ErrorState(
          message: 'Could not load the diary.',
          onRetry: () => ref.invalidate(ownerBookingsProvider),
        ),
        data: (all) {
          final live = all.where((b) => !ScheduleStatus.of(b.status).isDropped).toList();
          final onDay = all.where((b) => _key(b.startLocal) == _key(_day)).toList()
            ..sort((a, b) => a.startLocal.compareTo(b.startLocal));

          final load = <DateTime, int>{};
          for (final booking in live) {
            load.update(_key(booking.startLocal), (v) => v + 1, ifAbsent: () => 1);
          }

          final visible = onDay.where((b) {
            if (_status.isNotEmpty && b.status != _status) return false;
            if (_search.isEmpty) return true;
            final haystack = '${b.title ?? ''} ${b.resourceName} ${b.bookingTypeName}'.toLowerCase();
            return haystack.contains(_search.toLowerCase());
          }).toList();

          final pending = onDay.where((b) => b.status == 'Pending').length;
          final now = DateTime.now();
          final happening = onDay
              .where((b) =>
                  b.startLocal.isBefore(now) && b.endLocal.isAfter(now) && !ScheduleStatus.of(b.status).isDropped)
              .toList();
          final heads = onDay
              .where((b) => !ScheduleStatus.of(b.status).isDropped)
              .fold<int>(0, (sum, b) => sum + (b.attendeeCount ?? 1));

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async {
              ref.invalidate(ownerBookingsProvider);
              ref.invalidate(ownerConflictsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                ScheduleHero(
                  eyebrow: _relativeDayLabel(_day),
                  headline: _headline(onDay.where((b) => !ScheduleStatus.of(b.status).isDropped).length),
                  support: formatFullDate(_day),
                  accent: happening.isNotEmpty ? AppColors.violet : AppColors.cyan,
                  trailing: _DayStepper(
                    onPrevious: () => setState(() => _setDay(_day.subtract(const Duration(days: 1)))),
                    onNext: () => setState(() => _setDay(_day.add(const Duration(days: 1)))),
                  ),
                  chips: [
                    if (happening.isNotEmpty)
                      HeroMetric(
                        icon: Icons.play_circle_fill_rounded,
                        value: '${happening.length}',
                        label: 'happening now',
                        color: AppColors.violet,
                      ),
                    HeroMetric(icon: Icons.groups_rounded, value: '$heads', label: 'people'),
                    if (pending > 0)
                      HeroMetric(
                        icon: Icons.hourglass_top_rounded,
                        value: '$pending',
                        label: 'to approve',
                        color: AppColors.warning,
                        onTap: () => setState(() => _status = 'Pending'),
                      ),
                    if (!_isToday(_day))
                      HeroMetric(
                        icon: Icons.today_rounded,
                        value: 'Today',
                        label: '',
                        color: AppColors.cyan,
                        onTap: () => setState(() => _setDay(DateTime.now())),
                      ),
                  ],
                ),
                if (conflicts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  AlertBanner(
                    icon: Icons.warning_amber_rounded,
                    title: '${conflicts.length} double booking${conflicts.length == 1 ? '' : 's'}',
                    detail: 'Two reservations share one resource at the same time.',
                    actionLabel: 'Review',
                    onAction: () => _showConflicts(conflicts),
                  ),
                ],
                const SizedBox(height: 14),

                // Week strip, with a load bar per day.
                Row(
                  children: [
                    _StripArrow(
                      icon: Icons.chevron_left_rounded,
                      onTap: () => setState(() => _weekAnchor = _weekAnchor.subtract(const Duration(days: 7))),
                    ),
                    Expanded(
                      child: WeekStrip(
                        anchor: _weekAnchor,
                        selected: _day,
                        load: load,
                        onSelected: (d) => setState(() => _day = d),
                      ),
                    ),
                    _StripArrow(
                      icon: Icons.chevron_right_rounded,
                      onTap: () => setState(() => _weekAnchor = _weekAnchor.add(const Duration(days: 7))),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (_searching) ...[
                  NeonInputField(
                    hintText: 'Search guest, service or resource',
                    icon: Icons.search_rounded,
                    clearable: true,
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 12),
                ],

                SegmentedSwitch<_View>(
                  segments: const [
                    (value: _View.timeline, icon: Icons.view_timeline_rounded, label: 'Timeline'),
                    (value: _View.list, icon: Icons.view_agenda_rounded, label: 'List'),
                  ],
                  selected: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
                const SizedBox(height: 12),

                _StatusFilter(
                  counts: {
                    for (final status in ScheduleStatus.filterable)
                      status.value: onDay.where((b) => b.status == status.value).length,
                  },
                  selected: _status,
                  total: onDay.length,
                  onSelected: (v) => setState(() => _status = v),
                ),
                const SizedBox(height: 16),

                if (visible.isEmpty)
                  ScheduleEmpty(
                    icon: onDay.isEmpty ? Icons.event_available_outlined : Icons.filter_alt_off_outlined,
                    title: onDay.isEmpty ? 'Nothing booked' : 'Nothing matches',
                    detail: onDay.isEmpty
                        ? '${formatFullDate(_day)} is clear. Pick another day from the strip above.'
                        : 'Clear the filter to see all ${onDay.length} booking${onDay.length == 1 ? '' : 's'} on this day.',
                    actionLabel: onDay.isEmpty ? null : 'Clear the filter',
                    onAction: onDay.isEmpty ? null : () => setState(() => _status = ''),
                  )
                else if (_view == _View.timeline)
                  DayTimeline(
                    day: _day,
                    entries: [
                      for (final booking in visible)
                        TimelineEntry(booking, colorOf[booking.bookingTypeId] ?? AppColors.cyan),
                    ],
                    onTap: _openBooking,
                  )
                else
                  for (final booking in visible)
                    _BookingRow(
                      booking: booking,
                      accent: colorOf[booking.bookingTypeId] ?? AppColors.cyan,
                      onTap: () => _openBooking(booking),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _isToday(DateTime d) => _key(d) == _key(DateTime.now());

  void _setDay(DateTime day) {
    _day = day;
    // Keep the strip on the week the selected day belongs to, so stepping
    // past Sunday scrolls the week rather than losing the selection.
    _weekAnchor = day.subtract(Duration(days: day.weekday % 7));
  }

  String _headline(int count) {
    if (count == 0) return 'A clear day';
    return '$count booking${count == 1 ? '' : 's'}';
  }

  String _relativeDayLabel(DateTime day) {
    final today = _key(DateTime.now());
    final diff = _key(day).difference(today).inDays;
    return switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => diff > 0 ? 'In $diff days' : '${-diff} days ago',
    };
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 120)),
    );
    if (picked != null) setState(() => _setDay(picked));
  }

  void _openBooking(Booking booking) => showBookingDetailSheet(context, ref, booking);

  void _showConflicts(List<ConflictPair> conflicts) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.pill)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetGrip(),
              const SizedBox(height: 10),
              Text('Double bookings', style: AppTextStyles.title),
              const SizedBox(height: 4),
              Text('Two reservations on one resource at the same time.', style: AppTextStyles.caption),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: conflicts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final c = conflicts[i];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(AppRadii.row),
                        border: Border.all(color: AppColors.error.withValues(alpha: .3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.meeting_room_outlined, size: 15, color: AppColors.error),
                              const SizedBox(width: 8),
                              Text(c.resourceName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _ConflictLine(title: c.firstTitle, at: c.firstStart),
                          const SizedBox(height: 4),
                          _ConflictLine(title: c.secondTitle, at: c.secondStart),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConflictLine extends StatelessWidget {
  final String title;
  final DateTime? at;
  const _ConflictLine({required this.title, this.at});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption)),
        if (at != null)
          Text(
            '${formatDayMonth(at!)} ${formatTimeOfDay(at!)}',
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
          ),
      ],
    );
  }
}

class _DayStepper extends StatelessWidget {
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _DayStepper({required this.onPrevious, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            onPressed: onPrevious,
            tooltip: 'Previous day',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            onPressed: onNext,
            tooltip: 'Next day',
          ),
        ],
      ),
    );
  }
}

class _StripArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StripArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 44),
      icon: Icon(icon, size: 20, color: AppColors.iconSecondary),
    );
  }
}

/// Status filters carrying their own counts, and only for statuses the day
/// actually contains — a filter row of nine mostly-empty options is noise.
class _StatusFilter extends StatelessWidget {
  final Map<String, int> counts;
  final String selected;
  final int total;
  final ValueChanged<String> onSelected;

  const _StatusFilter({
    required this.counts,
    required this.selected,
    required this.total,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final used = ScheduleStatus.filterable.where((s) => (counts[s.value] ?? 0) > 0).toList();

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Chip(
            label: 'All',
            count: total,
            color: AppColors.cyan,
            isSelected: selected.isEmpty,
            onTap: () => onSelected(''),
          ),
          for (final status in used)
            _Chip(
              label: status.label,
              icon: status.icon,
              count: counts[status.value] ?? 0,
              color: status.color,
              isSelected: selected == status.value,
              onTap: () => onSelected(selected == status.value ? '' : status.value),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final int count;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    this.icon,
    required this.count,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: .18) : AppColors.glassFill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: isSelected ? color : AppColors.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: isSelected ? color : AppColors.iconSecondary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: isSelected ? color : AppColors.textBody,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: AppTextStyles.caption.copyWith(
                  color: isSelected ? color : AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list view's row. One line of identity, one of detail, and the state —
/// no action buttons, because the sheet does that far better.
class _BookingRow extends StatelessWidget {
  final Booking booking;
  final Color accent;
  final VoidCallback onTap;

  const _BookingRow({required this.booking, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = ScheduleStatus.of(booking.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.row),
          child: Opacity(
            opacity: status.isDropped ? .55 : 1,
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppColors.glassFill,
                borderRadius: BorderRadius.circular(AppRadii.row),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  // The service's colour as a spine, then the time — the two
                  // things a desk scans a list by.
                  Container(
                    width: 4,
                    height: 44,
                    decoration: BoxDecoration(
                      color: status.isDropped ? AppColors.textMuted : accent,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 52,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatTimeOfDay(booking.startLocal),
                          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          formatTimeOfDay(booking.endLocal),
                          style: AppTextStyles.caption.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.title?.isNotEmpty == true ? booking.title! : booking.bookingTypeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${booking.resourceName}'
                          '${booking.attendeeCount != null ? ' · ${booking.attendeeCount} pax' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption,
                        ),
                        const SizedBox(height: 7),
                        StatusPill(status: booking.status, compact: true),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.chevron),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
