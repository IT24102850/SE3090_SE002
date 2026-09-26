import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/admin_billing_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../shared/color_utils.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// How an invoice looks when the customer opens it — the mobile twin of the
/// web Invoice Designer. A template is an ordered list of blocks; this
/// screen turns them on and off and reorders them, and the preview is built
/// from that same list, so what is shown is what the PDF will carry.
class InvoiceDesignerScreen extends ConsumerWidget {
  const InvoiceDesignerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OwnerScaffold(
      title: 'Invoice Designer',
      subtitle: 'How your invoices look',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New template'),
      ),
      body: AsyncList<InvoiceTemplate>(
        provider: invoiceTemplatesProvider,
        onRefresh: (ref) => ref.invalidate(invoiceTemplatesProvider),
        emptyMessage: 'No templates yet — invoices use the plain default.',
        emptyIcon: Icons.palette_outlined,
        builder: (templates) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: templates.length,
          itemBuilder: (context, i) => _TemplateCard(template: templates[i]),
        ),
      ),
    );
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, InvoiceTemplate? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _TemplateForm(existing: existing),
      ),
    );
    if (saved == true) ref.invalidate(invoiceTemplatesProvider);
  }
}

class _TemplateCard extends ConsumerWidget {
  final InvoiceTemplate template;
  const _TemplateCard({required this.template});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        onTap: () => InvoiceDesignerScreen._edit(context, ref, template),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(template.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (template.isDefault) const OwnerStatusChip(status: 'Default'),
              ],
            ),
            const SizedBox(height: 4),
            Text('${template.blocks.length} block${template.blocks.length == 1 ? '' : 's'}',
                style: AppTextStyles.caption),
            const SizedBox(height: 10),
            _Preview(template: template),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  try {
                    await ref.read(adminBillingRepositoryProvider).deleteTemplate(template.id);
                    ref.invalidate(invoiceTemplatesProvider);
                    if (context.mounted) AppSnackBar.success(context, 'Template deleted.');
                  } catch (error) {
                    if (context.mounted) AppSnackBar.error(context, serverMessage(error, 'Could not delete this template.'));
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

/// A miniature of the invoice, rendered from the template's own block list
/// and accent, so turning a block off is visible immediately.
class _Preview extends StatelessWidget {
  final InvoiceTemplate template;
  const _Preview({required this.template});

  static const _sample = <String, List<String>>{
    'header': ['INVOICE'],
    'businessInfo': ['Your Business Ltd', '23 Example Road, Colombo'],
    'invoiceMeta': ['INV-20260923-0001 · due 7 Oct'],
    'customerInfo': ['Billed to: A. Customer'],
    'items': ['Service — 1 × 5,000.00', 'Materials — 2 × 750.00'],
    'totals': ['Total  LKR 6,500.00'],
    'payments': ['Paid 6,500.00 · Card'],
    'notes': ['Thanks for your custom.'],
    'footer': ['Bank: 1234567890 · VAT 000000000'],
  };

  @override
  Widget build(BuildContext context) {
    final accent = parseHexColor(template.accentColor) ?? AppColors.cyan;
    final blocks = template.blocks.isEmpty ? const ['header', 'items', 'totals'] : template.blocks;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 6, width: double.infinity, color: accent),
          const SizedBox(height: 10),
          for (final block in blocks) ...[
            if (block == 'header')
              Text(
                template.headerText?.isNotEmpty == true ? template.headerText! : 'INVOICE',
                style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 15),
              )
            else if (block == 'footer')
              Text(
                template.footerText?.isNotEmpty == true ? template.footerText! : (_sample[block]?.first ?? ''),
                style: const TextStyle(color: Colors.black45, fontSize: 10),
              )
            else if (block == 'totals')
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(color: Colors.black54, fontSize: 11)),
                  Text('LKR 6,500.00', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
                ],
              )
            else
              for (final line in _sample[block] ?? const <String>[])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(line, style: const TextStyle(color: Colors.black87, fontSize: 11)),
                ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _TemplateForm extends ConsumerStatefulWidget {
  final InvoiceTemplate? existing;
  const _TemplateForm({this.existing});

  @override
  ConsumerState<_TemplateForm> createState() => _TemplateFormState();
}

class _TemplateFormState extends ConsumerState<_TemplateForm> {
  late final TextEditingController _name;
  late final TextEditingController _header;
  late final TextEditingController _footer;
  late String _accent;
  late bool _isDefault;
  late List<String> _blocks;
  bool _saving = false;

