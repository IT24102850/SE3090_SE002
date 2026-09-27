import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/agent_workflow_model.dart';
import '../../../models/copilot_trace.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';

/// The four agents, in pipeline order, with the colour each wears on both
/// the phone and the web Copilot.
const copilotAgents = <({String key, String label, String role, Color color})>[
  (key: 'PlannerAgent', label: 'Planner', role: 'Reads the objective, plans, delegates', color: AppColors.violet),
  (key: 'DomainAnalysisAgent', label: 'Domain Analysis', role: 'Ranks resources on hours, load, no-shows', color: AppColors.electricBlue),
  (key: 'ActionToolAgent', label: 'Action / Tool', role: 'Searches real slots, optimises', color: AppColors.cyan),
  (key: 'ValidationSafetyAgent', label: 'Validation / Safety', role: 'Business rules and approval', color: AppColors.success),
];

const copilotRuleLabels = <String, String>{
  'prefer_mornings': 'Prefer mornings',
  'prefer_afternoons': 'Prefer afternoons',
  'balance_load': 'Balance load',
  'minimise_travel': 'Minimise travel',
  'avoid_high_no_show': 'Avoid no-shows',
  'earliest_first': 'Earliest first',
  'keep_lunch_free': 'Keep lunch free',
  'cluster_same_day': 'Cluster days',
};

const _checkLabels = <String, String>{
  'proposals': 'Something to schedule',
  'schema': 'Well-formed proposals',
  'count': 'Within the requested count',
  'future': 'Nothing in the past',
  'duration': 'Within the 2-hour limit',
  'no_double_booking': 'No double-booking',
  'daily_hours': 'Daily hour cap (8h)',
  'lunch_break': 'Lunch break kept',
  'live_conflicts': 'Re-verified against live bookings',
  'coverage': 'Request coverage',
};

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The pipeline. While a run is in flight the request is one synchronous
/// call, so the highlight advances at a plausible pace and is labelled
/// "working" - it never shows a timing it does not have. With a trace, each
/// agent shows the duration the agent service measured.
class CopilotPipeline extends StatefulWidget {
  final bool running;
  final CopilotTrace? trace;
  const CopilotPipeline({super.key, this.running = false, this.trace});

  @override
  State<CopilotPipeline> createState() => _CopilotPipelineState();
}

class _CopilotPipelineState extends State<CopilotPipeline> {
  Timer? _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    if (widget.running) {
      _timer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
        if (mounted) setState(() => _tick++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = {for (final s in widget.trace?.agentSteps ?? const <CopilotAgentStep>[]) s.agent: s};
    final active = widget.running ? _tick.clamp(0, copilotAgents.length - 1) : -1;

    return Column(
      children: [
        for (var i = 0; i < copilotAgents.length; i++)
          _node(i, copilotAgents[i], steps[copilotAgents[i].key], active),
      ],
    );
  }

  Widget _node(int i, ({String key, String label, String role, Color color}) agent, CopilotAgentStep? step, int active) {
    final isActive = i == active;
    final done = widget.running ? i < active : step?.ok == true;
    final failed = !widget.running && step != null && !step.ok;
    final waiting = widget.running ? i > active : step == null;
    final status = widget.running
        ? (isActive ? 'working…' : done ? 'handed on' : 'queued')
        : failed
            ? 'stopped here'
            : step == null
                ? 'did not run'
                : '${(step.durationMs / 1000).toStringAsFixed(step.durationMs < 1000 ? 2 : 1)}s';

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: waiting ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: failed ? AppColors.error.withValues(alpha: 0.12) : AppColors.glassFill,
          border: Border.all(
            color: failed ? AppColors.error : isActive || done ? agent.color : AppColors.glassBorder,
            width: isActive ? 1.6 : 1,
          ),
          boxShadow: isActive ? [BoxShadow(color: agent.color.withValues(alpha: 0.35), blurRadius: 16)] : null,
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: agent.color, borderRadius: BorderRadius.circular(9)),
              child: isActive
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('${i + 1}', style: AppTextStyles.label.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(agent.label, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
                  Text(agent.role, style: AppTextStyles.caption),
                ],
              ),
            ),
            Text(status, style: AppTextStyles.caption.copyWith(color: failed ? AppColors.error : AppColors.textBody)),
          ],
        ),
      ),
    );
  }
}

