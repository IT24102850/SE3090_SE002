import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/ui/ui.dart';

class SaleReceipt {
  const SaleReceipt({
    required this.reference,
    required this.itemName,
    this.sku,
    required this.branch,
    required this.quantity,
    required this.unit,
    this.unitPrice,
    required this.total,
    required this.occurredAt,
    this.remainingQuantity,
    this.reorderLevel,
  });

  final String reference;
  final String itemName;
  final String? sku;
  final String branch;
  final double quantity;
  final String unit;
  final double? unitPrice;
  final double total;
  final DateTime occurredAt;
  final double? remainingQuantity;
  final double? reorderLevel;

  String get shareText {
    final time = occurredAt.toLocal().toString();
    return [
      'UNIFY · SALES RECEIPT',
      'Reference: $reference',
      'Date: ${time.substring(0, 16)}',
      'Branch: $branch',
      '',
      itemName,
      if (sku != null && sku!.isNotEmpty) 'SKU: $sku',
      if (unitPrice != null)
        '${_formatQuantity(quantity)} $unit × LKR ${_money(unitPrice!)}',
      if (unitPrice == null) 'Quantity total: ${_formatQuantity(quantity)}',
      'TOTAL: LKR ${_money(total)}',
      '',
      'Inventory sale recorded in Unify. Payment collection is not recorded by this receipt.',
    ].join('\n');
  }

  static String _formatQuantity(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  static String _money(double value) => value.toStringAsFixed(2);

  Future<Uint8List> toPdf() => SaleReceiptPdfGenerator.generate(this);
}

class SaleReceiptPdfGenerator {
  const SaleReceiptPdfGenerator._();

  static const _navy = PdfColor.fromInt(0xFF101B2D);
  static const _cyan = PdfColor.fromInt(0xFF00AFC8);
  static const _ink = PdfColor.fromInt(0xFF172033);
  static const _muted = PdfColor.fromInt(0xFF667085);
  static const _line = PdfColor.fromInt(0xFFE5EAF0);
  static const _pale = PdfColor.fromInt(0xFFF4F8FB);
  static const _amber = PdfColor.fromInt(0xFF9A6700);
  static const _amberPale = PdfColor.fromInt(0xFFFFF5D9);