  static const _palette = ['#2563eb', '#0ea5e9', '#16a34a', '#7c3aed', '#f59e0b', '#ef4444', '#0f172a'];

  static const _blockLabels = <String, String>{
    'header': 'Header',
    'businessInfo': 'Your details',
    'invoiceMeta': 'Invoice number & dates',
    'customerInfo': 'Customer details',
    'items': 'Line items',
    'totals': 'Totals',
    'payments': 'Payments received',
    'notes': 'Notes',
    'footer': 'Footer',
  };

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _header = TextEditingController(text: e?.headerText ?? '');
    _footer = TextEditingController(text: e?.footerText ?? '');
    _accent = e?.accentColor ?? _palette.first;
    _isDefault = e?.isDefault ?? false;
    // A new template starts with the blocks an invoice cannot do without.
    _blocks = [...?e?.blocks];
    if (_blocks.isEmpty) {
      _blocks = ['header', 'businessInfo', 'invoiceMeta', 'customerInfo', 'items', 'totals', 'footer'];
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _header, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      AppSnackBar.error(context, 'Give the template a name.');
      return;
    }
    if (_blocks.isEmpty) {
      AppSnackBar.error(context, 'An invoice needs at least one block.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(adminBillingRepositoryProvider).saveTemplate(
            id: widget.existing?.id,
            name: _name.text.trim(),
            blocks: _blocks,
            accentColor: _accent,
            headerText: _header.text.trim().isEmpty ? null : _header.text.trim(),
            footerText: _footer.text.trim().isEmpty ? null : _footer.text.trim(),
            isDefault: _isDefault,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) AppSnackBar.error(context, serverMessage(error, 'Could not save this template.'));
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
            Text(widget.existing == null ? 'New template' : 'Edit template', style: AppTextStyles.title),
            const SizedBox(height: 12),
            NeonInputField(label: 'Template name', controller: _name),
            const SizedBox(height: 10),
            NeonInputField(label: 'Header text', controller: _header, onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            NeonInputField(
              label: 'Footer text',
              controller: _footer,
              maxLines: 2,
              helperText: 'Bank details, thanks, terms…',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Text('Blocks', style: AppTextStyles.label),
            const SizedBox(height: 4),
            Text('Drag to reorder; a block can appear once.', style: AppTextStyles.caption),
            const SizedBox(height: 8),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorder: (oldIndex, newIndex) => setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                _blocks.insert(newIndex, _blocks.removeAt(oldIndex));
              }),
              children: [
                for (final block in _blocks)
                  ListTile(
                    key: ValueKey(block),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.drag_handle_rounded, color: AppColors.chevron),
                    title: Text(_blockLabels[block] ?? block, style: AppTextStyles.body),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.error, size: 20),
                      onPressed: () => setState(() => _blocks.remove(block)),
                    ),
                  ),
              ],
            ),
            if (_blocks.length < InvoiceTemplate.allBlocks.length) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final block in InvoiceTemplate.allBlocks.where((b) => !_blocks.contains(b)))
                    ActionChip(
                      label: Text('+ ${_blockLabels[block] ?? block}', style: AppTextStyles.caption),
                      backgroundColor: AppColors.glassFill,
                      side: const BorderSide(color: AppColors.glassBorder),
                      onPressed: () => setState(() => _blocks.add(block)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Text('Accent colour', style: AppTextStyles.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                for (final hex in _palette)
                  GestureDetector(
                    onTap: () => setState(() => _accent = hex),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: parseHexColor(hex) ?? AppColors.cyan,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _accent == hex ? AppColors.textPrimary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isDefault,
              activeColor: AppColors.cyan,
              title: Text('Use this by default', style: AppTextStyles.body),
              onChanged: (v) => setState(() => _isDefault = v),
            ),
            const SizedBox(height: 10),
            Text('Preview', style: AppTextStyles.label),
            const SizedBox(height: 8),
            _Preview(
              template: InvoiceTemplate(
                id: '',
                name: _name.text,
                isDefault: _isDefault,
                accentColor: _accent,
                headerText: _header.text,
                footerText: _footer.text,
                blocks: _blocks,
              ),
            ),
            const SizedBox(height: 14),
            NeonButton(label: 'Save template', isLoading: _saving, onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }
}
