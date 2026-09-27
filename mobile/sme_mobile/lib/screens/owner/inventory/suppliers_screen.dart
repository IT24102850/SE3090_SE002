import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/owner_models.dart';
import '../../../providers/owner_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';
import '../owner_widgets.dart';

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  final _query = TextEditingController();
  bool _showForm = false;
  bool _saving = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _addSupplier() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(ownerRepositoryProvider).createSupplier(
            name: name,
            email: _email.text.trim(),
            phone: _phone.text.trim(),
          );
      ref.invalidate(ownerSuppliersProvider);
      _name.clear();
      _email.clear();
      _phone.clear();
      if (mounted) {
        setState(() => _showForm = false);
        AppSnackBar.success(context, 'Supplier added.');
      }
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'Could not add this supplier.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(ownerSuppliersProvider);
    return OwnerScaffold(
      title: 'Suppliers',
      subtitle: 'Inventory partners and contacts',
      body: suppliersAsync.when(
        loading: () => const AppLoader(),
        error: (_, __) => ErrorState(
          message: 'Could not load suppliers.',
          onRetry: () => ref.invalidate(ownerSuppliersProvider),
        ),
        data: (suppliers) {
          final query = _query.text.trim().toLowerCase();
          final filtered = suppliers.where((supplier) {
            if (query.isEmpty) return true;
            return '${supplier.name} ${supplier.email} ${supplier.phone}'
                .toLowerCase()
                .contains(query);
          }).toList();
          final contacts = suppliers
              .where((supplier) =>
                  supplier.email.isNotEmpty || supplier.phone.isNotEmpty)
              .length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              StatGrid(tiles: [
                StatTile(
                    label: 'Suppliers',
                    value: '${suppliers.length}',
                    sub: 'in directory'),
                StatTile(
                    label: 'With contacts',
                    value: '$contacts',
                    sub: 'ready to reach',
                    accent: AppColors.success),
              ]),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: NeonInputField(
                          label: 'Search suppliers',
                          controller: _query,
                          onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: _showForm ? 'Close form' : 'Add supplier',
                    onPressed: () => setState(() => _showForm = !_showForm),
                    icon: Icon(
                        _showForm ? Icons.close : Icons.add_circle_outline,
                        color: AppColors.cyan),
                  ),
                ],
              ),
              if (_showForm) ...[
                const SizedBox(height: 12),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader('New supplier'),
                      NeonInputField(label: 'Supplier name', controller: _name),
                      const SizedBox(height: 10),
                      NeonInputField(
                          label: 'Email',
                          controller: _email,
                          keyboardType: TextInputType.emailAddress),
                      const SizedBox(height: 10),
                      NeonInputField(
                          label: 'Phone',
                          controller: _phone,
                          keyboardType: TextInputType.phone),
                      const SizedBox(height: 14),
                      NeonButton(
                          label: 'Save supplier',
                          isLoading: _saving,
                          onPressed: _saving ? null : _addSupplier),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const SectionHeader('Directory'),
              if (filtered.isEmpty)
                EmptyState(
                    icon: Icons.handshake_outlined,
                    message: suppliers.isEmpty
                        ? 'No suppliers yet.'
                        : 'No suppliers match your search.')
              else
                ...filtered
                    .map((supplier) => _SupplierCard(supplier: supplier)),
            ],
          );
        },
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.supplier});
  final Supplier supplier;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.cyan.withValues(alpha: .16),
              child: Text(
                  supplier.name.isEmpty ? '?' : supplier.name[0].toUpperCase(),
                  style: AppTextStyles.title.copyWith(color: AppColors.cyan)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(supplier.name,
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                      supplier.email.isEmpty
                          ? 'No email saved'
                          : supplier.email,
                      style: AppTextStyles.caption),
                  Text(
                      supplier.phone.isEmpty
                          ? 'No phone saved'
                          : supplier.phone,
                      style: AppTextStyles.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
