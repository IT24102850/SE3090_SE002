import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/inventory/sale_receipt.dart';

void main() {
  test('generates a valid PDF receipt with a visible PDF signature', () async {
    final receipt = SaleReceipt(
      reference: 'SALE-TEST-001',
      itemName: 'Coffee Beans',
      sku: 'COF-01',
      branch: 'Main branch',
      quantity: 2,
      unit: 'kg',
      unitPrice: 120,
      total: 240,
      occurredAt: DateTime.utc(2026, 9, 29, 8),
      remainingQuantity: 3,
      reorderLevel: 3,
    );

    final pdf = await receipt.toPdf();

    expect(pdf, isNotEmpty);
    expect(latin1.decode(pdf.take(5).toList()), '%PDF-');
  });
}
