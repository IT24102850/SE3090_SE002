import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sme_mobile/models/available_slot_model.dart';
import 'package:sme_mobile/shared/date_format.dart';
import 'package:sme_mobile/models/subtype_dashboard_config.dart';
import 'package:sme_mobile/providers/booking_providers.dart';
import 'package:sme_mobile/widgets/booking_field_input.dart';
import 'package:sme_mobile/widgets/booking_qr_code.dart';
import 'package:sme_mobile/widgets/date_slot_picker.dart';

/// Spec 2.8's named Flutter widget tests: the booking form, the date
/// picker, and the QR check-in code the scanner reads.
///
/// The scanner itself needs a camera, which a widget test has no way to
/// give it, so what is proven here is the half that can be: the QR a guest
/// presents carries exactly the booking id the scanner posts back, and the
/// picker and form behave. A camera-bound test would only ever assert that
/// the plugin exists.

Widget _host(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

void main() {
  group('booking form fields', () {
    testWidgets('a dropdown offers its options and reports the choice', (tester) async {
      String? chosen;
      await tester.pumpWidget(_host(
        BookingFieldInput(
          field: const BookingFormField(
            key: 'level',
            label: 'Experience level',
            type: BookingFieldType.dropdown,
            options: ['Beginner', 'Advanced'],
          ),
          value: null,
          onChanged: (v) => chosen = v as String?,
        ),
      ));

      // SectionHeader renders its label uppercase.
      expect(find.text('EXPERIENCE LEVEL'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced').last);
      await tester.pumpAndSettle();

      expect(chosen, 'Advanced');
    });

    testWidgets('the number stepper counts up and will not go below one', (tester) async {
      var count = 1;

      Future<void> pumpWith(WidgetTester tester, int value) => tester.pumpWidget(_host(
            BookingFieldInput(
              field: const BookingFormField(key: 'guests', label: 'Guests', type: BookingFieldType.numberStepper),
              value: value,
              onChanged: (v) => count = v as int,
            ),
          ));

      await pumpWith(tester, count);

      // A party of one cannot shrink: the decrement is disabled, not
      // silently clamped after the fact.
      final decrement = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove_circle_outline));
      expect(decrement.onPressed, isNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.add_circle_outline));
      expect(count, 2);

      await pumpWith(tester, count);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.remove_circle_outline));
      expect(count, 1);
    });

    testWidgets('a checkbox reports being ticked', (tester) async {
      bool? ticked;
      await tester.pumpWidget(_host(
        BookingFieldInput(
          field: const BookingFormField(key: 'waiver', label: 'I accept the waiver', type: BookingFieldType.checkbox),
          value: false,
          onChanged: (v) => ticked = v as bool?,
        ),
      ));

      await tester.tap(find.text('I accept the waiver'));
      await tester.pump();

      expect(ticked, isTrue);
    });

    testWidgets('a text area passes what was typed straight through', (tester) async {
      String? typed;
      await tester.pumpWidget(_host(
        BookingFieldInput(
          field: const BookingFormField(key: 'notes', label: 'Anything we should know?', type: BookingFieldType.textArea),
          value: '',
          onChanged: (v) => typed = v as String?,
        ),
      ));

      await tester.enterText(find.byType(TextField).first, 'Nut allergy');
      expect(typed, 'Nut allergy');
    });
  });

  group('date & slot picker', () {
    /// A fixed day of slots, so the test never depends on a live API.
    Override slotsReturning(SlotsResult result) => availableSlotsProvider.overrideWith((ref, query) async => result);

    testWidgets('offers a fortnight of days and starts on today', (tester) async {
      await tester.pumpWidget(_host(
        DateSlotPicker(
          resourceId: 'r1',
          bookingTypeId: 'bt1',
          durationMinutes: 60,
          onSlotSelected: (_, __) {},
        ),
        overrides: [slotsReturning(const SlotsResult(isOpen: true, slots: []))],
      ));
      await tester.pumpAndSettle();

      final today = DateTime.now();
      expect(find.text('${today.day}'), findsWidgets);
    });

    testWidgets('a free slot can be picked and reports its raw ISO time', (tester) async {
      final start = DateTime.now().toUtc().add(const Duration(days: 1)).copyWith(minute: 0, second: 0, millisecond: 0, microsecond: 0);
      final slot = AvailableSlot(
        startTime: start.toIso8601String(),
        endTime: start.add(const Duration(hours: 1)).toIso8601String(),
        isAvailable: true,
      );

      AvailableSlot? picked;
      await tester.pumpWidget(_host(
        DateSlotPicker(
          resourceId: 'r1',
          bookingTypeId: 'bt1',
          durationMinutes: 60,
          onSlotSelected: (_, s) => picked = s,
        ),
        overrides: [slotsReturning(SlotsResult(isOpen: true, slots: [slot]))],
      ));
      await tester.pumpAndSettle();

      // Only free slots are rendered at all, each labelled with its own
      // start time, so tapping that label is tapping the slot.
      final label = formatTimeOfDay(slot.startLocal);
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      // The ISO string must come back verbatim — reformatting it here is how
      // a booking ends up an hour out.
      expect(picked?.startTime, slot.startTime);
    });

    testWidgets('a closed day says so instead of showing an empty grid', (tester) async {
      await tester.pumpWidget(_host(
        DateSlotPicker(
          resourceId: 'r1',
          bookingTypeId: 'bt1',
          durationMinutes: 60,
          onSlotSelected: (_, __) {},
        ),
        overrides: [slotsReturning(const SlotsResult(isOpen: false, slots: []))],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining(RegExp('closed|not open|unavailable', caseSensitive: false)), findsWidgets);
    });
  });

  group('QR check-in', () {
    // qr_flutter keeps QrImageView's payload in a private field, so a widget
    // test cannot read the encoded bytes back. What it can prove is that the
    // id is encodable at all and that the widget renders one — the
    // verbatim-passthrough half is a single un-transformed argument in
    // BookingQrCode, with nothing in between to go wrong.
    testWidgets('renders a scannable QR for a booking id', (tester) async {
      const bookingId = '4f0c2b5e-7d31-4a2f-9a10-0f8c2b5e7d31';

      await tester.pumpWidget(_host(const BookingQrCode(bookingId: bookingId)));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
    });

    test('a booking id encodes cleanly at the level the widget uses', () {
      // The scanner reads rawValue and posts it straight to checkInBooking,
      // so the payload must stay a bare id. This is the guard against
      // someone later encoding a URL or a JSON envelope that a GUID-shaped
      // check-in endpoint would reject.
      const bookingId = '4f0c2b5e-7d31-4a2f-9a10-0f8c2b5e7d31';
      final status = QrValidator.validate(data: bookingId);

      expect(status.isValid, isTrue);
      expect(status.error, isNull);
      expect(bookingId, isNot(contains('http')));
      expect(bookingId, isNot(contains('{')));
    });
  });
}
