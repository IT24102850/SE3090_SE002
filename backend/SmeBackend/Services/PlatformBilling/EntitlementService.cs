using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Services.PlatformBilling;

/// What a tenant is currently allowed to do, and the one place that answers
/// it. Everything else - the attribute on a controller, the subscription
/// screen, the paywall the apps show - reads this.
public sealed record EntitlementSnapshot(
    Guid TenantId,
    string PlanCode,
    string PlanName,
    int Tier,
    string Status,
    bool HasAccess,
    bool IsTrialing,
    DateTime? TrialEndsAt,
    DateTime? CurrentPeriodEnd,
    DateTime? GraceEndsAt,
    bool CancelAtPeriodEnd,
    PlanLimits Limits,
    int ExtraSeats,
    IReadOnlyDictionary<string, int> Credits)
{
    /// The plan allowance plus any seats bought as an add-on. Null stays
    /// null: unlimited plus five is still unlimited.
    public int? SeatAllowance => Limits.MaxStaffSeats is { } s ? s + ExtraSeats : null;

    public bool Has(string feature) => HasAccess && Limits.Has(feature);

    public int Credit(string type) => Credits.TryGetValue(type, out var n) ? n : 0;
}

/// Why a request was refused and what would fix it. This is the body of
/// every 402 the API returns, and the apps render it as the paywall.
public sealed record PaywallInfo(
    string Reason,
    string? Feature,
    string? Metric,
    int? Used,
    int? Limit,
    string CurrentPlanCode,
    string? RequiredPlanCode,
    string? RequiredPlanName,
    string Message,
    string? AddOnCode = null);

public sealed record QuotaDecision(bool Allowed, bool FromCredits, PaywallInfo? Paywall)
{
    public static readonly QuotaDecision Ok = new(true, false, null);
    public static QuotaDecision Credits() => new(true, true, null);
    public static QuotaDecision Deny(PaywallInfo paywall) => new(false, false, paywall);
}

public interface IEntitlementService
{
    Task<EntitlementSnapshot> GetAsync(Guid tenantId, CancellationToken ct = default);

    /// The gate a controller calls. Null when the tenant may proceed.
    Task<PaywallInfo?> CheckFeatureAsync(Guid tenantId, string feature, CancellationToken ct = default);

    /// Checks a counted allowance without spending anything. `current` is
    /// what the caller already knows (rows in the table, for the caps that
    /// are a count of live records rather than a monthly meter).
    Task<PaywallInfo?> CheckCapAsync(Guid tenantId, string cap, int current, CancellationToken ct = default);

    /// Checks a monthly meter and, if the allowance is spent, falls back to
    /// bought credits. Nothing is consumed - call ConsumeAsync after the
    /// work actually succeeded.
    Task<QuotaDecision> CheckQuotaAsync(Guid tenantId, string metric, int amount = 1, CancellationToken ct = default);

    /// Records the usage the decision allowed. Safe to call with a decision
    /// that was denied; it does nothing.
    Task ConsumeAsync(Guid tenantId, string metric, QuotaDecision decision, int amount = 1, CancellationToken ct = default);

    /// What this tenant has spent of a monthly meter, for the usage bars on
    /// the subscription screen.
    Task<int> UsedThisMonthAsync(Guid tenantId, string metric, CancellationToken ct = default);

    /// Spends bought credits directly, for the things that are not metered
    /// against a monthly allowance at all - a Spotlight is one credit, spent
    /// the moment the tenant switches it on.
    Task<int> SpendCreditsAsync(Guid tenantId, string creditType, int amount, string? detail, CancellationToken ct = default);

    /// Every tenant has a subscription row; a tenant created before this
    /// feature existed gets the free one the first time anybody asks.
    Task<PlatformSubscription> EnsureSubscriptionAsync(Guid tenantId, CancellationToken ct = default);

    void Invalidate(Guid tenantId);
}

public sealed class EntitlementService : IEntitlementService
{
    /// Caps that count live rows rather than a monthly meter.
    public const string CapBranches = "branches";
    public const string CapStaffSeats = "staff-seats";
    public const string CapResources = "resources";

    /// Short enough that an upgrade takes effect while the tenant is still
    /// looking at the screen, long enough that a busy dashboard is not a
    /// query per request. Every write path calls Invalidate anyway.
    private static readonly TimeSpan CacheFor = TimeSpan.FromSeconds(60);

    private readonly AppDbContext _db;
    private readonly IMemoryCache _cache;
    private readonly ILogger<EntitlementService> _logger;

    public EntitlementService(AppDbContext db, IMemoryCache cache, ILogger<EntitlementService> logger)
    {
        _db = db;
        _cache = cache;
        _logger = logger;
    }

