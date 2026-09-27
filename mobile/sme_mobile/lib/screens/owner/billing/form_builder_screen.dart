import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/admin_billing_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

/// The dynamic form builder — the mobile twin of the web Form Builder.
/// Fields are edited as a list rather than as raw JSON (a phone is a poor
/// place to hand-write a schema), and the same server-side validator that
/// guards real submissions is used for the preview, so a form cannot look
/// valid here and be rejected in production.
class FormBuilderScreen extends ConsumerWidget {
  const FormBuilderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OwnerScaffold(
      title: 'Form Builder',
      subtitle: 'Extra fields you collect',
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New form'),
      ),
      body: AsyncList<DynamicFormDefinition>(
        provider: dynamicFormsProvider,
        onRefresh: (ref) => ref.invalidate(dynamicFormsProvider),
        emptyMessage: 'No custom forms yet.',
        emptyIcon: Icons.extension_outlined,
        builder: (forms) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: forms.length,
          itemBuilder: (context, i) => _FormCard(definition: forms[i]),
        ),
      ),
    );
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, DynamicFormDefinition? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _FormEditor(existing: existing),
      ),
    );
    if (saved == true) ref.invalidate(dynamicFormsProvider);
  }
}

class _FormCard extends ConsumerWidget {
  final DynamicFormDefinition definition;
  const _FormCard({required this.definition});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: () => FormBuilderScreen._edit(context, ref, definition),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(definition.formType, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text('${definition.submissionCount} submitted', style: AppTextStyles.caption),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final field in definition.fieldNames)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.glassFill,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: definition.requiredFields.contains(field)
                            ? AppColors.cyan.withValues(alpha: .5)
                            : AppColors.glassBorder,
                      ),
                    ),
                    child: Text(
                      definition.requiredFields.contains(field) ? '$field *' : field,
                      style: AppTextStyles.caption,
                    ),
                  ),
                if (definition.fieldNames.isEmpty) Text('No fields yet.', style: AppTextStyles.caption),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  try {
                    await ref.read(adminBillingRepositoryProvider).deleteForm(definition.formType);
                    ref.invalidate(dynamicFormsProvider);
                    if (context.mounted) AppSnackBar.success(context, 'Form deleted.');
                  } catch (_) {
                    if (context.mounted) AppSnackBar.error(context, 'Could not delete this form.');
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

/// One field being edited. `type` maps straight onto the JSON-schema type
/// the server validates against.
class _FieldDraft {
  String name;
  String type;
  bool required;
  int minLength;

  _FieldDraft({this.name = '', this.type = 'string', this.required = false, this.minLength = 0});
}

class _FormEditor extends ConsumerStatefulWidget {
  final DynamicFormDefinition? existing;
  const _FormEditor({this.existing});

  @override
  ConsumerState<_FormEditor> createState() => _FormEditorState();
}

class _FormEditorState extends ConsumerState<_FormEditor> {
  late final TextEditingController _formType;
  late List<_FieldDraft> _fields;
  final Map<String, TextEditingController> _sample = {};
  bool _saving = false;
  ({bool isValid, List<String> errors})? _preview;

  static const _types = ['string', 'number', 'integer', 'boolean'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _formType = TextEditingController(text: e?.formType ?? '');
    _fields = [];
    if (e != null) {
      final properties = (e.schema['properties'] as Map<String, dynamic>?) ?? const {};
      for (final entry in properties.entries) {
        final spec = (entry.value as Map<String, dynamic>?) ?? const {};
        _fields.add(_FieldDraft(
          name: entry.key,
          type: (spec['type'] ?? 'string').toString(),
          required: e.requiredFields.contains(entry.key),
          minLength: (spec['minLength'] as num?)?.toInt() ?? 0,
        ));
      }
    }
    if (_fields.isEmpty) _fields.add(_FieldDraft());
  }

  @override
  void dispose() {
    _formType.dispose();
    for (final c in _sample.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _buildSchema() {
    final properties = <String, dynamic>{};
    final required = <String>[];
    for (final field in _fields) {
      final name = field.name.trim();
      if (name.isEmpty) continue;
      properties[name] = {
        'type': field.type,
        if (field.type == 'string' && field.minLength > 0) 'minLength': field.minLength,
      };
      if (field.required) required.add(name);
    }
    return {
      'type': 'object',
      if (required.isNotEmpty) 'required': required,
      'properties': properties,
    };
  }

  Future<void> _save() async {
    final formType = _formType.text.trim();
    if (formType.isEmpty) {
      AppSnackBar.error(context, 'Name the form, e.g. "insurance".');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(adminBillingRepositoryProvider).saveForm(formType, schema: _buildSchema());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not save this form.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runPreview() async {
    final formType = _formType.text.trim();
    if (formType.isEmpty) return;
    // Save first: the validator runs against the stored schema, so a
    // preview of unsaved edits would test the previous version.
    setState(() => _saving = true);
    try {
      final repo = ref.read(adminBillingRepositoryProvider);
      await repo.saveForm(formType, schema: _buildSchema());
      final data = <String, dynamic>{};
      for (final field in _fields) {
        final name = field.name.trim();
        final raw = _sample[name]?.text ?? '';
        if (name.isEmpty || raw.isEmpty) continue;
        data[name] = switch (field.type) {
          'number' => double.tryParse(raw) ?? raw,
          'integer' => int.tryParse(raw) ?? raw,
          'boolean' => raw.toLowerCase() == 'true',
          _ => raw,
        };
      }
      final result = await repo.validateForm(formType, data);
      if (mounted) setState(() => _preview = result);
      ref.invalidate(dynamicFormsProvider);
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not run the preview.');
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
            Text(widget.existing == null ? 'New form' : 'Edit form', style: AppTextStyles.title),
            const SizedBox(height: 12),
            NeonInputField(
              label: 'Form type',
              controller: _formType,
              enabled: widget.existing == null,
              helperText: 'A short key, e.g. insurance or intake',
            ),
            const SizedBox(height: 14),
            Text('Fields', style: AppTextStyles.label),
            const SizedBox(height: 8),
            for (var i = 0; i < _fields.length; i++) _fieldEditor(i),
            GhostButton(
              label: 'Add a field',
              icon: Icons.add_rounded,
              height: 42,
              onPressed: () => setState(() => _fields.add(_FieldDraft())),
            ),
            const SizedBox(height: 16),
            Text('Try it', style: AppTextStyles.label),
            const SizedBox(height: 8),
            for (final field in _fields.where((f) => f.name.trim().isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NeonInputField(
                  label: field.required ? '${field.name} *' : field.name,
                  controller: _sample.putIfAbsent(field.name.trim(), TextEditingController.new),
                ),
              ),
            GhostButton(
              label: 'Save and validate',
              icon: Icons.fact_check_outlined,
              height: 44,
              onPressed: _saving ? null : _runPreview,
            ),
            if (_preview != null) ...[
              const SizedBox(height: 10),
              GlassCard(
                borderColor: (_preview!.isValid ? AppColors.success : AppColors.error).withValues(alpha: .5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _preview!.isValid ? 'Valid — this would be accepted.' : 'Rejected',
                      style: AppTextStyles.body.copyWith(
                        color: _preview!.isValid ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    for (final error in _preview!.errors)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(error, style: AppTextStyles.caption),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            NeonButton(label: 'Save form', isLoading: _saving, onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }

  Widget _fieldEditor(int index) {
    final field = _fields[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: NeonInputField(
                    label: 'Field name',
                    initialValue: field.name,
                    onChanged: (v) => setState(() => field.name = v),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                  onPressed: _fields.length == 1 ? null : () => setState(() => _fields.removeAt(index)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilterChips<String>(
              options: [for (final t in _types) (value: t, label: t)],
              selected: field.type,
              onSelected: (v) => setState(() => field.type = v ?? 'string'),
            ),
            Row(
              children: [
                Checkbox(
                  value: field.required,
                  activeColor: AppColors.cyan,
                  onChanged: (v) => setState(() => field.required = v ?? false),
                ),
                Text('Required', style: AppTextStyles.caption),
                if (field.type == 'string') ...[
                  const Spacer(),
                  SizedBox(
                    width: 110,
                    child: NeonInputField(
                      label: 'Min length',
                      initialValue: '${field.minLength}',
                      keyboardType: TextInputType.number,
                      onChanged: (v) => setState(() => field.minLength = int.tryParse(v) ?? 0),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
