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

/// Every invoice the business has raised — the mobile twin of the web
/// Invoices page, including raising one, taking a payment against it and
/// adjusting it (which, past the agent's cap, parks for approval rather
/// than silently changing the total).
class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(invoiceStatusFilterProvider);

    return OwnerScaffold(
      title: 'Invoices',
      subtitle: 'Everything raised',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _newInvoice(context, ref),
        icon: const Icon(Icons.post_add_rounded),
        label: const Text('New invoice'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: FilterChips<String>(
              options: const [
                (value: '', label: 'All'),
                (value: 'Issued', label: 'Issued'),
                (value: 'PartiallyPaid', label: 'Part paid'),
                (value: 'Paid', label: 'Paid'),
                (value: 'Overdue', label: 'Overdue'),
                (value: 'Cancelled', label: 'Cancelled'),
              ],
              selected: status,
              onSelected: (v) => ref.read(invoiceStatusFilterProvider.notifier).state = v ?? '',
            ),
          ),
          Expanded(
            child: AsyncList<Invoice>(
              provider: adminInvoicesProvider,
              onRefresh: (ref) => ref.invalidate(adminInvoicesProvider),
              emptyMessage: 'No invoices match this filter.',
              emptyIcon: Icons.receipt_long_outlined,
              builder: (invoices) => ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                itemCount: invoices.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) return _Totals(invoices: invoices);
                  return _InvoiceCard(invoice: invoices[i - 1]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _newInvoice(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const _InvoiceForm(),
      ),
    );
    if (saved == true) {
      ref.invalidate(adminInvoicesProvider);
      ref.invalidate(billingDashboardProvider);
    }
  }
}

class _Totals extends StatelessWidget {
  final List<Invoice> invoices;
  const _Totals({required this.invoices});

  @override
  Widget build(BuildContext context) {
    final billed = invoices.fold<double>(0, (sum, i) => sum + i.finalAmount);
    final paid = invoices.fold<double>(0, (sum, i) => sum + i.amountPaid);
    final currency = invoices.isEmpty ? 'LKR' : invoices.first.currency;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StatGrid(tiles: [
        StatTile(label: 'Shown', value: '${invoices.length}', sub: 'invoices in view'),
        StatTile(label: 'Billed', value: formatMoney(billed, currency), sub: 'total of these'),
        StatTile(label: 'Paid', value: formatMoney(paid, currency), sub: 'received', accent: AppColors.success),
        StatTile(
          label: 'Owed',
          value: formatMoney(billed - paid, currency),
          sub: 'still to come',
          accent: billed - paid > 0 ? AppColors.warning : AppColors.success,
        ),
      ]),
    );
  }
}

