namespace SmeBackend.Models;

/// A tenant's standing with Unify: which plan they are on, until when, and
/// whether it renews. Exactly one row per tenant - changing plan rewrites
/// this row and appends a PlatformSubscriptionEvent, so the current state is
/// always one lookup and the history is never lost.
///
/// Deliberately not ITenantScoped. The renewal worker, the webhook handler
/// and the owner's console all touch these rows with no tenant in context,
/// which the tenant-scope save guard would refuse.
public class PlatformSubscription : BaseEntity
{
    public Guid TenantId { get; set; }
    public Tenant Tenant { get; set; } = null!;

    public Guid PlanId { get; set; }
    public PlatformPlan Plan { get; set; } = null!;

    /// Copied from the plan so a lookup of "what is this tenant allowed to
    /// do" never needs the join, and so a retired plan's code survives.
    public string PlanCode { get; set; } = PlatformPlanCodes.Starter;
    public int Tier { get; set; }

    /// Null on the free plan, which has no price row.
    public Guid? PriceId { get; set; }

    public string Status { get; set; } = PlatformSubscriptionStatuses.Active;

    /// Monthly | SemiAnnual | Annual. Meaningless on the free plan, where it
    /// stays Monthly and the period simply never ends.
    public string Period { get; set; } = BillingPeriods.Monthly;

    public string Currency { get; set; } = "LKR";

    /// What the next renewal will charge - the price as it stood when they
    /// subscribed, not today's catalogue price. Price rises do not reach an
    /// existing subscriber until they change plan.
    public decimal Amount { get; set; }

    public DateTime CurrentPeriodStart { get; set; } = DateTime.UtcNow;

    /// Null only on the free plan: it does not expire.
    public DateTime? CurrentPeriodEnd { get; set; }

    public DateTime? TrialEndsAt { get; set; }

    /// Set the first time this tenant starts a trial, and never cleared - one
    /// free trial per business, whatever they do afterwards.
    public DateTime? TrialUsedAt { get; set; }

    public bool AutoRenew { get; set; } = true;

    /// A cancellation that has not taken effect yet: they keep everything
    /// they paid for until CurrentPeriodEnd, then drop to Starter. The
    /// opposite of switching the account off the moment they click cancel.
    public bool CancelAtPeriodEnd { get; set; }
    public DateTime? CancelRequestedAt { get; set; }
    public string? CancelReason { get; set; }

    /// A failed renewal does not lock the account: it starts a grace window
    /// during which the tenant keeps their features and gets chased.
    public DateTime? GraceEndsAt { get; set; }
    public int FailedRenewalAttempts { get; set; }

    /// Extra staff seats bought on top of the plan's allowance.
    public int ExtraSeats { get; set; }

    /// The promotion applied to the current term, for the receipt and for
    /// the "your intro price ends on ..." notice.
    public string? PromotionCode { get; set; }
    public decimal DiscountAmount { get; set; }

    /// Set by the owner console when a plan is comped (a partner, a pilot).
    /// A comped subscription renews for free and is left out of MRR.
    public bool IsComplimentary { get; set; }
    public string? ComplimentaryReason { get; set; }

    public DateTime? LastPaymentAt { get; set; }
    public DateTime? StartedAt { get; set; } = DateTime.UtcNow;

    /// True while the tenant may use everything the plan grants.
    public bool GrantsAccess(DateTime now) =>
        Status is PlatformSubscriptionStatuses.Active
            or PlatformSubscriptionStatuses.Trialing
            or PlatformSubscriptionStatuses.PastDue
            or PlatformSubscriptionStatuses.Cancelling
        && (CurrentPeriodEnd is null || CurrentPeriodEnd > now || (GraceEndsAt is { } g && g > now));
}

public static class PlatformSubscriptionStatuses
{
    /// Inside a free trial of a paid plan.
    public const string Trialing = "Trialing";
    /// Paid and current - and the state the free Starter plan sits in for ever.
    public const string Active = "Active";
    /// A renewal charge failed. Full access continues until GraceEndsAt.
    public const string PastDue = "PastDue";
    /// Cancelled and the term has run out, or the grace window lapsed. The
    /// tenant is back on Starter.
    public const string Expired = "Expired";
    /// Cancelled by the tenant with the term still running.
    public const string Cancelling = "Cancelling";

    public static readonly string[] All = { Trialing, Active, PastDue, Expired, Cancelling };
}

/// Every change of standing, kept for the owner's console, for disputes and
/// for the churn and trial-conversion figures.
public class PlatformSubscriptionEvent : BaseEntity
{
    public Guid TenantId { get; set; }
    public Guid? SubscriptionId { get; set; }

    /// subscribe | upgrade | downgrade | renew | renew.failed | trial.start |
    /// trial.convert | trial.expire | cancel | resume | expire | comp | addon.purchase
    public string EventType { get; set; } = string.Empty;

    public string? FromPlanCode { get; set; }
    public string? ToPlanCode { get; set; }
    public string? Period { get; set; }
    public string? Currency { get; set; }
    public decimal? Amount { get; set; }
    public string? ActorEmail { get; set; }
    public string? Detail { get; set; }
}
