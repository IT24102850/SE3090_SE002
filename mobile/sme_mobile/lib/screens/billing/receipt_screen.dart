import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/billing_models.dart';
import '../../providers/billing_providers.dart';
import '../../services/billing_repository.dart';
import '../../shared/date_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui/ui.dart';

/// How a receipt leaves the app. Behind a provider so widget tests can
/// check what would be shared without opening WhatsApp or a mail client.
class ReceiptSharer {
  const ReceiptSharer();

  /// The system share sheet with the PDF attached - Save to Files /
  /// Downloads, WhatsApp, Gmail, Drive... On web this downloads the file.
  Future<void> sharePdf(Uint8List pdf, String fileName, String text) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(pdf, name: fileName, mimeType: 'application/pdf')],
      fileNameOverrides: [fileName],
      text: text,
      subject: fileName.replaceAll('.pdf', ''),
    ));
  }

  Future<bool> whatsApp(String text) =>
      launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);

  Future<bool> email(String to, String subject, String body) => launchUrl(Uri(
        scheme: 'mailto',
        path: to,
        query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
      ));
}

final receiptSharerProvider = Provider<ReceiptSharer>((ref) => const ReceiptSharer());

class ReceiptScreen extends ConsumerStatefulWidget {
  final String invoiceId;
  const ReceiptScreen({super.key, required this.invoiceId});

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  bool _busy = false;

  Future<void> _sharePdf(Receipt r) async {
    setState(() => _busy = true);
    try {
      final pdf = await ref.read(billingRepositoryProvider).receiptPdf(widget.invoiceId);
      final name = '${r.isPaidInFull ? r.receiptNumber : r.invoiceNumber}.pdf';
      await ref.read(receiptSharerProvider).sharePdf(pdf, name, r.shareText());
    } catch (e) {
      if (mounted) AppSnackBar.error(context, billingErrorMessage(e, 'Could not get the PDF.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _whatsApp(Receipt r) async {
    final ok = await ref.read(receiptSharerProvider).whatsApp(r.shareText());
    if (!ok && mounted) AppSnackBar.error(context, 'WhatsApp is not available on this device.');
  }

  Future<void> _email(Receipt r) async {
    final ok = await ref.read(receiptSharerProvider).email(
          r.customerEmail ?? '',
          '${r.businessName ?? 'Receipt'} - ${r.receiptNumber}',
          r.shareText(),
        );
    if (!ok && mounted) AppSnackBar.error(context, 'No email app is set up on this device.');
  }

  @override
  Widget build(BuildContext context) {
    final receipt = ref.watch(receiptProvider(widget.invoiceId));

    return AppBackgroundScaffold(
      appBar: const GlassAppBar(title: 'Receipt'),
      child: SafeArea(
        child: receipt.when(
          loading: () => const AppLoader(),
          error: (e, _) => ErrorState(message: 'Could not load the receipt.', onRetry: () => ref.invalidate(receiptProvider(widget.invoiceId))),
          data: (r) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              ReceiptView(receipt: r),
              const SizedBox(height: 20),
              NeonButton(
                key: const Key('share-pdf'),
                label: 'Download / share PDF',
                icon: Icons.picture_as_pdf_outlined,
                isLoading: _busy,
                onPressed: _busy ? null : () => _sharePdf(r),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      key: const Key('share-whatsapp'),
                      label: 'WhatsApp',
                      icon: Icons.chat_outlined,
                      onPressed: () => _whatsApp(r),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GhostButton(
                      key: const Key('share-email'),
                      label: 'Email',
                      icon: Icons.mail_outline_rounded,
                      onPressed: () => _email(r),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The receipt itself, drawn as a paper slip (light, like the PDF).
class ReceiptView extends StatelessWidget {
  final Receipt receipt;
  const ReceiptView({super.key, required this.receipt});

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    const ink = Color(0xFF1F2328);
    const muted = Color(0xFF6B7280);
    TextStyle s(double size, {FontWeight weight = FontWeight.w400, Color color = ink}) =>
        TextStyle(fontSize: size, fontWeight: weight, color: color);

    Widget line(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: s(13, weight: bold ? FontWeight.w700 : FontWeight.w400))),
            Text(value, style: s(13, weight: bold ? FontWeight.w700 : FontWeight.w400)),
          ]),
        );

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.electricBlue,
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(child: Text(r.businessName ?? 'Receipt', style: s(18, weight: FontWeight.w700, color: Colors.white))),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(r.isPaidInFull ? 'RECEIPT' : 'INVOICE', style: s(13, weight: FontWeight.w700, color: Colors.white)),
                    Text(r.isPaidInFull ? r.receiptNumber : r.invoiceNumber, style: s(11, color: Colors.white)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BILLED TO', style: s(10, color: muted, weight: FontWeight.w700)),
                Text(r.customerName ?? '', style: s(14, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Issued ${formatFullDate(r.issuedAt)} · ${r.paymentStatus}', style: s(12, color: muted)),
                const SizedBox(height: 14),
                for (final i in r.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Expanded(child: Text('${i.description} × ${i.quantity}', style: s(13))),
                      Text(formatMoney(i.amount, r.currency), style: s(13)),
                    ]),
                  ),
                const Divider(color: Color(0xFFE5E7EB)),
                line('Subtotal', formatMoney(r.totalAmount, r.currency)),
                if (r.discount > 0) line('Discount', '-${formatMoney(r.discount, r.currency)}'),
                if (r.tax > 0) line('Tax', formatMoney(r.tax, r.currency)),
                line('Total', formatMoney(r.finalAmount, r.currency), bold: true),
                line('Paid', formatMoney(r.totalPaid, r.currency)),
                line('Balance due', formatMoney(r.balanceDue, r.currency), bold: true),
                if (r.payments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('PAYMENTS', style: s(10, color: muted, weight: FontWeight.w700)),
                  for (final p in r.payments)
                    line('${p.method}${p.paidAt == null ? '' : ' · ${formatDayMonth(p.paidAt!)}'}${p.status == 'Succeeded' ? '' : ' · ${p.status}'}',
                        formatMoney(p.amount, r.currency)),
                ],
                const SizedBox(height: 14),
                Text(r.footerText ?? 'Thank you for your business.', style: s(11, color: muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
