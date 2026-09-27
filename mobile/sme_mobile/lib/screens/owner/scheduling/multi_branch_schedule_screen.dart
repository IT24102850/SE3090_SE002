import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/booking_model.dart';
import '../../../providers/owner_providers.dart';
import '../../../shared/color_utils.dart';
import '../../../shared/date_format.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';
import 'booking_detail_sheet.dart';
import 'scheduling_kit.dart';

/// One day across every site.
///
/// The question a multi-site manager is asking is comparative — which branch
/// is carrying the load, and where is the slack — so the screen leads with a
/// ranked utilisation bar and gives each branch an hour band showing *when*
/// it is busy. A branch opens to its own resources only when asked, because
/// the comparison is the point and the detail is the follow-up.
class MultiBranchScheduleScreen extends ConsumerStatefulWidget {
  const MultiBranchScheduleScreen({super.key});

  @override
  ConsumerState<MultiBranchScheduleScreen> createState() => _MultiBranchScheduleScreenState();
}

class _MultiBranchScheduleScreenState extends ConsumerState<MultiBranchScheduleScreen> {
  DateTime _day = DateTime.now();
  DateTime _weekAnchor = DateTime.now().subtract(Duration(days: DateTime.now().weekday % 7));
  String? _open;

  static DateTime _key(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(ownerBookingsProvider);
    final branches = ref.watch(ownerBranchesProvider).valueOrNull ?? const [];
    final resources = ref.watch(ownerResourcesProvider).valueOrNull ?? const [];
    final types = ref.watch(ownerBookingTypesProvider).valueOrNull ?? const [];

    final branchOfResource = {for (final r in resources) r.id: r.branchId};
    final branchName = {for (final b in branches) b.id: b.name};
    final colorOf = {for (final t in types) t.id: parseHexColor(t.colorHex) ?? AppColors.cyan};

    return OwnerScaffold(
      title: 'Multi-Branch',
      subtitle: 'One day, every site',
      actions: [
        IconButton(
          tooltip: 'Jump to a date',
          icon: const Icon(Icons.calendar_month_rounded),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _day,
              firstDate: DateTime.now().subtract(const Duration(days: 30)),
              lastDate: DateTime.now().add(const Duration(days: 120)),
            );
            if (picked != null) {
              setState(() {
                _day = picked;
                _weekAnchor = picked.subtract(Duration(days: picked.weekday % 7));
              });
            }
          },
        ),
      ],
      body: bookingsAsync.when(
        loading: () => const ScheduleSkeleton(),
        error: (error, _) => ErrorState(
          message: 'Could not load the schedule.',
          onRetry: () => ref.invalidate(ownerBookingsProvider),
        ),
        data: (all) {
          final live = all.where((b) => !ScheduleStatus.of(b.status).isDropped).toList();
          final onDay = live.where((b) => _key(b.startLocal) == _key(_day)).toList()
            ..sort((a, b) => a.startLocal.compareTo(b.startLocal));

          final load = <DateTime, int>{};
          for (final booking in live) {
            load.update(_key(booking.startLocal), (v) => v + 1, ifAbsent: () => 1);
          }

          // Group by branch, with anything whose resource has no branch
          // gathered under one heading rather than silently dropped.
          final byBranch = <String, List<Booking>>{};
          for (final booking in onDay) {
            byBranch.putIfAbsent(branchOfResource[booking.resourceId] ?? '_none', () => []).add(booking);
          }
          final ordered = byBranch.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
          final busiest = ordered.isEmpty ? 1 : ordered.first.value.length;

          final heads = onDay.fold<int>(0, (sum, b) => sum + (b.attendeeCount ?? 1));
          final quiet = branches.where((b) => !byBranch.containsKey(b.id)).toList();

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async {
              ref.invalidate(ownerBookingsProvider);
              ref.invalidate(ownerResourcesProvider);
              ref.invalidate(ownerBranchesProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                ScheduleHero(
                  eyebrow: _relativeDayLabel(_day),
                  headline: onDay.isEmpty
                      ? 'Everywhere is clear'
                      : '${onDay.length} across ${byBranch.length} site${byBranch.length == 1 ? '' : 's'}',
                  support: formatFullDate(_day),
                  accent: AppColors.electricBlue,
                  chips: [
                    HeroMetric(icon: Icons.groups_rounded, value: '$heads', label: 'people'),
                    HeroMetric(
                      icon: Icons.meeting_room_outlined,
                      value: '${onDay.map((b) => b.resourceId).toSet().length}',
                      label: 'of ${resources.length} resources',
                    ),
                    if (quiet.isNotEmpty)
                      HeroMetric(
                        icon: Icons.bedtime_outlined,
                        value: '${quiet.length}',
                        label: 'site${quiet.length == 1 ? '' : 's'} idle',
                        color: AppColors.warning,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                WeekStrip(
                  anchor: _weekAnchor,
                  selected: _day,
                  load: load,
                  onSelected: (d) => setState(() => _day = d),
                ),
                const SizedBox(height: 18),

                if (onDay.isEmpty)
                  ScheduleEmpty(
                    icon: Icons.location_city_outlined,
                    title: 'Nothing booked anywhere',
                    detail: 'No site has a reservation on ${formatFullDate(_day)}.',
                  )
                else ...[
                  Text('Where the load is', style: AppTextStyles.label),
                  const SizedBox(height: 10),
                  for (final entry in ordered)
                    _BranchCard(
                      name: entry.key == '_none' ? 'Unassigned' : (branchName[entry.key] ?? 'Unknown site'),
                      bookings: entry.value,
                      busiest: busiest,
                      colorOf: colorOf,
                      isOpen: _open == entry.key,
                      onToggle: () => setState(() => _open = _open == entry.key ? null : entry.key),
                      onBooking: (booking) => showBookingDetailSheet(context, ref, booking),
                    ),
                  if (quiet.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.glassFill,
                        borderRadius: BorderRadius.circular(AppRadii.row),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bedtime_outlined, size: 17, color: AppColors.warning),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Nothing booked at', style: AppTextStyles.caption),
                                Text(
                                  quiet.map((b) => b.name).join(' · '),
                                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _relativeDayLabel(DateTime day) {
    final diff = _key(day).difference(_key(DateTime.now())).inDays;
    return switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => diff > 0 ? 'In $diff days' : '${-diff} days ago',
    };
  }
}

class _BranchCard extends StatelessWidget {
  final String name;
  final List<Booking> bookings;
  final int busiest;
  final Map<String, Color> colorOf;
  final bool isOpen;
  final VoidCallback onToggle;
  final ValueChanged<Booking> onBooking;

  const _BranchCard({
    required this.name,
    required this.bookings,
    required this.busiest,
    required this.colorOf,
    required this.isOpen,
    required this.onToggle,
    required this.onBooking,
  });

  @override
  Widget build(BuildContext context) {
    final share = busiest <= 0 ? 0.0 : (bookings.length / busiest).clamp(0.0, 1.0);
    final heads = bookings.fold<int>(0, (sum, b) => sum + (b.attendeeCount ?? 1));
    final byResource = <String, List<Booking>>{};
    for (final booking in bookings) {
      byResource.putIfAbsent(booking.resourceName, () => []).add(booking);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              color: AppColors.glassFill,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            '${bookings.length} booking${bookings.length == 1 ? '' : 's'} · $heads people · '
                            '${byResource.length} resource${byResource.length == 1 ? '' : 's'}',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isOpen ? .5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.expand_more_rounded, color: AppColors.chevron),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Share of the day's load, against the busiest site.
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: share,
                    minHeight: 5,
                    backgroundColor: AppColors.glassBorder,
                    valueColor: AlwaysStoppedAnimation(share > .75 ? AppColors.magenta : AppColors.cyan),
                  ),
                ),
                const SizedBox(height: 12),

                // When the site is busy, as a band of hours. Cheap to read,
                // and it answers "can I move something here at 3pm?".
                _HourBand(bookings: bookings),

                if (isOpen) ...[
                  const Divider(color: AppColors.hairline, height: 24),
                  for (final entry in byResource.entries) ...[
                    Row(
                      children: [
                        const Icon(Icons.meeting_room_outlined, size: 14, color: AppColors.iconSecondary),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(entry.key, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        Text('${entry.value.length}', style: AppTextStyles.caption),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final booking in entry.value)
                      InkWell(
                        onTap: () => onBooking(booking),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: colorOf[booking.bookingTypeId] ?? AppColors.cyan,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 78,
                                child: Text(
                                  '${formatTimeOfDay(booking.startLocal)}–${formatTimeOfDay(booking.endLocal)}',
                                  style: AppTextStyles.caption.copyWith(fontSize: 10),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  booking.title?.isNotEmpty == true ? booking.title! : booking.bookingTypeName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption,
                                ),
                              ),
                              const SizedBox(width: 8),
                              StatusPill(status: booking.status, compact: true),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 6am–10pm band with an hour lit for every hour that has a booking in
/// it. Sixteen cells is small enough to take in at a glance and precise
/// enough to plan against.
class _HourBand extends StatelessWidget {
  final List<Booking> bookings;
  const _HourBand({required this.bookings});

  static const _from = 6;
  static const _to = 22;

  @override
  Widget build(BuildContext context) {
    final perHour = List<int>.filled(_to - _from, 0);
    for (final booking in bookings) {
      final start = math.max(_from, booking.startLocal.hour);
      final end = math.min(_to, booking.endLocal.hour + (booking.endLocal.minute > 0 ? 1 : 0));
      for (var h = start; h < end; h++) {
        perHour[h - _from]++;
      }
    }
    final peak = perHour.fold<int>(0, math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < perHour.length; i++)
              Expanded(
                child: Container(
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: perHour[i] == 0
                        ? AppColors.glassBorder
                        : AppColors.cyan.withValues(alpha: .25 + .6 * (perHour[i] / math.max(peak, 1))),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('6am', style: AppTextStyles.caption.copyWith(fontSize: 9)),
            Text('2pm', style: AppTextStyles.caption.copyWith(fontSize: 9)),
            Text('10pm', style: AppTextStyles.caption.copyWith(fontSize: 9)),
          ],
        ),
      ],
    );
  }
}
