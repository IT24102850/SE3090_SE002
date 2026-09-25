import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/agent_workflow_model.dart';
import '../../../models/copilot_trace.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';
import 'agent_workflows_screen.dart';
import 'copilot_widgets.dart';

/// Schedule Copilot - the mobile twin of the web Copilot. Say what you need;
/// the Planner, Domain Analysis, Action/Tool and Validation/Safety agents
/// plan it against real availability and hand it back. It is read-only:
/// nothing is booked until the result is approved (where the safety gate
/// asks for that) and applied.
class AiPlannerAdminScreen extends ConsumerStatefulWidget {
  const AiPlannerAdminScreen({super.key});

  @override
  ConsumerState<AiPlannerAdminScreen> createState() => _AiPlannerAdminScreenState();
}

class _AiPlannerAdminScreenState extends ConsumerState<AiPlannerAdminScreen> {
  static const _examples = [
    'Fit 5 follow-ups this week, mornings only, and keep lunch free',
    "Line up 6 property viewings for Thursday's buyers and leave time to drive between houses",
    'Spread 12 sessions evenly across the team, avoiding lots of no-shows',
  ];

  final _objective = TextEditingController(text: _examples.first);
  String? _bookingTypeId;
  int _count = 5;
  late DateTimeRange _range;
  final Set<String> _rules = {};
  AgentWorkflow? _result;
  CopilotTrace? _trace;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final tomorrow = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));
    _range = DateTimeRange(start: tomorrow, end: tomorrow.add(const Duration(days: 6)));
  }

  @override
  void dispose() {
    _objective.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: _range,
      helpText: 'Plan within (up to 31 days)',
    );
    if (picked == null) return;
    if (picked.duration.inDays + 1 > 31) {
      if (mounted) AppSnackBar.error(context, 'Plan at most 31 days at a time.');
      return;
    }
    setState(() => _range = picked);
  }

  void _toggleRule(String rule) {
    setState(() {
      if (!_rules.remove(rule)) {
        _rules.add(rule);
        // Mornings and afternoons are mutually exclusive.
        if (rule == 'prefer_mornings') _rules.remove('prefer_afternoons');
        if (rule == 'prefer_afternoons') _rules.remove('prefer_mornings');
      }
    });
  }

  Future<void> _run() async {
    if (_objective.text.trim().length < 3) {
      AppSnackBar.error(context, 'Say a little more about what you want.');
      return;
    }
    if (_bookingTypeId == null) {
      AppSnackBar.error(context, 'Pick which service to schedule.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(agentRepositoryProvider).planSchedule(
            tenantId: ref.read(ownerTenantIdProvider),
            objective: _objective.text.trim(),
            bookingTypeId: _bookingTypeId!,
            dateFrom: _range.start,
            dateTo: _range.end,
            targetCount: _count,
            priorityRules: _rules.toList(),
            branchId: ref.read(ownerBranchFilterProvider),
          );
      if (mounted) {
        setState(() {
          _result = result.workflow;
          _trace = result.trace ?? result.workflow.copilot;
        });
      }
      ref.invalidate(agentWorkflowsProvider);
    } on DioException catch (e) {
      final data = e.response?.data;
      final message = data is Map && data['message'] != null ? data['message'].toString() : 'The Schedule Copilot could not run.';
      if (mounted) AppSnackBar.error(context, message);
      ref.invalidate(agentWorkflowsProvider);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'The Schedule Copilot could not run.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _day(DateTime d) => '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]} ${d.day}/${d.month}';

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(ownerBookingTypesProvider).valueOrNull ?? const [];
    final all = ref.watch(agentWorkflowsProvider).valueOrNull ?? const <AgentWorkflow>[];
    final waiting = all.where((w) => w.awaitingApproval).toList();
    // Keep the shown result current as it is approved or applied elsewhere.
    final current = _result == null ? null : all.firstWhere((w) => w.id == _result!.id, orElse: () => _result!);

    return OwnerScaffold(
      title: 'Schedule Copilot',
      subtitle: 'Four agents plan it · you approve it',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _hero(all),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What should the agents schedule?', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Name days, times, gaps or counts — the planner reads them. Your settings below always win.',
                    style: AppTextStyles.caption),
                const SizedBox(height: 12),
                NeonInputField(hintText: 'e.g. Fit 5 follow-ups this week, mornings only', controller: _objective, maxLines: 3),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final ex in _examples)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(ex, style: AppTextStyles.caption),
                          backgroundColor: AppColors.glassFill,
                          side: const BorderSide(color: AppColors.glassBorder),
                          onPressed: () => setState(() => _objective.text = ex),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 14),
                Text('When', style: AppTextStyles.label),
                const SizedBox(height: 8),
                GlassCard(
                  onTap: _pickRange,
                  child: Row(children: [
                    const Icon(Icons.date_range_rounded, color: AppColors.cyan),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${_day(_range.start)}  →  ${_day(_range.end)}', style: AppTextStyles.body)),
                    Text('${_range.duration.inDays + 1} days', style: AppTextStyles.caption),
                  ]),
                ),
                const SizedBox(height: 14),
                Text('How many (max)', style: AppTextStyles.label),
                const SizedBox(height: 8),
                FilterChips<int>(
                  options: const [
                    (value: 3, label: '3'),
                    (value: 5, label: '5'),
                    (value: 10, label: '10'),
                    (value: 20, label: '20'),
                    (value: 25, label: '25'),
                  ],
                  selected: _count,
                  onSelected: (v) => setState(() => _count = v ?? 5),
                ),
                const SizedBox(height: 14),
                Text('Priority rules', style: AppTextStyles.label),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final entry in copilotRuleLabels.entries)
                    FilterChip(
                      label: Text(entry.value, style: AppTextStyles.caption.copyWith(
                          color: _rules.contains(entry.key) ? AppColors.cyan : AppColors.textBody)),
                      selected: _rules.contains(entry.key),
                      onSelected: (_) => _toggleRule(entry.key),
                      backgroundColor: AppColors.glassFill,
                      selectedColor: AppColors.cyan.withValues(alpha: 0.16),
                      checkmarkColor: AppColors.cyan,
                      side: BorderSide(color: _rules.contains(entry.key) ? AppColors.cyan : AppColors.glassBorder),
                    ),
                ]),
                const SizedBox(height: 14),
                Text('🔒 Read-only: the agents act with your permissions and cannot book anything. Over 20 bookings or ~\$500 always waits for a manager.',
                    style: AppTextStyles.caption),
                const SizedBox(height: 12),
                NeonButton(
                  label: _busy ? 'Agents working…' : 'Run the agents',
                  icon: Icons.auto_awesome_rounded,
                  isLoading: _busy,
                  onPressed: _busy ? null : _run,
                ),
              ],
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const SectionHeader('Agents at work'),
            const CopilotPipeline(running: true),
          ] else if (current != null && _trace != null) ...[
            const SizedBox(height: 16),
            const SectionHeader('Result'),
            CopilotResultView(workflow: current, trace: _trace!),
          ],
          const SizedBox(height: 18),
          SectionHeader('Waiting on you', trailing: Text('${waiting.length}', style: AppTextStyles.caption)),
          if (waiting.isEmpty)
            GlassCard(child: Text('Nothing is waiting for a decision.', style: AppTextStyles.caption))
          else
            ...waiting.map((w) => WorkflowCard(workflow: w)),
        ],
      ),
    );
  }

  Widget _hero(List<AgentWorkflow> all) {
    final runs = all.where((w) => w.copilot != null).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Color(0xFF4C1D95), Color(0xFF1D4ED8), Color(0xFF0E7490)]),
        boxShadow: [BoxShadow(color: AppColors.electricBlue.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: Colors.white.withValues(alpha: 0.16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: const Text('✦', style: TextStyle(fontSize: 22, color: Colors.white)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PLANNER · COORDINATOR AGENT', style: AppTextStyles.caption.copyWith(color: Colors.white70, letterSpacing: 1.2, fontSize: 10)),
            Text('Schedule Copilot', style: AppTextStyles.title.copyWith(color: Colors.white)),
            Text('$runs run${runs == 1 ? '' : 's'} · ${all.where((w) => w.awaitingApproval).length} awaiting approval',
                style: AppTextStyles.caption.copyWith(color: Colors.white70)),
          ]),
        ),
      ]),
    );
  }
}