    private static string CacheKey(Guid tenantId) => $"entitlements:{tenantId}";

    public void Invalidate(Guid tenantId) => _cache.Remove(CacheKey(tenantId));

    public async Task<EntitlementSnapshot> GetAsync(Guid tenantId, CancellationToken ct = default)
    {
        if (_cache.TryGetValue<EntitlementSnapshot>(CacheKey(tenantId), out var cached) && cached is not null)
            return cached;

        var snapshot = await BuildAsync(tenantId, ct);
        _cache.Set(CacheKey(tenantId), snapshot, CacheFor);
        return snapshot;
    }

    private async Task<EntitlementSnapshot> BuildAsync(Guid tenantId, CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var subscription = await EnsureSubscriptionAsync(tenantId, ct);
        var plan = await _db.PlatformPlans.AsNoTracking().FirstOrDefaultAsync(p => p.Id == subscription.PlanId, ct);

        var hasAccess = subscription.GrantsAccess(now);

        // A lapsed subscription does not keep the plan it stopped paying
        // for. The row is left alone - the renewal worker is what rewrites
        // it - but what the tenant may do right now is the free plan.
        var effectiveLimits = hasAccess
            ? PlanLimits.Parse(plan?.LimitsJson)
            : PlanLimits.Parse((await _db.PlatformPlans.AsNoTracking()
                .FirstOrDefaultAsync(p => p.Code == PlatformPlanCodes.Starter, ct))?.LimitsJson);

        var credits = await CreditBalancesAsync(tenantId, now, ct);

        return new EntitlementSnapshot(
            tenantId,
            hasAccess ? subscription.PlanCode : PlatformPlanCodes.Starter,
            hasAccess ? plan?.Name ?? subscription.PlanCode : "Starter",
            hasAccess ? subscription.Tier : 0,
            subscription.Status,
            hasAccess,
            subscription.Status == PlatformSubscriptionStatuses.Trialing,
            subscription.TrialEndsAt,
            subscription.CurrentPeriodEnd,
            subscription.GraceEndsAt,
            subscription.CancelAtPeriodEnd,
            effectiveLimits,
            hasAccess ? subscription.ExtraSeats : 0,
            credits);
    }

    /// The sum of what is left in every lot that has not expired. Spend rows
    /// are audit only - they have already been taken off a lot's Remaining.
    private async Task<Dictionary<string, int>> CreditBalancesAsync(Guid tenantId, DateTime now, CancellationToken ct)
    {
        var rows = await _db.PlatformCreditEntries.AsNoTracking()
            .Where(e => e.TenantId == tenantId && e.Delta > 0 && e.Remaining > 0
                        && (e.ExpiresAt == null || e.ExpiresAt > now))
            .GroupBy(e => e.CreditType)
            .Select(g => new { Type = g.Key, Balance = g.Sum(e => e.Remaining) })
            .ToListAsync(ct);
        return rows.ToDictionary(r => r.Type, r => Math.Max(0, r.Balance), StringComparer.OrdinalIgnoreCase);
    }

    public async Task<PlatformSubscription> EnsureSubscriptionAsync(Guid tenantId, CancellationToken ct = default)
    {
        var existing = await _db.PlatformSubscriptions.FirstOrDefaultAsync(s => s.TenantId == tenantId, ct);
        if (existing is not null) return existing;

        var starter = await _db.PlatformPlans.FirstOrDefaultAsync(p => p.Code == PlatformPlanCodes.Starter, ct);
        if (starter is null)
        {
            // The catalogue has not been synced yet (a test fixture, or a
            // first boot racing the seeder). An in-memory Starter keeps the
            // caller working without writing a row that points nowhere.
            _logger.LogWarning("No Starter plan in the catalogue; tenant {TenantId} is treated as free.", tenantId);
            return new PlatformSubscription { TenantId = tenantId, PlanCode = PlatformPlanCodes.Starter, Tier = 0 };
        }

        var subscription = new PlatformSubscription
        {
            TenantId = tenantId,
            PlanId = starter.Id,
            PlanCode = starter.Code,
            Tier = starter.Tier,
            Status = PlatformSubscriptionStatuses.Active,
            Currency = PlatformPlanCatalog.DefaultCurrency,
            Amount = 0m,
            CurrentPeriodStart = DateTime.UtcNow,
            CurrentPeriodEnd = null,
            AutoRenew = false,
        };
        _db.PlatformSubscriptions.Add(subscription);
        try
        {
            await _db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // Two requests for a brand-new tenant can race here; the unique
            // index on TenantId is what makes one of them lose.
            _db.Entry(subscription).State = EntityState.Detached;
            return await _db.PlatformSubscriptions.FirstAsync(s => s.TenantId == tenantId, ct);
        }
        return subscription;
    }

