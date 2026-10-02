import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/booking_event_model.dart';
import 'package:sme_mobile/providers/owner_providers.dart';
import 'package:sme_mobile/screens/owner/scheduling/booking_history_timeline.dart';
import 'package:sme_mobile/services/owner_repository.dart';

/// A booking's audit trail on the phone. The trail is evidence, so what
/// matters is that each row says what changed, when, and who did it — and
/// that a background service is named as such rather than left blank.
class _Api implements HttpClientAdapter {
  _Api(this.answer);
  final (int, Object) Function(RequestOptions) answer;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(options);
    final (status, body) = answer(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Widget _host(Dio dio) => ProviderScope(
      overrides: [
        ownerRepositoryProvider.overrideWithValue(OwnerRepository(dio)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: BookingHistoryTimeline(bookingId: 'b1')),
        ),
      ),
    );

void main() {
  group('BookingEvent', () {
    test('names a background service rather than leaving the actor blank', () {
      final event = BookingEvent.fromJson({
        'id': 'e1',
        'type': 'StatusChanged',
        'actorName': null,
        'actorRole': 'System',
      });
      expect(event.actor, 'System');
    });

    test('shows the person with their role', () {
      final event = BookingEvent.fromJson({
        'id': 'e1',
        'type': 'StatusChanged',
        'actorName': 'Nihal Nandana',
        'actorRole': 'Manager',
      });
      expect(event.actor, 'Nihal Nandana (Manager)');
    });

    test('an actor the server could not resolve is Unknown, not empty', () {
      expect(BookingEvent.fromJson({'id': 'e1', 'type': 'Created'}).actor, 'Unknown');
    });
  });

  group('BookingHistoryTimeline', () {
    Dio serving((int, Object) Function(RequestOptions) answer) =>
        Dio(BaseOptions(baseUrl: 'http://api.test/api'))..httpClientAdapter = _Api(answer);

    testWidgets('describes each kind of change in the operator\'s words', (tester) async {
      final dio = serving((_) => (
            200,
            [
              {
                'id': 'e1',
                'type': 'Created',
                'from': null,
                'to': 'Pending',
                'actorName': 'Nihal Nandana',
                'actorRole': 'Manager',
                'reason': null,
                'at': '2026-10-01T04:00:00Z',
              },
              {
                'id': 'e2',
                'type': 'StatusChanged',
                'from': 'Pending',
                'to': 'Confirmed',
                'actorName': null,
                'actorRole': 'System',
                'reason': 'Deposit received',
                'at': '2026-10-01T05:00:00Z',
              },
              {
                'id': 'e3',
                'type': 'ResourceChanged',
                'from': 'Dawn Departure',
                'to': 'Morning Cruise',
                'actorName': 'Nihal Nandana',
                'actorRole': 'Manager',
                'reason': null,
                'at': '2026-10-02T06:00:00Z',
              },
            ]
          ));

      await tester.pumpWidget(_host(dio));
      await tester.pumpAndSettle();

      expect(find.text('Booking created as Pending'), findsOneWidget);
      expect(find.text('Status changed from Pending to Confirmed'), findsOneWidget);
      expect(find.text('Reassigned from Dawn Departure to Morning Cruise'), findsOneWidget);
      expect(find.textContaining('by System'), findsOneWidget);
      expect(find.text('Reason: Deposit received'), findsOneWidget);
    });

    testWidgets('renders a reschedule as a readable window', (tester) async {
      final dio = serving((_) => (
            200,
            [
              {
                'id': 'e1',
                'type': 'Rescheduled',
                // The server stores a reschedule as "<start>/<end>".
                'from': '2026-10-03T01:00:00Z/2026-10-03T05:00:00Z',
                'to': '2026-10-04T01:00:00Z/2026-10-04T05:00:00Z',
                'actorName': 'Nihal Nandana',
                'actorRole': 'Manager',
                'at': '2026-10-02T06:00:00Z',
              }
            ]
          ));

      await tester.pumpWidget(_host(dio));
      await tester.pumpAndSettle();

      final row = tester.widget<Text>(find.textContaining('Moved from'));
      expect(row.data, contains('–'));
      expect(row.data, isNot(contains('/')));
    });

    testWidgets('an empty trail says so rather than showing nothing', (tester) async {
      await tester.pumpWidget(_host(serving((_) => (200, <dynamic>[]))));
      await tester.pumpAndSettle();

      expect(find.text('No changes recorded yet.'), findsOneWidget);
    });

    testWidgets('a failed load is reported, not silently empty', (tester) async {
      await tester.pumpWidget(_host(serving((_) => (500, {'message': 'boom'}))));
      await tester.pumpAndSettle();

      expect(find.text('History could not be loaded.'), findsOneWidget);
    });

    testWidgets('asks for the history of the booking it was given', (tester) async {
      final api = _Api((_) => (200, <dynamic>[]));
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test/api'))..httpClientAdapter = api;

      await tester.pumpWidget(_host(dio));
      await tester.pumpAndSettle();

      expect(api.requests.single.path, '/bookings/b1/history');
    });
  });
}
