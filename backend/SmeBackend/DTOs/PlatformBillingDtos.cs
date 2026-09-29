using System.ComponentModel.DataAnnotations;

namespace SmeBackend.DTOs;

// ── Catalogue (public: this is the pricing page) ─────────────────────────

public sealed record PlanPriceResponse(
    Guid Id,
    string Period,
    string PeriodLabel,
    string Currency,
    decimal Amount,
    decimal MonthlyEquivalent,
    int SavingsPercent,
    bool IsBestValue,
    /// What the same term would cost at the monthly rate - the anchor the
    /// saving is measured against, shown struck through on the card.
    decimal ComparedAtAmount);

public sealed record PlanResponse(
    Guid Id,
    string Code,
    string Name,
    int Tier,
    string Tagline,
    string[] Highlights,
    bool IsMostPopular,
    int TrialDays,
    int? MaxBranches,
    int? MaxStaffSeats,
    int? MaxBookingsPerMonth,
    int? AiRunsPerMonth,
    int? SmsPerMonth,
    int SpotlightsPerMonth,
    int? SupportResponseHours,
    string[] Features,
    IReadOnlyList<PlanPriceResponse> Prices);

public sealed record AddOnResponse(
    Guid Id,
    string Code,
    string Name,
    string Tagline,
    string Category,
    string CreditType,
    int Quantity,
    int ExpiryDays,
    decimal Amount,
    string Currency,
    /// The same quantity bought one at a time, for the struck-through price.
    decimal ComparedAtAmount,
    int SavingsPercent,
    bool IsBestValue,
    int MinimumTier,
    bool AvailableOnCurrentPlan);

public sealed record PricingCatalogResponse(
    string Currency,
    IReadOnlyList<string> Currencies,
    IReadOnlyList<PlanResponse> Plans,
    IReadOnlyList<AddOnResponse> AddOns,
    /// The best offer this caller can take without typing a code.
    PromotionResponse? FeaturedOffer);

public sealed record PromotionResponse(
    string Code,
    string Name,
    string Kind,
    int? PercentOff,
    decimal? AmountOff,
    string? Currency,
    string? PlanCode,
    string? Period,
    int Terms,
    DateTime? EndsAt,
    string Description);

// ── The tenant's own subscription ────────────────────────────────────────

public sealed record UsageMeterResponse(string Metric, string Label, int Used, int? Limit, int Credits);

public sealed record PlatformSubscriptionResponse(
    Guid TenantId,
    string PlanCode,
    string PlanName,
    int Tier,
    string Status,
    bool HasAccess,
    string Period,
    string PeriodLabel,
    string Currency,
    decimal Amount,
    DateTime CurrentPeriodStart,
    DateTime? CurrentPeriodEnd,
    DateTime? TrialEndsAt,
    bool TrialAvailable,
    int TrialDays,
    bool AutoRenew,
    bool CancelAtPeriodEnd,
    DateTime? GraceEndsAt,
    int ExtraSeats,
    bool IsComplimentary,
    string? PromotionCode,
    string[] Features,
    IReadOnlyList<UsageMeterResponse> Usage,
    IReadOnlyDictionary<string, int> Credits,
    DateTime? LastPaymentAt);

public sealed record PlatformInvoiceLine(string Description, int Quantity, decimal UnitAmount, decimal Amount);

public sealed record PlatformInvoiceResponse(
    Guid Id,
    string Number,
    string Kind,
    string? PlanCode,
    string? Period,
    string Currency,
    decimal Subtotal,
    decimal Discount,
    decimal Tax,
    decimal Total,
    string Status,
    string? PromotionCode,
    DateTime IssuedAt,
    DateTime DueAt,
    DateTime? PaidAt,
    DateTime? PeriodStart,
    DateTime? PeriodEnd,
    IReadOnlyList<PlatformInvoiceLine> Lines);

/// What a checkout will cost before the tenant commits to it. The
/// subscription screen shows this in the confirm step so the discount, the
/// proration credit and the renewal price are all visible before paying.
public sealed record SubscriptionQuoteResponse(
    string PlanCode,
    string PlanName,
    string Period,
    string PeriodLabel,
    string Currency,
    decimal ListAmount,
    decimal Discount,
    decimal ProrationCredit,
    decimal Total,
    decimal RenewalAmount,
    string? PromotionCode,
    string? PromotionMessage,
    DateTime PeriodStart,
    DateTime PeriodEnd,
    IReadOnlyList<PlatformInvoiceLine> Lines);

// ── Requests ─────────────────────────────────────────────────────────────

public class SubscriptionQuoteRequest
{
    [Required, MaxLength(40)] public string PlanCode { get; set; } = string.Empty;
    [MaxLength(20)] public string? Period { get; set; }
    [MaxLength(3)] public string? Currency { get; set; }
    [MaxLength(40)] public string? PromotionCode { get; set; }
}

public sealed class SubscriptionCheckoutRequest : SubscriptionQuoteRequest
{
    /// Stripe | PayPal | Manual. Null picks the platform default.
    [MaxLength(20)] public string? Provider { get; set; }

    /// Where the gateway sends the tenant back to.
    [MaxLength(500)] public string? ReturnUrl { get; set; }
}

public sealed class AddOnCheckoutRequest
{
    [Required, MaxLength(60)] public string AddOnCode { get; set; } = string.Empty;
    [Range(1, 20)] public int Quantity { get; set; } = 1;
    [MaxLength(3)] public string? Currency { get; set; }
    [MaxLength(20)] public string? Provider { get; set; }
    [MaxLength(500)] public string? ReturnUrl { get; set; }
}

public sealed class ConfirmPlatformPaymentRequest
{
    [Required] public Guid PaymentId { get; set; }
    /// Sandbox only: exercise the failure path.
    public bool SimulateFailure { get; set; }
}

public sealed class CancelPlatformSubscriptionRequest
{
    [MaxLength(500)] public string? Reason { get; set; }
    /// Default false: the tenant keeps what they paid for until the term
    /// ends. True is only honoured for a subscription still inside its trial.
    public bool Immediate { get; set; }
}

public sealed record PlatformCheckoutResponse(
    Guid PaymentId,
    Guid InvoiceId,
    string InvoiceNumber,
    string Provider,
    string Status,
    decimal Amount,
    string Currency,
    string? RedirectUrl,
    string? ClientSecret,
    string? PublicKey,
    bool Simulated,
    string? SettlementCurrency,
    decimal? SettlementAmount,
    decimal? ExchangeRate,
    /// Set when the plan change needed no payment at all (a free plan, a
    /// comped account, a promotion that covered the whole term): the
    /// subscription is already live and there is nothing to redirect to.
    bool Completed);
