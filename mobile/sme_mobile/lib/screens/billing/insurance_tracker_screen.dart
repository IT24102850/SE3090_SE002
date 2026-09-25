import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/billing_models.dart';
import '../../providers/billing_providers.dart';
import '../../services/billing_repository.dart';
import '../../shared/date_format.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/billing_status_chip.dart';
import '../../widgets/ui/ui.dart';

/// Submit claims, add documents from the camera, and follow each claim
/// through Submitted -> Under review -> Approved / Rejected.
class InsuranceTrackerScreen extends ConsumerWidget {
  const InsuranceTrackerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claims = ref.watch(myClaimsProvider);

    return AppBackgroundScaffold(
      appBar: const GlassAppBar(title: 'Insurance claims'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New claim'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.overlaySurface,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.pill))),
          builder: (_) => const _NewClaimSheet(),
        ),
      ),
      child: SafeArea(
        child: claims.when(
          loading: () => const AppLoader(),
          error: (e, _) => ErrorState(message: 'Could not load your claims.', onRetry: () => ref.invalidate(myClaimsProvider)),
          data: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.health_and_safety_outlined, message: 'No insurance claims yet. Tap "New claim" to submit one against a bill.')
              : RefreshIndicator(
                  color: AppColors.cyan,
                  backgroundColor: AppColors.overlaySurface,
                  onRefresh: () async => ref.invalidate(myClaimsProvider),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [for (final c in list) ...[_ClaimCard(claim: c), const SizedBox(height: 14)]],
                  ),
                ),
        ),
      ),
    );
  }
}

class _ClaimCard extends ConsumerStatefulWidget {
  final InsuranceClaim claim;
  const _ClaimCard({required this.claim});

