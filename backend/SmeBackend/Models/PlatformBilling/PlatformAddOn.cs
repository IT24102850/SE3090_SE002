namespace SmeBackend.Models;

/// Something a tenant buys on top of their plan, one click, no new
/// subscription: a visibility boost, a pack of AI runs, a pack of SMS, an
/// extra staff seat. Priced per pack with a bulk discount, so the bigger
/// pack is always the better unit price.
///
/// Catalogue-defined like PlatformPlan; prices sit in a jsonb map rather
/// than a child table because an add-on has one price per currency and no
/// term ladder.
public class PlatformAddOn : BaseEntity
{
    /// spotlight-1 | spotlight-5 | ai-credits-500 | sms-2000 | seat-1 ...
    public string Code { get; set; } = string.Empty;

    public string Name { get; set; } = string.Empty;
    public string Tagline { get; set; } = string.Empty;

    /// The credit this grants - see PlatformCreditTypes. "seat" is the one
    /// that is not a credit: it raises the subscription's ExtraSeats.
    public string CreditType { get; set; } = string.Empty;

    /// How many units of CreditType one purchase grants.
    public int Quantity { get; set; } = 1;

    /// Days until unused credits lapse. 0 = never.
    public int ExpiryDays { get; set; }

    /// JSON map of currency to amount.
    public string PricesJson { get; set; } = "{}";

    /// Grouping on the store page: Visibility, AI, Messaging, Seats.
    public string Category { get; set; } = string.Empty;

    /// The pack the store nudges towards - the one with the best unit price.
    public bool IsBestValue { get; set; }

    /// Whole percent saved against buying Quantity single units, for the
    /// savings badge. 0 on a single-unit pack.
    public int SavingsPercent { get; set; }

    /// The lowest tier that may buy this at all (Spotlight is worth nothing
    /// to a tenant who is not in the public directory).
    public int MinimumTier { get; set; }

    public bool IsPublic { get; set; } = true;
    public int SortOrder { get; set; }
}

public static class PlatformCreditTypes
{
    /// 24 hours at the top of the public directory for one business.
    public const string Spotlight = "spotlight";
    /// One agentic-AI run beyond the plan's monthly allowance.
    public const string AiRun = "ai-run";
    /// One SMS or WhatsApp reminder beyond the plan's monthly allowance.
    public const string Sms = "sms";
    /// Not a credit: one more staff seat, for as long as the plan runs.
    public const string Seat = "seat";

    public static readonly string[] All = { Spotlight, AiRun, Sms, Seat };
}

/// A tenant's credit ledger, as lots rather than as a running total.
///
/// Every grant is a row with its own expiry and its own Remaining, and a
/// spend draws down the lot that expires soonest. The alternative - a single
/// balance, filtered by expiry at read time - cannot say which grant a spend
/// came out of, so a tenant who spends from a pack and then watches a
/// free monthly grant lapse loses credits they actually paid for. This shape
/// costs one extra column and makes the balance arithmetic, not a guess.
///
/// Balance = the sum of Remaining over grant rows that have not expired. The
/// negative rows are the audit trail of spends and refunds; they are never
/// part of the balance.
public class PlatformCreditEntry : BaseEntity
{
    public Guid TenantId { get; set; }

    /// PlatformCreditTypes.
    public string CreditType { get; set; } = string.Empty;

    /// Positive on a purchase or a monthly plan grant, negative on a spend
    /// or a refund.
    public int Delta { get; set; }

    /// Grant rows only: how much of this lot is still unspent. Always 0 on a
    /// negative row.
    public int Remaining { get; set; }

    /// purchase | plan-grant | spend | comp | refund
    public string Reason { get; set; } = string.Empty;

    public Guid? InvoiceId { get; set; }
    public string? Detail { get; set; }

    /// Null = never lapses. A lot past its expiry stops counting towards the
    /// balance; no write-off row is needed, because Remaining already says
    /// what was left when it went.
    public DateTime? ExpiresAt { get; set; }
}

/// What a tenant has used this calendar month against a metered limit. One
/// row per tenant per metric per month; the turn of the month is implicit in
/// PeriodKey rather than a job that resets counters.
public class PlatformUsageCounter : BaseEntity
{
    public Guid TenantId { get; set; }

    /// bookings | ai-runs | sms - see UsageMetrics.
    public string Metric { get; set; } = string.Empty;

    /// The calendar month this count belongs to, as yyyy-MM.
    public string PeriodKey { get; set; } = string.Empty;

    public int Used { get; set; }
}

public static class UsageMetrics
{
    public const string Bookings = "bookings";
    public const string AiRuns = "ai-runs";
    public const string Sms = "sms";

    public static string PeriodKey(DateTime utcNow) => utcNow.ToString("yyyy-MM");
}
