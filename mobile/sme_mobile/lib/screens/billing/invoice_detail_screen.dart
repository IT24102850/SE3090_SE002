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
import 'payment_flow_screen.dart';
import 'receipt_screen.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoice = ref.watch(invoiceProvider(invoiceId));

    return AppBackgroundScaffold(
      appBar: const GlassAppBar(title: 'Bill details'),
      child: SafeArea(
        child: invoice.when(
          loading: () => const AppLoader(),
          error: (e, _) => ErrorState(message: 'Could not load this bill.', onRetry: () => ref.invalidate(invoiceProvider(invoiceId))),
          data: (inv) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(inv.invoiceNumber, style: AppTextStyles.title)),
                        BillingStatusChip(status: inv.billState),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Issued ${formatFullDate(inv.createdAt)} · due ${formatFullDate(inv.dueDate)}',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: 16),
                    for (final item in inv.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(child: Text('${item.description} × ${item.quantity}', style: AppTextStyles.body)),
                            Text(formatMoney(item.amount, inv.currency), style: AppTextStyles.body),
                          ],
                        ),
                      ),
                    const Divider(color: AppColors.hairline),
                    _Line('Subtotal', formatMoney(inv.totalAmount, inv.currency)),
                    if (inv.discount > 0) _Line('Discount', '-${formatMoney(inv.discount, inv.currency)}'),
                    if (inv.tax > 0) _Line('Tax', formatMoney(inv.tax, inv.currency)),
                    _Line('Total', formatMoney(inv.finalAmount, inv.currency), bold: true),
                    _Line('Paid', formatMoney(inv.amountPaid, inv.currency)),
                    _Line('Balance due', formatMoney(inv.balanceDue, inv.currency), bold: true),
                  ],
                ),
              ),
              if (inv.payments.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionHeader('Payments'),
                for (final p in inv.payments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassListTile(
                      icon: p.method == 'Cash' ? Icons.payments_outlined : p.method == 'QR' ? Icons.qr_code_2_rounded : Icons.credit_card_rounded,
                      title: '${p.method}${p.payerLabel == null ? '' : ' · ${p.payerLabel}'}',
                      subtitle: p.paidAt == null ? p.status : '${formatDayMonth(p.paidAt!)} ${formatTimeOfDay(p.paidAt!)}',
                      showChevron: false,
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatMoney(p.amount, inv.currency), style: AppTextStyles.body),
                          if (p.status != 'Succeeded') BillingStatusChip(status: p.status),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              if (inv.isOpen) ...[
                NeonButton(
                  label: 'Pay ${formatMoney(inv.balanceDue, inv.currency)}',
                  icon: Icons.lock_outline_rounded,
                  onPressed: () async {
                    await Navigator.of(context).push(slideFadeRoute(PaymentFlowScreen(invoice: inv)));
                    ref.invalidate(invoiceProvider(invoiceId));
                    ref.invalidate(myInvoicesProvider);
                  },
                ),
                const SizedBox(height: 12),
              ],
              GhostButton(
                label: inv.amountPaid > 0 ? 'View receipt' : 'View invoice',
                icon: Icons.receipt_long_outlined,
                onPressed: () => Navigator.of(context).push(slideFadeRoute(ReceiptScreen(invoiceId: inv.id))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _Line(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = bold ? AppTextStyles.subtitle : AppTextStyles.bodyMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text(value, style: style)]),
    );
  }
}
