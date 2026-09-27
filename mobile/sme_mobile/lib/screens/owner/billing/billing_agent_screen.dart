import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/admin_billing_models.dart';
import '../../../models/billing_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../shared/date_format.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// The Billing Domain Analysis Agent — the mobile twin of the web Billing
/// Agent monitor. It runs an analysis, shows what the agent found and what
/// it proposes, and works the approval queue. Nothing here applies a change
/// on its own: anything past the agent's own limits is parked for a human,
/// and this screen says so plainly.
class BillingAgentScreen extends ConsumerStatefulWidget {
  const BillingAgentScreen({super.key});

  @override
  ConsumerState<BillingAgentScreen> createState() => _BillingAgentScreenState();
}

class _BillingAgentScreenState extends ConsumerState<BillingAgentScreen> {
  String _analysisType = 'full';
  BillingAnalysis? _analysis;
  bool _running = false;

  static const _types = ['full', 'anomalies', 'revenue', 'insurance', 'pricing'];

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      final analysis = await ref
          .read(adminBillingRepositoryProvider)
          .analyze(tenantId: ref.read(ownerTenantIdProvider), analysisType: _analysisType);
      if (mounted) setState(() => _analysis = analysis);
      ref.invalidate(billingAgentWorkflowsProvider);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'The agent could not complete this analysis.');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tools = ref.watch(billingAgentToolsProvider).valueOrNull ?? const [];
    final workflows = ref.watch(billingAgentWorkflowsProvider).valueOrNull ?? const [];
    final pending = workflows.where((w) => w.awaitingApproval).toList();

    return OwnerScaffold(
      title: 'Billing Agent',
      subtitle: 'Analysis, proposals and approvals',
      body: RefreshIndicator(
        color: AppColors.cyan,
        backgroundColor: AppColors.overlaySurface,
        onRefresh: () async {
          ref.invalidate(billingAgentWorkflowsProvider);
          ref.invalidate(billingAgentToolsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Run an analysis', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  FilterChips<String>(
                    options: [for (final t in _types) (value: t, label: t)],
                    selected: _analysisType,
                    onSelected: (v) => setState(() => _analysisType = v ?? 'full'),
                  ),
                  const SizedBox(height: 12),
                  NeonButton(
                    label: _running ? 'Analysing…' : 'Analyse',
                    icon: Icons.psychology_outlined,
                    isLoading: _running,
                    onPressed: _running ? null : _run,
                  ),
                  if (tools.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Tools it is allowed to call', style: AppTextStyles.label),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tool in tools)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.glassFill,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: Text(tool, style: AppTextStyles.caption),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (_analysis != null) ...[
              const SizedBox(height: 16),
              _AnalysisView(analysis: _analysis!),
            ],
            const SizedBox(height: 18),
            SectionHeader(
              'Approval queue',
              trailing: Text('${pending.length} waiting', style: AppTextStyles.caption),
            ),
            if (pending.isEmpty)
              GlassCard(child: Text('Nothing is waiting on a human.', style: AppTextStyles.caption))
            else
              ...pending.map((w) => _WorkflowCard(workflow: w, actionable: true)),
            const SizedBox(height: 18),
            const SectionHeader('Audit trail'),
            if (workflows.isEmpty)
              GlassCard(child: Text('The agent has not been run yet.', style: AppTextStyles.caption))
            else
              ...workflows.take(25).map((w) => _WorkflowCard(workflow: w, actionable: false)),
          ],
        ),
      ),
    );
  }
}