  static Future<Uint8List> generate(SaleReceipt receipt) async {
    final document = pw.Document(
      title: 'Sales receipt ${receipt.reference}',
      author: 'SME Mobile',
      subject: 'Inventory sales receipt',
    );
    final localTime = receipt.occurredAt.toLocal();
    final date = '${_two(localTime.day)}/${_two(localTime.month)}/'
        '${localTime.year}  ${_two(localTime.hour)}:${_two(localTime.minute)}';

    document.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(38),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(24, 23, 24, 22),
            decoration: const pw.BoxDecoration(
              color: _navy,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(16)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'SALES RECEIPT',
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.8,
                        ),
                      ),
                      pw.SizedBox(height: 7),
                      pw.Text(
                        'Sale recorded',
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 23,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Official inventory sale record',
                        style: pw.TextStyle(
                          color: PdfColor.fromInt(0xFFC3D1E1),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFF1E3148),
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(9)),
                  ),
                  child: pw.Text(
                    'SALE RECORDED',
                    style: pw.TextStyle(
                      color: PdfColor.fromInt(0xFF8CEBFA),
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: .5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 22),
          pw.Row(
            children: [
              pw.Expanded(child: _meta('REFERENCE', receipt.reference)),
              pw.SizedBox(width: 16),
              pw.Expanded(child: _meta('DATE & TIME', date)),
            ],
          ),
          pw.SizedBox(height: 12),
          _meta('BRANCH', receipt.branch),
          pw.SizedBox(height: 24),
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _line),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            child: pw.Column(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: const pw.BoxDecoration(
                    color: _pale,
                    borderRadius: pw.BorderRadius.only(
                      topLeft: pw.Radius.circular(12),
                      topRight: pw.Radius.circular(12),
                    ),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(child: _tableHeader('ITEM')),
                      pw.SizedBox(width: 8),
                      _tableHeader('QTY'),
                      if (receipt.unitPrice != null) ...[
                        pw.SizedBox(width: 18),
                        _tableHeader('UNIT PRICE'),
                      ],
                      pw.SizedBox(width: 18),
                      _tableHeader('AMOUNT'),
                    ],
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(16),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              receipt.itemName,
                              style: const pw.TextStyle(
                                color: _ink,
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            if (receipt.sku != null &&
                                receipt.sku!.isNotEmpty) ...[
                              pw.SizedBox(height: 4),
                              pw.Text(
                                'SKU ${receipt.sku}',
                                style: const pw.TextStyle(
                                  color: _muted,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Text(
                        receipt.unitPrice == null
                            ? 'Qty ${_quantity(receipt.quantity)}'
                            : '${_quantity(receipt.quantity)} ${receipt.unit}',
                        style: const pw.TextStyle(color: _ink, fontSize: 9),
                      ),
                      if (receipt.unitPrice != null) ...[
                        pw.SizedBox(width: 18),
                        pw.Text(
                          'LKR ${_money(receipt.unitPrice!)}',
                          style: const pw.TextStyle(color: _ink, fontSize: 9),
                        ),
                      ],
                      pw.SizedBox(width: 18),
                      pw.Text(
                        'LKR ${_money(receipt.total)}',
                        style: const pw.TextStyle(
                          color: _ink,
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 19),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(14),
                  decoration: const pw.BoxDecoration(
                    color: _pale,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _tableHeader(
                        receipt.remainingQuantity == null
                            ? 'SALE RECORD'
                            : 'INVENTORY UPDATE',
                      ),
                      pw.SizedBox(height: 7),
                      pw.Text(
                        receipt.remainingQuantity == null
                            ? 'Saved sale transaction'
                            : 'Stock remaining: ${_quantity(receipt.remainingQuantity!)} ${receipt.unit}',
                        style: const pw.TextStyle(color: _ink, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 18),
              pw.Container(
                width: 210,
                padding: const pw.EdgeInsets.all(17),
                decoration: const pw.BoxDecoration(
                  color: _navy,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text(
                      'TOTAL',
                      style: pw.TextStyle(
                        color: PdfColor.fromInt(0xFFC3D1E1),
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    pw.SizedBox(height: 7),
                    pw.Text(
                      'LKR ${_money(receipt.total)}',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 19,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _lowStockAlert(receipt),
          pw.Spacer(),
          pw.Container(height: 1, color: _line),
          pw.SizedBox(height: 12),
          pw.Text(
            'This receipt confirms that the inventory sale was recorded in Unify. Payment collection is not recorded by this receipt.',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(color: _muted, fontSize: 8),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'Generated by Unify',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(color: _cyan, fontSize: 8),
          ),
        ],
      ),
    ));
    return document.save();
  }

  static pw.Widget _meta(String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _tableHeader(label),
          pw.SizedBox(height: 5),
          pw.Text(
            value,
            style: const pw.TextStyle(
              color: _ink,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      );

  static pw.Widget _tableHeader(String value) => pw.Text(
        value,
        style: const pw.TextStyle(
          color: _muted,
          fontSize: 7,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: .7,
        ),
      );

  static pw.Widget _lowStockAlert(SaleReceipt receipt) {
    if (receipt.remainingQuantity == null ||
        receipt.reorderLevel == null ||
        receipt.remainingQuantity! > receipt.reorderLevel!) {
      return pw.SizedBox();
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 13),
      child: pw.Container(
        padding: const pw.EdgeInsets.all(11),
        decoration: const pw.BoxDecoration(
          color: _amberPale,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(9)),
        ),
        child: pw.Text(
          'LOW STOCK  |  Remaining quantity is at or below the reorder level.',
          style: const pw.TextStyle(
            color: _amber,
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  static String _quantity(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  static String _money(double value) => value.toStringAsFixed(2);

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class SaleReceiptDialog extends StatefulWidget {
  const SaleReceiptDialog({super.key, required this.receipt});

  final SaleReceipt receipt;

  @override
  State<SaleReceiptDialog> createState() => _SaleReceiptDialogState();
}

class _SaleReceiptDialogState extends State<SaleReceiptDialog> {
  bool _sharing = false;

  Future<void> _shareReceipt() async {
    setState(() => _sharing = true);
    try {
      final pdfBytes = await widget.receipt.toPdf();
      final safeReference =
          widget.receipt.reference.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final fileName = 'Receipt_$safeReference.pdf';
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(
            pdfBytes,
            name: fileName,
            mimeType: 'application/pdf',
          ),
        ],
        fileNameOverrides: [fileName],
        text: widget.receipt.shareText,
        subject: fileName.replaceAll('.pdf', ''),
      ));
    } catch (error) {
      if (mounted) {
        AppSnackBar.error(context, 'Could not share the receipt: $error');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final localTime = receipt.occurredAt.toLocal();
    final date = localTime.toString();
    return Dialog(
      key: const Key('sale-receipt-dialog'),
      backgroundColor: AppColors.bgMid,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.receipt_long_rounded,
                color: AppColors.cyan, size: 34),
            const SizedBox(height: 8),
            Text(
              'UNIFY · SALES RECEIPT',
              textAlign: TextAlign.center,
              style: AppTextStyles.label.copyWith(
                color: AppColors.cyan,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sale recorded',
              textAlign: TextAlign.center,
              style: AppTextStyles.subtitle.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Official inventory sale record',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Text(
              receipt.reference,
              key: const Key('sale-receipt-reference'),
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(color: AppColors.cyan),
            ),
            const SizedBox(height: 18),
            _line('Date', date.substring(0, 16)),
            _line('Branch', receipt.branch),
            const Divider(height: 24, color: AppColors.hairline),
            _line(receipt.itemName, 'LKR ${receipt.total.toStringAsFixed(2)}',
                bold: true),
            const SizedBox(height: 3),
            Text(
              receipt.unitPrice == null
                  ? 'Quantity total: ${_formatQuantity(receipt.quantity)}'
                  : '${receipt.sku ?? ''} | ${_formatQuantity(receipt.quantity)} ${receipt.unit} x '
                      'LKR ${receipt.unitPrice!.toStringAsFixed(2)}',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
            const Divider(height: 24, color: AppColors.hairline),
            _line(
              'TOTAL',
              'LKR ${receipt.total.toStringAsFixed(2)}',
              bold: true,
              accent: true,
            ),
            const SizedBox(height: 10),
            if (receipt.remainingQuantity != null)
              _line(
                'Stock remaining',
                '${_formatQuantity(receipt.remainingQuantity!)} ${receipt.unit}',
              ),
            if (receipt.remainingQuantity != null &&
                receipt.reorderLevel != null &&
                receipt.remainingQuantity! <= receipt.reorderLevel!) ...[
              const SizedBox(height: 9),
              Container(
                key: const Key('sale-receipt-low-stock'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: .38),
                  ),
                ),
                child: Text(
                  'Low stock — plan a restock for this item.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.warning,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Inventory sale recorded in Unify. Payment collection is not recorded by this receipt.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textMuted,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 18),
            NeonButton(
              key: const Key('share-sale-receipt'),
              label: _sharing ? 'Preparing PDF…' : 'Share / save PDF',
              icon: Icons.picture_as_pdf_outlined,
              isLoading: _sharing,
              onPressed: _sharing ? null : _shareReceipt,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value,
      {bool bold = false, bool accent = false}) {
    final color = accent ? AppColors.cyan : AppColors.textPrimary;
    final style = AppTextStyles.body.copyWith(
      color: color,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }

  String _formatQuantity(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}
