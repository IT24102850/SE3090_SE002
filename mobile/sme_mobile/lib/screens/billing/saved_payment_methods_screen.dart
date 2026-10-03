import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../inventory/app_notifications.dart';
import '../../providers/billing_providers.dart';
import '../../services/payment_method_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/ui/ui.dart';

/// Saved payment methods, kept in the device's secure storage.
class SavedPaymentMethodsScreen extends ConsumerWidget {
  const SavedPaymentMethodsScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final label = TextEditingController();
    final last4 = TextEditingController();
    var type = 'Card';
    var makeDefault = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          backgroundColor: AppColors.overlaySurface,
          title: Text('Save a payment method', style: AppTextStyles.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final t in PaymentMethodStore.types)
                    DropdownMenuItem(value: t, child: Text(t))
                ],
                onChanged: (v) => setState(() => type = v ?? 'Card'),
              ),
              TextField(
                  key: const Key('method-label'),
                  controller: label,
                  decoration: const InputDecoration(
                      labelText: 'Nickname (e.g. Work Visa)')),
              if (type == 'Card')
                TextField(
                  key: const Key('method-last4'),
                  controller: last4,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Last 4 digits (optional)',
                      helperText: 'Never your full card number.'),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: makeDefault,
                onChanged: (v) => setState(() => makeDefault = v ?? false),
                title: const Text('Use by default'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialog).pop(false),
                child: const Text('Cancel')),
            TextButton(
                key: const Key('save-method'),
                onPressed: () => Navigator.of(dialog).pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;

    try {
      await ref.read(paymentMethodStoreProvider).add(
          type: type,
          label: label.text,
          last4: last4.text,
          makeDefault: makeDefault);
      ref.invalidate(savedPaymentMethodsProvider);
    } on PaymentMethodValidationException catch (e) {
      if (context.mounted) AppSnackBar.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(savedPaymentMethodsProvider);
    final store = ref.read(paymentMethodStoreProvider);

    return AppBackgroundScaffold(
      appBar: const GlassAppBar(title: 'Saved payment methods'),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        tooltip: 'Add a method',
        onPressed: () => _add(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      child: SafeArea(
        child: methods.when(
          loading: () => const AppLoader(),
          error: (e, _) => ErrorState(
              message: 'Could not read saved methods.',
              onRetry: () => ref.invalidate(savedPaymentMethodsProvider)),
          data: (list) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              GlassCard(
                child: Text(
                  'Stored encrypted on this device only. Card numbers are never saved - you enter them on the payment provider\'s secure page.',
                  style: AppTextStyles.bodyMuted,
                ),
              ),
              const SizedBox(height: 16),
              if (list.isEmpty)
                const EmptyState(
                    icon: Icons.wallet_outlined,
                    message: 'No saved methods yet.'),
              for (final m in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassListTile(
                    key: Key('saved-method-${m.id}'),
                    icon: m.type == 'Card'
                        ? Icons.credit_card_rounded
                        : m.type == 'Cash'
                            ? Icons.payments_outlined
                            : Icons.qr_code_2_rounded,
                    title: m.display,
                    subtitle: m.isDefault ? '${m.type} · default' : m.type,
                    showChevron: false,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'default') await store.setDefault(m.id);
                        if (!context.mounted) return;
                        if (action == 'remove') {
                          final confirmed = await showAppConfirmation(
                            context: context,
                            title: 'Remove payment method?',
                            message:
                                'Remove ${m.display} from this device? This cannot be undone.',
                            confirmLabel: 'Remove',
                            icon: Icons.delete_outline_rounded,
                            accent: AppColors.danger,
                            isDestructive: true,
                          );
                          if (confirmed) await store.remove(m.id);
                        }
                        if (!context.mounted) return;
                        ref.invalidate(savedPaymentMethodsProvider);
                      },
                      itemBuilder: (_) => [
                        if (!m.isDefault)
                          const PopupMenuItem(
                              value: 'default', child: Text('Make default')),
                        const PopupMenuItem(
                            value: 'remove', child: Text('Remove')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
