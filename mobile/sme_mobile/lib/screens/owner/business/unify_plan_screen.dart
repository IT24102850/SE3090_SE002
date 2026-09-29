import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/billing_models.dart' show formatMoney;
import '../../../models/unify_plan_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/unify_plan_providers.dart';
import '../../../services/api_service.dart';
import '../../../services/unify_plan_repository.dart';
import '../../../shared/date_format.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// The business's own Unify plan, on the phone — the mobile twin of the web
/// /subscription screen.
///
/// What the business pays *us*. Not to be confused with the Subscriptions
/// screen under Billing, which is the memberships this business sells to its
/// own customers.
class UnifyPlanScreen extends ConsumerStatefulWidget {
  const UnifyPlanScreen({super.key});

  @override
  ConsumerState<UnifyPlanScreen> createState() => _UnifyPlanScreenState();
}

class _UnifyPlanScreenState extends ConsumerState<UnifyPlanScreen>
    with WidgetsBindingObserver {
  /// Annual first: it is the best-value rung, so anchoring on it makes the
  /// monthly price read as what flexibility costs rather than as the default.
  String _period = 'Annual';
  bool _busy = false;

  /// A checkout that went out to the system browser and has not been
  /// resolved yet. The card form runs outside the app, so nothing here knows
  /// the outcome until we ask the server, which asks the gateway.
  String? _pendingPaymentId;

  /// Where the gateway sends the customer back to. A phone has nowhere of
  /// its own to land without app-link registration, so it lands on a plain
  /// page the API serves and then comes back to the app by hand.
  String get _returnUrl => '${ApiService.origin}/payment-complete';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the browser is the signal that a payment may have
    // finished. Without this the payment sits Pending for ever on a phone:
    // there is no redirect back into the app to trigger the check.
    if (state == AppLifecycleState.resumed) unawaited(_confirmPending());
  }

  bool get _isAdmin => ref.read(authProvider).user?.role == 'Admin';

  void _refresh() {
    ref.invalidate(unifySubscriptionProvider);
    ref.invalidate(pricingCatalogProvider);
    ref.invalidate(unifyInvoicesProvider);
  }

  void _say(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: bad ? AppColors.error : AppColors.overlaySurface,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionAsync = ref.watch(unifySubscriptionProvider);
    final catalogAsync = ref.watch(pricingCatalogProvider);
    final invoices =
        ref.watch(unifyInvoicesProvider).valueOrNull ?? const <UnifyInvoice>[];

    return OwnerScaffold(
      title: 'Your Unify plan',
      subtitle: 'What this business pays for the platform',
      body: subscriptionAsync.when(
        loading: () => const AppLoader(),
        error: (error, _) => ErrorState(
          message: 'Could not load your plan.',
          onRetry: _refresh,
        ),
        data: (sub) => RefreshIndicator(
          color: AppColors.cyan,
          backgroundColor: AppColors.overlaySurface,
          onRefresh: () async {
            await _confirmPending();
            _refresh();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
            children: [
              ..._banners(sub),
              _CurrentPlanCard(
                sub: sub,
                busy: _busy,
                canManage: _isAdmin,
                onStartTrial: () => _startTrial(sub),
                onResume: _resume,
                onCancel: () => _cancel(sub),
              ),
              const SizedBox(height: 18),
              if (sub.usage.isNotEmpty) ...[
                const SectionHeader('This month'),
                for (final meter in sub.usage) ...[
                  _MeterCard(meter: meter),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
              ],
              if (sub.credits.isNotEmpty || sub.extraSeats > 0) ...[
                const SectionHeader('Credits in hand'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in sub.credits.entries)
                      _Pill('${entry.value} ${_creditLabel(entry.key)}'),
                    if (sub.extraSeats > 0)
                      _Pill('+${sub.extraSeats} extra seats'),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              catalogAsync.when(
                loading: () => const AppLoader(),
                error: (error, _) => ErrorState(
                  message: 'Could not load the plans.',
                  onRetry: () => ref.invalidate(pricingCatalogProvider),
                ),
                data: (catalog) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (catalog.featuredOffer != null) ...[
                      _OfferCard(offer: catalog.featuredOffer!),
                      const SizedBox(height: 14),
                    ],
                    const SectionHeader('Plans'),
                    _TermPicker(
                      catalog: catalog,
                      period: _period,
                      onChanged: (p) => setState(() => _period = p),
                    ),
                    const SizedBox(height: 12),
                    for (final plan in catalog.plans) ...[
                      _PlanCard(
                        plan: plan,
                        price: plan.priceFor(_period),
                        currency: catalog.currency,
                        isCurrent: plan.code == sub.planCode,
                        currentTier: sub.tier,
                        busy: _busy || !_isAdmin,
                        onChoose: () => _choose(plan, sub, catalog.currency),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_isAdmin)
                      Text(
                        'Only an Admin can change the plan.',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textMuted),
                      ),
                    const SizedBox(height: 18),
                    const SectionHeader('Add-ons'),
                    Text(
                      'Bought once, used whenever. The bigger pack is always the better unit price, and pack credits '
                      'are only spent after your monthly allowance runs out.',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    for (final addOn in catalog.addOns) ...[
                      _AddOnCard(
                        addOn: addOn,
                        busy: _busy || !_isAdmin,
                        onBuy: () => _buyAddOn(addOn, catalog.currency),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              if (invoices.isNotEmpty) ...[
                const SizedBox(height: 18),
                const SectionHeader('Unify invoices'),
                for (final invoice in invoices.take(12)) ...[
                  _InvoiceRow(
                    invoice: invoice,
                    busy: _busy || !_isAdmin,
                    onPay: () => _payInvoice(invoice),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _banners(UnifySubscription sub) {
    final banners = <Widget>[];

    // A checkout is still out in the browser. The resume hook usually closes
    // this out on its own, but a lifecycle callback is not something to bet a
    // payment on - so there is always a button.
    if (_pendingPaymentId != null) {
      banners.add(_PendingNotice(
        busy: _busy,
        onCheck: () => unawaited(_confirmPending()),
      ));
    }

    if (sub.isPastDue) {
      banners.add(_Notice(
        tone: AppColors.warning,
        title: 'Your renewal is unpaid',
        body: 'Nothing has switched off. Everything keeps working until '
            '${sub.graceEndsAt == null ? 'the grace period ends' : formatDayMonth(sub.graceEndsAt!)}. '
            'Pay the open invoice and your plan carries on as normal.',
      ));
    }
    if (sub.isTrialing && sub.trialEndsAt != null) {
      banners.add(_Notice(
        tone: AppColors.success,
        title: 'You are trialling ${sub.planName}',
        body:
            'Until ${formatDayMonth(sub.trialEndsAt!)}. No card was taken, so nothing will be charged when it ends.',
      ));
    }
    if (sub.cancelAtPeriodEnd && sub.currentPeriodEnd != null) {
      banners.add(_Notice(
        tone: AppColors.warning,
        title: 'This plan ends on ${formatDayMonth(sub.currentPeriodEnd!)}',
        body:
            'Until then nothing changes. You can undo the cancellation at any time.',
      ));
    }
    if (sub.status == 'Expired' && sub.isFree) {
      banners.add(const _Notice(
        tone: AppColors.textMuted,
        title: 'You are back on Starter',
        body:
            'Your paid plan has ended. All your data is still here — resubscribe and everything switches back on.',
      ));
    }

    return banners.isEmpty
        ? const []
        : [
            ...banners.expand((b) => [b, const SizedBox(height: 12)])
          ];
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _choose(
      UnifyPlan plan, UnifySubscription sub, String currency) async {
    if (plan.isFree) {
      await _cancel(sub);
      return;
    }

    setState(() => _busy = true);
    try {
      final quote = await ref.read(unifyPlanRepositoryProvider).quote(
            planCode: plan.code,
            period: _period,
            currency: currency,
          );
      if (!mounted) return;
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: AppColors.overlaySurface,
        isScrollControlled: true,
        builder: (_) => _QuoteSheet(quote: quote),
      );
      if (confirmed != true) return;

      final checkout = await ref.read(unifyPlanRepositoryProvider).checkout(
            planCode: plan.code,
            period: _period,
            currency: currency,
            promotionCode: quote.promotionCode,
            returnUrl: _returnUrl,
          );
      await _settle(checkout);
    } catch (error) {
      _handleError(error, 'That plan change could not be started.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buyAddOn(PlanAddOn addOn, String currency) async {
    setState(() => _busy = true);
    try {
      final checkout = await ref
          .read(unifyPlanRepositoryProvider)
          .buyAddOn(addOn.code, quantity: 1, currency: currency);
      await _settle(checkout);
    } catch (error) {
      _handleError(error, 'That purchase could not be started.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payInvoice(UnifyInvoice invoice) async {
    setState(() => _busy = true);
    try {
      final checkout = await ref
          .read(unifyPlanRepositoryProvider)
          .payInvoice(invoice.id, returnUrl: _returnUrl);
      await _settle(checkout);
    } catch (error) {
      _handleError(error, 'That invoice could not be paid.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The one place a checkout ends up, whichever button started it.
  ///
  /// A real gateway hands back a hosted page, which opens in the system
  /// browser. The plan only changes once the provider tells the server it
  /// was paid, so on the way back we ask rather than assume. The sandbox has
  /// no page to send anybody to, so it is confirmed inline - which is what
  /// makes the whole flow demonstrable without live credentials.
  Future<void> _settle(PlanCheckout checkout) async {
    if (checkout.completed) {
      _say('Your plan is live.');
      _refresh();
      return;
    }

    if (checkout.redirectUrl != null && checkout.provider != 'Manual') {
      // Remember it *before* leaving: once the browser is open this screen
      // may be disposed and rebuilt, and the id is the only handle we have
      // on a payment that is now happening somewhere else.
      _pendingPaymentId = checkout.paymentId;

      final opened = await launchUrl(Uri.parse(checkout.redirectUrl!),
          mode: LaunchMode.externalApplication);
      if (!opened) {
        _pendingPaymentId = null;
        _say('Could not open the payment page.', bad: true);
        return;
      }
      _say('Finish the payment in your browser, then come back here.');
      return;
    }

    final invoice =
        await ref.read(unifyPlanRepositoryProvider).confirm(checkout.paymentId);
    if (invoice.status == 'Paid') {
      _say(checkout.simulated
          ? 'Sandbox payment accepted — ${invoice.number} settled. No real money moved.'
          : 'Payment received — ${invoice.number} settled.');
    } else {
      _say('That payment did not settle. Nothing has changed on your plan.',
          bad: true);
    }
    _refresh();
  }

  /// Asks the server what became of a checkout that finished in the browser.
  ///
  /// Run when the app comes back to the foreground and on pull-to-refresh.
  /// The server reads the outcome back from the gateway; a still-pending
  /// answer is left alone so a slow bank does not look like a failure, and
  /// the next resume asks again.
  Future<void> _confirmPending() async {
    final paymentId = _pendingPaymentId;
    if (paymentId == null || _busy) return;

    setState(() => _busy = true);
    try {
      final invoice =
          await ref.read(unifyPlanRepositoryProvider).confirm(paymentId);
      switch (invoice.status) {
        case 'Paid':
          _pendingPaymentId = null;
          _say('Payment received — ${invoice.number} settled.');
        case 'Failed':
          _pendingPaymentId = null;
          _say(
              'That payment did not go through. Nothing has changed on your plan.',
              bad: true);
        default:
          // Still with the bank. Keep the id so the next resume re-checks.
          _say('Your payment is still being processed.');
      }
      _refresh();
    } catch (error) {
      _handleError(error, 'We could not check that payment.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startTrial(UnifySubscription sub) async {
    setState(() => _busy = true);
    try {
      await ref.read(unifyPlanRepositoryProvider).startTrial();
      _say('Your trial has started. Everything is switched on.');
      _refresh();
    } catch (error) {
      _handleError(error, 'The trial could not be started.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resume() async {
    setState(() => _busy = true);
    try {
      await ref.read(unifyPlanRepositoryProvider).resume();
      _say('Your plan will keep renewing.');
      _refresh();
    } catch (error) {
      _handleError(error, 'That could not be undone.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(UnifySubscription sub) async {
    if (sub.isFree) {
      _say('You are already on the free plan.');
      return;
    }

    final endsOn = sub.currentPeriodEnd;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.overlaySurface,
        title: Text('Cancel your plan?', style: AppTextStyles.title),
        content: Text(
          sub.isTrialing
              ? 'Your trial ends straight away and you move to Starter. Nothing is deleted.'
              : 'You keep everything in ${sub.planName}'
                  '${endsOn == null ? '' : ' until ${formatDayMonth(endsOn)}'}, then move to Starter. '
                  'Nothing is deleted — your bookings, invoices and stock all stay exactly where they are.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep my plan'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel plan',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(unifyPlanRepositoryProvider)
          .cancel(immediate: sub.isTrialing);
      _say(updated.cancelAtPeriodEnd
          ? 'Cancelled. You keep ${sub.planName} until the end of the term.'
          : 'You are back on Starter. All your data is still here.');
      _refresh();
    } catch (error) {
      _handleError(error, 'The cancellation did not go through.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handleError(Object error, String fallback) {
    final paywall = PlanPaywall.of(error);
    _say(paywall?.message ?? planErrorMessage(error, fallback), bad: true);
  }
}

/// The server's own message where there is one - the same rule
/// `billingErrorMessage` follows, kept here so this screen does not drag in
/// the whole billing repository for one function.
String planErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final body = error.response?.data;
    if (body is Map && body['message'] is String) {
      return body['message'] as String;
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Could not reach the server. Check your connection.';
    }
  }
  return fallback;
}

String _creditLabel(String type) => switch (type) {
      'spotlight' => 'Spotlights',
      'ai-run' => 'AI credits',
      'sms' => 'message credits',
      'seat' => 'extra seats',
      _ => type,
    };

// ── Pieces ──────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  const _Pill(this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Text(label,
            style: AppTextStyles.caption.copyWith(color: AppColors.textBody)),
      );
}

class _PendingNotice extends StatelessWidget {
  final bool busy;
  final VoidCallback onCheck;
  const _PendingNotice({required this.busy, required this.onCheck});

  @override
  Widget build(BuildContext context) => GlassCard(
        borderColor: AppColors.cyan,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Waiting for your payment',
                style: AppTextStyles.subtitle.copyWith(color: AppColors.cyan)),
            const SizedBox(height: 6),
            Text(
              'Finish it in the browser tab that opened. Once you are back here we check with '
              'your bank automatically - or check now.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textBody),
            ),
            const SizedBox(height: 12),
            GhostButton(
              label: 'Check payment status',
              onPressed: busy ? null : onCheck,
              height: 42,
            ),
          ],
        ),
      );
}

class _Notice extends StatelessWidget {
  final Color tone;
  final String title;
  final String body;
  const _Notice({required this.tone, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => GlassCard(
        borderColor: tone,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.subtitle.copyWith(color: tone)),
            const SizedBox(height: 6),
            Text(body,
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textBody)),
          ],
        ),
      );
}

class _OfferCard extends StatelessWidget {
  final PlanOffer offer;
  const _OfferCard({required this.offer});

  @override
  Widget build(BuildContext context) => GlassCard(
        borderColor: AppColors.success,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(offer.name,
                style:
                    AppTextStyles.subtitle.copyWith(color: AppColors.success)),
            const SizedBox(height: 6),
            Text(
              '${offer.description}. Applied automatically at checkout'
              '${offer.endsAt == null ? '' : ', until ${formatDayMonth(offer.endsAt!)}'}. '
              'The renewal after that is at the standard price.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textBody),
            ),
          ],
        ),
      );
}

class _CurrentPlanCard extends StatelessWidget {
  final UnifySubscription sub;
  final bool busy;
  final bool canManage;
  final VoidCallback onStartTrial;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  const _CurrentPlanCard({
    required this.sub,
    required this.busy,
    required this.canManage,
    required this.onStartTrial,
    required this.onResume,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final meta = sub.isFree
        ? 'Free forever. Upgrade whenever you need more.'
        : sub.isTrialing
            ? 'Trial ends ${sub.trialEndsAt == null ? 'soon' : formatDayMonth(sub.trialEndsAt!)}'
            : '${formatMoney(sub.amount, sub.currency)} every ${sub.periodLabel.toLowerCase()} · '
                '${sub.cancelAtPeriodEnd ? 'ends' : 'renews'} '
                '${sub.currentPeriodEnd == null ? '—' : formatDayMonth(sub.currentPeriodEnd!)}';

    return GlassCard(
      borderColor: sub.isFree ? null : AppColors.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child:
                      Text(sub.planName, style: AppTextStyles.headlineSmall)),
              if (sub.isComplimentary) const _Pill('Complimentary'),
            ],
          ),
          const SizedBox(height: 6),
          Text(meta,
              style: AppTextStyles.caption.copyWith(color: AppColors.textBody)),
          if (canManage) ...[
            const SizedBox(height: 14),
            if (sub.trialAvailable)
              NeonButton(
                label: 'Start ${sub.trialDays}-day free trial',
                onPressed: busy ? null : onStartTrial,
              ),
            if (sub.cancelAtPeriodEnd)
              GhostButton(
                  label: 'Keep my plan', onPressed: busy ? null : onResume),
            if (!sub.isFree && !sub.cancelAtPeriodEnd && !sub.isComplimentary)
              GhostButton(
                label: 'Cancel plan',
                color: AppColors.danger,
                onPressed: busy ? null : onCancel,
              ),
          ],
        ],
      ),
    );
  }
}

class _MeterCard extends StatelessWidget {
  final UsageMeter meter;
  const _MeterCard({required this.meter});

  @override
  Widget build(BuildContext context) {
    final tone = meter.isExhausted
        ? AppColors.error
        : meter.fraction >= 0.8
            ? AppColors.warning
            : AppColors.cyan;

    final note = meter.isUnlimited
        ? 'No limit on your plan.'
        : meter.limit == 0
            ? 'Not included on your plan.'
            : meter.isExhausted
                ? meter.credits > 0
                    ? 'Allowance spent — ${meter.credits} bought credits will cover the next ones.'
                    : 'Allowance spent for this month.'
                : '${meter.limit! - meter.used} left this month'
                    '${meter.credits > 0 ? ', plus ${meter.credits} bought' : ''}.';

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(meter.label,
                    style: AppTextStyles.label
                        .copyWith(color: AppColors.textMuted)),
              ),
              Text(
                '${meter.used} / ${meter.isUnlimited ? 'Unlimited' : meter.limit}',
                style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (!meter.isUnlimited) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: meter.fraction,
                minHeight: 6,
                backgroundColor: AppColors.glassFill,
                valueColor: AlwaysStoppedAnimation<Color>(tone),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(note,
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _TermPicker extends StatelessWidget {
  final PricingCatalog catalog;
  final String period;
  final ValueChanged<String> onChanged;

  const _TermPicker(
      {required this.catalog, required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    /// The saving on a term is the deepest any plan offers on it, read from
    /// the data so a future per-plan discount cannot make the label a lie.
    int saving(String term) {
      var best = 0;
      for (final plan in catalog.plans) {
        final price = plan.priceFor(term);
        if (price != null && price.savingsPercent > best) {
          best = price.savingsPercent;
        }
      }
      return best;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final term in const ['Monthly', 'SemiAnnual', 'Annual'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: term == period,
                onSelected: (_) => onChanged(term),
                showCheckmark: false,
                backgroundColor: AppColors.glassFill,
                selectedColor: AppColors.cyan,
                side: BorderSide(
                    color: term == period
                        ? AppColors.cyan
                        : AppColors.glassBorder),
                label: Text(
                  saving(term) > 0
                      ? '${billingPeriodLabel(term)} · save ${saving(term)}%'
                      : billingPeriodLabel(term),
                  style: AppTextStyles.caption.copyWith(
                    color: term == period
                        ? AppColors.onPrimary
                        : AppColors.textBody,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final UnifyPlan plan;
  final PlanPrice? price;
  final String currency;
  final bool isCurrent;
  final int currentTier;
  final bool busy;
  final VoidCallback onChoose;

  const _PlanCard({
    required this.plan,
    required this.price,
    required this.currency,
    required this.isCurrent,
    required this.currentTier,
    required this.busy,
    required this.onChoose,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: isCurrent
          ? AppColors.success
          : plan.isMostPopular
              ? AppColors.cyan
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(plan.name, style: AppTextStyles.title)),
              if (isCurrent)
                const _Pill('Your plan')
              else if (plan.isMostPopular)
                const _Pill('Most popular'),
            ],
          ),
          const SizedBox(height: 4),
          Text(plan.tagline,
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          if (plan.isFree)
            Text('Free', style: AppTextStyles.stat)
          else if (price == null)
            Text('Not sold in $currency on this term.',
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textMuted))
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(formatMoney(price!.monthlyEquivalent, currency),
                    style: AppTextStyles.stat),
                const SizedBox(width: 6),
                Text('/ month',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textMuted)),
                if (price!.savingsPercent > 0) ...[
                  const SizedBox(width: 8),
                  _Pill('−${price!.savingsPercent}%'),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${formatMoney(price!.amount, currency)} billed every ${price!.periodLabel.toLowerCase()}',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: 12),
          for (final highlight in plan.highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_rounded,
                      size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(highlight,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textBody)),
                  ),
                ],
              ),
            ),
          if (plan.trialDays > 0 && !isCurrent)
            Text('${plan.trialDays}-day free trial, no card needed.',
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          if (isCurrent)
            const GhostButton(label: 'Current plan', onPressed: null)
          else if (plan.isMostPopular)
            NeonButton(
              label: plan.tier > currentTier
                  ? 'Upgrade to ${plan.name}'
                  : 'Switch to ${plan.name}',
              onPressed:
                  busy || (!plan.isFree && price == null) ? null : onChoose,
            )
          else
            GhostButton(
              label: plan.isFree
                  ? 'Move to Starter'
                  : plan.tier > currentTier
                      ? 'Upgrade to ${plan.name}'
                      : 'Switch to ${plan.name}',
              onPressed:
                  busy || (!plan.isFree && price == null) ? null : onChoose,
            ),
        ],
      ),
    );
  }
}

class _AddOnCard extends StatelessWidget {
  final PlanAddOn addOn;
  final bool busy;
  final VoidCallback onBuy;

  const _AddOnCard(
      {required this.addOn, required this.busy, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      borderColor: addOn.isBestValue ? AppColors.success : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(addOn.name, style: AppTextStyles.subtitle)),
              if (addOn.isBestValue) const _Pill('Best value'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(formatMoney(addOn.amount, addOn.currency),
                  style: AppTextStyles.title),
              if (addOn.comparedAtAmount > addOn.amount) ...[
                const SizedBox(width: 8),
                Text(
                  formatMoney(addOn.comparedAtAmount, addOn.currency),
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textMuted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 6),
                _Pill('−${addOn.savingsPercent}%'),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(addOn.tagline,
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 10),
          GhostButton(
            label: addOn.availableOnCurrentPlan ? 'Buy' : 'Needs a paid plan',
            onPressed:
                busy || !addOn.availableOnCurrentPlan || addOn.amount <= 0
                    ? null
                    : onBuy,
            height: 42,
          ),
        ],
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final UnifyInvoice invoice;
  final bool busy;
  final VoidCallback onPay;

  const _InvoiceRow(
      {required this.invoice, required this.busy, required this.onPay});

  @override
  Widget build(BuildContext context) {
    final tone = switch (invoice.status) {
      'Paid' => AppColors.success,
      'Failed' => AppColors.error,
      'Issued' => AppColors.warning,
      _ => AppColors.textMuted,
    };

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invoice.number, style: AppTextStyles.body),
                const SizedBox(height: 2),
                Text(
                  '${invoice.kind == 'AddOn' ? 'Add-on' : invoice.planCode ?? 'Plan'} · '
                  '${formatDayMonth(invoice.issuedAt)}',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatMoney(invoice.total, invoice.currency),
                  style: AppTextStyles.body),
              const SizedBox(height: 2),
              Text(invoice.status,
                  style: AppTextStyles.caption.copyWith(color: tone)),
            ],
          ),
          if (invoice.isPayable) ...[
            const SizedBox(width: 10),
            GhostButton(
                label: 'Pay',
                onPressed: busy ? null : onPay,
                height: 38,
                expand: false),
          ],
        ],
      ),
    );
  }
}

/// The confirm step. Every number the tenant is about to agree to, including
/// what the renewal will cost once a first-term offer has run out.
class _QuoteSheet extends StatelessWidget {
  final PlanQuote quote;
  const _QuoteSheet({required this.quote});

  @override
  Widget build(BuildContext context) {
    Widget line(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: strong
                        ? AppTextStyles.subtitle
                        : AppTextStyles.caption
                            .copyWith(color: AppColors.textBody)),
              ),
              Text(value,
                  style:
                      strong ? AppTextStyles.subtitle : AppTextStyles.caption),
            ],
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${quote.planName} · ${quote.periodLabel}',
                style: AppTextStyles.title),
            const SizedBox(height: 14),
            line('${quote.planName} — ${quote.periodLabel}',
                formatMoney(quote.listAmount, quote.currency)),
            if (quote.prorationCredit > 0)
              line('Credit for unused time',
                  '−${formatMoney(quote.prorationCredit, quote.currency)}'),
            if (quote.discount > 0)
              line('Offer ${quote.promotionCode ?? ''}'.trim(),
                  '−${formatMoney(quote.discount, quote.currency)}'),
            const Divider(height: 20),
            line('Due now', formatMoney(quote.total, quote.currency),
                strong: true),
            const SizedBox(height: 12),
            Text(
              'Renews at ${formatMoney(quote.renewalAmount, quote.currency)} every '
              '${quote.periodLabel.toLowerCase()}. You can cancel any time and keep access until the term ends.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
            if (quote.promotionMessage != null) ...[
              const SizedBox(height: 6),
              Text(quote.promotionMessage!,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted)),
            ],
            const SizedBox(height: 18),
            NeonButton(
              label: quote.total <= 0
                  ? 'Activate'
                  : 'Pay ${formatMoney(quote.total, quote.currency)}',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 8),
            GhostButton(
                label: 'Not now',
                onPressed: () => Navigator.of(context).pop(false)),
          ],
        ),
      ),
    );
  }
}
