import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/disruption_models.dart';
import '../../../models/resource_model.dart';
import '../../../providers/owner_providers.dart';
import '../../../services/disruption_repository.dart';
import '../../../shared/date_format.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// Where a manager handles "a resource is out of service" — the mobile twin
/// of the web app's Disruption Recovery screen.
///
/// The shape is deliberately the same on both: report the outage, then decide
/// the plans already proposed. The evidence sits beside each decision — who is
/// stranded and why they were ranked that way, what the agents propose, and
/// every check the deterministic gate ran — because approving a plan you
/// cannot see is not approval. Nothing moves until the manager says so.
class DisruptionRecoveryScreen extends ConsumerStatefulWidget {
  const DisruptionRecoveryScreen({super.key});

  @override
  ConsumerState<DisruptionRecoveryScreen> createState() => _DisruptionRecoveryScreenState();
}

class _DisruptionRecoveryScreenState extends ConsumerState<DisruptionRecoveryScreen> {
  final _objective = TextEditingController();
  String? _resourceId;

  // An outage is rarely one day wide, and a same-day default silently excludes
  // tomorrow's bookings, which is most of what is worth recovering.
  late DateTime _from = _today;
  late DateTime _to = _today.add(const Duration(days: 7));

  bool _planning = false;
  String? _busyWorkflowId;
  String _message = '';
  bool _messageIsError = false;

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _objective.dispose();
    super.dispose();
  }

  void _say(String text, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = isError;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _today.subtract(const Duration(days: 365)),
      lastDate: _today.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _from = picked;
        // Keeping the range valid here beats refusing it on submit.
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  Future<void> _planRecovery() async {
    final objective = _objective.text.trim();
    if (_resourceId == null || _resourceId!.isEmpty) {
      _say('Choose the resource that is unavailable.', isError: true);
      return;
    }
    if (objective.length < 3) {
      _say('Describe what happened in at least 3 characters.', isError: true);
      return;
    }

    setState(() {
      _planning = true;
      _message = '';
    });
    try {
      final result = await ref.read(disruptionRepositoryProvider).plan(
            objective: objective,
            resourceId: _resourceId!,
            dateFrom: _from,
            dateTo: _to,
          );
      _say('Recovery planned: ${result.status}. Review it below.');
      ref.invalidate(disruptionWorkflowsProvider);
    } catch (e) {
      _say(disruptionErrorMessage(e, 'The recovery could not be planned.'), isError: true);
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<void> _apply(DisruptionWorkflow workflow) async {
    setState(() {
      _busyWorkflowId = workflow.id;
      _message = '';
    });
    try {
      final result = await ref.read(disruptionRepositoryProvider).apply(workflow.id);
      _say(result.outcome);
      ref.invalidate(disruptionWorkflowsProvider);
    } catch (e) {
      _say(disruptionErrorMessage(e, 'The decision could not be recorded.'), isError: true);
    } finally {
      if (mounted) setState(() => _busyWorkflowId = null);
    }
  }

  Future<void> _reject(DisruptionWorkflow workflow) async {
    final reason = await _askForReason(workflow);
    if (reason == null) return;

    setState(() {
      _busyWorkflowId = workflow.id;
      _message = '';
    });
    try {
      _say(await ref.read(disruptionRepositoryProvider).reject(workflow.id, reason));
      ref.invalidate(disruptionWorkflowsProvider);
    } catch (e) {
      _say(disruptionErrorMessage(e, 'The decision could not be recorded.'), isError: true);
    } finally {
      if (mounted) setState(() => _busyWorkflowId = null);
    }
  }

  /// A rejection is part of the audit trail, so it has to carry a reason. The
  /// sheet will not return one shorter than the server would refuse.
  Future<String?> _askForReason(DisruptionWorkflow workflow) {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reject this recovery', style: AppTextStyles.title),
              const SizedBox(height: 6),
              Text(
                'Nothing will move. The reason is kept with the plan.',
                style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              StatefulBuilder(
                builder: (_, setSheetState) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NeonInputField(
                      label: 'Reason',
                      hintText: 'I will call the guests myself',
                      controller: controller,
                      maxLines: 3,
                      minLines: 2,
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 14),
                    NeonButton(
                      label: 'Reject',
                      icon: Icons.block_outlined,
                      onPressed: controller.text.trim().length < 3
                          ? null
                          : () => Navigator.of(sheetContext).pop(controller.text.trim()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              GhostButton(
                label: 'Keep it waiting',
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workflowsAsync = ref.watch(disruptionWorkflowsProvider);
    final resourcesAsync = ref.watch(ownerResourcesProvider);

    return OwnerScaffold(
      title: 'Disruption Recovery',
      subtitle: 'When a resource goes out of service',
      body: workflowsAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: disruptionErrorMessage(error, 'Recovery plans could not be loaded.'),
          onRetry: () => ref.invalidate(disruptionWorkflowsProvider),
        ),
        data: (workflows) {
          final waiting = workflows.where((w) => w.awaitingApproval).toList();
          // The newest plan knows what this business calls its resources, so
          // the form can speak the operator's language rather than ours.
          final noun = workflows
                  .map((w) => w.trace?.impact?.resourceNoun)
                  .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => null) ??
              'resource';

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async => ref.invalidate(disruptionWorkflowsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StatGrid(tiles: [
                  StatTile(
                    label: 'Waiting',
                    value: '${waiting.length}',
                    // Short on purpose: a StatTile is a fixed height, and a
                    // subtitle that wraps to a second line overflows it.
                    sub: 'need approval',
                    accent: waiting.isEmpty ? AppColors.success : AppColors.warning,
                  ),
                  StatTile(
                    label: 'Plans',
                    value: '${workflows.length}',
                    sub: 'on record',
                  ),
                ]),
                const SizedBox(height: 16),
                if (_message.isNotEmpty) ...[
                  _Notice(message: _message, isError: _messageIsError),
                  const SizedBox(height: 12),
                ],
                _OutageForm(
                  resources: resourcesAsync.asData?.value ?? const <Resource>[],
                  resourcesLoading: resourcesAsync.isLoading,
                  selectedResourceId: _resourceId,
                  onResourceChanged: (id) => setState(() => _resourceId = id),
                  objective: _objective,
                  from: _from,
                  to: _to,
                  onPickFrom: () => _pickDate(isStart: true),
                  onPickTo: () => _pickDate(isStart: false),
                  planning: _planning,
                  onPlan: _planRecovery,
                  resourceNoun: noun,
                ),
                const SizedBox(height: 20),
                if (workflows.isEmpty)
                  const EmptyState(
                    icon: Icons.health_and_safety_outlined,
                    title: 'No recovery plans yet',
                    message:
                        'Report an outage above and the agents will work out who is stranded and where each booking can go.',
                  )
                else
                  ...workflows.map((w) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _RecoveryPlanCard(
                          workflow: w,
                          busy: _busyWorkflowId == w.id,
                          onApprove: () => _apply(w),
                          onReject: () => _reject(w),
                        ),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final accent = isError ? AppColors.error : AppColors.cyan;
    return GlassCard(
      borderColor: accent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.error_outline : Icons.info_outline, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}

class _OutageForm extends StatelessWidget {
  const _OutageForm({
    required this.resources,
    required this.resourcesLoading,
    required this.selectedResourceId,
    required this.onResourceChanged,
    required this.objective,
    required this.from,
    required this.to,
    required this.onPickFrom,
    required this.onPickTo,
    required this.planning,
    required this.onPlan,
    required this.resourceNoun,
  });

  final List<Resource> resources;
  final bool resourcesLoading;
  final String? selectedResourceId;
  final ValueChanged<String?> onResourceChanged;
  final TextEditingController objective;
  final DateTime from;
  final DateTime to;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final bool planning;
  final VoidCallback onPlan;
  final String resourceNoun;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Report an outage'),
          Text(
            'The agents only read and propose.',
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Text('Which $resourceNoun is unavailable?', style: AppTextStyles.label),
          const SizedBox(height: 6),
          if (resourcesLoading && resources.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.overlaySurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButton<String>(
                  key: const Key('disruption-resource'),
                  value: selectedResourceId,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppColors.overlaySurface,
                  hint: Text('Choose a $resourceNoun…',
                      style: AppTextStyles.body.copyWith(color: AppColors.textMuted)),
                  items: resources
                      .map((r) => DropdownMenuItem(
                            value: r.id,
                            child: Text(r.name,
                                overflow: TextOverflow.ellipsis, style: AppTextStyles.body),
                          ))
                      .toList(),
                  onChanged: onResourceChanged,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('Out of service', style: AppTextStyles.label),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _DateBox(label: 'From', date: from, onTap: onPickFrom)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 16, color: AppColors.textMuted),
              ),
              Expanded(child: _DateBox(label: 'To', date: to, onTap: onPickTo)),
            ],
          ),
          const SizedBox(height: 16),
          NeonInputField(
            key: const Key('disruption-objective'),
            label: 'What happened, and how would you rather recover?',
            hintText: 'Engine fault — keep guests on the same day if you can',
            controller: objective,
            maxLines: 3,
            minLines: 2,
            helperText: 'Say whether you would rather keep the time and change the '
                '$resourceNoun, or keep the $resourceNoun and move the time.',
          ),
          const SizedBox(height: 18),
          NeonButton(
            label: planning ? 'Planning the recovery…' : 'Plan recovery',
            icon: Icons.auto_awesome_outlined,
            isLoading: planning,
            onPressed: planning ? null : onPlan,
          ),
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.label, required this.date, required this.onTap});

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.overlaySurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                formatDayMonth(date),
                style: AppTextStyles.body,
                overflow: TextOverflow.ellipsis,
                semanticsLabel: '$label ${formatFullDate(date)}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One proposed recovery, with the evidence above the decision.
class _RecoveryPlanCard extends StatelessWidget {
  const _RecoveryPlanCard({
    required this.workflow,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final DisruptionWorkflow workflow;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final trace = workflow.trace;
    final impact = trace?.impact;

    return GlassCard(
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
                    Text(workflow.objective, style: AppTextStyles.subtitle),
                    const SizedBox(height: 4),
                    Text(
                      workflow.finalOutcome ?? workflow.status,
                      style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OwnerStatusChip(status: workflow.status),
            ],
          ),
          if (workflow.errorLog != null && workflow.errorLog!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Notice(message: workflow.errorLog!, isError: true),
          ],
          if (impact != null) ...[
            const SizedBox(height: 12),
            Text(
              '${impact.affected.length} booking(s) on ${impact.resourceName} '
              '(${impact.resourceNoun}), ${impact.totalAttendees} people, '
              'LKR ${impact.revenueAtRisk.toStringAsFixed(2)} at risk.',
              style: AppTextStyles.caption,
            ),
          ],
          if (trace != null && trace.proposals.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...trace.proposals.map((p) => _ProposalRow(proposal: p)),
          ],
          if (trace?.safety != null && trace!.safety!.checks.isNotEmpty) ...[
            const SizedBox(height: 12),
            const SectionHeader('Safety gate'),
            ...trace.safety!.checks.map((c) => _CheckRow(check: c)),
          ],
          if (trace != null && trace.agentSteps.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Agents: ${trace.agentSteps.map((s) => '${s.agent} (${s.durationMs}ms)').join(' → ')}'
              ' · ${trace.toolCallCount} tool call(s)',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
          if (workflow.awaitingApproval) ...[
            const SizedBox(height: 16),
            NeonButton(
              label: 'Approve and move them',
              icon: Icons.check_circle_outline,
              isLoading: busy,
              onPressed: busy ? null : onApprove,
            ),
            const SizedBox(height: 8),
            GhostButton(
              label: 'Reject',
              icon: Icons.block_outlined,
              color: AppColors.error,
              onPressed: busy ? null : onReject,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProposalRow extends StatelessWidget {
  const _ProposalRow({required this.proposal});

  final RecoveryProposal proposal;

  @override
  Widget build(BuildContext context) {
    final moved = proposal.proposedStartsAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            proposal.kind.isActionable ? Icons.swap_horiz_rounded : Icons.help_outline,
            size: 18,
            color: proposal.kind.isActionable ? AppColors.cyan : AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${proposal.customerName} · ${proposal.kind.label}',
                    style: AppTextStyles.body),
                if (moved != null)
                  Text(
                    '${formatDayMonth(moved)} ${formatTimeOfDay(moved)}'
                    '${proposal.proposedResourceName != null ? ' · ${proposal.proposedResourceName}' : ''}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                  ),
                if (proposal.explanation.isNotEmpty)
                  Text(proposal.explanation,
                      style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final SafetyCheck check;

  @override
  Widget build(BuildContext context) {
    final colour = check.passed ? AppColors.success : AppColors.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(check.passed ? Icons.check_rounded : Icons.priority_high_rounded,
              size: 16, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Text(check.detail, style: AppTextStyles.caption),
          ),
        ],
      ),
    );
  }
}