    public async Task<PaywallInfo?> CheckFeatureAsync(Guid tenantId, string feature, CancellationToken ct = default)
    {
        var snapshot = await GetAsync(tenantId, ct);
        if (snapshot.Has(feature)) return null;

        var required = await CheapestPlanWithAsync(feature, ct);
        return new PaywallInfo(
            Reason: "feature",
            Feature: feature,
            Metric: null,
            Used: null,
            Limit: null,
            CurrentPlanCode: snapshot.PlanCode,
            RequiredPlanCode: required?.Code,
            RequiredPlanName: required?.Name,
            Message: required is null
                ? $"{Capitalise(PlanFeatures.Describe(feature))} is not available on your plan."
                : $"{Capitalise(PlanFeatures.Describe(feature))} is part of {required.Name}. Upgrade to switch it on.");
    }

    public async Task<PaywallInfo?> CheckCapAsync(Guid tenantId, string cap, int current, CancellationToken ct = default)
    {
        var snapshot = await GetAsync(tenantId, ct);
        var limit = cap switch
        {
            CapBranches => snapshot.Limits.MaxBranches,
            CapStaffSeats => snapshot.SeatAllowance,
            CapResources => snapshot.Limits.MaxResources,
            _ => null,
        };
        if (!PlanLimits.Exceeds(limit, current)) return null;

        var required = await CheapestPlanWithCapAsync(cap, current + 1, ct);
        var noun = cap switch
        {
            CapBranches => "branches",
            CapStaffSeats => "team members",
            _ => "resources",
        };

        return new PaywallInfo(
            Reason: "cap",
            Feature: null,
            Metric: cap,
            Used: current,
            Limit: limit,
            CurrentPlanCode: snapshot.PlanCode,
            RequiredPlanCode: required?.Code,
            RequiredPlanName: required?.Name,
            Message: required is null
                ? $"Your plan allows {limit} {noun}."
                : $"Your plan allows {limit} {noun}. {required.Name} raises that.",
            AddOnCode: cap == CapStaffSeats ? $"{PlatformCreditTypes.Seat}-1" : null);
    }

    public async Task<QuotaDecision> CheckQuotaAsync(Guid tenantId, string metric, int amount = 1, CancellationToken ct = default)
    {
        var snapshot = await GetAsync(tenantId, ct);
        var limit = metric switch
        {
            UsageMetrics.Bookings => snapshot.Limits.MaxBookingsPerMonth,
            UsageMetrics.AiRuns => snapshot.Limits.AiRunsPerMonth,
            UsageMetrics.Sms => snapshot.Limits.SmsPerMonth,
            _ => null,
        };
        if (limit is null) return QuotaDecision.Ok;

        var used = await UsedThisMonthAsync(tenantId, metric, ct);
        if (used + amount <= limit.Value) return QuotaDecision.Ok;

        // The allowance is spent. A bought pack covers the overflow - this
        // is the whole point of selling credits beside the plan.
        var creditType = CreditTypeFor(metric);
        if (creditType is not null && snapshot.Credit(creditType) >= amount)
            return QuotaDecision.Credits();

        var required = await CheapestPlanWithQuotaAsync(metric, used + amount, ct);
        var noun = metric switch
        {
            UsageMetrics.Bookings => "bookings",
            UsageMetrics.AiRuns => "AI copilot runs",
            _ => "messages",
        };

        return QuotaDecision.Deny(new PaywallInfo(
            Reason: "quota",
            Feature: null,
            Metric: metric,
            Used: used,
            Limit: limit,
            CurrentPlanCode: snapshot.PlanCode,
            RequiredPlanCode: required?.Code,
            RequiredPlanName: required?.Name,
            Message: limit.Value == 0
                ? $"Your plan does not include {noun}."
                : $"You have used all {limit.Value} {noun} in your plan this month.",
            AddOnCode: creditType is null ? null : DefaultPackFor(creditType)));
    }