class _AnalysisView extends StatelessWidget {
  final BillingAnalysis analysis;
  const _AnalysisView({required this.analysis});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatGrid(tiles: [
          StatTile(
            label: 'Confidence',
            value: '${(analysis.confidenceScore * 100).toStringAsFixed(0)}%',
            sub: 'in this analysis',
            accent: analysis.confidenceScore >= 0.7 ? AppColors.success : AppColors.warning,
          ),
          StatTile(
            label: 'Anomalies',
            value: '${analysis.anomalies.length}',
            sub: 'flagged for review',
            accent: analysis.anomalies.isEmpty ? AppColors.success : AppColors.warning,
          ),
          StatTile(label: 'Insights', value: '${analysis.insights.length}', sub: 'things worth knowing'),
          StatTile(label: 'Actions', value: '${analysis.recommendedActions.length}', sub: 'proposed'),
        ]),
        const SizedBox(height: 14),
        if (analysis.anomalies.isNotEmpty) ...[
          const SectionHeader('What it flagged'),
          for (final anomaly in analysis.anomalies)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                borderColor: OwnerStatusChip.colorOf(anomaly.severity).withValues(alpha: .4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(anomaly.entityLabel,
                              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        OwnerStatusChip(status: anomaly.severity),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(anomaly.description, style: AppTextStyles.caption),
                    if (anomaly.amount != 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(formatMoney(anomaly.amount),
                            style: AppTextStyles.caption.copyWith(color: AppColors.warning)),
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (analysis.insights.isNotEmpty) ...[
          const SizedBox(height: 8),
          const SectionHeader('What it noticed'),
          GlassCard(
            child: Column(
              children: [
                for (final insight in analysis.insights)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(insight.title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                        Text(insight.detail, style: AppTextStyles.caption),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (analysis.recommendedActions.isNotEmpty) ...[
          const SizedBox(height: 8),
          const SectionHeader('What it suggests'),
          for (final action in analysis.recommendedActions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action.actionType, style: AppTextStyles.label),
                    const SizedBox(height: 4),
                    Text(action.description, style: AppTextStyles.caption),
                    if (action.requiresApproval)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Needs a human to approve it — ${action.approvalReason ?? 'over the agent\'s limit'}.',
                          style: AppTextStyles.caption.copyWith(color: AppColors.warning),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (analysis.toolCalls.isNotEmpty) ...[
          const SizedBox(height: 8),
          const SectionHeader('How it got there'),
          GlassCard(
            child: Column(
              children: [
                for (final call in analysis.toolCalls)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.build_outlined, size: 14, color: AppColors.cyan),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(call.tool, style: AppTextStyles.caption.copyWith(color: AppColors.cyan)),
                              Text(call.summary, style: AppTextStyles.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _WorkflowCard extends ConsumerStatefulWidget {
  final BillingAgentWorkflow workflow;
  final bool actionable;
  const _WorkflowCard({required this.workflow, required this.actionable});

  @override
  ConsumerState<_WorkflowCard> createState() => _WorkflowCardState();
}

class _WorkflowCardState extends ConsumerState<_WorkflowCard> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(adminBillingRepositoryProvider);
      if (approve) {
        await repo.approveAgentWorkflow(widget.workflow.id);
      } else {
        await repo.rejectAgentWorkflow(widget.workflow.id, reason: 'Rejected from the app');
      }
      ref.invalidate(billingAgentWorkflowsProvider);
      ref.invalidate(adminInvoicesProvider);
      ref.invalidate(billingDashboardProvider);
      if (mounted) AppSnackBar.success(context, approve ? 'Approved and applied.' : 'Rejected.');
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not record that decision.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.workflow;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(w.objective, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                ),
                OwnerStatusChip(status: w.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                w.actionType,
                if (w.amount != 0) formatMoney(w.amount),
                if (w.createdAt != null) formatDayMonth(w.createdAt!),
              ].join(' · '),
              style: AppTextStyles.caption,
            ),
            if (w.reason?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Reason: ${w.reason}', style: AppTextStyles.caption),
              ),
            if (w.finalOutcome?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(w.finalOutcome!, style: AppTextStyles.caption.copyWith(color: AppColors.success)),
              ),
            if (widget.actionable) ...[
              const SizedBox(height: 10),
              if (_busy)
                const AppLoader(size: 18)
              else
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        label: 'Approve',
                        icon: Icons.check_rounded,
                        height: 40,
                        color: AppColors.success,
                        onPressed: () => _decide(true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GhostButton(
                        label: 'Reject',
                        icon: Icons.close_rounded,
                        height: 40,
                        color: AppColors.error,
                        onPressed: () => _decide(false),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
