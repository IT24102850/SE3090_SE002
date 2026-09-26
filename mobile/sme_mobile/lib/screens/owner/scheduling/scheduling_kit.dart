import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/booking_model.dart';
import '../../../shared/date_format.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

/// The visual language the scheduling screens share.
///
/// Three ideas run through it:
///
/// * **One status system.** A booking's colour, icon and wording are decided
///   once, here, so Confirmed never looks like one thing on the timeline and
///   another in a list. Status is also a *progression*, which is what lets a
///   detail sheet offer the single obvious next step instead of nine equal
///   buttons.
/// * **Show the shape of the day.** A schedule laid out against time is read
///   in a glance; the same bookings as rows are read one at a time. The
///   timeline, the now-line and the week strip's density dots all exist to
///   make load pre-attentive.
/// * **Calm surfaces, loud signal.** The canvas stays dark and quiet so the
///   only saturated things on screen are the state of the business - a
///   conflict, a booking in progress, a day that is full.

// ─────────────────────────────────────────────────────────────────────────
// Status
// ─────────────────────────────────────────────────────────────────────────

/// Everything a screen needs to know about one booking status.
class ScheduleStatus {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  /// Where it sits on the journey from booked to done, or -1 for the ways a
  /// booking can end early. The timeline uses it to dim what is finished and
  /// the detail sheet uses it to pick the primary action.
  final int step;

  const ScheduleStatus(this.value, this.label, this.icon, this.color, this.step);

  bool get isOpen => step >= 0 && step < 4;
  bool get isDone => step >= 4;
  bool get isDropped => step < 0;

  static const _all = <ScheduleStatus>[
    ScheduleStatus('Pending', 'Awaiting approval', Icons.hourglass_top_rounded, AppColors.warning, 0),
    ScheduleStatus('Confirmed', 'Confirmed', Icons.event_available_rounded, AppColors.cyan, 1),
    ScheduleStatus('CheckedIn', 'Checked in', Icons.how_to_reg_rounded, AppColors.electricBlue, 2),
    ScheduleStatus('InProgress', 'In progress', Icons.play_circle_fill_rounded, AppColors.violet, 3),
    ScheduleStatus('Completed', 'Completed', Icons.task_alt_rounded, AppColors.success, 4),
    ScheduleStatus('Cancelled', 'Cancelled', Icons.event_busy_rounded, AppColors.textMuted, -1),
    ScheduleStatus('Rejected', 'Declined', Icons.block_rounded, AppColors.error, -1),
    ScheduleStatus('NoShow', 'No-show', Icons.person_off_rounded, AppColors.error, -1),
    ScheduleStatus('WeatherCancelled', 'Off — weather', Icons.thunderstorm_rounded, AppColors.textMuted, -1),
  ];

  static ScheduleStatus of(String value) => _all.firstWhere(
        (s) => s.value == value,
        orElse: () => ScheduleStatus(value, value, Icons.circle_outlined, AppColors.textMuted, 0),
      );

  /// The statuses a desk filters by, in the order a booking travels.
  static List<ScheduleStatus> get filterable => _all;
}

/// A status as a small pill. Tinted rather than filled so a list of them
/// stays calm; the icon carries the meaning for anyone who cannot rely on
/// the hue alone.
class StatusPill extends StatelessWidget {
  final String status;
  final bool compact;

