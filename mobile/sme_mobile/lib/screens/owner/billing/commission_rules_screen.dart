import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/admin_billing_models.dart';
import '../../../models/billing_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// Who gets paid what on a sale — the mobile twin of the web Commission
/// Rules page, with the same calculator so a rule can be checked against a
/// real figure before anyone relies on it.
class CommissionRulesScreen extends ConsumerWidget {
  const CommissionRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OwnerScaffold(
      title: 'Commission Rules',
      subtitle: 'What each role earns',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New rule'),
      ),
      body: AsyncList<CommissionRule>(
        provider: commissionRulesProvider,
        onRefresh: (ref) => ref.invalidate(commissionRulesProvider),
        emptyMessage: 'No payout rules yet. Add the first one.',
        emptyIcon: Icons.handshake_outlined,
        builder: (rules) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            const _Calculator(),
            const SizedBox(height: 14),
            SectionHeader('${rules.length} rule${rules.length == 1 ? '' : 's'}'),
            ...rules.map((rule) => _RuleCard(rule: rule)),
          ],
        ),
      ),
    );
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, CommissionRule? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _RuleForm(existing: existing),
      ),
    );
    if (saved == true) ref.invalidate(commissionRulesProvider);
  }
}

class _Calculator extends ConsumerStatefulWidget {
  const _Calculator();

  @override
  ConsumerState<_Calculator> createState() => _CalculatorState();
}

class _CalculatorState extends ConsumerState<_Calculator> {
  final _amount = TextEditingController(text: '10000');
  Map<String, dynamic>? _result;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(adminBillingRepositoryProvider)
          .calculateSplit(amount: double.tryParse(_amount.text) ?? 0);
      if (mounted) setState(() => _result = result);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not work that out.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = (_result?['lines'] as List<dynamic>?) ?? const [];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Try a sale', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('See what every live rule would pay out on this amount.', style: AppTextStyles.caption),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: NeonInputField(
                  label: 'Sale amount',
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 118,
                child: GhostButton(label: 'Work it out', height: 48, onPressed: _busy ? null : _calculate),
              ),
            ],
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: AppLoader(size: 18)),
          if (_result != null && !_busy) ...[
            const Divider(color: AppColors.hairline, height: 22),
            if (lines.isEmpty)
              Text('No active rule applies to this sale.', style: AppTextStyles.caption)
            else
              for (final line in lines.whereType<Map<String, dynamic>>())
                DetailRow(
                  label: '${line['ruleName'] ?? line['role'] ?? 'Payout'}'
                      '${line['clamped'] == true ? ' (capped)' : ''}',
                  value: formatMoney((line['amount'] as num?)?.toDouble() ?? 0),
                ),
            if (_result!['totalCommission'] != null)
              DetailRow(
                label: 'Total paid out',
                value: formatMoney((_result!['totalCommission'] as num).toDouble()),
                valueColor: AppColors.cyan,
              ),
            if (_result!['netToBusiness'] != null)
              DetailRow(
                label: 'Left for the business',
                value: formatMoney((_result!['netToBusiness'] as num).toDouble()),
                valueColor: AppColors.success,
              ),
          ],
        ],
      ),
    );
  }
}