    public async Task ConsumeAsync(Guid tenantId, string metric, QuotaDecision decision, int amount = 1, CancellationToken ct = default)
    {
        if (!decision.Allowed || amount <= 0) return;

        if (decision.FromCredits && CreditTypeFor(metric) is { } creditType)
        {
            await SpendCreditsAsync(tenantId, creditType, amount, metric, ct);
            return;
        }

        var period = UsageMetrics.PeriodKey(DateTime.UtcNow);
        var counter = await _db.PlatformUsageCounters
            .FirstOrDefaultAsync(c => c.TenantId == tenantId && c.Metric == metric && c.PeriodKey == period, ct);
        if (counter is null)
        {
            counter = new PlatformUsageCounter { TenantId = tenantId, Metric = metric, PeriodKey = period, Used = 0 };
            _db.PlatformUsageCounters.Add(counter);
        }
        counter.Used += amount;
        counter.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);
    }

    /// Draws `amount` out of the lots that expire soonest, and records one
    /// negative row for the audit trail. Returns what it could not cover.
    public async Task<int> SpendCreditsAsync(Guid tenantId, string creditType, int amount, string? detail, CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var lots = await _db.PlatformCreditEntries
            .Where(e => e.TenantId == tenantId && e.CreditType == creditType && e.Delta > 0 && e.Remaining > 0
                        && (e.ExpiresAt == null || e.ExpiresAt > now))
            // Soonest to lapse first, so nothing is wasted; a lot that never
            // lapses is drawn on last.
            .OrderBy(e => e.ExpiresAt ?? DateTime.MaxValue)
            .ThenBy(e => e.CreatedAt)
            .ToListAsync(ct);

        var outstanding = amount;
        foreach (var lot in lots)
        {
            if (outstanding <= 0) break;
            var take = Math.Min(lot.Remaining, outstanding);
            lot.Remaining -= take;
            lot.UpdatedAt = now;
            outstanding -= take;
        }

        var spent = amount - outstanding;
        if (spent > 0)
        {
            _db.PlatformCreditEntries.Add(new PlatformCreditEntry
            {
                TenantId = tenantId,
                CreditType = creditType,
                Delta = -spent,
                Remaining = 0,
                Reason = "spend",
                Detail = detail,
            });
        }

        if (_db.ChangeTracker.HasChanges())
        {
            await _db.SaveChangesAsync(ct);
            Invalidate(tenantId);
        }
        return outstanding;
    }

    public async Task<int> UsedThisMonthAsync(Guid tenantId, string metric, CancellationToken ct = default)
    {
        var period = UsageMetrics.PeriodKey(DateTime.UtcNow);
        return await _db.PlatformUsageCounters.AsNoTracking()
            .Where(c => c.TenantId == tenantId && c.Metric == metric && c.PeriodKey == period)
            .Select(c => c.Used)
            .FirstOrDefaultAsync(ct);
    }

    public static string? CreditTypeFor(string metric) => metric switch
    {
        UsageMetrics.AiRuns => PlatformCreditTypes.AiRun,
        UsageMetrics.Sms => PlatformCreditTypes.Sms,
        _ => null,
    };

    private static string? DefaultPackFor(string creditType) => creditType switch
    {
        PlatformCreditTypes.AiRun => "ai-run-500",
        PlatformCreditTypes.Sms => "sms-2000",
        PlatformCreditTypes.Spotlight => "spotlight-5",
        _ => null,
    };

    private sealed record PlanRef(string Code, string Name, int Tier, string LimitsJson);

    private async Task<List<PlanRef>> LadderAsync(CancellationToken ct) =>
        await _db.PlatformPlans.AsNoTracking()
            .Where(p => p.IsPublic && !p.IsRetired)
            .OrderBy(p => p.Tier)
            .Select(p => new PlanRef(p.Code, p.Name, p.Tier, p.LimitsJson))
            .ToListAsync(ct);

    private async Task<PlanRef?> CheapestPlanWithAsync(string feature, CancellationToken ct) =>
        (await LadderAsync(ct)).FirstOrDefault(p => PlanLimits.Parse(p.LimitsJson).Has(feature));

    private async Task<PlanRef?> CheapestPlanWithCapAsync(string cap, int needed, CancellationToken ct) =>
        (await LadderAsync(ct)).FirstOrDefault(p =>
        {
            var limits = PlanLimits.Parse(p.LimitsJson);
            var value = cap switch
            {
                CapBranches => limits.MaxBranches,
                CapStaffSeats => limits.MaxStaffSeats,
                CapResources => limits.MaxResources,
                _ => null,
            };
            return value is null || value.Value >= needed;
        });

    private async Task<PlanRef?> CheapestPlanWithQuotaAsync(string metric, int needed, CancellationToken ct) =>
        (await LadderAsync(ct)).FirstOrDefault(p =>
        {
            var limits = PlanLimits.Parse(p.LimitsJson);
            var value = metric switch
            {
                UsageMetrics.Bookings => limits.MaxBookingsPerMonth,
                UsageMetrics.AiRuns => limits.AiRunsPerMonth,
                UsageMetrics.Sms => limits.SmsPerMonth,
                _ => null,
            };
            return value is null || value.Value >= needed;
        });

    private static string Capitalise(string s) =>
        string.IsNullOrEmpty(s) ? s : char.ToUpperInvariant(s[0]) + s[1..];
}
