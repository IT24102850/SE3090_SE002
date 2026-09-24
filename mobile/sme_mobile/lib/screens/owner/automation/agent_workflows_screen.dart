import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/agent_workflow_model.dart';
import '../../../providers/owner_providers.dart';
import '../../../shared/date_format.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// Every plan the agent has proposed — the mobile twin of the web Agent
/// Workflow Monitor. Approving a plan does not create the bookings; it
/// unlocks Apply, which does, and reports what it could not fit.
class AgentWorkflowsScreen extends ConsumerStatefulWidget {
  const AgentWorkflowsScreen({super.key});

  @override
  ConsumerState<AgentWorkflowsScreen> createState() => _AgentWorkflowsScreenState();
}

class _AgentWorkflowsScreenState extends ConsumerState<AgentWorkflowsScreen> {
  String _status = '';

  static const _statuses = ['AwaitingApproval', 'Approved', 'Completed', 'Rejected', 'Failed'];

  @override
  Widget build(BuildContext context) {
    final workflowsAsync = ref.watch(agentWorkflowsProvider);

    return OwnerScaffold(
      title: 'Agent Workflows',
      subtitle: 'What the agent has proposed',
      body: workflowsAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load the workflows.',
          onRetry: () => ref.invalidate(agentWorkflowsProvider),
        ),
        data: (all) {
          final rows = _status.isEmpty ? all : all.where((w) => w.status == _status).toList();
          final waiting = all.where((w) => w.awaitingApproval).toList();

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async => ref.invalidate(agentWorkflowsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StatGrid(tiles: [
                  StatTile(label: 'Workflows', value: '${all.length}', sub: 'on the audit trail'),
                  StatTile(
                    label: 'Waiting',
                    value: '${waiting.length}',
                    sub: 'need a decision',
                    accent: waiting.isEmpty ? AppColors.success : AppColors.warning,
                  ),
                  StatTile(
                    label: 'Completed',
                    value: '${all.where((w) => w.status == 'Completed').length}',
                    sub: 'applied',
                    accent: AppColors.success,
                  ),
                  StatTile(
                    label: 'Failed',
                    value: '${all.where((w) => w.status == 'Failed').length}',
                    sub: 'could not finish',
                    accent: AppColors.error,
                  ),
                ]),
                const SizedBox(height: 14),
                FilterChips<String>(
                  options: [
                    (value: '', label: 'All'),
                    for (final s in _statuses) (value: s, label: s == 'AwaitingApproval' ? 'Waiting' : s),
                  ],
                  selected: _status,
                  onSelected: (v) => setState(() => _status = v ?? ''),
                ),
                const SizedBox(height: 14),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(icon: Icons.satellite_alt_outlined, message: 'No workflows match this filter.'),
                  )
                else
                  ...rows.map((w) => WorkflowCard(workflow: w)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Shared with the AI Planner screen, which shows the plan it has just
/// proposed using exactly this card.
class WorkflowCard extends ConsumerStatefulWidget {
  final AgentWorkflow workflow;
  const WorkflowCard({super.key, required this.workflow});

  @override
  ConsumerState<WorkflowCard> createState() => _WorkflowCardState();
}

class _WorkflowCardState extends ConsumerState<WorkflowCard> {
  bool _busy = false;
  bool _expanded = false;

  Future<void> _run(Future<void> Function() action, String done) async {
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
        content: NeonInputField(label: 'Reason', controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(agentRepositoryProvider).reject(widget.workflow.id, controller.text.trim()),
      'Plan rejected.',
    );
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(agentRepositoryProvider).apply(widget.workflow.id);
      ref.invalidate(agentWorkflowsProvider);
      ref.invalidate(ownerBookingsProvider);
      if (!mounted) return;
      // Slots can go while a plan waits, so say what actually happened
      // rather than claiming the whole plan landed.
      AppSnackBar.success(
        context,
        result.skipped > 0
            ? '${result.created} booked, ${result.skipped} skipped — those slots had gone.'
            : '${result.created} booking${result.created == 1 ? '' : 's'} created.',
      );
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not apply this plan.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.workflow;
    final steps = w.steps;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: steps.isEmpty ? null : () => setState(() => _expanded = !_expanded),
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
                if (w.isBilling) 'billing agent' else 'scheduling agent',
                '${steps.length} step${steps.length == 1 ? '' : 's'}',
                if (w.createdAt != null) formatDayMonth(w.createdAt!),
              ].join(' · '),
              style: AppTextStyles.caption,
            ),
            if (w.estimatedRevenueImpact != 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Estimated impact ${w.estimatedRevenueImpact.toStringAsFixed(2)}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.cyan),
                ),
              ),
            if (w.finalOutcome?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(w.finalOutcome!, style: AppTextStyles.caption.copyWith(color: AppColors.success)),
              ),
            if (w.errorLog?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(w.errorLog!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
              ),
            if (_expanded && steps.isNotEmpty) ...[
              const Divider(color: AppColors.hairline, height: 20),
              for (final step in steps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '• ${step['summary'] ?? step['description'] ?? step['startTime'] ?? step.toString()}',
                    style: AppTextStyles.caption,
                  ),
                ),
            ],
            if (!w.isTerminal) ...[
              const SizedBox(height: 10),
              if (_busy)
                const AppLoader(size: 18)
              else
                Row(
                  children: [
                    if (w.awaitingApproval) ...[
                      Expanded(
                        child: GhostButton(
                          label: 'Approve',
                          icon: Icons.check_rounded,
                          height: 40,
                          color: AppColors.success,
                          onPressed: () => _run(
                            () => ref.read(agentRepositoryProvider).approve(w.id),
                            'Approved — Apply it when you are ready.',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GhostButton(
                          label: 'Reject',
                          icon: Icons.close_rounded,
                          height: 40,
                          color: AppColors.error,
                          onPressed: _reject,
                        ),
                      ),
                    ] else
                      Expanded(
                        child: GhostButton(
                          label: 'Apply plan',
                          icon: Icons.play_arrow_rounded,
                          height: 40,
                          onPressed: _apply,
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
