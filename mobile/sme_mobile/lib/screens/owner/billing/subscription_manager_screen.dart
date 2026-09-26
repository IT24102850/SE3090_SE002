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

/// The recurring book — the mobile twin of the web Subscription Manager:
/// who is on a plan, what it earns each month, what is renewing soon and
/// whose payment has slipped.
class SubscriptionManagerScreen extends ConsumerStatefulWidget {
  const SubscriptionManagerScreen({super.key});

  @override
  ConsumerState<SubscriptionManagerScreen> createState() => _SubscriptionManagerScreenState();
}

class _SubscriptionManagerScreenState extends ConsumerState<SubscriptionManagerScreen> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final subscriptionsAsync = ref.watch(adminSubscriptionsProvider);
    final renewals = ref.watch(subscriptionRenewalsProvider).valueOrNull ?? const [];

    return OwnerScaffold(
      title: 'Subscriptions',
      subtitle: 'The recurring book',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        onPressed: _newSubscription,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New plan'),
      ),
      body: subscriptionsAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load the subscriptions.',
          onRetry: () => ref.invalidate(adminSubscriptionsProvider),
        ),
        data: (all) {
          final rows = _status.isEmpty ? all : all.where((s) => s.status == _status).toList();
          final active = all.where((s) => s.isActive).toList();
          final mrr = active.fold<double>(0, (sum, s) => sum + _monthlyValue(s));

          return RefreshIndicator(
            color: AppColors.cyan,
            backgroundColor: AppColors.overlaySurface,
            onRefresh: () async {
              ref.invalidate(adminSubscriptionsProvider);
              ref.invalidate(subscriptionRenewalsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                StatGrid(tiles: [
                  StatTile(label: 'Active', value: '${active.length}', sub: 'plans running', accent: AppColors.success),
                  StatTile(label: 'MRR', value: formatMoney(mrr), sub: 'per month, normalised'),
                  StatTile(
                    label: 'Payment late',
                    value: '${all.where((s) => s.paymentStatus == 'Overdue').length}',
                    sub: 'need chasing',
                    accent: AppColors.error,
                  ),
                  StatTile(label: 'Renewing soon', value: '${renewals.length}', sub: 'within 30 days'),
                ]),
                const SizedBox(height: 14),
                FilterChips<String>(
                  options: const [
                    (value: '', label: 'All'),
                    (value: 'Active', label: 'Active'),
                    (value: 'Cancelled', label: 'Cancelled'),
                    (value: 'Expired', label: 'Expired'),
                  ],
                  selected: _status,
                  onSelected: (v) => setState(() => _status = v ?? ''),
                ),
                const SizedBox(height: 14),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(icon: Icons.autorenew_outlined, message: 'No subscriptions match this filter.'),
                  )
                else
                  ...rows.map((s) => _SubscriptionCard(subscription: s)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// A quarterly or yearly plan is worth a fraction of its price each
  /// month; without this the MRR tile would flatter a yearly book.
  static double _monthlyValue(Subscription s) {
    switch (s.billingCycle.toLowerCase()) {
      case 'yearly':
      case 'annual':
        return s.amount / 12;
      case 'quarterly':
        return s.amount / 3;
      case 'weekly':
        return s.amount * 52 / 12;
      default:
        return s.amount;
    }
  }

  Future<void> _newSubscription() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const _SubscriptionForm(),
      ),
    );
    if (saved == true) {
      ref.invalidate(adminSubscriptionsProvider);
      ref.invalidate(billingDashboardProvider);
    }
  }
}