class _InvoiceCard extends ConsumerWidget {
  final Invoice invoice;
  const _InvoiceCard({required this.invoice});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: AppColors.overlaySurface,
          isScrollControlled: true,
          builder: (_) => _InvoiceSheet(invoice: invoice),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(invoice.invoiceNumber, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        'Due ${formatDayMonth(invoice.dueDate)} · ${invoice.items.length} line${invoice.items.length == 1 ? '' : 's'}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                OwnerStatusChip(status: invoice.isOverdue && invoice.balanceDue > 0 ? 'Overdue' : invoice.status),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(formatMoney(invoice.finalAmount, invoice.currency),
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (invoice.balanceDue > 0)
                  Text('${formatMoney(invoice.balanceDue, invoice.currency)} owed',
                      style: AppTextStyles.caption.copyWith(color: AppColors.warning))
                else
                  Text('Settled', style: AppTextStyles.caption.copyWith(color: AppColors.success)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceSheet extends ConsumerStatefulWidget {
  final Invoice invoice;
  const _InvoiceSheet({required this.invoice});

  @override
  ConsumerState<_InvoiceSheet> createState() => _InvoiceSheetState();
}

class _InvoiceSheetState extends ConsumerState<_InvoiceSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final i = widget.invoice;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(i.invoiceNumber, style: AppTextStyles.title)),
                OwnerStatusChip(status: i.status),
              ],
            ),
            const SizedBox(height: 12),
            for (final item in i.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text('${item.quantity} × ${item.description}', style: AppTextStyles.caption)),
                    Text(formatMoney(item.amount, i.currency), style: AppTextStyles.caption),
                  ],
                ),
              ),
            const Divider(color: AppColors.hairline, height: 22),
            DetailRow(label: 'Subtotal', value: formatMoney(i.totalAmount, i.currency)),
            if (i.discount > 0) DetailRow(label: 'Discount', value: '-${formatMoney(i.discount, i.currency)}'),
            if (i.tax > 0) DetailRow(label: 'Tax', value: formatMoney(i.tax, i.currency)),
            DetailRow(label: 'Total', value: formatMoney(i.finalAmount, i.currency)),
            DetailRow(label: 'Paid', value: formatMoney(i.amountPaid, i.currency), valueColor: AppColors.success),
            DetailRow(
              label: 'Balance',
              value: formatMoney(i.balanceDue, i.currency),
              valueColor: i.balanceDue > 0 ? AppColors.warning : AppColors.success,
            ),
            DetailRow(label: 'Due', value: formatFullDate(i.dueDate)),
            if (i.payments.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Payments', style: AppTextStyles.label),
              for (final payment in i.payments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${payment.method} · ${payment.status}'
                          '${payment.paidAt != null ? ' · ${formatDayMonth(payment.paidAt!)}' : ''}',
                          style: AppTextStyles.caption,
                        ),
                      ),
                      Text(formatMoney(payment.amount, i.currency), style: AppTextStyles.caption),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),
            if (_busy)
              const AppLoader(size: 20)
            else ...[
              if (i.balanceDue > 0)
                NeonButton(label: 'Record a payment', onPressed: () => _takePayment(i)),
              const SizedBox(height: 8),
              GhostButton(label: 'Adjust', icon: Icons.edit_outlined, onPressed: () => _adjust(i)),
              const SizedBox(height: 8),
              if (i.status != 'Cancelled')
                GhostButton(
                  label: 'Cancel invoice',
                  icon: Icons.block_outlined,
                  color: AppColors.error,
                  onPressed: () => _cancel(i),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(adminInvoicesProvider);
      ref.invalidate(billingDashboardProvider);
    } catch (error) {
      // The API refuses some of these on purpose - an invoice with a payment
      // against it cannot simply be cancelled - and explains why, which is
      // what the desk needs to see.
      if (mounted) AppSnackBar.error(context, serverMessage(error, 'That did not go through.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takePayment(Invoice invoice) async {
    final amountController = TextEditingController(text: invoice.balanceDue.toStringAsFixed(2));
    var method = 'Cash';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.overlaySurface,
          title: Text('Record a payment', style: AppTextStyles.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NeonInputField(
                label: 'Amount',
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 10),
              FilterChips<String>(
                options: const [
                  (value: 'Cash', label: 'Cash'),
                  (value: 'Card', label: 'Card'),
                  (value: 'QR', label: 'QR'),
                  (value: 'BankTransfer', label: 'Transfer'),
                ],
                selected: method,
                onSelected: (v) => setDialogState(() => method = v ?? 'Cash'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Record')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final amount = double.tryParse(amountController.text) ?? 0;
    if (amount <= 0) return;
    await _run(() async {
      await ref.read(adminBillingRepositoryProvider).payInvoice(invoice.id, amount: amount, method: method);
      if (mounted) {
        Navigator.pop(context);
        AppSnackBar.success(context, 'Payment recorded.');
      }
    });
  }

  Future<void> _adjust(Invoice invoice) async {
    final discountController = TextEditingController(text: invoice.discount.toStringAsFixed(2));
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        title: Text('Adjust this invoice', style: AppTextStyles.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeonInputField(
              label: 'Discount',
              controller: discountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),
            NeonInputField(label: 'Reason', controller: reasonController),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ),
    );
    if (confirmed != true || reasonController.text.trim().isEmpty) return;

    await _run(() async {
      final result = await ref.read(adminBillingRepositoryProvider).adjustInvoice(
            invoice.id,
            discount: double.tryParse(discountController.text),
            reason: reasonController.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      // A large adjustment is parked, not applied — saying "done" here
      // would be a lie the approver would later have to undo.
      if (result.requiresApproval) {
        AppSnackBar.info(context, result.message ?? 'Sent for approval — the invoice is unchanged for now.');
      } else {
        AppSnackBar.success(context, 'Invoice adjusted.');
      }
    });
  }

  Future<void> _cancel(Invoice invoice) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        title: Text('Cancel ${invoice.invoiceNumber}?', style: AppTextStyles.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel it', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(adminBillingRepositoryProvider).cancelInvoice(invoice.id, reason: 'Cancelled from the app');
      if (mounted) {
        Navigator.pop(context);
        AppSnackBar.success(context, 'Invoice cancelled.');
      }
    });
  }
}

class _InvoiceForm extends ConsumerStatefulWidget {
  const _InvoiceForm();

  @override
  ConsumerState<_InvoiceForm> createState() => _InvoiceFormState();
}

class _LineDraft {
  final TextEditingController description = TextEditingController();
  final TextEditingController quantity = TextEditingController(text: '1');
  final TextEditingController unitPrice = TextEditingController();

  void dispose() {
    description.dispose();
    quantity.dispose();
    unitPrice.dispose();
  }
}

class _InvoiceFormState extends ConsumerState<_InvoiceForm> {
  final _discount = TextEditingController(text: '0');
  final _tax = TextEditingController(text: '0');
  final _notes = TextEditingController();
  final List<_LineDraft> _lines = [_LineDraft()];
  BillingCustomer? _customer;
  DateTime _dueDate = DateTime.now().add(const Duration(days: 14));
  bool _saving = false;

  @override
  void dispose() {
    _discount.dispose();
    _tax.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  double get _subtotal => _lines.fold<double>(0, (sum, l) {
        final qty = double.tryParse(l.quantity.text) ?? 0;
        final price = double.tryParse(l.unitPrice.text) ?? 0;
        return sum + qty * price;
      });

  Future<void> _save() async {
    if (_customer == null) {
      AppSnackBar.error(context, 'Pick who this is for.');
      return;
    }
    final items = _lines
        .where((l) => l.description.text.trim().isNotEmpty)
        .map((l) => (
              description: l.description.text.trim(),
              quantity: int.tryParse(l.quantity.text) ?? 1,
              unitPrice: double.tryParse(l.unitPrice.text) ?? 0,
              category: 'General',
            ))
        .toList();
    if (items.isEmpty) {
      AppSnackBar.error(context, 'Add at least one line.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(adminBillingRepositoryProvider).createInvoice(
            customerId: _customer!.id,
            dueDate: _dueDate,
            discountPercent: double.tryParse(_discount.text),
            taxRatePercent: double.tryParse(_tax.text),
            notes: _notes.text.trim(),
            items: items,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not raise this invoice.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(billingCustomersProvider).valueOrNull ?? const [];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New invoice', style: AppTextStyles.title),
            const SizedBox(height: 12),
            Text('Bill to', style: AppTextStyles.label),
            const SizedBox(height: 8),
            if (customers.isEmpty)
              Text('No customers on file yet.', style: AppTextStyles.caption)
            else
              FilterChips<String>(
                options: [for (final c in customers) (value: c.id, label: c.fullName)],
                selected: _customer?.id,
                onSelected: (id) => setState(
                  () => _customer = customers.where((c) => c.id == id).cast<BillingCustomer?>().firstWhere(
                        (_) => true,
                        orElse: () => null,
                      ),
                ),
              ),
            const SizedBox(height: 14),
            Text('Lines', style: AppTextStyles.label),
            const SizedBox(height: 8),
            for (var i = 0; i < _lines.length; i++) ...[
              NeonInputField(label: 'Description', controller: _lines[i].description),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: NeonInputField(
                    label: 'Qty',
                    controller: _lines[i].quantity,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: NeonInputField(
                    label: 'Unit price',
                    controller: _lines[i].unitPrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
            ],
            GhostButton(
              label: 'Add a line',
              icon: Icons.add_rounded,
              height: 42,
              onPressed: () => setState(() => _lines.add(_LineDraft())),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: NeonInputField(
                  label: 'Discount %',
                  controller: _discount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NeonInputField(
                  label: 'Tax %',
                  controller: _tax,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            NeonInputField(label: 'Notes', controller: _notes, maxLines: 2),
            const SizedBox(height: 10),
            GlassListTile(
              title: 'Due ${formatFullDate(_dueDate)}',
              icon: Icons.event_outlined,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dueDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _dueDate = picked);
              },
            ),
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                children: [
                  DetailRow(label: 'Subtotal', value: formatMoney(_subtotal)),
                  DetailRow(
                    label: 'After discount & tax',
                    value: formatMoney(_previewTotal()),
                    valueColor: AppColors.cyan,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            NeonButton(label: 'Raise invoice', isLoading: _saving, onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }

  /// Mirrors the server's own arithmetic — discount off the subtotal, then
  /// tax on what is left — so the preview cannot disagree with the invoice
  /// that comes back.
  double _previewTotal() {
    final discount = _subtotal * ((double.tryParse(_discount.text) ?? 0) / 100);
    final net = _subtotal - discount;
    return net + net * ((double.tryParse(_tax.text) ?? 0) / 100);
  }
}
