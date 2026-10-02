import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/disruption_models.dart';
import 'package:sme_mobile/models/resource_model.dart';
import 'package:sme_mobile/providers/owner_providers.dart';
import 'package:sme_mobile/screens/owner/automation/disruption_recovery_screen.dart';
import 'package:sme_mobile/services/disruption_repository.dart';
import 'package:sme_mobile/widgets/ui/neon_button.dart';

/// The Disruption Recovery Copilot on the phone.
///
/// Two layers are covered: the trace parser, because the trace is produced by
/// a Python service and stored as free JSON, so a plan that failed part-way is
/// a normal case rather than an exotic one; and the screen, because what has
/// to be true there is that the evidence is on screen before the approve
/// button is.
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

Map<String, dynamic> _trace() => {
      'status': 'AwaitingApproval',
      'business_type': 'Tourism',
      'impact': {
        'resource_name': 'Dawn Departure',
        'resource_noun': 'vessel or vehicle',
        'affected': [
          {
            'booking_id': 'b1',
            'customer_name': 'Dilani Fernando',
            'starts_at': '2026-10-03T01:00:00Z',
            'ends_at': '2026-10-03T05:00:00Z',
            'attendee_count': 6,
            'deposit_paid': true,
            'priority': 0.9,
            'priority_reason': 'deposit paid, party of six',
          }
        ],
        'total_attendees': 6,
        'revenue_at_risk': 41000,
        'warnings': <String>[],
      },
      'action': {
        'proposals': [
          {
            'booking_id': 'b1',
            'customer_name': 'Dilani Fernando',
            'kind': 'MoveResource',
            'original_starts_at': '2026-10-03T01:00:00Z',
            'original_ends_at': '2026-10-03T05:00:00Z',
            'proposed_resource_id': 'r2',
            'proposed_resource_name': 'Morning Cruise',
            'proposed_starts_at': '2026-10-03T04:30:00Z',
            'proposed_ends_at': '2026-10-03T08:30:00Z',
            'explanation': 'Same day, on the Morning Cruise.',
            'confidence': 0.9,
          }
        ],
        'unresolved': <String>[],
        'notes': <String>[],
      },
      'safety': {
        'is_allowed': true,
        'requires_human_approval': true,
        'rejection_reason': null,
        'checks': [
          {'rule': 'no_conflict', 'passed': true, 'detail': 'Every destination slot is free.'},
          {'rule': 'equal_capacity', 'passed': false, 'detail': '1 vessel has a smaller capacity.'},
        ],
        'rejected_booking_ids': <String>[],
      },
      'warnings': <String>[],
      'error': null,
      'agent_steps': [
        {'agent': 'DisruptionPlannerAgent', 'duration_ms': 9722, 'ok': true, 'error': null}
      ],
      'tool_calls': [
        {'tool': 'list_affected_bookings', 'agent': 'ImpactAnalysisAgent', 'duration_ms': 4, 'success': true}
      ],
    };

Map<String, dynamic> _workflow({String status = 'AwaitingApproval'}) => {
      'id': 'w1',
      'objective': 'Engine fault on Dawn Departure',
      'status': status,
      'approvalStatus': status == 'AwaitingApproval' ? 'Pending' : 'Approved',
      'finalOutcome': '1 booking(s) affected, 1 with a proposed move.',
      'errorLog': null,
      'createdAt': '2026-10-02T06:00:00Z',
      // The list endpoint sends the trace as a JSON *string*, not an object.
      'trace': jsonEncode(_trace()),
    };

Widget _host(Dio dio) {
  return ProviderScope(
    overrides: [
      disruptionRepositoryProvider.overrideWithValue(DisruptionRepository(dio)),
      ownerResourcesProvider.overrideWith((ref) async => const [
            Resource(
              id: 'r1',
              tenantId: 't1',
              name: 'Dawn Departure',
              category: 'vessel',
              status: 'Active',
            ),
          ]),
      // Standing in for a signed-in manager. Every owner provider is scoped to
      // the tenant and skips its fetch when there is none, so overriding this
      // one is what makes the screen fetch at all.
      ownerTenantIdProvider.overrideWithValue('t1'),
    ],
    child: const MaterialApp(home: DisruptionRecoveryScreen()),
  );
}

