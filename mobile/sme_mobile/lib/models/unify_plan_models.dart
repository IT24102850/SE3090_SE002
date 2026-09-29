/// What the business pays Unify for the platform.
///
/// Deliberately separate from `billing_models.dart`, whose `Subscription` is
/// a membership a tenant sells to its own customers. Two different ledgers;
/// one file each, so a screen cannot pick up the wrong one.
library;

String billingPeriodLabel(String period) => switch (period) {
      'SemiAnnual' => '6 months',
      'Annual' => '12 months',
      _ => 'Monthly',
    };

class PlanPrice {
  final String id;
  final String period;
  final String periodLabel;
  final String currency;
  final double amount;
  final double monthlyEquivalent;
  final int savingsPercent;
  final bool isBestValue;

  /// The same months bought one at a time - the number the saving is
  /// measured against.
  final double comparedAtAmount;

  const PlanPrice({
    required this.id,
    required this.period,
    required this.periodLabel,
    required this.currency,
    required this.amount,
    required this.monthlyEquivalent,
    required this.savingsPercent,
    required this.isBestValue,
    required this.comparedAtAmount,
  });

  factory PlanPrice.fromJson(Map<String, dynamic> json) => PlanPrice(
        id: json['id'] as String,
        period: json['period'] as String? ?? 'Monthly',
        periodLabel: json['periodLabel'] as String? ?? 'Monthly',
        currency: json['currency'] as String? ?? 'LKR',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        monthlyEquivalent: (json['monthlyEquivalent'] as num?)?.toDouble() ?? 0,
        savingsPercent: (json['savingsPercent'] as num?)?.toInt() ?? 0,
        isBestValue: json['isBestValue'] as bool? ?? false,
        comparedAtAmount: (json['comparedAtAmount'] as num?)?.toDouble() ?? 0,
      );
}

class UnifyPlan {
  final String id;
  final String code;
  final String name;
  final int tier;
  final String tagline;
  final List<String> highlights;
  final bool isMostPopular;
  final int trialDays;
  final int? maxBranches;
  final int? maxStaffSeats;
  final int? maxBookingsPerMonth;
  final int? aiRunsPerMonth;
  final int? smsPerMonth;
  final int spotlightsPerMonth;
  final int? supportResponseHours;
  final List<String> features;
  final List<PlanPrice> prices;

  const UnifyPlan({
    required this.id,
    required this.code,
    required this.name,
    required this.tier,
    required this.tagline,
    required this.highlights,
    required this.isMostPopular,
    required this.trialDays,
    required this.maxBranches,
    required this.maxStaffSeats,
    required this.maxBookingsPerMonth,
    required this.aiRunsPerMonth,
    required this.smsPerMonth,
    required this.spotlightsPerMonth,
    required this.supportResponseHours,
    required this.features,
    required this.prices,
  });

  bool get isFree => tier == 0;

  PlanPrice? priceFor(String period) =>
      prices.where((p) => p.period == period).firstOrNull;

