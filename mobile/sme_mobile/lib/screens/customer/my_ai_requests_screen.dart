import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/booking_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ui/ui.dart';

/// Ongoing status of every AI booking request the customer has made,
/// including ones sent for manager approval (AiPlannerScreen only shows the
/// *immediate* outcome — this is where "Sent for approval" leads to see what
/// happened next). Status changes arrive as push notifications too, via
/// AgentWorkflowController's Approve/Reject/Apply.
class MyAiRequestsScreen extends ConsumerWidget {
  const MyAiRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflowsAsync = ref.watch(myAgentWorkflowsProvider);

    return AppBackgroundScaffold(
      appBar: const GlassAppBar(title: 'My AI requests'),
      child: SafeArea(
        child: workflowsAsync.when(
          loading: () => const AppLoader(),
          error: (err, stack) => ErrorState(
            message: 'Could not load your requests.',
            onRetry: () => ref.invalidate(myAgentWorkflowsProvider),
          ),
          data: (workflows) {
            if (workflows.isEmpty) {
              return const EmptyState(
                icon: Icons.auto_awesome_outlined,
                message: 'No AI booking requests yet.',
              );
            }
            return RefreshIndicator(
              color: AppColors.cyan,
              backgroundColor: AppColors.overlaySurface,
              onRefresh: () async => ref.invalidate(myAgentWorkflowsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: workflows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _RequestCard(workflow: workflows[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RequestVisual {
  final Color color;
  final IconData icon;
  final String label;
  const _RequestVisual(this.color, this.icon, this.label);

  // AgentWorkflow's status vocabulary (Pending/AwaitingApproval/Approved/
  // Rejected/Completed/Failed) doesn't overlap with Booking's — a separate
  // mapping, not a reuse of StatusBadge/BookingStatusVisual, which would
  // show "Unknown" for half of these.
  static _RequestVisual of(String status) {
    switch (status) {
      case 'AwaitingApproval':
      case 'Pending':
        return const _RequestVisual(
            AppColors.warning, Icons.hourglass_top_rounded, 'Awaiting approval');
      case 'Approved':
        return const _RequestVisual(AppColors.cyan, Icons.thumb_up_alt_outlined, 'Approved');
      case 'Completed':
        return const _RequestVisual(AppColors.success, Icons.check_circle_rounded, 'Confirmed');
      case 'Rejected':
        return const _RequestVisual(AppColors.danger, Icons.block_rounded, 'Declined');
      case 'Failed':
        return const _RequestVisual(
            AppColors.danger, Icons.error_outline_rounded, 'Could not complete');
      default:
        return const _RequestVisual(AppColors.textMuted, Icons.help_outline, 'Unknown');
    }
  }
}

class _RequestCard extends StatelessWidget {
  final MyAgentWorkflow workflow;
  const _RequestCard({required this.workflow});

  @override
  Widget build(BuildContext context) {
    final visual = _RequestVisual.of(workflow.status);
    final detail = workflow.finalOutcome ?? workflow.errorLog;

    return GlassCard(
      borderRadius: AppRadii.row,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              width: 6,
              height: 44,
              decoration:
                  BoxDecoration(color: visual.color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(workflow.objective, style: AppTextStyles.subtitle.copyWith(fontSize: 14)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: visual.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: visual.color.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(visual.icon, size: 13, color: visual.color),
                      const SizedBox(width: 5),
                      Text(visual.label,
                          style: AppTextStyles.caption
                              .copyWith(color: visual.color, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                if (detail != null && detail.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(detail, style: AppTextStyles.caption.copyWith(fontSize: 12.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
