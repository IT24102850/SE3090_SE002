namespace SmeBackend.Models;

/// One rung of Unify's own price ladder - what a tenant admin buys from us,
/// not what their customers buy from them (that is Models/Subscription.cs).
///
/// The catalogue is code-defined and synced at startup
/// (Data/PlatformPlanCatalog.cs) rather than edited in a table, so a price
/// change is a reviewable commit and every environment shows the same
/// ladder. Rows the catalogue no longer names are retired, never deleted:
/// a tenant sitting on last year's price keeps paying it until they move.
public class PlatformPlan : BaseEntity
{
    /// Stable machine name - "starter", "grow", "pro", "prime". This, not
    /// the id, is what the apps and the seed data refer to.
    public string Code { get; set; } = string.Empty;

    public string Name { get; set; } = string.Empty;

    /// Where it sits on the ladder: 0 = free. A feature check is "is the
    /// tenant's tier at least N", so the order matters more than the name.
    public int Tier { get; set; }

    /// One line under the plan name on the pricing page.
    public string Tagline { get; set; } = string.Empty;

    /// JSON string[] - the bullets on the pricing card, in order.
    public string HighlightsJson { get; set; } = "[]";

    /// JSON PlanLimits - the caps and feature flags this plan grants.
    /// Services/PlatformBilling/PlanLimits.cs is the shape.
    public string LimitsJson { get; set; } = "{}";

    /// Shown on the public pricing page. A retired plan stays payable by the
    /// tenants already on it but stops being offered.
    public bool IsPublic { get; set; } = true;

    /// The one card the pricing page pushes. Exactly one plan carries it.
    public bool IsMostPopular { get; set; }

    /// Free trial length for a tenant that has never trialled before. 0 = none.
    public int TrialDays { get; set; }

    public bool IsRetired { get; set; }

    public ICollection<PlatformPlanPrice> Prices { get; set; } = new List<PlatformPlanPrice>();
}

/// A plan's price for one currency and one commitment length. The ladder is
/// deliberately three rungs (see BillingPeriods): the monthly price is the
/// anchor that makes the yearly one read as a saving.
public class PlatformPlanPrice : BaseEntity
{
    public Guid PlanId { get; set; }
    public PlatformPlan Plan { get; set; } = null!;

    /// ISO 4217. LKR is the home market; USD is everyone else.
    public string Currency { get; set; } = "LKR";

    /// Monthly | SemiAnnual | Annual - see BillingPeriods.
    public string Period { get; set; } = BillingPeriods.Monthly;

    /// What is charged, once, at the start of the term.
    public decimal Amount { get; set; }

    /// Amount / months, precomputed so the card and the invoice cannot
    /// disagree about "LKR 3,540/mo".
    public decimal MonthlyEquivalent { get; set; }

    /// Whole percent off this plan's monthly price at the same currency.
    /// 0 on the monthly rung itself.
    public int SavingsPercent { get; set; }

    /// The "Best value" flag on the term toggle.
    public bool IsBestValue { get; set; }

    public bool IsActive { get; set; } = true;
}

public static class BillingPeriods
{
    public const string Monthly = "Monthly";
    public const string SemiAnnual = "SemiAnnual";
    public const string Annual = "Annual";

    public static readonly string[] All = { Monthly, SemiAnnual, Annual };

    public static int Months(string period) => period switch
    {
        SemiAnnual => 6,
        Annual => 12,
        _ => 1,
    };

    public static string Label(string period) => period switch
    {
        SemiAnnual => "6 months",
        Annual => "12 months",
        _ => "Monthly",
    };

    public static string? Normalize(string? period) =>
        All.FirstOrDefault(p => p.Equals(period?.Trim(), StringComparison.OrdinalIgnoreCase));
}

public static class PlatformPlanCodes
{
    public const string Starter = "starter";
    public const string Grow = "grow";
    public const string Pro = "pro";
    public const string Prime = "prime";
}
