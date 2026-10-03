/// Billing & payments models - the mobile side of backend component 3
/// (invoices, payments, receipts, subscriptions, insurance claims).
library;

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

/// "LKR 12,500.00" - grouping by hand so no intl dependency is needed.
String formatMoney(double amount, [String currency = 'LKR']) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0];
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '${negative ? '-' : ''}$currency $grouped.${parts[1]}';
}

class InvoiceItem {
  final String id;
  final String description;
  final int quantity;
  final double unitPrice;
  final double amount;
  final String category;

  const InvoiceItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
    this.category = 'General',
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
        id: j['id'] as String? ?? '',
        description: j['description'] as String? ?? '',
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: _d(j['unitPrice']),
        amount: _d(j['amount']),
        category: j['category'] as String? ?? 'General',
      );
}

class PaymentRecord {
  final String id;
  final double amount;
  final String method;
  final String status;
  final String? provider;
  final String? payerLabel;
  final String? transactionRef;
  final DateTime? paidAt;
  final DateTime? createdAt;

  const PaymentRecord({
    required this.id,
    required this.amount,
    required this.method,
    required this.status,
    this.provider,
    this.payerLabel,
    this.transactionRef,
    this.paidAt,
    this.createdAt,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> j) => PaymentRecord(
        id: j['id'] as String? ?? '',
        amount: _d(j['amount']),
        method: j['method'] as String? ?? '',
        status: j['status'] as String? ?? 'Succeeded',
        provider: j['provider'] as String?,
        payerLabel: j['payerLabel'] as String?,
        transactionRef: j['transactionRef'] as String?,
        paidAt: _date(j['paidAt']),
        createdAt: _date(j['createdAt']),
      );
}

class Invoice {
  final String id;
  final String invoiceNumber;
  final String status;
  final String currency;
  final double totalAmount;
  final double discount;
  final double tax;
  final double finalAmount;
  final double amountPaid;
  final double balanceDue;
  final bool isOverdue;
  final DateTime dueDate;
  final DateTime createdAt;
  final String? scheduleLabel;
  final String? subscriptionId;
  final String? notes;
  final List<InvoiceItem> items;
  final List<PaymentRecord> payments;

  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.status,
    required this.currency,
    required this.totalAmount,
    required this.discount,
    required this.tax,
    required this.finalAmount,
    required this.amountPaid,
    required this.balanceDue,
    required this.isOverdue,
    required this.dueDate,
    required this.createdAt,
    this.scheduleLabel,
    this.subscriptionId,
    this.notes,
    this.items = const [],
    this.payments = const [],
  });

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: j['id'] as String,
        invoiceNumber: j['invoiceNumber'] as String? ?? '',
        status: j['status'] as String? ?? 'Issued',
        currency: j['currency'] as String? ?? 'LKR',
        totalAmount: _d(j['totalAmount']),
        discount: _d(j['discount']),
        tax: _d(j['tax']),
        finalAmount: _d(j['finalAmount']),
        amountPaid: _d(j['amountPaid']),
        balanceDue: _d(j['balanceDue']),
        isOverdue: j['isOverdue'] as bool? ?? false,
        dueDate: _date(j['dueDate']) ?? DateTime.now(),
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
        scheduleLabel: j['scheduleLabel'] as String?,
        subscriptionId: j['subscriptionId'] as String?,
        notes: j['notes'] as String?,
        items: (j['items'] as List<dynamic>? ?? const [])
            .map((e) => InvoiceItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        payments: (j['payments'] as List<dynamic>? ?? const [])
            .map((e) => PaymentRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  bool get isOpen => status == 'Issued' || status == 'PartiallyPaid' || status == 'Overdue';
  bool get isPaid => status == 'Paid';

  /// The three states the "My Bills" list shows: Paid, Overdue, Pending.
  String get billState => isPaid
      ? 'Paid'
      : isOverdue || status == 'Overdue'
          ? 'Overdue'
          : status == 'Cancelled'
              ? 'Cancelled'
              : 'Pending';

  String get summary => items.map((i) => i.description).join(', ');
}

class Receipt {
  final String receiptNumber;
  final String invoiceId;
  final String invoiceNumber;
  final String currency;
  final double totalAmount;
  final double discount;
  final double tax;
  final double finalAmount;
  final double totalPaid;
  final double balanceDue;
  final String paymentStatus;
  final DateTime issuedAt;
  final DateTime dueDate;
  final String? businessName;
  final String? customerName;
  final String? customerEmail;
  final String? notes;
  final String? footerText;
  final List<InvoiceItem> items;
  final List<PaymentRecord> payments;

  const Receipt({
    required this.receiptNumber,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.currency,
    required this.totalAmount,
    required this.discount,
    required this.tax,
    required this.finalAmount,
    required this.totalPaid,
    required this.balanceDue,
    required this.paymentStatus,
    required this.issuedAt,
    required this.dueDate,
    this.businessName,
    this.customerName,
    this.customerEmail,
    this.notes,
    this.footerText,
    this.items = const [],
    this.payments = const [],
  });

  factory Receipt.fromJson(Map<String, dynamic> j) => Receipt(
        receiptNumber: j['receiptNumber'] as String? ?? '',
        invoiceId: j['invoiceId'] as String? ?? '',
        invoiceNumber: j['invoiceNumber'] as String? ?? '',
        currency: j['currency'] as String? ?? 'LKR',
        totalAmount: _d(j['totalAmount']),
        discount: _d(j['discount']),
        tax: _d(j['tax']),
        finalAmount: _d(j['finalAmount']),
        totalPaid: _d(j['totalPaid']),
        balanceDue: _d(j['balanceDue']),
        paymentStatus: j['paymentStatus'] as String? ?? '',
        issuedAt: _date(j['issuedAt']) ?? DateTime.now(),
        dueDate: _date(j['dueDate']) ?? DateTime.now(),
        businessName: j['businessName'] as String?,
        customerName: j['customerName'] as String?,
        customerEmail: j['customerEmail'] as String?,
        notes: j['notes'] as String?,
        footerText: (j['template'] as Map<String, dynamic>?)?['footerText'] as String?,
        items: (j['items'] as List<dynamic>? ?? const [])
            .map((e) => InvoiceItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        payments: (j['payments'] as List<dynamic>? ?? const [])
            .map((e) => PaymentRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  bool get isPaidInFull => balanceDue <= 0.004;

  /// What goes into a WhatsApp / email share - short and readable.
  String shareText() {
    final lines = <String>[
      '${businessName ?? 'Receipt'} - ${isPaidInFull ? 'Receipt' : 'Invoice'} $receiptNumber',
      for (final i in items) '• ${i.description} x${i.quantity}: ${formatMoney(i.amount, currency)}',
      'Total: ${formatMoney(finalAmount, currency)}',
      'Paid: ${formatMoney(totalPaid, currency)}',
      if (!isPaidInFull) 'Balance due: ${formatMoney(balanceDue, currency)}',
    ];
    return lines.join('\n');
  }
}

class ProviderOption {
  final String provider;
  final String name;
  final String? publicKey;
  final bool isTestMode;

  const ProviderOption({required this.provider, required this.name, this.publicKey, this.isTestMode = true});

  factory ProviderOption.fromJson(Map<String, dynamic> j) => ProviderOption(
        provider: j['provider'] as String,
        name: j['name'] as String? ?? j['provider'] as String,
        publicKey: j['publicKey'] as String?,
        isTestMode: j['isTestMode'] as bool? ?? true,
      );
}

class AvailableProviders {
  final List<ProviderOption> providers;
  const AvailableProviders(this.providers);

  factory AvailableProviders.fromJson(Map<String, dynamic> j) => AvailableProviders(
        (j['providers'] as List<dynamic>? ?? const [])
            .map((e) => ProviderOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  bool has(String provider) => providers.any((p) => p.provider == provider);
}

class CheckoutSession {
  final String paymentId;
  final String invoiceId;
  final String provider;
  final String status;
  final double amount;
  final String currency;
  final String? redirectUrl;
  final String? externalReference;
  final bool simulated;

  const CheckoutSession({
    required this.paymentId,
    required this.invoiceId,
    required this.provider,
    required this.status,
    required this.amount,
    required this.currency,
    this.redirectUrl,
    this.externalReference,
    this.simulated = false,
  });

  factory CheckoutSession.fromJson(Map<String, dynamic> j) => CheckoutSession(
        paymentId: j['paymentId'] as String,
        invoiceId: j['invoiceId'] as String,
        provider: j['provider'] as String? ?? 'Manual',
        status: j['status'] as String? ?? 'Pending',
        amount: _d(j['amount']),
        currency: j['currency'] as String? ?? 'LKR',
        redirectUrl: j['redirectUrl'] as String?,
        externalReference: j['externalReference'] as String?,
        simulated: j['simulated'] as bool? ?? false,
      );
}

class PaymentConfirmation {
  final PaymentRecord payment;
  final Invoice invoice;
  const PaymentConfirmation(this.payment, this.invoice);

  factory PaymentConfirmation.fromJson(Map<String, dynamic> j) => PaymentConfirmation(
        PaymentRecord.fromJson(j['payment'] as Map<String, dynamic>),
        Invoice.fromJson(j['invoice'] as Map<String, dynamic>),
      );
}

class Subscription {
  final String id;
  final String planName;
  final double amount;
  final String billingCycle;
  final DateTime startDate;
  final DateTime endDate;
  final bool autoRenew;
  final String status;
  final String paymentStatus;
  final DateTime? nextBillingAt;
  final DateTime? lastPaymentAt;

  const Subscription({
    required this.id,
    required this.planName,
    required this.amount,
    required this.billingCycle,
    required this.startDate,
    required this.endDate,
    required this.autoRenew,
    required this.status,
    required this.paymentStatus,
    this.nextBillingAt,
    this.lastPaymentAt,
  });

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'] as String,
        planName: j['planName'] as String? ?? '',
        amount: _d(j['amount']),
        billingCycle: j['billingCycle'] as String? ?? 'Monthly',
        startDate: _date(j['startDate']) ?? DateTime.now(),
        endDate: _date(j['endDate']) ?? DateTime.now(),
        autoRenew: j['autoRenew'] as bool? ?? false,
        status: j['status'] as String? ?? 'Active',
        paymentStatus: j['paymentStatus'] as String? ?? 'Paid',
        nextBillingAt: _date(j['nextBillingAt']),
        lastPaymentAt: _date(j['lastPaymentAt']),
      );

  bool get isActive => status == 'Active';
}

class PlanOption {
  final String planName;
  final double amount;
  final String billingCycle;

  const PlanOption({required this.planName, required this.amount, required this.billingCycle});

  factory PlanOption.fromJson(Map<String, dynamic> j) => PlanOption(
        planName: j['planName'] as String? ?? '',
        amount: _d(j['amount']),
        billingCycle: j['billingCycle'] as String? ?? 'Monthly',
      );
}

class ClaimDocument {
  final String url;
  final String fileName;
  const ClaimDocument(this.url, this.fileName);
}

class InsuranceClaim {
  final String id;
  final String? invoiceNumber;
  final String provider;
  final String policyNumber;
  final double claimAmount;
  final String status;
  final String currency;
  final DateTime? submittedAt;
  final DateTime? reviewStartedAt;
  final DateTime? approvedAt;
  final String? rejectionReason;
  final bool requiresAdminApproval;
  final List<ClaimDocument> documents;

  const InsuranceClaim({
    required this.id,
    required this.provider,
    required this.policyNumber,
    required this.claimAmount,
    required this.status,
    this.currency = 'LKR',
    this.invoiceNumber,
    this.submittedAt,
    this.reviewStartedAt,
    this.approvedAt,
    this.rejectionReason,
    this.requiresAdminApproval = false,
    this.documents = const [],
  });

  factory InsuranceClaim.fromJson(Map<String, dynamic> j) => InsuranceClaim(
        id: j['id'] as String,
        invoiceNumber: j['invoiceNumber'] as String?,
        provider: j['provider'] as String? ?? '',
        policyNumber: j['policyNumber'] as String? ?? '',
        claimAmount: _d(j['claimAmount']),
        status: j['status'] as String? ?? 'Submitted',
        currency: j['currency'] as String? ?? 'LKR',
        submittedAt: _date(j['submittedAt']),
        reviewStartedAt: _date(j['reviewStartedAt']),
        approvedAt: _date(j['approvedAt']),
        rejectionReason: j['rejectionReason'] as String?,
        requiresAdminApproval: j['requiresAdminApproval'] as bool? ?? false,
        documents: (j['documents'] as List<dynamic>? ?? const [])
            .map((e) => ClaimDocument((e as Map<String, dynamic>)['url'] as String, e['fileName'] as String? ?? 'document'))
            .toList(),
      );

  /// 0 Submitted, 1 Under review, 2 decided (Approved or Rejected).
  int get stage => switch (status) {
        'Submitted' => 0,
        'UnderReview' || 'Pending' => 1,
        _ => 2,
      };

  bool get isClosed => status == 'Approved' || status == 'Rejected';
}
