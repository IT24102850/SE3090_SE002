import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/billing_models.dart';
import '../../providers/billing_providers.dart';
import '../../services/billing_repository.dart';
import '../../shared/date_format.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/billing_status_chip.dart';
import '../../widgets/route_transitions.dart';
import '../../widgets/ui/ui.dart';
import 'invoice_detail_screen.dart';

/// Current plan(s), upgrade / downgrade, payment history and cancellation.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(mySubscriptionsProvider);

    return AppBackgroundScaffold(
      appBar: const GlassAppBar(title: 'My subscriptions'),
      child: SafeArea(
        child: subs.when(
          loading: () => const AppLoader(),
          error: (e, _) => ErrorState(message: 'Could not load your subscriptions.', onRetry: () => ref.invalidate(mySubscriptionsProvider)),
          data: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.autorenew_rounded, message: 'You have no memberships or subscriptions.')
              : RefreshIndicator(
                  color: AppColors.cyan,
                  backgroundColor: AppColors.overlaySurface,
                  onRefresh: () async => ref.invalidate(mySubscriptionsProvider),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [for (final s in list) ...[_SubscriptionCard(sub: s), const SizedBox(height: 14)]],
                  ),
                ),
        ),
      ),
    );
  }
}

class _SubscriptionCard extends ConsumerWidget {
  final Subscription sub;
  const _SubscriptionCard({required this.sub});

  Future<void> _changePlan(BuildContext context, WidgetRef ref) async {
    final plans = await ref.read(planOptionsProvider.future).catchError((_) => <PlanOption>[]);
    final options = plans.where((p) => p.billingCycle == sub.billingCycle && !(p.planName == sub.planName && p.amount == sub.amount)).toList();
    if (!context.mounted) return;
    if (options.isEmpty) {
      AppSnackBar.info(context, 'There are no other ${sub.billingCycle.toLowerCase()} plans to switch to.');
      return;
    }

    final chosen = await showModalBottomSheet<PlanOption>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.pill))),
      builder: (sheet) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text('Change plan', style: AppTextStyles.title),
            const SizedBox(height: 4),
            Text('Upgrades are charged pro rata now; downgrades start at your next renewal.', style: AppTextStyles.caption),
            const SizedBox(height: 16),
            for (final p in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassListTile(
                  icon: p.amount > sub.amount ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  iconColor: p.amount > sub.amount ? AppColors.success : AppColors.warning,
                  title: p.planName,
                  subtitle: '${p.amount > sub.amount ? 'Upgrade' : 'Downgrade'} · ${formatMoney(p.amount)} ${p.billingCycle.toLowerCase()}',
                  onTap: () => Navigator.of(sheet).pop(p),
                ),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;

    try {
      await ref.read(billingRepositoryProvider).changePlan(sub.id, planName: chosen.planName, amount: chosen.amount);
      ref.invalidate(mySubscriptionsProvider);
      ref.invalidate(myInvoicesProvider);
      if (context.mounted) {
        AppSnackBar.success(context, chosen.amount > sub.amount
            ? 'Upgraded to ${chosen.planName}. A pro-rata bill is in My Bills.'
            : 'Switched to ${chosen.planName} from your next renewal.');
      }
    } catch (e) {
      if (context.mounted) AppSnackBar.error(context, billingErrorMessage(e, 'Could not change the plan.'));
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final refund = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        title: Text('Cancel ${sub.planName}?', style: AppTextStyles.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (optional)')),
            const SizedBox(height: 10),
            TextField(
              controller: refund,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Refund to request (optional)',
                helperText: 'A refund is reviewed by the business first.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Cancel subscription', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final message = await ref.read(billingRepositoryProvider).cancelSubscription(
            sub.id,
            reason: reason.text.trim(),
            refundAmount: double.tryParse(refund.text.trim()) ?? 0,
          );
      ref.invalidate(mySubscriptionsProvider);
      if (context.mounted) AppSnackBar.success(context, message);
    } catch (e) {
      if (context.mounted) AppSnackBar.error(context, billingErrorMessage(e, 'Could not cancel.'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(sub.planName, style: AppTextStyles.title)),
            BillingStatusChip(status: sub.status),
          ]),
          const SizedBox(height: 6),
          Text('${formatMoney(sub.amount)} ${sub.billingCycle.toLowerCase()}', style: AppTextStyles.subtitle),
          const SizedBox(height: 4),
          Text(
            sub.isActive
                ? (sub.autoRenew
                    ? 'Renews ${formatFullDate(sub.nextBillingAt ?? sub.endDate)}'
                    : 'Ends ${formatFullDate(sub.endDate)}')
                : 'Period ${formatDayMonth(sub.startDate)} – ${formatDayMonth(sub.endDate)} ${sub.endDate.year}',
            style: AppTextStyles.caption,
          ),
          if (sub.paymentStatus != 'Paid') ...[
            const SizedBox(height: 8),
            BillingStatusChip(status: sub.paymentStatus == 'Pending' ? 'Pending' : 'Overdue'),
          ],
          const SizedBox(height: 14),
          _PaymentHistory(subscriptionId: sub.id),
          if (sub.isActive) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: GhostButton(label: 'Change plan', icon: Icons.swap_vert_rounded, height: 44, onPressed: () => _changePlan(context, ref))),
              const SizedBox(width: 10),
              Expanded(child: GhostButton(label: 'Cancel', icon: Icons.close_rounded, height: 44, color: AppColors.danger, onPressed: () => _cancel(context, ref))),
            ]),
          ],
        ],
      ),
    );
  }
}

class _PaymentHistory extends ConsumerWidget {
  final String subscriptionId;
  const _PaymentHistory({required this.subscriptionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(subscriptionInvoicesProvider(subscriptionId));
    return invoices.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (_, __) => Text('Payment history unavailable.', style: AppTextStyles.caption),
      data: (list) => list.isEmpty
          ? Text('No bills yet for this subscription.', style: AppTextStyles.caption)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PAYMENT HISTORY', style: AppTextStyles.label),
                const SizedBox(height: 6),
                for (final inv in list.take(6))
                  InkWell(
                    onTap: () => Navigator.of(context).push(slideFadeRoute(InvoiceDetailScreen(invoiceId: inv.id))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(child: Text(formatFullDate(inv.createdAt), style: AppTextStyles.bodyMuted)),
                        Text(formatMoney(inv.finalAmount, inv.currency), style: AppTextStyles.body),
                        const SizedBox(width: 8),
                        BillingStatusChip(status: inv.billState),
                      ]),
                    ),
                  ),
              ],
            ),
    );
  }
}