  @override
  ConsumerState<_ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends ConsumerState<_ClaimCard> {
  bool _uploading = false;

  Future<void> _addDocument(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 2000);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      await ref.read(billingRepositoryProvider).uploadClaimDocument(widget.claim.id, bytes, picked.name.isEmpty ? 'document.jpg' : picked.name);
      ref.invalidate(myClaimsProvider);
      if (mounted) AppSnackBar.success(context, 'Document attached.');
    } catch (e) {
      if (mounted) AppSnackBar.error(context, billingErrorMessage(e, 'The document could not be uploaded.'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.claim;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('${c.provider} · ${formatMoney(c.claimAmount, c.currency)}', style: AppTextStyles.subtitle)),
            BillingStatusChip(status: c.status),
          ]),
          const SizedBox(height: 4),
          Text('Policy ${c.policyNumber}${c.invoiceNumber == null ? '' : ' · ${c.invoiceNumber}'}', style: AppTextStyles.caption),
          const SizedBox(height: 14),
          ClaimProgress(claim: c),
          if (c.rejectionReason != null) ...[
            const SizedBox(height: 10),
            InlineErrorBanner(message: c.rejectionReason!),
          ],
          if (c.documents.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in c.documents)
                  ActionChip(
                    avatar: const Icon(Icons.attach_file_rounded, size: 16),
                    label: Text(d.fileName, overflow: TextOverflow.ellipsis),
                    onPressed: () => launchUrl(Uri.parse(d.url), mode: LaunchMode.externalApplication),
                  ),
              ],
            ),
          ],
          if (!c.isClosed) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: GhostButton(
                  label: _uploading ? 'Uploading…' : 'Take photo',
                  icon: Icons.photo_camera_outlined,
                  height: 42,
                  onPressed: _uploading ? () {} : () => _addDocument(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GhostButton(
                  label: 'From gallery',
                  icon: Icons.photo_library_outlined,
                  height: 42,
                  onPressed: _uploading ? () {} : () => _addDocument(ImageSource.gallery),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Submitted -> Under review -> Approved/Rejected, as three steps.
class ClaimProgress extends StatelessWidget {
  final InsuranceClaim claim;
  const ClaimProgress({super.key, required this.claim});

  @override
  Widget build(BuildContext context) {
    final rejected = claim.status == 'Rejected';
    final steps = [
      ('Submitted', claim.submittedAt),
      ('Under review', claim.reviewStartedAt),
      (rejected ? 'Rejected' : 'Approved', rejected ? null : claim.approvedAt),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Icon(
                  i < claim.stage || (i == claim.stage && i == 2)
                      ? (i == 2 && rejected ? Icons.cancel_rounded : Icons.check_circle_rounded)
                      : i == claim.stage
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                  size: 22,
                  color: i > claim.stage
                      ? AppColors.iconDisabled
                      : i == 2 && rejected
                          ? AppColors.danger
                          : i == claim.stage && i < 2
                              ? AppColors.warning
                              : AppColors.success,
                ),
                const SizedBox(height: 4),
                Text(steps[i].$1, style: AppTextStyles.caption, textAlign: TextAlign.center),
                if (steps[i].$2 != null) Text(formatDayMonth(steps[i].$2!), style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          if (i < steps.length - 1)
            Container(width: 24, height: 2, color: i < claim.stage ? AppColors.success : AppColors.hairline),
        ],
      ],
    );
  }
}

class _NewClaimSheet extends ConsumerStatefulWidget {
  const _NewClaimSheet();

  @override
  ConsumerState<_NewClaimSheet> createState() => _NewClaimSheetState();
}

class _NewClaimSheetState extends ConsumerState<_NewClaimSheet> {
  final _form = GlobalKey<FormState>();
  final _provider = TextEditingController();
  final _policy = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  Invoice? _invoice;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_provider, _policy, _amount, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false) || _invoice == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(billingRepositoryProvider).createClaim(
            invoiceId: _invoice!.id,
            provider: _provider.text.trim(),
            policyNumber: _policy.text.trim(),
            claimAmount: double.parse(_amount.text.trim()),
            notes: _notes.text.trim(),
          );
      ref.invalidate(myClaimsProvider);
      if (mounted) {
        Navigator.of(context).pop();
        AppSnackBar.success(context, 'Claim submitted. Add photos of your documents from the claim card.');
      }
    } catch (e) {
      if (mounted) AppSnackBar.error(context, billingErrorMessage(e, 'The claim could not be submitted.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(myInvoicesProvider).valueOrNull?.where((i) => i.status != 'Cancelled').toList() ?? const <Invoice>[];

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('New insurance claim', style: AppTextStyles.title),
            const SizedBox(height: 16),
            DropdownButtonFormField<Invoice>(
              initialValue: _invoice,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Bill'),
              items: [
                for (final i in invoices)
                  DropdownMenuItem(value: i, child: Text('${i.invoiceNumber} · ${formatMoney(i.finalAmount, i.currency)}', overflow: TextOverflow.ellipsis)),
              ],
              validator: (v) => v == null ? 'Choose the bill to claim for.' : null,
              onChanged: (v) => setState(() {
                _invoice = v;
                if (v != null && _amount.text.isEmpty) _amount.text = v.finalAmount.toStringAsFixed(2);
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _provider,
              decoration: const InputDecoration(labelText: 'Insurer (e.g. Ceylinco, AIA)'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the insurer.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _policy,
              decoration: const InputDecoration(labelText: 'Policy number'),
              validator: (v) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9/-]{3,39}$').hasMatch(v?.trim() ?? '') ? null : '4-40 letters, digits, "/" or "-".',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Claim amount'),
              validator: (v) {
                final value = double.tryParse(v?.trim() ?? '');
                if (value == null || value <= 0) return 'Enter an amount above 0.';
                if (_invoice != null && value > _invoice!.finalAmount) return 'Cannot exceed the bill (${formatMoney(_invoice!.finalAmount, _invoice!.currency)}).';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
            const SizedBox(height: 20),
            NeonButton(label: 'Submit claim', isLoading: _saving, onPressed: _saving ? null : _submit),
          ],
        ),
      ),
    );
  }
}
