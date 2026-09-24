import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/booking_model.dart';
import 'package:sme_mobile/screens/owner/scheduling/scheduling_kit.dart';
import 'package:sme_mobile/theme/app_colors.dart';

/// The two pieces of the scheduling redesign that carry real logic: the
/// status system the whole section reads its colours and next steps from,
/// and the lane packing that makes a double-booked hour *look* double-booked.

Booking _booking(String id, String start, String end, {String status = 'Confirmed'}) => Booking(
      id: id,
      tenantId: 't',
      resourceId: 'r',
      resourceName: 'Room A',
      bookingTypeId: 'bt',
      bookingTypeName: 'Class',
      colorHex: '#2563EB',
      bookingUnit: 'Slot',
      bookedBy: 'u',
      startTime: start,
      endTime: end,
      status: status,
      priority: 'Normal',
      createdAt: start,
    );

TimelineEntry _entry(Booking b) => TimelineEntry(b, AppColors.cyan);

void main() {
  group('ScheduleStatus', () {
    test('knows where each status sits on the journey', () {
      expect(ScheduleStatus.of('Pending').isOpen, isTrue);
      expect(ScheduleStatus.of('InProgress').isOpen, isTrue);
      expect(ScheduleStatus.of('Completed').isDone, isTrue);
      expect(ScheduleStatus.of('Cancelled').isDropped, isTrue);
      expect(ScheduleStatus.of('NoShow').isDropped, isTrue);
      expect(ScheduleStatus.of('Rejected').isDropped, isTrue);
    });

    test('a status travels forward through the journey', () {
      const order = ['Pending', 'Confirmed', 'CheckedIn', 'InProgress', 'Completed'];
      final steps = order.map((s) => ScheduleStatus.of(s).step).toList();
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThan(steps[i - 1]), reason: '${order[i]} should come after ${order[i - 1]}');
      }
    });

    test('an unknown status degrades instead of throwing', () {
      final unknown = ScheduleStatus.of('SomethingNew');
      expect(unknown.label, 'SomethingNew');
      expect(unknown.color, AppColors.textMuted);
    });

    test('every status carries its own icon, so colour is never the only cue', () {
      final icons = <IconData>{};
      for (final status in ScheduleStatus.filterable) {
        icons.add(status.icon);
      }
      expect(icons.length, ScheduleStatus.filterable.length);
    });
  });

  group('DayTimeline lane packing', () {
    test('bookings that do not overlap share one lane', () {
      final lanes = DayTimeline.assignLanes([
        _entry(_booking('a', '2026-09-23T09:00:00Z', '2026-09-23T10:00:00Z')),
        _entry(_booking('b', '2026-09-23T10:00:00Z', '2026-09-23T11:00:00Z')),
        _entry(_booking('c', '2026-09-23T11:00:00Z', '2026-09-23T12:00:00Z')),
      ]);
      expect(lanes.values.toSet(), {0});
    });

    test('two bookings on the same hour are placed side by side', () {
      final lanes = DayTimeline.assignLanes([
        _entry(_booking('a', '2026-09-23T09:00:00Z', '2026-09-23T10:30:00Z')),
        _entry(_booking('b', '2026-09-23T09:30:00Z', '2026-09-23T10:00:00Z')),
      ]);
      expect(lanes['a'], isNot(equals(lanes['b'])));
    });

    test('a third overlapping booking takes a third lane', () {
      final lanes = DayTimeline.assignLanes([
        _entry(_booking('a', '2026-09-23T09:00:00Z', '2026-09-23T11:00:00Z')),
        _entry(_booking('b', '2026-09-23T09:15:00Z', '2026-09-23T11:00:00Z')),
        _entry(_booking('c', '2026-09-23T09:30:00Z', '2026-09-23T11:00:00Z')),
      ]);
      expect(lanes.values.toSet(), {0, 1, 2});
    });

    test('a lane is reused once its booking has finished', () {
      final lanes = DayTimeline.assignLanes([
        _entry(_booking('a', '2026-09-23T09:00:00Z', '2026-09-23T10:00:00Z')),
        _entry(_booking('b', '2026-09-23T09:30:00Z', '2026-09-23T10:30:00Z')),
        _entry(_booking('c', '2026-09-23T10:00:00Z', '2026-09-23T11:00:00Z')),
      ]);
      // c starts exactly as a ends, so it belongs back in a's lane rather
      // than opening a third column nobody needs.
      expect(lanes['c'], equals(lanes['a']));
      expect(lanes['b'], isNot(equals(lanes['a'])));
    });

    test('input order does not change the packing', () {
      final forwards = DayTimeline.assignLanes([
        _entry(_booking('a', '2026-09-23T09:00:00Z', '2026-09-23T10:30:00Z')),
        _entry(_booking('b', '2026-09-23T09:30:00Z', '2026-09-23T10:00:00Z')),
      ]);
      final backwards = DayTimeline.assignLanes([
        _entry(_booking('b', '2026-09-23T09:30:00Z', '2026-09-23T10:00:00Z')),
        _entry(_booking('a', '2026-09-23T09:00:00Z', '2026-09-23T10:30:00Z')),
      ]);
      expect(forwards, equals(backwards));
    });
  });

  group('widgets render', () {
    testWidgets('a status pill shows its label and icon', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: StatusPill(status: 'InProgress')),
      ));
      expect(find.text('In progress'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    });

    testWidgets('the empty state offers a way out, not just an absence', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScheduleEmpty(
            icon: Icons.event_available_outlined,
            title: 'Nothing booked',
            detail: 'This day is clear.',
            actionLabel: 'Add a booking',
            onAction: () => tapped = true,
          ),
        ),
      ));
      expect(find.text('Nothing booked'), findsOneWidget);
      await tester.tap(find.text('Add a booking'));
      expect(tapped, isTrue);
    });

    testWidgets('the week strip marks the selected day and reports taps', (tester) async {
      final monday = DateTime(2026, 9, 21);
      DateTime? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WeekStrip(
            anchor: monday,
            selected: monday,
            load: {monday: 4, DateTime(2026, 9, 23): 1},
            onSelected: (d) => picked = d,
          ),
        ),
      ));
      expect(find.text('21'), findsOneWidget);
      await tester.tap(find.text('23'));
      expect(picked?.day, 23);
    });
  });
}