  factory UnifyPlan.fromJson(Map<String, dynamic> json) => UnifyPlan(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        tier: (json['tier'] as num?)?.toInt() ?? 0,
        tagline: json['tagline'] as String? ?? '',
        highlights: ((json['highlights'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(),
        isMostPopular: json['isMostPopular'] as bool? ?? false,
        trialDays: (json['trialDays'] as num?)?.toInt() ?? 0,
        maxBranches: (json['maxBranches'] as num?)?.toInt(),
        maxStaffSeats: (json['maxStaffSeats'] as num?)?.toInt(),
        maxBookingsPerMonth: (json['maxBookingsPerMonth'] as num?)?.toInt(),
        aiRunsPerMonth: (json['aiRunsPerMonth'] as num?)?.toInt(),
        smsPerMonth: (json['smsPerMonth'] as num?)?.toInt(),
        spotlightsPerMonth: (json['spotlightsPerMonth'] as num?)?.toInt() ?? 0,
        supportResponseHours: (json['supportResponseHours'] as num?)?.toInt(),
        features: ((json['features'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(),
        prices: ((json['prices'] as List<dynamic>?) ?? const [])
            .map((e) => PlanPrice.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class PlanAddOn {
  final String code;
  final String name;
  final String tagline;
  final String category;
  final String creditType;
  final int quantity;
  final int expiryDays;
  final double amount;
  final String currency;
  final double comparedAtAmount;
  final int savingsPercent;
  final bool isBestValue;
  final int minimumTier;
  final bool availableOnCurrentPlan;

  const PlanAddOn({
    required this.code,
    required this.name,
    required this.tagline,
    required this.category,
    required this.creditType,
    required this.quantity,
    required this.expiryDays,
    required this.amount,
    required this.currency,
    required this.comparedAtAmount,
    required this.savingsPercent,
    required this.isBestValue,
    required this.minimumTier,
    required this.availableOnCurrentPlan,
  });

  factory PlanAddOn.fromJson(Map<String, dynamic> json) => PlanAddOn(
        code: json['code'] as String,
        name: json['name'] as String,
        tagline: json['tagline'] as String? ?? '',
        category: json['category'] as String? ?? '',
        creditType: json['creditType'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        expiryDays: (json['expiryDays'] as num?)?.toInt() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'LKR',
        comparedAtAmount: (json['comparedAtAmount'] as num?)?.toDouble() ?? 0,
        savingsPercent: (json['savingsPercent'] as num?)?.toInt() ?? 0,
        isBestValue: json['isBestValue'] as bool? ?? false,
        minimumTier: (json['minimumTier'] as num?)?.toInt() ?? 0,
        availableOnCurrentPlan: json['availableOnCurrentPlan'] as bool? ?? true,
      );
}

class PlanOffer {
  final String code;
  final String name;
  final String kind;
  final int? percentOff;
  final String description;
  final DateTime? endsAt;

  const PlanOffer({
    required this.code,
    required this.name,
    required this.kind,
    required this.percentOff,
    required this.description,
    required this.endsAt,
  });

  factory PlanOffer.fromJson(Map<String, dynamic> json) => PlanOffer(
        code: json['code'] as String,
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? 'Campaign',
        percentOff: (json['percentOff'] as num?)?.toInt(),
        description: json['description'] as String? ?? '',
        endsAt: json['endsAt'] == null ? null : DateTime.parse(json['endsAt'] as String).toLocal(),
      );
}

class PricingCatalog {
  final String currency;
  final List<String> currencies;
  final List<UnifyPlan> plans;
  final List<PlanAddOn> addOns;
  final PlanOffer? featuredOffer;

  const PricingCatalog({
    required this.currency,
    required this.currencies,
    required this.plans,
    required this.addOns,
    required this.featuredOffer,
  });

  factory PricingCatalog.fromJson(Map<String, dynamic> json) => PricingCatalog(
        currency: json['currency'] as String? ?? 'LKR',
        currencies: ((json['currencies'] as List<dynamic>?) ?? const ['LKR'])
            .map((e) => e as String)
            .toList(),
        plans: ((json['plans'] as List<dynamic>?) ?? const [])
            .map((e) => UnifyPlan.fromJson(e as Map<String, dynamic>))
            .toList(),
        addOns: ((json['addOns'] as List<dynamic>?) ?? const [])
            .map((e) => PlanAddOn.fromJson(e as Map<String, dynamic>))
            .toList(),
        featuredOffer: json['featuredOffer'] == null
            ? null
            : PlanOffer.fromJson(json['featuredOffer'] as Map<String, dynamic>),
      );
}

class UsageMeter {
  final String metric;
  final String label;
  final int used;

  /// Null means unlimited; zero means not included at all. The distinction
  /// is load-bearing, so it is never collapsed into a single int.
  final int? limit;
  final int credits;

  const UsageMeter({
    required this.metric,
    required this.label,
    required this.used,
    required this.limit,
    required this.credits,
  });

  bool get isUnlimited => limit == null;
  bool get isExhausted => limit != null && used >= limit!;
  double get fraction => (limit == null || limit == 0) ? 0 : (used / limit!).clamp(0, 1).toDouble();

  factory UsageMeter.fromJson(Map<String, dynamic> json) => UsageMeter(
        metric: json['metric'] as String,
        label: json['label'] as String? ?? '',
        used: (json['used'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt(),
        credits: (json['credits'] as num?)?.toInt() ?? 0,
      );
}

class UnifySubscription {
  final String planCode;
  final String planName;
  final int tier;
  final String status;
  final bool hasAccess;
  final String period;
  final String periodLabel;
  final String currency;
  final double amount;
  final DateTime? currentPeriodEnd;
  final DateTime? trialEndsAt;
  final bool trialAvailable;
  final int trialDays;
  final bool autoRenew;
  final bool cancelAtPeriodEnd;
  final DateTime? graceEndsAt;
  final int extraSeats;
  final bool isComplimentary;
  final String? promotionCode;
  final List<String> features;
  final List<UsageMeter> usage;
  final Map<String, int> credits;

  const UnifySubscription({
    required this.planCode,
    required this.planName,
    required this.tier,
    required this.status,
    required this.hasAccess,
    required this.period,
    required this.periodLabel,
    required this.currency,
    required this.amount,
    required this.currentPeriodEnd,
    required this.trialEndsAt,
    required this.trialAvailable,
    required this.trialDays,
    required this.autoRenew,
    required this.cancelAtPeriodEnd,
    required this.graceEndsAt,
    required this.extraSeats,
    required this.isComplimentary,
    required this.promotionCode,
    required this.features,
    required this.usage,
    required this.credits,
  });

  bool get isFree => tier == 0;
  bool get isTrialing => status == 'Trialing';
  bool get isPastDue => status == 'PastDue';

  factory UnifySubscription.fromJson(Map<String, dynamic> json) => UnifySubscription(
        planCode: json['planCode'] as String? ?? 'starter',
        planName: json['planName'] as String? ?? 'Starter',
        tier: (json['tier'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'Active',
        hasAccess: json['hasAccess'] as bool? ?? true,
        period: json['period'] as String? ?? 'Monthly',
        periodLabel: json['periodLabel'] as String? ?? 'Monthly',
        currency: json['currency'] as String? ?? 'LKR',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currentPeriodEnd: json['currentPeriodEnd'] == null
            ? null
            : DateTime.parse(json['currentPeriodEnd'] as String).toLocal(),
        trialEndsAt:
            json['trialEndsAt'] == null ? null : DateTime.parse(json['trialEndsAt'] as String).toLocal(),
        trialAvailable: json['trialAvailable'] as bool? ?? false,
        trialDays: (json['trialDays'] as num?)?.toInt() ?? 0,
        autoRenew: json['autoRenew'] as bool? ?? false,
        cancelAtPeriodEnd: json['cancelAtPeriodEnd'] as bool? ?? false,
        graceEndsAt:
            json['graceEndsAt'] == null ? null : DateTime.parse(json['graceEndsAt'] as String).toLocal(),
        extraSeats: (json['extraSeats'] as num?)?.toInt() ?? 0,
        isComplimentary: json['isComplimentary'] as bool? ?? false,
        promotionCode: json['promotionCode'] as String?,
        features: ((json['features'] as List<dynamic>?) ?? const []).map((e) => e as String).toList(),
        usage: ((json['usage'] as List<dynamic>?) ?? const [])
            .map((e) => UsageMeter.fromJson(e as Map<String, dynamic>))
            .toList(),
        credits: ((json['credits'] as Map<String, dynamic>?) ?? const {})
            .map((k, v) => MapEntry(k, (v as num).toInt())),
      );
}

class PlanQuote {
  final String planCode;
  final String planName;
  final String period;
  final String periodLabel;
  final String currency;
  final double listAmount;
  final double discount;
  final double prorationCredit;
  final double total;
  final double renewalAmount;
  final String? promotionCode;
  final String? promotionMessage;
  final DateTime periodEnd;

  const PlanQuote({
    required this.planCode,
    required this.planName,
    required this.period,
    required this.periodLabel,
    required this.currency,
    required this.listAmount,
    required this.discount,
    required this.prorationCredit,
    required this.total,
    required this.renewalAmount,
    required this.promotionCode,
    required this.promotionMessage,
    required this.periodEnd,
  });

  factory PlanQuote.fromJson(Map<String, dynamic> json) => PlanQuote(
        planCode: json['planCode'] as String,
        planName: json['planName'] as String? ?? '',
        period: json['period'] as String? ?? 'Monthly',
        periodLabel: json['periodLabel'] as String? ?? 'Monthly',
        currency: json['currency'] as String? ?? 'LKR',
        listAmount: (json['listAmount'] as num?)?.toDouble() ?? 0,
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        prorationCredit: (json['prorationCredit'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        renewalAmount: (json['renewalAmount'] as num?)?.toDouble() ?? 0,
        promotionCode: json['promotionCode'] as String?,
        promotionMessage: json['promotionMessage'] as String?,
        periodEnd: DateTime.parse(json['periodEnd'] as String).toLocal(),
      );
}

class PlanCheckout {
  final String paymentId;
  final String invoiceNumber;
  final String provider;
  final String status;
  final double amount;
  final String currency;
  final String? redirectUrl;
  final bool simulated;
  final bool completed;

  const PlanCheckout({
    required this.paymentId,
    required this.invoiceNumber,
    required this.provider,
    required this.status,
    required this.amount,
    required this.currency,
    required this.redirectUrl,
    required this.simulated,
    required this.completed,
  });

  factory PlanCheckout.fromJson(Map<String, dynamic> json) => PlanCheckout(
        paymentId: json['paymentId'] as String,
        invoiceNumber: json['invoiceNumber'] as String? ?? '',
        provider: json['provider'] as String? ?? 'Manual',
        status: json['status'] as String? ?? 'Pending',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'LKR',
        redirectUrl: json['redirectUrl'] as String?,
        simulated: json['simulated'] as bool? ?? false,
        completed: json['completed'] as bool? ?? false,
      );
}

class UnifyInvoice {
  final String id;
  final String number;
  final String kind;
  final String? planCode;
  final String currency;
  final double total;
  final String status;
  final DateTime issuedAt;
  final DateTime? paidAt;

  const UnifyInvoice({
    required this.id,
    required this.number,
    required this.kind,
    required this.planCode,
    required this.currency,
    required this.total,
    required this.status,
    required this.issuedAt,
    required this.paidAt,
  });

  bool get isPayable => (status == 'Issued' || status == 'Failed') && total > 0;

  factory UnifyInvoice.fromJson(Map<String, dynamic> json) => UnifyInvoice(
        id: json['id'] as String,
        number: json['number'] as String? ?? '',
        kind: json['kind'] as String? ?? 'Subscription',
        planCode: json['planCode'] as String?,
        currency: json['currency'] as String? ?? 'LKR',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? 'Issued',
        issuedAt: DateTime.parse(json['issuedAt'] as String).toLocal(),
        paidAt: json['paidAt'] == null ? null : DateTime.parse(json['paidAt'] as String).toLocal(),
      );
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
