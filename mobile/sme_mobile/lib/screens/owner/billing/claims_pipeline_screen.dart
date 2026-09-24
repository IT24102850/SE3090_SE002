import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/billing_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../shared/date_format.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// The claim pipeline as staff work it — the mobile twin of the web
/// Insurance Claim Tracker. Distinct from the customer's tracker, which
/// shows only their own claims and cannot move one along.
class ClaimsPipelineScreen extends ConsumerStatefulWidget {
  const ClaimsPipelineScreen({super.key});

  @override
  ConsumerState<ClaimsPipelineScreen> createState() => _ClaimsPipelineScreenState();
}

class _ClaimsPipelineScreenState extends ConsumerState<ClaimsPipelineScreen> {
  String _status = '';

  /// The order a claim actually travels in, which is what the "move on"
  /// button offers rather than a free choice of any status.
  static const _flow = ['Submitted', 'UnderReview', 'Approved', 'Rejected', 'Paid'];

  @override
  Widget build(BuildContext context) {
    final claimsAsync = ref.watch(adminClaimsProvider);

    return OwnerScaffold(
      title: 'Insurance Claims',
      subtitle: 'What the insurers owe',
      body: claimsAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load the claims.',
          onRetry: () => ref.invalidate(adminClaimsProvider),
        ),
        data: (all) {
          final rows = _status.isEmpty ? all : all.where((c) => c.status == _status).toList();
          final open = all.where((c) => c.status != 'Paid' && c.status != 'Rejected').toList();

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async => ref.invalidate(adminClaimsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                StatGrid(tiles: [
                  StatTile(label: 'Open', value: '${open.length}', sub: 'still in flight', accent: AppColors.warning),
                  StatTile(
                    label: 'Open value',
                    value: formatMoney(open.fold<double>(0, (sum, c) => sum + c.claimAmount)),
                    sub: 'claimed, not settled',
                  ),
                  StatTile(
                    label: 'Approved',
                    value: '${all.where((c) => c.status == 'Approved' || c.status == 'Paid').length}',
                    sub: 'accepted by the insurer',
                    accent: AppColors.success,
                  ),
                  StatTile(
                    label: 'Rejected',
                    value: '${all.where((c) => c.status == 'Rejected').length}',
                    sub: 'turned down',
                    accent: AppColors.error,
                  ),
                ]),
                const SizedBox(height: 14),
                FilterChips<String>(
                  options: [
                    (value: '', label: 'All'),
                    for (final s in _flow) (value: s, label: s),
                  ],
                  selected: _status,
                  onSelected: (v) => setState(() => _status = v ?? ''),
                ),
                const SizedBox(height: 14),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(icon: Icons.shield_outlined, message: 'No claims match this filter.'),
                  )
                else
                  ...rows.map((claim) => _ClaimCard(claim: claim, flow: _flow)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ClaimCard extends ConsumerStatefulWidget {
  final InsuranceClaim claim;
  final List<String> flow;
  const _ClaimCard({required this.claim, required this.flow});

  @override
  ConsumerState<_ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends ConsumerState<_ClaimCard> {
  bool _busy = false;

  Future<void> _moveTo(String status) async {
    String? reason;
    if (status == 'Rejected') {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.overlaySurface,
          title: Text('Why is it rejected?', style: AppTextStyles.title),
          content: NeonInputField(label: 'Reason', controller: controller),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject')),
          ],
        ),
      );
      if (ok != true) return;
      reason = controller.text.trim();
    }

    setState(() => _busy = true);
    try {
      final result = await ref.read(adminBillingRepositoryProvider).setClaimStatus(
            widget.claim.id,
            status: status,
            rejectionReason: reason,
          );
      ref.invalidate(adminClaimsProvider);
      ref.invalidate(billingDashboardProvider);
      if (!mounted) return;
      // A large claim needs an Admin's sign-off; the pipeline must say so
      // rather than show a status the insurer has not actually been told.
      if (result.requiresApproval) {
        AppSnackBar.info(context, result.message ?? 'Sent for approval — the claim has not moved yet.');
      } else {
        AppSnackBar.success(context, 'Claim moved to $status.');
      }
    } catch (error) {
      if (mounted) AppSnackBar.error(context, serverMessage(error, 'Could not move this claim.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.claim;
    final nextOptions = widget.flow.where((s) => s != c.status).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.provider, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        'Policy ${c.policyNumber}${c.invoiceNumber != null ? ' · ${c.invoiceNumber}' : ''}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                OwnerStatusChip(status: c.status),
              ],
            ),
            const SizedBox(height: 10),
            DetailRow(label: 'Claimed', value: formatMoney(c.claimAmount, c.currency)),
            if (c.submittedAt != null) DetailRow(label: 'Submitted', value: formatFullDate(c.submittedAt!)),
            if (c.reviewStartedAt != null) DetailRow(label: 'In review since', value: formatFullDate(c.reviewStartedAt!)),
            if (c.approvedAt != null) DetailRow(label: 'Approved', value: formatFullDate(c.approvedAt!)),
            if (c.rejectionReason?.isNotEmpty == true)
              DetailRow(label: 'Rejected because', value: c.rejectionReason!, valueColor: AppColors.error),
            if (c.requiresAdminApproval)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Over the desk limit — an Admin has to sign this one off.',
                  style: AppTextStyles.caption.copyWith(color: AppColors.warning),
                ),
              ),
            const SizedBox(height: 10),
            if (_busy)
              const AppLoader(size: 18)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in nextOptions)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: OwnerStatusChip.colorOf(status).withValues(alpha: .5)),
                      ),
                      onPressed: () => _moveTo(status),
                      child: Text(
                        status,
                        style: AppTextStyles.caption.copyWith(color: OwnerStatusChip.colorOf(status)),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