/// A Copilot run: decision banner, numbers, plan, proposed schedule, checks
/// and trace. Offers exactly the decisions the backend accepts - nothing to
/// approve or apply on a plan the safety gate returned.
class CopilotResultView extends ConsumerStatefulWidget {
  final AgentWorkflow workflow;
  final CopilotTrace trace;
  final ValueChanged<AgentWorkflow>? onChanged;
  const CopilotResultView({super.key, required this.workflow, required this.trace, this.onChanged});

  @override
  ConsumerState<CopilotResultView> createState() => _CopilotResultViewState();
}

class _CopilotResultViewState extends ConsumerState<CopilotResultView> {
  bool _busy = false;
  bool _showTrace = false;

  Future<void> _act(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(agentWorkflowsProvider);
      ref.invalidate(ownerBookingsProvider);
      if (mounted) AppSnackBar.success(context, done);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'That did not go through.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        title: Text('Why reject it?', style: AppTextStyles.title),
        content: NeonInputField(label: 'Reason (kept in the audit trail)', controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject')),
        ],
      ),
    );
    if (ok != true) return;
    final reason = controller.text.trim().isEmpty ? 'Rejected without a reason.' : controller.text.trim();
    await _act(() => ref.read(agentRepositoryProvider).reject(widget.workflow.id, reason), 'Schedule rejected.');
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(agentRepositoryProvider).apply(widget.workflow.id);
      ref.invalidate(agentWorkflowsProvider);
      ref.invalidate(ownerBookingsProvider);
      if (mounted) {
        AppSnackBar.success(
          context,
          result.skipped > 0
              ? '${result.created} booked, ${result.skipped} skipped — those slots had gone.'
              : '${result.created} booking${result.created == 1 ? '' : 's'} created.',
        );
      }
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not apply this schedule.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ({Color color, IconData icon, String title, String body, List<String> list}) _banner() {
    final w = widget.workflow;
    final t = widget.trace;
    if (w.status == 'Completed') {
      return (color: AppColors.cyan, icon: Icons.task_alt_rounded, title: 'Applied to the schedule', body: w.finalOutcome ?? 'The bookings were created.', list: const []);
    }
    if (w.status == 'Failed' || t.status == 'Failed') {
      return (
        color: AppColors.error,
        icon: Icons.report_gmailerrorred_rounded,
        title: 'Stopped safely',
        body: 'The agents stopped before producing a plan. Nothing was booked.',
        list: [t.error ?? w.errorLog ?? 'Unknown error'],
      );
    }
    if (w.approvalStatus == 'Rejected') {
      return (color: AppColors.error, icon: Icons.pan_tool_rounded, title: 'Rejected by a manager', body: w.errorLog ?? '', list: const []);
    }
    if (t.status == 'Rejected' || w.status == 'Rejected') {
      return (
        color: AppColors.error,
        icon: Icons.undo_rounded,
        title: 'Returned for revision',
        body: 'The Validation/Safety agent found a rule this plan would break, so it was not offered for approval.',
        list: [t.rejectionReason ?? t.error ?? 'A business rule failed.'],
      );
    }
    if (w.awaitingApproval) {
      return (
        color: AppColors.warning,
        icon: Icons.pause_circle_rounded,
        title: 'Needs your approval',
        body: 'Every rule passed, but this change is high-impact, so it waits for a manager.',
        list: t.approvalReasons,
      );
    }
    return (
      color: AppColors.success,
      icon: Icons.check_circle_rounded,
      title: w.approvalStatus == 'Approved' ? 'Approved — ready to apply' : 'Ready to apply',
      body: 'Every rule passed. Nothing is booked until you apply it.',
      list: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.workflow;
    final t = widget.trace;
    final banner = _banner();
    final canApply = w.status == 'Approved';
    final m = t.metrics;
    final p = t.planner;

    final byDay = <String, List<CopilotProposal>>{};
    for (final prop in t.proposals) {
      final key = '${_weekdayNames[prop.start.weekday - 1]} ${prop.start.day}/${prop.start.month}';
      byDay.putIfAbsent(key, () => []).add(prop);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── decision ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: banner.color.withValues(alpha: 0.12),
            border: Border.all(color: banner.color.withValues(alpha: 0.7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(banner.icon, color: banner.color),
                const SizedBox(width: 8),
                Expanded(child: Text(banner.title, style: AppTextStyles.title)),
              ]),
              const SizedBox(height: 6),
              Text(banner.body, style: AppTextStyles.caption),
              for (final line in banner.list)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• $line', style: AppTextStyles.caption.copyWith(color: AppColors.textBody)),
                ),
              const SizedBox(height: 12),
              if (_busy)
                const AppLoader(size: 18)
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (w.awaitingApproval) ...[
                    _action('Approve', Icons.check_rounded, AppColors.success,
                        () => _act(() => ref.read(agentRepositoryProvider).approve(w.id), 'Approved — apply it when you are ready.')),
                    _action('Reject', Icons.close_rounded, AppColors.error, _reject),
                  ],
                  if (canApply) ...[
                    _action('Apply ${t.proposals.length}', Icons.play_arrow_rounded, AppColors.cyan, _apply),
                    _action('Discard', Icons.delete_outline_rounded, AppColors.error, _reject),
                  ],
                ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CopilotPipeline(trace: t),

        // ── numbers ────────────────────────────────────────────────
        if (m != null) ...[
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.2,
            children: [
              _kpi('${m.proposed}/${m.requested}', 'Proposed', '${m.coverage.round()}% of request', AppColors.violet),
              _kpi(p == null ? '—' : '${(p.confidence * 100).round()}%', 'Planner confidence',
                  p?.usedFallback == true ? 'deterministic planner' : 'language-model plan', AppColors.electricBlue),
              _kpi('${m.utilisationBefore.round()}→${m.utilisationAfter.round()}%', 'Utilisation', 'before → after', AppColors.success),
              _kpi(m.expectedNoShows.toStringAsFixed(1), 'Expected no-shows', m.revenue == null ? 'from history' : '${m.currency} ${m.revenue!.round()}',
                  AppColors.magenta),
            ],
          ),
        ],

        // ── plan ───────────────────────────────────────────────────
        if (p != null) ...[
          const SizedBox(height: 16),
          const SectionHeader('The plan'),
          if (p.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(p.summary, style: AppTextStyles.bodyMuted)),
          for (final step in p.plan) _planStep(step),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in p.rules) _pill(copilotRuleLabels[r] ?? r),
            if (p.weekdays.isNotEmpty) _pill(p.weekdays.map((d) => _weekdayNames[d.clamp(0, 6)]).join(', ')),
            if (p.timeWindow != 'any') _pill('${p.timeWindow} only'),
          ]),
          for (final warning in t.warnings)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('ⓘ $warning', style: AppTextStyles.caption)),
          for (final c in p.predictedConflicts)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c.kind.replaceAll('_', ' ')} · ${(c.likelihood * 100).round()}% likely',
                      style: AppTextStyles.label.copyWith(color: AppColors.warning)),
                  const SizedBox(height: 4),
                  Text(c.description, style: AppTextStyles.caption),
                ]),
              ),
            ),
        ],

        // ── schedule ───────────────────────────────────────────────
        const SizedBox(height: 16),
        SectionHeader('Proposed schedule', trailing: Text('${t.proposals.length}', style: AppTextStyles.caption)),
        if (t.proposals.isEmpty)
          GlassCard(child: Text('No slot satisfied every rule.', style: AppTextStyles.caption))
        else
          for (final entry in byDay.entries) ...[
            Padding(padding: const EdgeInsets.only(top: 6, bottom: 6), child: Text(entry.key, style: AppTextStyles.label)),
            for (final prop in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GlassCard(
                  child: Row(children: [
                    SizedBox(
                      width: 92,
                      child: Text('${_hm(prop.start)}–${_hm(prop.end)}', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(prop.resourceName, style: AppTextStyles.body),
                        if (prop.reasons.isNotEmpty) Text(prop.reasons.first, style: AppTextStyles.caption, maxLines: 2),
                      ]),
                    ),
                    Text(prop.score.round().toString(), style: AppTextStyles.stat.copyWith(fontSize: 16, color: AppColors.cyan)),
                  ]),
                ),
              ),
          ],

        // ── checks ─────────────────────────────────────────────────
        if (t.checks.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionHeader('Validation & safety', trailing: Text('${t.checksPassed}/${t.checks.length} passed', style: AppTextStyles.caption)),
          for (final c in t.checks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  c.status == 'pass' ? Icons.check_circle_rounded : c.status == 'warn' ? Icons.error_rounded : Icons.cancel_rounded,
                  size: 18,
                  color: c.status == 'pass' ? AppColors.success : c.status == 'warn' ? AppColors.warning : AppColors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_checkLabels[c.rule] ?? c.rule, style: AppTextStyles.body.copyWith(fontSize: 13)),
                    Text(c.detail, style: AppTextStyles.caption),
                  ]),
                ),
              ]),
            ),
        ],

        // ── trace ──────────────────────────────────────────────────
        const SizedBox(height: 10),
        GlassCard(
          onTap: () => setState(() => _showTrace = !_showTrace),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_showTrace ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.iconSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Execution trace · ${t.toolCalls.length} tool calls · ${t.llmCalls.where((c) => !c.ok).length} model retries',
                  style: AppTextStyles.label,
                ),
              ),
            ]),
            if (_showTrace) ...[
              const Divider(color: AppColors.hairline, height: 18),
              for (final entry in _toolCounts(t).entries)
                Text('${entry.key}  ×${entry.value}', style: AppTextStyles.caption.copyWith(fontFamily: 'monospace')),
              const SizedBox(height: 8),
              for (final c in t.llmCalls)
                Text('${c.model} · try ${c.attempt} · ${c.ok ? 'ok' : 'failed → next'}',
                    style: AppTextStyles.caption.copyWith(color: c.ok ? AppColors.textBody : AppColors.warning)),
              if (t.llmCalls.isEmpty) Text('No model call — the deterministic planner ran.', style: AppTextStyles.caption),
            ],
          ]),
        ),
      ],
    );
  }

  static Map<String, int> _toolCounts(CopilotTrace t) {
    final counts = <String, int>{};
    for (final c in t.toolCalls) {
      counts['${c.tool} (${c.agent.replaceAll('Agent', '')})'] = (counts['${c.tool} (${c.agent.replaceAll('Agent', '')})'] ?? 0) + 1;
    }
    return counts;
  }

  static String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _action(String label, IconData icon, Color color, VoidCallback onPressed) =>
      SizedBox(width: 150, child: GhostButton(label: label, icon: icon, height: 40, color: color, onPressed: onPressed));

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: AppColors.cyan.withValues(alpha: 0.12),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.4)),
        ),
        child: Text(text, style: AppTextStyles.caption.copyWith(color: AppColors.cyan)),
      );

  Widget _kpi(String value, String label, String sub, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.45)]),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          FittedBox(child: Text(value, style: AppTextStyles.stat.copyWith(color: Colors.white, fontSize: 20))),
          Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white)),
          Text(sub, style: AppTextStyles.caption.copyWith(color: Colors.white70, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );

  Widget _planStep(({int order, String action, String agent, String description, List<String> tools}) step) {
    final agent = copilotAgents.firstWhere((a) => a.key == step.agent, orElse: () => copilotAgents.first);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: agent.color, borderRadius: BorderRadius.circular(8)),
          child: Text('${step.order}', style: AppTextStyles.label.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(agent.label, style: AppTextStyles.caption.copyWith(color: agent.color, fontWeight: FontWeight.w800)),
            Text(step.action, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
            Text(step.description, style: AppTextStyles.caption),
            if (step.tools.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(step.tools.join(' · '), style: AppTextStyles.caption.copyWith(fontFamily: 'monospace', fontSize: 11)),
              ),
          ]),
        ),
      ]),
    );
  }
}
