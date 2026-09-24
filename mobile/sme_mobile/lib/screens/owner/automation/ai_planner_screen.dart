import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/agent_workflow_model.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';
import 'agent_workflows_screen.dart';

/// The owner's planner — the mobile twin of the web AI Planner. State an
/// objective, pick the service and how many, and the agent proposes a
/// schedule. It is a proposal: nothing is booked until it is approved and
/// applied, which the card below does.
class AiPlannerAdminScreen extends ConsumerStatefulWidget {
  const AiPlannerAdminScreen({super.key});

  @override
  ConsumerState<AiPlannerAdminScreen> createState() => _AiPlannerAdminScreenState();
}

class _AiPlannerAdminScreenState extends ConsumerState<AiPlannerAdminScreen> {
  final _objective = TextEditingController();
  String? _bookingTypeId;
  int _count = 5;
  int _withinDays = 14;
  AgentWorkflow? _proposal;
  bool _busy = false;

  @override
  void dispose() {
    _objective.dispose();
    super.dispose();
  }

  Future<void> _propose() async {
    if (_objective.text.trim().length < 6) {
      AppSnackBar.error(context, 'Say a little more about what you want.');
      return;
    }
    if (_bookingTypeId == null) {
      AppSnackBar.error(context, 'Pick which service to schedule.');
      return;
    }
    setState(() => _busy = true);
    try {
      final workflow = await ref.read(agentRepositoryProvider).propose(
            tenantId: ref.read(ownerTenantIdProvider),
            objective: _objective.text.trim(),
            count: _count,
            bookingTypeId: _bookingTypeId!,
            branchId: ref.read(ownerBranchFilterProvider),
            withinDays: _withinDays,
          );
      if (mounted) setState(() => _proposal = workflow);
      ref.invalidate(agentWorkflowsProvider);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'The planner could not build a plan for that.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(ownerBookingTypesProvider).valueOrNull ?? const [];
    final waiting = (ref.watch(agentWorkflowsProvider).valueOrNull ?? const <AgentWorkflow>[])
        .where((w) => w.awaitingApproval)
        .toList();

    return OwnerScaffold(
      title: 'AI Planner',
      subtitle: 'Let the agent draft a schedule',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What do you want scheduled?', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'It plans against real availability and never books anything you have not approved.',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 12),
                NeonInputField(
                  hintText: 'e.g. Fill next week\'s quiet morning slots with beginner classes',
                  controller: _objective,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Text('Service', style: AppTextStyles.label),
                const SizedBox(height: 8),
                if (types.isEmpty)
                  Text('No bookable services yet.', style: AppTextStyles.caption)
                else
                  FilterChips<String>(
                    options: [for (final t in types) (value: t.id, label: t.name)],
                    selected: _bookingTypeId,
                    onSelected: (v) => setState(() => _bookingTypeId = v),
                  ),
                const SizedBox(height: 12),
                Text('How many', style: AppTextStyles.label),
                const SizedBox(height: 8),
                FilterChips<int>(
                  options: const [
                    (value: 3, label: '3'),
                    (value: 5, label: '5'),
                    (value: 10, label: '10'),
                    (value: 20, label: '20'),
                  ],
                  selected: _count,
                  onSelected: (v) => setState(() => _count = v ?? 5),
                ),
                const SizedBox(height: 12),
                Text('Within', style: AppTextStyles.label),
                const SizedBox(height: 8),
                FilterChips<int>(
                  options: const [
                    (value: 7, label: '7 days'),
                    (value: 14, label: '14 days'),
                    (value: 30, label: '30 days'),
                  ],
                  selected: _withinDays,
                  onSelected: (v) => setState(() => _withinDays = v ?? 14),
                ),
                const SizedBox(height: 14),
                NeonButton(
                  label: _busy ? 'Planning…' : 'Draft a plan',
                  icon: Icons.auto_awesome_outlined,
                  isLoading: _busy,
                  onPressed: _busy ? null : _propose,
                ),
              ],
            ),
          ),
          if (_proposal != null) ...[
            const SizedBox(height: 18),
            const SectionHeader('The plan it drafted'),
            WorkflowCard(workflow: _proposal!),
          ],
          const SizedBox(height: 18),
          SectionHeader(
            'Waiting on you',
            trailing: Text('${waiting.length}', style: AppTextStyles.caption),
          ),
          if (waiting.isEmpty)
            GlassCard(child: Text('Nothing is waiting for a decision.', style: AppTextStyles.caption))
          else
            ...waiting.map((w) => WorkflowCard(workflow: w)),
        ],
      ),
    );
  }
}
