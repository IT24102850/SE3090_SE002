import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/admin_billing_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// Where the money actually lands — the mobile twin of the web Payment
/// Gateways page. Secrets are write-only: the server returns whether a key
/// is stored and a hint, never the key, and leaving the field blank on an
/// edit keeps whatever is already there rather than wiping it.
class PaymentGatewaysScreen extends ConsumerWidget {
  const PaymentGatewaysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OwnerScaffold(
      title: 'Payment Gateways',
      subtitle: 'How customers pay you',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Connect'),
      ),
      body: AsyncList<PaymentGatewayConfig>(
        provider: paymentGatewaysProvider,
        onRefresh: (ref) => ref.invalidate(paymentGatewaysProvider),
        emptyMessage: 'No gateway connected — payments are recorded by hand.',
        emptyIcon: Icons.lock_outline,
        builder: (gateways) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: gateways.length,
          itemBuilder: (context, i) => _GatewayCard(gateway: gateways[i]),
        ),
      ),
    );
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, PaymentGatewayConfig? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _GatewayForm(existing: existing),
      ),
    );
    if (saved == true) ref.invalidate(paymentGatewaysProvider);
  }
}

class _GatewayCard extends ConsumerStatefulWidget {
  final PaymentGatewayConfig gateway;
  const _GatewayCard({required this.gateway});

  @override
  ConsumerState<_GatewayCard> createState() => _GatewayCardState();
}

class _GatewayCardState extends ConsumerState<_GatewayCard> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.gateway;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: () => PaymentGatewaysScreen._edit(context, ref, g),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconWell(icon: Icons.account_balance_outlined, color: AppColors.cyan),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      Text('${g.provider} · ${g.currency}', style: AppTextStyles.caption),
                    ],
                  ),
                ),
                OwnerStatusChip(status: g.isActive ? 'Active' : 'Paused'),
              ],
            ),
            const SizedBox(height: 10),
            DetailRow(label: 'Mode', value: g.isTestMode ? 'Test' : 'Live', valueColor: g.isTestMode ? AppColors.warning : AppColors.success),
            DetailRow(label: 'Secret key', value: g.hasApiKey ? (g.apiKeyHint ?? 'stored') : 'not set'),
            DetailRow(label: 'Webhook secret', value: g.hasWebhookSecret ? 'stored' : 'not set'),
            if (g.webhookUrl?.isNotEmpty == true) DetailRow(label: 'Webhook URL', value: g.webhookUrl!),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: _testing ? 'Testing…' : 'Test connection',
                    icon: Icons.network_check_rounded,
                    height: 40,
                    onPressed: _testing ? null : () => _test(g),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GhostButton(
                    label: 'Remove',
                    icon: Icons.link_off_rounded,
                    height: 40,
                    color: AppColors.error,
                    onPressed: () async {
                      try {
                        await ref.read(adminBillingRepositoryProvider).deleteGateway(g.id);
                        ref.invalidate(paymentGatewaysProvider);
                        if (context.mounted) AppSnackBar.success(context, 'Gateway removed.');
                      } catch (_) {
                        if (context.mounted) AppSnackBar.error(context, 'Could not remove this gateway.');
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _test(PaymentGatewayConfig gateway) async {
    setState(() => _testing = true);
    try {
      final result = await ref.read(adminBillingRepositoryProvider).testGateway(gateway.id);
      if (!mounted) return;
      // A simulated pass is not a real one; saying so keeps anyone from
      // believing live card payments have been proven to work.
      final suffix = result.simulated ? ' (simulated — no live call was made)' : '';
      if (result.ok) {
        AppSnackBar.success(context, '${result.message}$suffix');
      } else {
        AppSnackBar.error(context, '${result.message}$suffix');
      }
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'The test could not be run.');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }
}

class _GatewayForm extends ConsumerStatefulWidget {
  final PaymentGatewayConfig? existing;
  const _GatewayForm({this.existing});

  @override
  ConsumerState<_GatewayForm> createState() => _GatewayFormState();
}

class _GatewayFormState extends ConsumerState<_GatewayForm> {
  late final TextEditingController _name;
  late final TextEditingController _currency;
  late final TextEditingController _publicKey;
  final _apiKey = TextEditingController();
  final _webhookSecret = TextEditingController();
  late String _provider;
  late bool _isActive;
  late bool _isTestMode;
  bool _saving = false;

  static const _providers = ['Stripe', 'PayPal', 'Manual'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _currency = TextEditingController(text: e?.currency ?? 'LKR');
    _publicKey = TextEditingController(text: e?.publicKey ?? '');
    _provider = e?.provider ?? 'Stripe';
    _isActive = e?.isActive ?? true;
    _isTestMode = e?.isTestMode ?? true;
  }

  @override
  void dispose() {
    for (final c in [_name, _currency, _publicKey, _apiKey, _webhookSecret]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      AppSnackBar.error(context, 'Give the connection a name.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(adminBillingRepositoryProvider).saveGateway(
            id: widget.existing?.id,
            name: _name.text.trim(),
            provider: _provider,
            currency: _currency.text.trim().isEmpty ? 'LKR' : _currency.text.trim().toUpperCase(),
            isActive: _isActive,
            isTestMode: _isTestMode,
            publicKey: _publicKey.text.trim().isEmpty ? null : _publicKey.text.trim(),
            // Blank means "leave the stored secret alone".
            apiKey: _apiKey.text.isEmpty ? null : _apiKey.text,
            webhookSecret: _webhookSecret.text.isEmpty ? null : _webhookSecret.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not save this gateway.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'Connect a gateway' : 'Edit gateway', style: AppTextStyles.title),
            const SizedBox(height: 12),
            NeonInputField(label: 'Name', controller: _name),
            const SizedBox(height: 12),
            Text('Provider', style: AppTextStyles.label),
            const SizedBox(height: 8),
            FilterChips<String>(
              options: [for (final p in _providers) (value: p, label: p)],
              selected: _provider,
              onSelected: (v) => setState(() => _provider = v ?? 'Stripe'),
            ),
            const SizedBox(height: 12),
            NeonInputField(label: 'Currency', controller: _currency),
            const SizedBox(height: 10),
            NeonInputField(label: 'Publishable key', controller: _publicKey),
            const SizedBox(height: 10),
            NeonInputField(
              label: 'Secret key',
              controller: _apiKey,
              obscurable: true,
              helperText: widget.existing?.hasApiKey == true ? 'Leave blank to keep the stored key' : null,
            ),
            const SizedBox(height: 10),
            NeonInputField(
              label: 'Webhook secret',
              controller: _webhookSecret,
              obscurable: true,
              helperText: widget.existing?.hasWebhookSecret == true ? 'Leave blank to keep the stored secret' : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isTestMode,
              activeColor: AppColors.warning,
              title: Text('Test mode', style: AppTextStyles.body),
              subtitle: Text('No real money moves while this is on.', style: AppTextStyles.caption),
              onChanged: (v) => setState(() => _isTestMode = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              activeColor: AppColors.cyan,
              title: Text('Accept payments through this', style: AppTextStyles.body),
              onChanged: (v) => setState(() => _isActive = v),
            ),
            const SizedBox(height: 12),
            NeonButton(label: 'Save gateway', isLoading: _saving, onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }
}