void main() {
  group('DisruptionTrace parsing', () {
    test('reads the impact, proposals and safety checks', () {
      final trace = DisruptionTrace.fromJson(_trace());

      expect(trace.impact!.resourceName, 'Dawn Departure');
      expect(trace.impact!.resourceNoun, 'vessel or vehicle');
      expect(trace.impact!.totalAttendees, 6);
      expect(trace.proposals.single.kind, RecoveryKind.moveResource);
      expect(trace.proposals.single.proposedResourceName, 'Morning Cruise');
      expect(trace.safety!.failedCount, 1);
      expect(trace.toolCallCount, 1);
    });

    test('an unknown recovery kind is "no option found", not a crash', () {
      final proposal = RecoveryProposal.fromJson({'kind': 'SomethingNew', 'booking_id': 'b1'});
      expect(proposal.kind, RecoveryKind.noOptionFound);
      expect(proposal.kind.isActionable, isFalse);
    });

    test('a plan that failed before the later agents still parses', () {
      // What the service returns when an agent throws part-way: the sections
      // that never ran are simply absent.
      final trace = DisruptionTrace.fromJson({
        'status': 'Failed',
        'business_type': 'Tourism',
        'error': "'str' object has no attribute 'get'",
        'warnings': <String>[],
        'agent_steps': <dynamic>[],
      });

      expect(trace.impact, isNull);
      expect(trace.safety, isNull);
      expect(trace.proposals, isEmpty);
      expect(trace.error, isNotNull);
      expect(trace.resourceNoun, 'resource');
    });

    test('the trace is accepted as a string or an object', () {
      expect(DisruptionWorkflow.parseTrace(_trace()), isNotNull);
      expect(DisruptionWorkflow.parseTrace(jsonEncode(_trace())), isNotNull);
    });

    test('an unreadable trace does not take the workflow down with it', () {
      final workflow = DisruptionWorkflow.fromJson({
        'id': 'w1',
        'objective': 'Engine fault',
        'status': 'Failed',
        'trace': 'not json at all',
      });

      expect(workflow.id, 'w1');
      expect(workflow.trace, isNull);
    });
  });

  group('error messages', () {
    DioException dio(int status) => DioException(
          requestOptions: RequestOptions(path: '/agent/disruption/plan'),
          response: Response(
            requestOptions: RequestOptions(path: '/agent/disruption/plan'),
            statusCode: status,
            data: {'message': 'server said so'},
          ),
        );

    test('404 explains the server lacks the feature rather than echoing Not Found', () {
      expect(disruptionErrorMessage(dio(404), 'fallback'), contains('does not have Disruption Recovery'));
    });

    test('402 points at the plan, not at the operator', () {
      expect(disruptionErrorMessage(dio(402), 'fallback'), contains('AI features'));
    });

    test('anything else uses the server message, which is already written for this reader', () {
      expect(disruptionErrorMessage(dio(400), 'fallback'), 'server said so');
    });
  });

  group('DisruptionRecoveryScreen', () {
    late Dio dio;
    late _Api api;

    void serve((int, Object) Function(RequestOptions) answer) {
      api = _Api(answer);
      dio = Dio(BaseOptions(baseUrl: 'http://api.test/api'))..httpClientAdapter = api;
    }

    /// A roomy, deliberately tall viewport.
    ///
    /// Height matters because the plans live in a lazy ListView: at the 600px
    /// default the cards under test are never built, and the failure then
    /// reads as "the data did not load" when it is only off-screen. Width is
    /// generous because these tests are about behaviour — what is sent, what
    /// is shown, what stays disabled — and a cramped surface makes them fail
    /// on StatGrid's tile proportions instead. Layout across real phone sizes
    /// is covered separately, in unify_login_screen_test.dart's pattern.
    Future<void> pumpScreen(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(600, 2600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(dio));
      await tester.pumpAndSettle();
    }

    testWidgets('shows who is affected and what is proposed for them', (tester) async {
      serve((_) => (200, [_workflow()]));
      await pumpScreen(tester);

      expect(find.text('Engine fault on Dawn Departure'), findsOneWidget);
      expect(find.textContaining('Dilani Fernando'), findsWidgets);
      expect(find.textContaining('Same time, different resource'), findsOneWidget);
      expect(find.textContaining('6 people'), findsOneWidget);
    });

    testWidgets('shows every safety check, including the ones that failed', (tester) async {
      serve((_) => (200, [_workflow()]));
      await pumpScreen(tester);

      expect(find.text('Every destination slot is free.'), findsOneWidget);
      expect(find.text('1 vessel has a smaller capacity.'), findsOneWidget);
    });

    testWidgets('will not plan without a resource', (tester) async {
      serve((_) => (200, [_workflow()]));
      await pumpScreen(tester);

      await tester.tap(find.text('Plan recovery'));
      await tester.pumpAndSettle();

      expect(find.text('Choose the resource that is unavailable.'), findsOneWidget);
      expect(api.requests.where((r) => r.path.contains('/plan')), isEmpty);
    });

    testWidgets('will not plan without a description', (tester) async {
      serve((_) => (200, [_workflow()]));
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('disruption-resource')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dawn Departure').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Plan recovery'));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least 3 characters'), findsOneWidget);
      expect(api.requests.where((r) => r.path.contains('/plan')), isEmpty);
    });

    testWidgets('sends the outage and reports the planned status', (tester) async {
      serve((options) => options.path.contains('/plan')
          ? (200, {'workflowId': 'w2', 'status': 'AwaitingApproval', 'trace': _trace()})
          : (200, [_workflow()]));
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('disruption-resource')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dawn Departure').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('disruption-objective')), 'Engine fault');
      await tester.tap(find.text('Plan recovery'));
      await tester.pumpAndSettle();

      final planned = api.requests.firstWhere((r) => r.path.contains('/plan'));
      final body = planned.data as Map<String, dynamic>;
      expect(body['objective'], 'Engine fault');
      expect(body['resourceId'], 'r1');
      // The window must be a plain date, not an instant: the server takes DateOnly.
      expect(body['dateFrom'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(find.textContaining('Recovery planned'), findsOneWidget);
    });

    testWidgets('applies the recovery and reports the outcome', (tester) async {
      serve((options) => options.path.contains('/apply')
          ? (
              200,
              {
                'workflowId': 'w1',
                'moved': [
                  {'bookingId': 'b1'}
                ],
                'skipped': <dynamic>[],
                'outcome': '1 booking(s) moved, 0 skipped.',
              }
            )
          : (200, [_workflow()]));
      await pumpScreen(tester);

      await tester.tap(find.text('Approve and move them'));
      await tester.pumpAndSettle();

      expect(api.requests.any((r) => r.path.contains('/agent/disruption/w1/apply')), isTrue);
      expect(find.text('1 booking(s) moved, 0 skipped.'), findsOneWidget);
    });

    testWidgets('will not reject without a reason', (tester) async {
      serve((_) => (200, [_workflow()]));
      await pumpScreen(tester);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      // The sheet is open, but its confirm button stays disabled until a
      // reason is typed, so nothing can reach the server.
      expect(find.text('Reject this recovery'), findsOneWidget);
      final confirm = tester.widget<NeonButton>(
        find.widgetWithText(NeonButton, 'Reject'),
      );
      expect(confirm.onPressed, isNull);

      await tester.tap(find.widgetWithText(NeonButton, 'Reject'));
      await tester.pumpAndSettle();
      expect(api.requests.where((r) => r.path.contains('/reject')), isEmpty);
    });

    testWidgets('sends the reason when rejecting', (tester) async {
      serve((options) => options.path.contains('/reject')
          ? (200, {'outcome': 'Rejected: I will call them. Nothing was moved.'})
          : (200, [_workflow()]));
      await pumpScreen(tester);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).last, 'I will call them');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InkWell, 'Reject').last);
      await tester.pumpAndSettle();

      final rejected = api.requests.firstWhere((r) => r.path.contains('/reject'));
      expect((rejected.data as Map<String, dynamic>)['reason'], 'I will call them');
      expect(find.textContaining('Nothing was moved'), findsOneWidget);
    });

    testWidgets('offers no decision buttons once a plan is completed', (tester) async {
      serve((_) => (200, [_workflow(status: 'Completed')]));
      await pumpScreen(tester);

      expect(find.text('Approve and move them'), findsNothing);
    });

    testWidgets('shows an empty state when there is nothing to review', (tester) async {
      serve((_) => (200, <dynamic>[]));
      await pumpScreen(tester);

      expect(find.text('No recovery plans yet'), findsOneWidget);
    });

    testWidgets('a backend without the feature says so plainly', (tester) async {
      serve((_) => (404, {'detail': 'Not Found'}));
      await pumpScreen(tester);

      expect(find.textContaining('does not have Disruption Recovery'), findsOneWidget);
    });
  });
}