class _RuleCard extends ConsumerWidget {
  final CommissionRule rule;
  const _RuleCard({required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: () => CommissionRulesScreen._edit(context, ref, rule),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rule.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                      Text('${rule.role.isEmpty ? 'Any role' : rule.role} · ${rule.summary}',
                          style: AppTextStyles.caption),
                    ],
                  ),
                ),
                OwnerStatusChip(status: rule.isActive ? 'Active' : 'Paused'),
              ],
            ),
            if (rule.description?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(rule.description!, style: AppTextStyles.caption),
            ],
            if (rule.minAmount != null || rule.maxAmount != null) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (rule.minAmount != null) 'at least ${formatMoney(rule.minAmount!)}',
                  if (rule.maxAmount != null) 'capped at ${formatMoney(rule.maxAmount!)}',
                ].join(' · '),
                style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: AppColors.overlaySurface,
                      title: Text('Delete "${rule.name}"?', style: AppTextStyles.title),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete', style: TextStyle(color: AppColors.error)),
                        ),
                      ],
                    ),
                  );
                  if (ok != true || !context.mounted) return;
                  try {
                    await ref.read(adminBillingRepositoryProvider).deleteCommissionRule(rule.id);
                    ref.invalidate(commissionRulesProvider);
                    if (context.mounted) AppSnackBar.success(context, 'Rule deleted.');
                  } catch (_) {
                    if (context.mounted) AppSnackBar.error(context, 'Could not delete this rule.');
                  }
                },
                child: Text('Delete', style: AppTextStyles.caption.copyWith(color: AppColors.error)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleForm extends ConsumerStatefulWidget {
  final CommissionRule? existing;
  const _RuleForm({this.existing});

  @override
  ConsumerState<_RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends ConsumerState<_RuleForm> {
  late final TextEditingController _name;
  late final TextEditingController _role;
  late final TextEditingController _rate;
  late final TextEditingController _fixed;
  late final TextEditingController _min;
  late final TextEditingController _max;
  late final TextEditingController _description;
  late String _ruleType;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _role = TextEditingController(text: e?.role ?? '');
    _rate = TextEditingController(text: e?.rate.toString() ?? '10');
    _fixed = TextEditingController(text: e?.fixedAmount?.toString() ?? '');
    _min = TextEditingController(text: e?.minAmount?.toString() ?? '');
    _max = TextEditingController(text: e?.maxAmount?.toString() ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _ruleType = e?.ruleType ?? 'Percentage';
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final c in [_name, _role, _rate, _fixed, _min, _max, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      AppSnackBar.error(context, 'Give the rule a name.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(adminBillingRepositoryProvider).saveCommissionRule(
            id: widget.existing?.id,
            name: _name.text.trim(),
            ruleType: _ruleType,
            rate: double.tryParse(_rate.text) ?? 0,
            fixedAmount: double.tryParse(_fixed.text),
            minAmount: double.tryParse(_min.text),
            maxAmount: double.tryParse(_max.text),
            role: _role.text.trim().isEmpty ? null : _role.text.trim(),
            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
            isActive: _isActive,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not save this rule.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPercentage = _ruleType == 'Percentage';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'New rule' : 'Edit rule', style: AppTextStyles.title),
            const SizedBox(height: 12),
            NeonInputField(label: 'Name', controller: _name),
            const SizedBox(height: 10),
            NeonInputField(label: 'Role it pays', controller: _role, helperText: 'blank = any role'),
            const SizedBox(height: 12),
            Text('How it is worked out', style: AppTextStyles.label),
            const SizedBox(height: 8),
            FilterChips<String>(
              options: const [(value: 'Percentage', label: 'Percentage'), (value: 'Fixed', label: 'Fixed amount')],
              selected: _ruleType,
              onSelected: (v) => setState(() => _ruleType = v ?? 'Percentage'),
            ),
            const SizedBox(height: 12),
            if (isPercentage)
              NeonInputField(
                label: 'Rate %',
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              )
            else
              NeonInputField(
                label: 'Amount per sale',
                controller: _fixed,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: NeonInputField(
                  label: 'Minimum payout',
                  controller: _min,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NeonInputField(
                  label: 'Cap',
                  controller: _max,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            NeonInputField(label: 'Description', controller: _description, maxLines: 2),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              activeColor: AppColors.cyan,
              title: Text('Live', style: AppTextStyles.body),
              subtitle: Text('Turn off to stop paying it without deleting.', style: AppTextStyles.caption),
              onChanged: (v) => setState(() => _isActive = v),
            ),
            const SizedBox(height: 12),
            NeonButton(label: 'Save rule', isLoading: _saving, onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }
}
