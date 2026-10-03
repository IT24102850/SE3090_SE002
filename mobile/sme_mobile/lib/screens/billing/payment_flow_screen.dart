import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/billing_models.dart';
import '../../providers/billing_providers.dart';
import '../../services/billing_repository.dart';
import '../../services/payment_flow.dart';
import '../../services/payment_method_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/route_transitions.dart';
import '../../widgets/ui/ui.dart';
import 'receipt_screen.dart';

enum _Step { choose, starting, sandbox, redirect, cash, confirming, done, error }

/// Select invoice (already chosen) -> choose method (Card / QR / Cash) ->
/// process via Stripe / PayPal (or the sandbox) -> result.
class PaymentFlowScreen extends ConsumerStatefulWidget {
  final Invoice invoice;
  const PaymentFlowScreen({super.key, required this.invoice});

  @override
  ConsumerState<PaymentFlowScreen> createState() => _PaymentFlowScreenState();
}

class _PaymentFlowScreenState extends ConsumerState<PaymentFlowScreen> {
  PayMethod _method = PayMethod.card;
  final _amount = TextEditingController();
  bool _remember = false;
  _Step _step = _Step.choose;
  CheckoutSession? _session;
  String _resultStatus = '';
  String? _error;

  Invoice get invoice => widget.invoice;

