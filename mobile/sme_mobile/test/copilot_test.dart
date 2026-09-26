import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/agent_workflow_model.dart';
import 'package:sme_mobile/models/copilot_trace.dart';
import 'package:sme_mobile/screens/owner/automation/copilot_widgets.dart';

/// The Schedule Copilot on the phone: it reads the same stored trace as the
/// web, and offers only the decisions the backend will accept.

Map<String, dynamic> _trace({String status = 'Completed', List<Map<String, dynamic>>? checks, String? error}) => {
      'workflow_type': 'schedule-copilot',
      'status': status,
      'objective': 'Fit 2 follow-ups',
      'error': error,
      'planner': {
        'plan': [
          {'order': 1, 'action': 'Rank resources', 'assigned_agent': 'DomainAnalysisAgent', 'description': 'Rank.', 'tools': ['check_staff_schedule']},
          {'order': 2, 'action': 'Build schedule', 'assigned_agent': 'ActionToolAgent', 'description': 'Slots.', 'tools': []},
          {'order': 3, 'action': 'Validate', 'assigned_agent': 'ValidationSafetyAgent', 'description': 'Gate.', 'tools': []},
        ],
        'predicted_conflicts': [
          {'kind': 'capacity_exceeded', 'description': 'Tight week.', 'likelihood': 0.4},
        ],
        'confidence_score': 0.82,
        'used_fallback': false,
        'summary': 'Two morning follow-ups.',
        'intent': {'priority_rules': ['prefer_mornings'], 'weekdays': [3], 'time_window': 'morning'},
      },
      'action': {
        'proposals': [
          {'resource_name': 'Dr. Perera', 'start': '2030-01-07T09:00:00Z', 'end': '2030-01-07T10:00:00Z', 'score': 61, 'reasons': ['Matches the time-of-day preference.']},
          {'resource_name': 'Dr. Perera', 'start': '2030-01-07T10:00:00Z', 'end': '2030-01-07T11:00:00Z', 'score': 60, 'reasons': []},
        ],
        'skipped': [],
      },
      'safety': {
        'approval_reasons': status == 'AwaitingApproval' ? ['Affects 24 bookings (threshold 20).'] : [],
        'rejection_reason': status == 'Rejected' ? 'Double-booking: Dr. Perera Mon 09:00 overlaps 09:30' : null,
        'checks': checks ??
            [
              {'rule': 'no_double_booking', 'status': 'pass', 'detail': 'No clashes.'},
              {'rule': 'daily_hours', 'status': 'pass', 'detail': 'Within cap.'},
            ],
      },
      'metrics': {
        'requested': 2, 'proposed': 2, 'coverage_pct': 100, 'resources_used': 1, 'days_used': 1,
        'expected_no_shows': 0.2, 'estimated_revenue': 90, 'currency': 'USD',
        'utilisation_before_pct': 25, 'utilisation_after_pct': 30,
      },
      'warnings': ['Limited to Thursday as the objective asked.'],
      'agent_steps': [
        {'agent': 'PlannerAgent', 'duration_ms': 6100, 'ok': true},
        {'agent': 'DomainAnalysisAgent', 'duration_ms': 120, 'ok': true},
        {'agent': 'ActionToolAgent', 'duration_ms': 340, 'ok': true},
        {'agent': 'ValidationSafetyAgent', 'duration_ms': 80, 'ok': true},
      ],
      'tool_calls': [
        {'tool': 'check_staff_schedule', 'agent': 'DomainAnalysisAgent', 'duration_ms': 12, 'success': true},
      ],
      'llm_calls': [
        {'model': 'gemini-3.5-flash', 'attempt': 1, 'duration_ms': 900, 'ok': false},
        {'model': 'gemini-flash-lite-latest', 'attempt': 1, 'duration_ms': 5200, 'ok': true},
      ],
    };