  const StatusPill({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = ScheduleStatus.of(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: s.color.withValues(alpha: .38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: compact ? 11 : 13, color: s.color),
          SizedBox(width: compact ? 4 : 6),
          Text(
            s.label,
            style: AppTextStyles.caption.copyWith(
              color: s.color,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 10 : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Surfaces
// ─────────────────────────────────────────────────────────────────────────

/// A wide hero band for the top of a scheduling screen: a quiet gradient,
/// one headline figure and a supporting line. Gives the screen a single
/// focal point instead of four equal-weight tiles competing for attention.
class ScheduleHero extends StatelessWidget {
  final String eyebrow;
  final String headline;
  final String support;
  final Widget? trailing;
  final List<Widget> chips;
  final Color accent;

  const ScheduleHero({
    super.key,
    required this.eyebrow,
    required this.headline,
    required this.support,
    this.trailing,
    this.chips = const [],
    this.accent = AppColors.cyan,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradientFor(accent),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: accent.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      style: AppTextStyles.label.copyWith(color: accent, letterSpacing: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Text(headline, style: AppTextStyles.headlineSmall),
                    const SizedBox(height: 4),
                    Text(support, style: AppTextStyles.caption.copyWith(color: AppColors.textBody)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ],
      ),
    );
  }
}

/// A single figure inside the hero — deliberately small and flat, because
/// the hero headline is the thing that should be read first.
class HeroMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const HeroMetric({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color = AppColors.textPrimary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 7),
            Text(value, style: AppTextStyles.body.copyWith(color: color, fontWeight: FontWeight.w700)),
            const SizedBox(width: 5),
            Text(label, style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}

/// A banner for something that needs attention now — a double booking, a
/// queue of approvals. Sits above the fold and is the only red on screen.
class AlertBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color color;

  const AlertBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
    this.color = AppColors.error,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(AppRadii.row),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700, color: color)),
                Text(detail, style: AppTextStyles.caption),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

/// A segmented control. Two or three choices, one tap, current state
/// obvious — the right control for switching a view, where a dropdown hides
/// the options and chips imply multi-select.
class SegmentedSwitch<T> extends StatelessWidget {
  final List<({T value, IconData icon, String label})> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  const SegmentedSwitch({super.key, required this.segments, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          for (final segment in segments)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(segment.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: 38,
                  decoration: BoxDecoration(
                    color: segment.value == selected ? AppColors.cyan : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.control - 4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        segment.icon,
                        size: 15,
                        color: segment.value == selected ? AppColors.onPrimary : AppColors.iconSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        segment.label,
                        style: AppTextStyles.caption.copyWith(
                          color: segment.value == selected ? AppColors.onPrimary : AppColors.textBody,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// The week strip
// ─────────────────────────────────────────────────────────────────────────

/// Seven days with a density bar under each. The bar is what makes this
/// worth the space: a manager can see which day is full without opening any
/// of them.
class WeekStrip extends StatelessWidget {
  final DateTime anchor;
  final DateTime selected;
  final Map<DateTime, int> load;
  final ValueChanged<DateTime> onSelected;

  const WeekStrip({
    super.key,
    required this.anchor,
    required this.selected,
    required this.load,
    required this.onSelected,
  });

  static DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final start = dayKey(anchor);
    final days = List.generate(7, (i) => DateTime(start.year, start.month, start.day + i));
    final busiest = load.values.isEmpty ? 1 : load.values.reduce(math.max);
    final today = dayKey(DateTime.now());

    return Row(
      children: [
        for (final day in days)
          Expanded(
            child: _DayCell(
              day: day,
              count: load[dayKey(day)] ?? 0,
              busiest: busiest,
              isToday: dayKey(day) == today,
              isSelected: dayKey(day) == dayKey(selected),
              onTap: () => onSelected(day),
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final int count;
  final int busiest;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.count,
    required this.busiest,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fill = busiest <= 0 ? 0.0 : (count / busiest).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.cyan.withValues(alpha: .16) : AppColors.glassFill,
          borderRadius: BorderRadius.circular(AppRadii.row),
          border: Border.all(
            color: isSelected
                ? AppColors.cyan
                : isToday
                    ? AppColors.cyan.withValues(alpha: .35)
                    : AppColors.glassBorder,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              formatWeekday(day).substring(0, 3).toUpperCase(),
              style: AppTextStyles.caption.copyWith(
                fontSize: 9,
                letterSpacing: .6,
                color: isToday ? AppColors.cyan : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${day.day}',
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.textPrimary : AppColors.textBody,
              ),
            ),
            const SizedBox(height: 6),
            // The load bar. An empty day keeps a faint track so the row does
            // not jump around as the week changes.
            Container(
              height: 3,
              width: 22,
              decoration: BoxDecoration(
                color: AppColors.glassBorder,
                borderRadius: BorderRadius.circular(2),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: count == 0 ? 0 : math.max(fill, .18),
                child: Container(
                  decoration: BoxDecoration(
                    color: fill > .75 ? AppColors.magenta : AppColors.cyan,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// The day timeline
// ─────────────────────────────────────────────────────────────────────────

/// One booking placed on the timeline.
class TimelineEntry {
  final Booking booking;
  final Color accent;
  const TimelineEntry(this.booking, this.accent);
}

/// The day laid out against an hour rail.
///
/// Bookings that overlap are placed side by side rather than stacked, which
/// is the whole point: a double-booked hour should *look* double-booked
/// before anyone reads a conflict report. A live line marks now, so "what is
/// happening this minute" needs no interpretation.
class DayTimeline extends StatelessWidget {
  final DateTime day;
  final List<TimelineEntry> entries;
  final ValueChanged<Booking> onTap;

  /// Pixels per hour. Tuned so a 30-minute booking is still a comfortable
  /// touch target (≈34 px) without a working day needing endless scrolling.
  static const hourHeight = 68.0;
  static const railWidth = 52.0;

  const DayTimeline({super.key, required this.day, required this.entries, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    // Show only the hours the day actually uses, with an hour of air either
    // side - an empty 00:00-06:00 band teaches nobody anything.
    final startHour = math.max(0, entries.map((e) => e.booking.startLocal.hour).reduce(math.min) - 1);
    final endHour = math.min(24, entries.map((e) => e.booking.endLocal.hour + 1).reduce(math.max) + 1);
    final hours = math.max(1, endHour - startHour);
    final now = DateTime.now();
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;

    final lanes = assignLanes(entries);
    final laneCount = lanes.values.isEmpty ? 1 : lanes.values.reduce(math.max) + 1;

    return LayoutBuilder(builder: (context, constraints) {
      final trackWidth = constraints.maxWidth - railWidth;
      final laneWidth = trackWidth / laneCount;

      return SizedBox(
        height: hours * hourHeight + 12,
        child: Stack(
          children: [
            // Hour rail and grid lines.
            for (var h = startHour; h < endHour; h++)
              Positioned(
                top: (h - startHour) * hourHeight,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: hourHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: railWidth,
                        child: Text(
                          _hourLabel(h),
                          style: AppTextStyles.caption.copyWith(fontSize: 10, color: AppColors.textMuted),
                        ),
                      ),
                      Expanded(child: Container(height: 1, color: AppColors.hairline)),
                    ],
                  ),
                ),
              ),

            // The bookings.
            for (final entry in entries)
              Positioned(
                top: _offsetFor(entry.booking.startLocal, startHour),
                left: railWidth + (lanes[entry.booking.id] ?? 0) * laneWidth,
                width: math.max(laneWidth - 6, 60),
                height: math.max(
                  _offsetFor(entry.booking.endLocal, startHour) - _offsetFor(entry.booking.startLocal, startHour) - 4,
                  34,
                ),
                child: _TimelineCard(entry: entry, onTap: () => onTap(entry.booking)),
              ),

            // Now.
            if (isToday && now.hour >= startHour && now.hour < endHour)
              Positioned(
                top: _offsetFor(now, startHour),
                left: 0,
                right: 0,
                child: const _NowLine(),
              ),
          ],
        ),
      );
    });
  }

  static double _offsetFor(DateTime time, int startHour) =>
      ((time.hour - startHour) + time.minute / 60) * hourHeight;

  static String _hourLabel(int hour) {
    final suffix = hour < 12 ? 'am' : 'pm';
    final display = hour % 12 == 0 ? 12 : hour % 12;
    return '$display$suffix';
  }

  /// Greedy column packing: each booking takes the first lane whose last
  /// booking has already finished. Two reservations that genuinely clash end
  /// up in different lanes and are visibly parallel — which is the whole
  /// point, so it is exercised directly by a test.
  static Map<String, int> assignLanes(List<TimelineEntry> entries) {
    final sorted = [...entries]..sort((a, b) => a.booking.startLocal.compareTo(b.booking.startLocal));
    final laneEnds = <DateTime>[];
    final lanes = <String, int>{};

    for (final entry in sorted) {
      var lane = laneEnds.indexWhere((end) => !end.isAfter(entry.booking.startLocal));
      if (lane == -1) {
        laneEnds.add(entry.booking.endLocal);
        lane = laneEnds.length - 1;
      } else {
        laneEnds[lane] = entry.booking.endLocal;
      }
      lanes[entry.booking.id] = lane;
    }
    return lanes;
  }
}

class _TimelineCard extends StatelessWidget {
  final TimelineEntry entry;
  final VoidCallback onTap;

  const _TimelineCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final booking = entry.booking;
    final status = ScheduleStatus.of(booking.status);
    // Finished and dropped bookings recede so the live day reads first.
    final opacity = status.isDone ? .62 : (status.isDropped ? .42 : 1.0);
    final accent = status.isDropped ? AppColors.textMuted : entry.accent;

    return Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.image),
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 6, 8, 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(AppRadii.image),
              border: Border.all(color: accent.withValues(alpha: .45)),
              // A left spine in the service's own colour: the fastest way to
              // tell two kinds of booking apart at a glance.
              gradient: LinearGradient(
                colors: [accent.withValues(alpha: .28), accent.withValues(alpha: .08)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: const [0, .35],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(status.icon, size: 11, color: accent),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        formatTimeOfDay(booking.startLocal),
                        maxLines: 1,
                        style: AppTextStyles.caption.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    booking.title?.isNotEmpty == true ? booking.title! : booking.bookingTypeName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary, height: 1.15),
                  ),
                ),
                Flexible(
                  child: Text(
                    booking.resourceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 9.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: DayTimeline.railWidth,
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: AppColors.magenta, borderRadius: BorderRadius.circular(4)),
              child: Text(
                'now',
                style: AppTextStyles.caption.copyWith(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        Expanded(child: Container(height: 1.6, color: AppColors.magenta)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Loading
// ─────────────────────────────────────────────────────────────────────────

/// A shimmering placeholder in the shape of the content that is coming.
/// A spinner tells you to wait; a skeleton tells you what you are waiting
/// for, and makes the wait feel shorter because the layout does not jump.
class Skeleton extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;

  const Skeleton({super.key, required this.height, this.width, this.radius = 12});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1250))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(AppColors.glassFill, AppColors.chromeFill, _controller.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// The scheduling screens' loading state: a hero block and a few rows, in
/// roughly the proportions of the real thing.
class ScheduleSkeleton extends StatelessWidget {
  const ScheduleSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: const [
        Skeleton(height: 132, radius: AppRadii.card),
        SizedBox(height: 14),
        Skeleton(height: 66, radius: AppRadii.row),
        SizedBox(height: 14),
        Skeleton(height: 44, radius: AppRadii.control),
        SizedBox(height: 16),
        Skeleton(height: 78, radius: AppRadii.row),
        SizedBox(height: 10),
        Skeleton(height: 78, radius: AppRadii.row),
        SizedBox(height: 10),
        Skeleton(height: 78, radius: AppRadii.row),
      ],
    );
  }
}

/// An empty state that offers the way out rather than only naming the
/// absence — the difference between "no bookings" and "nothing booked; here
/// is how to add one".
class ScheduleEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  const ScheduleEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.glassFill,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Icon(icon, size: 30, color: AppColors.iconSecondary),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: AppTextStyles.title),
          const SizedBox(height: 6),
          Text(detail, textAlign: TextAlign.center, style: AppTextStyles.caption),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(actionLabel!),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.cyan,
                side: const BorderSide(color: AppColors.cyan),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The grab handle every sheet in this section shares — a small affordance
/// that tells a thumb the panel can be dragged away.
class SheetGrip extends StatelessWidget {
  const SheetGrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(color: AppColors.glassBorder, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}
