namespace SmeBackend.Models;

/// A bill Unify raises against a tenant. Separate from Models/Invoice.cs on
/// purpose: that one is a tenant billing their own customer and is filtered
/// by tenant on every read, which is exactly wrong for a bill the platform
/// owner needs to see across every tenant.
public class PlatformInvoice : BaseEntity
{
    public Guid TenantId { get; set; }
    public Tenant Tenant { get; set; } = null!;

    /// UNF-2026-000123. Unique across the platform.
    public string Number { get; set; } = string.Empty;

    /// Subscription | AddOn
    public string Kind { get; set; } = PlatformInvoiceKinds.Subscription;

    public string? PlanCode { get; set; }
    public string? Period { get; set; }

    public string Currency { get; set; } = "LKR";
    public decimal Subtotal { get; set; }
    public decimal Discount { get; set; }
    public decimal Tax { get; set; }
    public decimal Total { get; set; }

    /// Draft | Issued | Paid | Failed | Cancelled | Refunded
    public string Status { get; set; } = PlatformInvoiceStatuses.Issued;

    /// JSON array of { description, quantity, unitAmount, amount }.
    public string LinesJson { get; set; } = "[]";

    public string? PromotionCode { get; set; }

    public DateTime IssuedAt { get; set; } = DateTime.UtcNow;
    public DateTime DueAt { get; set; } = DateTime.UtcNow;
    public DateTime? PaidAt { get; set; }

    /// The term this bill buys, so a paid invoice can be replayed into a
    /// subscription without re-deriving the dates.
    public DateTime? PeriodStart { get; set; }
    public DateTime? PeriodEnd { get; set; }

    public ICollection<PlatformPayment> Payments { get; set; } = new List<PlatformPayment>();
}

public static class PlatformInvoiceKinds
{
    public const string Subscription = "Subscription";
    public const string AddOn = "AddOn";
}

public static class PlatformInvoiceStatuses
{
    public const string Draft = "Draft";
    public const string Issued = "Issued";
    public const string Paid = "Paid";
    public const string Failed = "Failed";
    public const string Cancelled = "Cancelled";
    public const string Refunded = "Refunded";
}

/// An attempt to pay a PlatformInvoice through Unify's own gateway account.
/// Mirrors Models/Payment.cs deliberately - same statuses, same settlement
/// columns - so the two reconcile the same way.
public class PlatformPayment : BaseEntity
{
    public Guid InvoiceId { get; set; }
    public PlatformInvoice Invoice { get; set; } = null!;

    public Guid TenantId { get; set; }

    public decimal Amount { get; set; }
    public string Currency { get; set; } = "LKR";

    /// Card | Wallet | BankTransfer
    public string Method { get; set; } = "Card";

    /// Stripe | PayPal | Manual
    public string Provider { get; set; } = string.Empty;

    /// Pending | Succeeded | Failed | Refunded (Models/Payment.cs).
    public string Status { get; set; } = PaymentStatuses.Pending;

    /// The provider's id for the checkout session / order.
    public string? ExternalId { get; set; }
    public string? GatewayResponse { get; set; }
    public DateTime? PaidAt { get; set; }

    /// Set when the gateway cannot take Currency (Stripe will not take LKR).
    /// Amount stays in the invoice's currency; these record the real charge.
    public string? SettlementCurrency { get; set; }
    public decimal? SettlementAmount { get; set; }
    public decimal? ExchangeRate { get; set; }

    /// What this payment buys, so the webhook can finish the job with no
    /// session state: a plan change, or a pack of credits.
    public string? IntentJson { get; set; }
}