  @override
  void initState() {
    super.initState();
    // Pre-select the customer's default saved method.
    ref.read(paymentMethodStoreProvider).defaultMethod().then((m) {
      if (m != null && mounted && _step == _Step.choose) setState(() => _method = PayMethodX.fromSaved(m.type));
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  BillingRepository get _repo => ref.read(billingRepositoryProvider);

  Future<void> _start() async {
    if (validatePayAmount(_amount.text, invoice.balanceDue) != null) return;
    if (_remember) await _rememberMethod();
    if (_method == PayMethod.cash) {
      setState(() => _step = _Step.cash);
      return;
    }

    setState(() => _step = _Step.starting);
    try {
      final available = await ref.read(availableProvidersProvider.future).catchError((_) => const AvailableProviders([]));
      final provider = providerFor(_method, available);
      final session = await _repo.checkout(
        invoice.id,
        method: _method.apiName,
        provider: provider,
        amount: _amount.text.trim().isEmpty ? null : amountToPay(_amount.text, invoice.balanceDue),
        // In the app a card is always entered on Stripe's hosted page.
        hostedPage: provider == 'Stripe',
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        if (session.status == 'Succeeded' || session.status == 'Failed') {
          _resultStatus = session.status;
          _step = _Step.done;
        } else {
          _step = session.redirectUrl != null && session.provider != 'Manual' ? _Step.redirect : _Step.sandbox;
        }
      });
    } catch (e) {
      if (mounted) setState(() { _error = billingErrorMessage(e, 'The payment could not be started.'); _step = _Step.error; });
    }
  }

  Future<void> _confirm({bool simulateFailure = false}) async {
    final session = _session;
    if (session == null) return;
    setState(() => _step = _Step.confirming);
    try {
      final result = await _repo.confirmPayment(session.paymentId, simulateFailure: simulateFailure);
      if (!mounted) return;
      ref.invalidate(myInvoicesProvider);
      setState(() {
        _resultStatus = result.payment.status;
        _step = _Step.done;
      });
    } catch (e) {
      if (mounted) setState(() { _error = billingErrorMessage(e, 'We could not confirm the payment.'); _step = _Step.error; });
    }
  }

  Future<void> _openProvider() async {
    final url = _session?.redirectUrl;
    if (url == null) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) AppSnackBar.error(context, 'Could not open ${_session!.provider}.');
  }

  Future<void> _rememberMethod() async {
    try {
      await ref.read(paymentMethodStoreProvider).add(
            type: _method.apiName,
            label: switch (_method) { PayMethod.card => 'Card', PayMethod.qr => 'QR / wallet', PayMethod.cash => 'Cash at the counter' },
            makeDefault: true,
          );
      ref.invalidate(savedPaymentMethodsProvider);
    } on PaymentMethodValidationException catch (e) {
      if (mounted) AppSnackBar.info(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackgroundScaffold(
      appBar: GlassAppBar(title: 'Pay ${invoice.invoiceNumber}'),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            GlassCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BALANCE DUE', style: AppTextStyles.label),
                        const SizedBox(height: 6),
                        Text(formatMoney(invoice.balanceDue, invoice.currency), style: AppTextStyles.headlineSmall),
                        Text(invoice.summary, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const IconWell(icon: Icons.lock_outline_rounded),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ..._body(),
          ],
        ),
      ),
    );
  }

  List<Widget> _body() {
    switch (_step) {
      case _Step.choose:
        final amountError = validatePayAmount(_amount.text, invoice.balanceDue);
        final saved = ref.watch(savedPaymentMethodsProvider).valueOrNull ?? const <SavedPaymentMethod>[];
        return [
          if (saved.isNotEmpty) ...[
            const SectionHeader('Saved methods'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in saved)
                  ChoiceChip(
                    key: Key('saved-${m.id}'),
                    label: Text(m.display),
                    selected: PayMethodX.fromSaved(m.type) == _method,
                    onSelected: (_) => setState(() => _method = PayMethodX.fromSaved(m.type)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          const SectionHeader('How would you like to pay?'),
          for (final m in PayMethod.values) ...[
            _MethodTile(method: m, selected: m == _method, onTap: () => setState(() => _method = m)),
            const SizedBox(height: 10),
          ],
          if (_method != PayMethod.cash) ...[
            const SizedBox(height: 6),
            TextField(
              key: const Key('amount-field'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_) => setState(() {}),
              style: AppTextStyles.body,
              decoration: InputDecoration(
                labelText: 'Amount (leave blank to pay it all)',
                hintText: invoice.balanceDue.toStringAsFixed(2),
                errorText: amountError,
              ),
            ),
          ],
          CheckboxListTile(
            key: const Key('remember-method'),
            contentPadding: EdgeInsets.zero,
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            title: Text('Remember this method on this device', style: AppTextStyles.bodyMuted),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 8),
          NeonButton(
            key: const Key('pay-button'),
            label: _method == PayMethod.cash
                ? 'Continue'
                : 'Pay ${formatMoney(amountError == null ? amountToPay(_amount.text, invoice.balanceDue) : 0, invoice.currency)}',
            icon: Icons.lock_outline_rounded,
            onPressed: amountError == null ? _start : null,
          ),
        ];

      case _Step.starting:
      case _Step.confirming:
        return [AppLoader(message: _step == _Step.starting ? 'Starting payment…' : 'Confirming your payment…')];

      case _Step.sandbox:
        final s = _session!;
        return [
          if (_method == PayMethod.qr) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: QrImageView(
                  key: const Key('payment-qr'),
                  data: 'unify-pay:${s.externalReference}:${s.amount.toStringAsFixed(2)}:${s.currency}',
                  size: 200,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Scan with your banking app, then confirm below.', style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
            const SizedBox(height: 16),
          ],
          GlassCard(
            child: Text(
              'This business has no live payment gateway yet, so this payment runs in the secure sandbox - no real money moves. '
              'Payment ${s.externalReference} for ${formatMoney(s.amount, s.currency)} is ready.',
              style: AppTextStyles.bodyMuted,
            ),
          ),
          const SizedBox(height: 16),
          NeonButton(key: const Key('complete-payment'), label: 'Complete payment', onPressed: () => _confirm()),
          const SizedBox(height: 10),
          GhostButton(key: const Key('simulate-decline'), label: 'Simulate a decline', color: AppColors.danger, onPressed: () => _confirm(simulateFailure: true)),
        ];

      case _Step.redirect:
        final s = _session!;
        return [
          GlassCard(
            child: Text(
              'You will enter your ${s.provider == 'Stripe' ? 'card' : 'PayPal'} details on ${s.provider}\'s secure page. '
              'Come back here when you are done.',
              style: AppTextStyles.bodyMuted,
            ),
          ),
          const SizedBox(height: 16),
          NeonButton(label: 'Continue to ${s.provider}', icon: Icons.open_in_new_rounded, onPressed: _openProvider),
          const SizedBox(height: 10),
          GhostButton(key: const Key('check-status'), label: 'I have paid - check status', onPressed: () => _confirm()),
        ];

      case _Step.cash:
        return [
          GlassCard(
            key: const Key('cash-instructions'),
            child: Text(
              'Pay ${formatMoney(invoice.balanceDue, invoice.currency)} at the counter and quote ${invoice.invoiceNumber}. '
              'The staff will record it and your receipt will appear in My Bills.',
              style: AppTextStyles.body,
            ),
          ),
          const SizedBox(height: 16),
          GhostButton(label: 'Choose another way', onPressed: () => setState(() => _step = _Step.choose)),
        ];

      case _Step.done:
        final ok = _resultStatus == 'Succeeded';
        return [
          GlassCard(
            borderColor: ok ? AppColors.success : _resultStatus == 'Failed' ? AppColors.danger : AppColors.warning,
            child: Row(
              children: [
                Icon(ok ? Icons.check_circle_rounded : _resultStatus == 'Failed' ? Icons.cancel_rounded : Icons.hourglass_top_rounded,
                    color: ok ? AppColors.success : _resultStatus == 'Failed' ? AppColors.danger : AppColors.warning, size: 32),
                const SizedBox(width: 12),
                Expanded(child: Text(resultMessage(_resultStatus), key: const Key('payment-result'), style: AppTextStyles.body)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (ok)
            NeonButton(
              label: 'View receipt',
              icon: Icons.receipt_long_outlined,
              onPressed: () => Navigator.of(context).pushReplacement(slideFadeRoute(ReceiptScreen(invoiceId: invoice.id))),
            )
          else
            NeonButton(label: 'Try again', onPressed: () => setState(() => _step = _Step.choose)),
          const SizedBox(height: 10),
          GhostButton(label: 'Back to my bills', onPressed: () => Navigator.of(context).pop()),
        ];

      case _Step.error:
        return [
          InlineErrorBanner(message: _error ?? 'Something went wrong.'),
          const SizedBox(height: 16),
          NeonButton(label: 'Try again', onPressed: () => setState(() => _step = _Step.choose)),
        ];
    }
  }
}

class _MethodTile extends StatelessWidget {
  final PayMethod method;
  final bool selected;
  final VoidCallback onTap;
  const _MethodTile({required this.method, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (icon, hint) = switch (method) {
      PayMethod.card => (Icons.credit_card_rounded, 'Visa, Mastercard, Amex - secured by Stripe'),
      PayMethod.qr => (Icons.qr_code_2_rounded, 'Scan with your banking app or pay with PayPal'),
      PayMethod.cash => (Icons.payments_outlined, 'Pay at the counter'),
    };
    return Semantics(
      selected: selected,
      button: true,
      child: GlassListTile(
        key: Key('method-${method.name}'),
        icon: icon,
        title: method.title,
        subtitle: hint,
        showChevron: false,
        borderColor: selected ? AppColors.cyan : null,
        trailing: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppColors.cyan : AppColors.iconSecondary),
        onTap: onTap,
      ),
    );
  }
}