AgentWorkflow _workflow({required String status, String approval = 'NotRequired', Map<String, dynamic>? trace}) =>
    AgentWorkflow.fromJson({
      'id': 'wf-1',
      'objective': 'Fit 2 follow-ups',
      'status': status,
      'approvalStatus': approval,
      'currentStep': 0,
      'planJson': jsonEncode({
        'Steps': [
          {'Agent': 'ActionToolAgent', 'Action': 'CreateBooking', 'Tool': 'bookings.create',
           'Parameters': {'resourceId': 'r1', 'resourceName': 'Dr. Perera', 'startTime': '2030-01-07T09:00:00Z'}},
        ],
        'EstimatedRevenueImpact': 90,
      }),
      'toolResultsJson': jsonEncode(trace ?? _trace()),
    });

Future<void> _pump(WidgetTester tester, AgentWorkflow w) async {
  await tester.binding.setSurfaceSize(const Size(430, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CopilotResultView(workflow: w, trace: w.copilot!)))),
  ));
  await tester.pump();
}

void main() {
  group('models', () {
    test('a plan serialised in PascalCase still yields its steps', () {
      // Regression: the model read only `steps`, so every scheduling plan
      // from ASP.NET Core (which writes `Steps`) showed "0 steps".
      final w = _workflow(status: 'Approved');
      expect(w.steps, hasLength(1));
      expect(w.steps.single['resourceName'], 'Dr. Perera');
      expect(w.steps.single['action'], 'CreateBooking');
      expect(w.estimatedRevenueImpact, 90);
    });

    test('the Copilot trace is parsed from the stored workflow', () {
      final t = _workflow(status: 'Approved').copilot!;
      expect(t.planner!.confidence, 0.82);
      expect(t.planner!.plan.last.agent, 'ValidationSafetyAgent');
      expect(t.planner!.weekdays, [3]);
      expect(t.proposals, hasLength(2));
      expect(t.checksPassed, 2);
      expect(t.llmCalls.where((c) => !c.ok), hasLength(1));
    });

    test('anything that is not a Copilot trace is ignored, not crashed on', () {
      expect(CopilotTrace.tryParse('{"workflowType":"booking"}'), isNull);
      expect(CopilotTrace.tryParse('not json'), isNull);
      expect(CopilotTrace.tryParse(null), isNull);
    });
  });

  group('CopilotResultView', () {
    testWidgets('a plan that passed the gate can be applied, not approved', (tester) async {
      await _pump(tester, _workflow(status: 'Approved'));

      expect(find.text('Ready to apply'), findsOneWidget);
      expect(find.text('Apply 2'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('82%'), findsOneWidget);
      expect(find.text('2/2 passed'), findsOneWidget);
    });

    testWidgets('an escalated plan asks for a decision and says why', (tester) async {
      await _pump(tester, _workflow(status: 'AwaitingApproval', approval: 'Pending', trace: _trace(status: 'AwaitingApproval')));

      expect(find.text('Needs your approval'), findsOneWidget);
      expect(find.textContaining('Affects 24 bookings'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Apply 2'), findsNothing);
    });

    testWidgets('a plan the safety gate returned offers no approve or apply', (tester) async {
      final rejected = _trace(status: 'Rejected', checks: [
        {'rule': 'no_double_booking', 'status': 'fail', 'detail': 'Double-booking.'},
      ]);
      await _pump(tester, _workflow(status: 'Rejected', trace: rejected));

      expect(find.text('Returned for revision'), findsOneWidget);
      expect(find.textContaining('Double-booking: Dr. Perera'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.textContaining('Apply'), findsNothing);
      expect(find.text('0/1 passed'), findsOneWidget);
    });

    testWidgets('every agent shows its measured time', (tester) async {
      await _pump(tester, _workflow(status: 'Approved'));
      expect(find.text('6.1s'), findsOneWidget);
      expect(find.text('0.12s'), findsOneWidget);
    });
  });
}
