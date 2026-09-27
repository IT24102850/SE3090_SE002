import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/billing_models.dart';
import '../../providers/billing_providers.dart';
import '../../shared/date_format.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/billing_status_chip.dart';
import '../../widgets/route_transitions.dart';
import '../../widgets/ui/ui.dart';
import 'insurance_tracker_screen.dart';
import 'invoice_detail_screen.dart';
import 'payment_flow_screen.dart';
import 'saved_payment_methods_screen.dart';
import 'subscription_screen.dart';

/// "My Bills": every invoice the customer has, with its status
/// (Paid / Pending / Overdue) and what is still owed.
class MyBillsScreen extends ConsumerWidget {
  const MyBillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(myInvoicesProvider);

    return DefaultTabController(
      length: 3,
      child: AppBackgroundScaffold(
        appBar: GlassAppBar(
          title: 'My Bills',
          actions: [
            IconButton(
              tooltip: 'Subscriptions',
              icon: const Icon(Icons.autorenew_rounded),
              onPressed: () => Navigator.of(context).push(slideFadeRoute(const SubscriptionScreen())),
            ),
            IconButton(
              tooltip: 'Insurance claims',
              icon: const Icon(Icons.health_and_safety_outlined),
              onPressed: () => Navigator.of(context).push(slideFadeRoute(const InsuranceTrackerScreen())),
            ),
            IconButton(
              tooltip: 'Saved payment methods',
              icon: const Icon(Icons.wallet_outlined),
              onPressed: () => Navigator.of(context).push(slideFadeRoute(const SavedPaymentMethodsScreen())),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'To pay'), Tab(text: 'Paid'), Tab(text: 'All')]),
        ),
        child: SafeArea(
          child: bills.when(
            loading: () => const AppLoader(message: 'Loading your bills…'),
            error: (e, _) => ErrorState(message: 'Could not load your bills.', onRetry: () => ref.invalidate(myInvoicesProvider)),
            data: (all) {
              final open = all.where((i) => i.isOpen).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
              final paid = all.where((i) => i.isPaid).toList();
              return TabBarView(
                children: [
                  _BillList(invoices: open, empty: 'You are all paid up.', showTotal: true),
                  _BillList(invoices: paid, empty: 'No paid bills yet.'),
                  _BillList(invoices: all, empty: 'No bills yet.'),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BillList extends ConsumerWidget {
  final List<Invoice> invoices;
  final String empty;
  final bool showTotal;

  const _BillList({required this.invoices, required this.empty, this.showTotal = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (invoices.isEmpty) return EmptyState(icon: Icons.receipt_long_outlined, message: empty);

    final currency = invoices.first.currency;
    final owed = invoices.fold<double>(0, (sum, i) => sum + i.balanceDue);
    final overdue = invoices.where((i) => i.billState == 'Overdue').length;

    return RefreshIndicator(
      color: AppColors.cyan,
      backgroundColor: AppColors.overlaySurface,
      onRefresh: () async => ref.invalidate(myInvoicesProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (showTotal) ...[
            GlassCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TOTAL TO PAY', style: AppTextStyles.label),
                        const SizedBox(height: 6),
                        Text(formatMoney(owed, currency), key: const Key('total-owed'), style: AppTextStyles.headlineSmall),
                        const SizedBox(height: 4),
                        Text(
                          overdue > 0 ? '$overdue overdue' : '${invoices.length} open bills',
                          style: AppTextStyles.caption.copyWith(color: overdue > 0 ? AppColors.danger : AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const IconWell(icon: Icons.account_balance_wallet_outlined),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          for (final invoice in invoices) ...[
            _BillCard(invoice: invoice),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  final Invoice invoice;
  const _BillCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: () => Navigator.of(context).push(slideFadeRoute(InvoiceDetailScreen(invoiceId: invoice.id))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(invoice.invoiceNumber, style: AppTextStyles.subtitle, overflow: TextOverflow.ellipsis)),
              BillingStatusChip(status: invoice.billState),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            invoice.scheduleLabel != null ? '${invoice.scheduleLabel} · ${invoice.summary}' : invoice.summary,
            style: AppTextStyles.bodyMuted,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatMoney(invoice.finalAmount, invoice.currency), style: AppTextStyles.title),
                    Text(
                      invoice.isPaid ? 'Paid in full' : 'Due ${formatDayMonth(invoice.dueDate)} ${invoice.dueDate.year}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              if (invoice.isOpen)
                NeonButton(
                  label: 'Pay ${formatMoney(invoice.balanceDue, invoice.currency)}',
                  expand: false,
                  height: 42,
                  onPressed: () => Navigator.of(context).push(slideFadeRoute(PaymentFlowScreen(invoice: invoice))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
