namespace SmeBackend.Models;

/// A discount code. Four kinds, and the distinction matters for how the
/// pricing page is allowed to talk about them:
///
///   Intro    - a cheap first term to get a business onto a paid plan. The
///              renewal is at full price and the subscription screen says so.
///   WinBack  - offered to a tenant whose subscription has lapsed.
///   Loyalty  - offered on a tenant's own anniversary.
///   Campaign - a flat public code with a window and a redemption cap.
///
/// Note on what this deliberately is not. Tinder's ladder also varied by the
/// buyer's age, which produced a class action in California and an ACCC
/// finding in Australia. Tenure and lapse are things a business does; age is
/// something a person is. The personalised half of that playbook is
/// reproduced here as offers earned by behaviour, and no demographic value
/// is an input to any price this system quotes.
public class PlatformPromotion : BaseEntity
{
    /// Typed by the tenant, matched case-insensitively.
    public string Code { get; set; } = string.Empty;

    public string Name { get; set; } = string.Empty;

    /// Intro | WinBack | Loyalty | Campaign
    public string Kind { get; set; } = PromotionKinds.Campaign;

    /// Whole percent off the term. Exactly one of this and AmountOff is set.
    public int? PercentOff { get; set; }
    public decimal? AmountOff { get; set; }
    public string? AmountCurrency { get; set; }

    /// Restrict to one plan or one term. Null = any.
    public string? PlanCode { get; set; }
    public string? Period { get; set; }

    /// How many terms the discount survives. 1 = first term only.
    public int Terms { get; set; } = 1;

    public DateTime? StartsAt { get; set; }
    public DateTime? EndsAt { get; set; }

    /// 0 = unlimited.
    public int MaxRedemptions { get; set; }
    public int Redemptions { get; set; }

    /// Only valid for a tenant that has never held a paid plan.
    public bool NewTenantsOnly { get; set; }

    /// Only valid for a tenant whose paid plan has lapsed.
    public bool LapsedTenantsOnly { get; set; }

    /// Offered without the tenant having to know the code: the subscription
    /// screen surfaces the best live auto-apply offer they qualify for.
    public bool AutoApply { get; set; }

    public bool IsActive { get; set; } = true;

    public bool IsLive(DateTime now) =>
        IsActive
        && (StartsAt is null || StartsAt <= now)
        && (EndsAt is null || EndsAt > now)
        && (MaxRedemptions == 0 || Redemptions < MaxRedemptions);
}

public static class PromotionKinds
{
    public const string Intro = "Intro";
    public const string WinBack = "WinBack";
    public const string Loyalty = "Loyalty";
    public const string Campaign = "Campaign";
}

public class PlatformPromotionRedemption : BaseEntity
{
    public Guid PromotionId { get; set; }
    public Guid TenantId { get; set; }
    public Guid? InvoiceId { get; set; }
    public string Code { get; set; } = string.Empty;
    public decimal DiscountAmount { get; set; }
    public string Currency { get; set; } = "LKR";
}