class _SubscriptionCard extends ConsumerWidget {
  final Subscription subscription;
  const _SubscriptionCard({required this.subscription});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = subscription;
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
                      Text(s.planName, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        '${s.customerName ?? 'Customer'} · ${s.billingCycle}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                OwnerStatusChip(status: s.status),
              ],
            ),
            const SizedBox(height: 10),
            DetailRow(label: 'Amount', value: formatMoney(s.amount)),
            DetailRow(
              label: 'Payment',
              value: s.paymentStatus,
              valueColor: OwnerStatusChip.colorOf(s.paymentStatus),
            ),
            DetailRow(label: 'Runs', value: '${formatDayMonth(s.startDate)} – ${formatDayMonth(s.endDate)}'),
            if (s.nextBillingAt != null) DetailRow(label: 'Next bill', value: formatFullDate(s.nextBillingAt!)),
            DetailRow(label: 'Auto-renew', value: s.autoRenew ? 'On' : 'Off'),
            if (s.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(s.notes!, style: AppTextStyles.caption),
            ],
            if (s.isActive) ...[
              const SizedBox(height: 10),
              GhostButton(
                label: 'Cancel plan',
                icon: Icons.stop_circle_outlined,
                height: 40,
                color: AppColors.error,
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: AppColors.overlaySurface,
                      title: Text('Cancel "${s.planName}"?', style: AppTextStyles.title),
                      content: Text('It stops renewing; invoices already raised stay.', style: AppTextStyles.caption),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Cancel plan', style: TextStyle(color: AppColors.error)),
                        ),
                      ],
                    ),
                  );
                  if (ok != true || !context.mounted) return;
                  try {
                    await ref.read(adminBillingRepositoryProvider).cancelSubscription(s.id, reason: 'Cancelled in app');
                    ref.invalidate(adminSubscriptionsProvider);
                    if (context.mounted) AppSnackBar.success(context, 'Plan cancelled.');
                  } catch (error) {
                    if (context.mounted) AppSnackBar.error(context, serverMessage(error, 'Could not cancel this plan.'));
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubscriptionForm extends ConsumerStatefulWidget {
  const _SubscriptionForm();

  @override
  ConsumerState<_SubscriptionForm> createState() => _SubscriptionFormState();
}

class _SubscriptionFormState extends ConsumerState<_SubscriptionForm> {
  final _planName = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String _cycle = 'Monthly';
  BillingCustomer? _customer;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 365));
  bool _autoRenew = true;
  bool _generateInvoice = false;
  bool _saving = false;

  @override
  void dispose() {
    _planName.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_customer == null || _planName.text.trim().isEmpty) {
      AppSnackBar.error(context, 'Pick a customer and name the plan.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(adminBillingRepositoryProvider).createSubscription(
            customerId: _customer!.id,
            planName: _planName.text.trim(),
            amount: double.tryParse(_amount.text) ?? 0,
            billingCycle: _cycle,
            startDate: _start,
            endDate: _end,
            autoRenew: _autoRenew,
            generateInvoice: _generateInvoice,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not create this plan — check the dates.');
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
            Text('New subscription', style: AppTextStyles.title),
            const SizedBox(height: 12),
            Text('Customer', style: AppTextStyles.label),
            const SizedBox(height: 8),
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
            const SizedBox(height: 12),
            NeonInputField(label: 'Plan name', controller: _planName),
            const SizedBox(height: 10),
            NeonInputField(
              label: 'Amount per cycle',
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            Text('Billing cycle', style: AppTextStyles.label),
            const SizedBox(height: 8),
            FilterChips<String>(
              options: const [
                (value: 'Weekly', label: 'Weekly'),
                (value: 'Monthly', label: 'Monthly'),
                (value: 'Quarterly', label: 'Quarterly'),
                (value: 'Yearly', label: 'Yearly'),
              ],
              selected: _cycle,
              onSelected: (v) => setState(() => _cycle = v ?? 'Monthly'),
            ),
            const SizedBox(height: 12),
            GlassListTile(
              title: 'Starts ${formatFullDate(_start)}',
              icon: Icons.play_circle_outline,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _start,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _start = picked);
              },
            ),
            const SizedBox(height: 8),
            GlassListTile(
              title: 'Ends ${formatFullDate(_end)}',
              icon: Icons.stop_circle_outlined,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _end,
                  firstDate: _start.add(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                );
                if (picked != null) setState(() => _end = picked);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autoRenew,
              activeColor: AppColors.cyan,
              title: Text('Auto-renew', style: AppTextStyles.body),
              onChanged: (v) => setState(() => _autoRenew = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _generateInvoice,
              activeColor: AppColors.cyan,
              title: Text('Raise the first invoice now', style: AppTextStyles.body),
              onChanged: (v) => setState(() => _generateInvoice = v),
            ),
            const SizedBox(height: 8),
            NeonInputField(label: 'Notes', controller: _notes, maxLines: 2),
            const SizedBox(height: 14),
            NeonButton(label: 'Create plan', isLoading: _saving, onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }
}
