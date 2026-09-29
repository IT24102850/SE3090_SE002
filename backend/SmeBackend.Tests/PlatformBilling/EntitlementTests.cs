using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services.PlatformBilling;
using Xunit;

namespace SmeBackend.Tests.PlatformBilling;

/// The gate itself: what a plan lets a tenant do, what happens when the
/// allowance runs out, and what a lapsed subscription still grants.
public class EntitlementTests
{
    private readonly Guid _tenantId = Guid.NewGuid();

    private async Task<(AppDbContext Db, EntitlementService Entitlements)> NewAsync()
    {
        var db = TestHelpers.NewInMemoryDb(_tenantId);
        await PlatformPlanCatalog.SyncAsync(db);
        db.Tenants.Add(new Tenant { Id = _tenantId, Name = "Blue Whale Tours", BusinessType = "Tourism" });
        await db.SaveChangesAsync();

        var entitlements = new EntitlementService(db, new MemoryCache(new MemoryCacheOptions()),
            NullLogger<EntitlementService>.Instance);
        return (db, entitlements);
    }

    private async Task PutOnPlanAsync(AppDbContext db, EntitlementService entitlements, string planCode,
        string status = PlatformSubscriptionStatuses.Active, DateTime? periodEnd = null, DateTime? graceEnd = null)
    {
        var plan = db.PlatformPlans.First(p => p.Code == planCode);
        var subscription = await entitlements.EnsureSubscriptionAsync(_tenantId);
        subscription.PlanId = plan.Id;
        subscription.PlanCode = plan.Code;
        subscription.Tier = plan.Tier;
        subscription.Status = status;
        subscription.Amount = 14900m;
        subscription.CurrentPeriodEnd = periodEnd ?? DateTime.UtcNow.AddDays(20);
        subscription.GraceEndsAt = graceEnd;
        await db.SaveChangesAsync();
        entitlements.Invalidate(_tenantId);
    }

    // ── The free plan ───────────────────────────────────────────────────

    [Fact]
    public async Task A_tenant_with_no_subscription_row_gets_the_free_plan()
    {
        var (_, entitlements) = await NewAsync();

        var snapshot = await entitlements.GetAsync(_tenantId);

        Assert.Equal(PlatformPlanCodes.Starter, snapshot.PlanCode);
        Assert.Equal(0, snapshot.Tier);
        Assert.True(snapshot.HasAccess);
    }

    [Fact]
    public async Task The_free_plan_is_capped_but_not_crippled()
    {
        var (_, entitlements) = await NewAsync();

        var snapshot = await entitlements.GetAsync(_tenantId);

        // It runs a real business...
        Assert.True(snapshot.Has(PlanFeatures.PublicDirectory));
        Assert.True(snapshot.Limits.MaxBookingsPerMonth > 0);
        // ...and the caps are where growth hurts.
        Assert.Equal(1, snapshot.Limits.MaxBranches);
        Assert.False(snapshot.Has(PlanFeatures.AiAgents));
    }

    [Fact]
    public async Task Ensuring_a_subscription_twice_creates_only_one_row()
    {
        var (db, entitlements) = await NewAsync();

        var first = await entitlements.EnsureSubscriptionAsync(_tenantId);
        var second = await entitlements.EnsureSubscriptionAsync(_tenantId);

        Assert.Equal(first.Id, second.Id);
        Assert.Single(db.PlatformSubscriptions);
    }

    // ── Feature gates ───────────────────────────────────────────────────

    [Fact]
    public async Task A_free_tenant_asking_for_an_AI_feature_is_told_which_plan_has_it()
    {
        var (_, entitlements) = await NewAsync();

        var paywall = await entitlements.CheckFeatureAsync(_tenantId, PlanFeatures.AiAgents);

        Assert.NotNull(paywall);
        Assert.Equal("feature", paywall!.Reason);
        Assert.Equal(PlatformPlanCodes.Pro, paywall.RequiredPlanCode);
        Assert.Contains("Pro", paywall.Message);
    }

    [Fact]
    public async Task A_paid_tenant_passes_the_feature_gate()
    {
        var (db, entitlements) = await NewAsync();
        await PutOnPlanAsync(db, entitlements, PlatformPlanCodes.Pro);

        Assert.Null(await entitlements.CheckFeatureAsync(_tenantId, PlanFeatures.AiAgents));
    }

    [Fact]
    public async Task The_cheapest_plan_that_unblocks_a_feature_is_the_one_offered()
    {
        var (_, entitlements) = await NewAsync();

        var paywall = await entitlements.CheckFeatureAsync(_tenantId, PlanFeatures.PaymentGateways);

        // Grow has it, so a free tenant must not be pushed at Prime.
        Assert.Equal(PlatformPlanCodes.Grow, paywall!.RequiredPlanCode);
    }

    // ── Caps that count rows ────────────────────────────────────────────

    [Fact]
    public async Task Branch_cap_blocks_the_one_past_the_limit_and_not_the_one_before()
    {
        var (_, entitlements) = await NewAsync();

        Assert.Null(await entitlements.CheckCapAsync(_tenantId, EntitlementService.CapBranches, 0));

        var paywall = await entitlements.CheckCapAsync(_tenantId, EntitlementService.CapBranches, 1);
        Assert.NotNull(paywall);
        Assert.Equal("cap", paywall!.Reason);
        Assert.Equal(1, paywall.Limit);
    }

    [Fact]
    public async Task An_unlimited_cap_never_blocks()
    {
        var (db, entitlements) = await NewAsync();
        await PutOnPlanAsync(db, entitlements, PlatformPlanCodes.Prime);

        Assert.Null(await entitlements.CheckCapAsync(_tenantId, EntitlementService.CapBranches, 5000));
    }

    [Fact]
    public async Task Bought_seats_raise_the_seat_cap()
    {
        var (db, entitlements) = await NewAsync();
        var subscription = await entitlements.EnsureSubscriptionAsync(_tenantId);

        Assert.NotNull(await entitlements.CheckCapAsync(_tenantId, EntitlementService.CapStaffSeats, 2));

        subscription.ExtraSeats = 3;
        await db.SaveChangesAsync();
        entitlements.Invalidate(_tenantId);

        Assert.Null(await entitlements.CheckCapAsync(_tenantId, EntitlementService.CapStaffSeats, 2));
    }

    // ── Monthly meters ──────────────────────────────────────────────────

    [Fact]
    public async Task Bookings_are_allowed_up_to_the_cap_and_refused_after_it()
    {
        var (db, entitlements) = await NewAsync();
        var limit = (await entitlements.GetAsync(_tenantId)).Limits.MaxBookingsPerMonth!.Value;

        for (var i = 0; i < limit; i++)
        {
            var decision = await entitlements.CheckQuotaAsync(_tenantId, UsageMetrics.Bookings);
            Assert.True(decision.Allowed);
            await entitlements.ConsumeAsync(_tenantId, UsageMetrics.Bookings, decision);
            entitlements.Invalidate(_tenantId);
        }

        var refused = await entitlements.CheckQuotaAsync(_tenantId, UsageMetrics.Bookings);
        Assert.False(refused.Allowed);
        Assert.Equal("quota", refused.Paywall!.Reason);
        Assert.Equal(limit, refused.Paywall.Used);
    }

    [Fact]
    public async Task A_metric_the_plan_does_not_include_is_refused_immediately()
    {
        var (_, entitlements) = await NewAsync();

        var decision = await entitlements.CheckQuotaAsync(_tenantId, UsageMetrics.AiRuns);

        Assert.False(decision.Allowed);
        Assert.Contains("does not include", decision.Paywall!.Message);
    }

    [Fact]
    public async Task An_unlimited_metric_is_never_metered()
    {
        var (db, entitlements) = await NewAsync();
        await PutOnPlanAsync(db, entitlements, PlatformPlanCodes.Prime);

        var decision = await entitlements.CheckQuotaAsync(_tenantId, UsageMetrics.AiRuns, 10_000);

        Assert.True(decision.Allowed);
        Assert.False(decision.FromCredits);
    }

    /// The reason credits are sold beside the plan at all.
    [Fact]
    public async Task Bought_credits_cover_the_overflow_once_the_allowance_is_spent()
    {
        var (db, entitlements) = await NewAsync();
        await PutOnPlanAsync(db, entitlements, PlatformPlanCodes.Grow);
        var limit = (await entitlements.GetAsync(_tenantId)).Limits.AiRunsPerMonth!.Value;

        db.PlatformUsageCounters.Add(new PlatformUsageCounter
        {
            TenantId = _tenantId,
            Metric = UsageMetrics.AiRuns,
            PeriodKey = UsageMetrics.PeriodKey(DateTime.UtcNow),
            Used = limit,
        });
        db.PlatformCreditEntries.Add(new PlatformCreditEntry
        {
            TenantId = _tenantId,
            CreditType = PlatformCreditTypes.AiRun,
            Delta = 100,
            Remaining = 100,
            Reason = "purchase",
        });
        await db.SaveChangesAsync();
        entitlements.Invalidate(_tenantId);

        var decision = await entitlements.CheckQuotaAsync(_tenantId, UsageMetrics.AiRuns);

        Assert.True(decision.Allowed);
        Assert.True(decision.FromCredits);

        await entitlements.ConsumeAsync(_tenantId, UsageMetrics.AiRuns, decision);
        Assert.Equal(99, (await entitlements.GetAsync(_tenantId)).Credit(PlatformCreditTypes.AiRun));
    }

    [Fact]
    public async Task A_denied_decision_consumes_nothing()
    {
        var (_, entitlements) = await NewAsync();

        var decision = await entitlements.CheckQuotaAsync(_tenantId, UsageMetrics.AiRuns);
        await entitlements.ConsumeAsync(_tenantId, UsageMetrics.AiRuns, decision);

        Assert.Equal(0, await entitlements.UsedThisMonthAsync(_tenantId, UsageMetrics.AiRuns));
    }

    // ── Credit lots ─────────────────────────────────────────────────────

    /// The reason the ledger is lots rather than a running total: a spend
    /// must come out of the grant that lapses first, so a tenant never loses
    /// credits they paid for because a free monthly grant expired.
    [Fact]
    public async Task Spending_draws_down_the_lot_that_expires_soonest()
    {
        var (db, entitlements) = await NewAsync();
        var now = DateTime.UtcNow;

        db.PlatformCreditEntries.AddRange(
            new PlatformCreditEntry
            {
                TenantId = _tenantId, CreditType = PlatformCreditTypes.Spotlight,
                Delta = 5, Remaining = 5, Reason = "plan-grant", ExpiresAt = now.AddDays(10),
            },
            new PlatformCreditEntry
            {
                TenantId = _tenantId, CreditType = PlatformCreditTypes.Spotlight,
                Delta = 10, Remaining = 10, Reason = "purchase", ExpiresAt = now.AddDays(300),
            });
        await db.SaveChangesAsync();
        entitlements.Invalidate(_tenantId);

        Assert.Equal(15, (await entitlements.GetAsync(_tenantId)).Credit(PlatformCreditTypes.Spotlight));

        var unmet = await entitlements.SpendCreditsAsync(_tenantId, PlatformCreditTypes.Spotlight, 5, "test");

        Assert.Equal(0, unmet);
        var grant = db.PlatformCreditEntries.First(e => e.Reason == "plan-grant");
        var purchase = db.PlatformCreditEntries.First(e => e.Reason == "purchase");
        Assert.Equal(0, grant.Remaining);
        Assert.Equal(10, purchase.Remaining);
        Assert.Equal(10, (await entitlements.GetAsync(_tenantId)).Credit(PlatformCreditTypes.Spotlight));
    }

    [Fact]
    public async Task Expired_lots_stop_counting_but_live_ones_are_untouched()
    {
        var (db, entitlements) = await NewAsync();
        var now = DateTime.UtcNow;

        db.PlatformCreditEntries.AddRange(
            new PlatformCreditEntry
            {
                TenantId = _tenantId, CreditType = PlatformCreditTypes.Spotlight,
                Delta = 5, Remaining = 5, Reason = "plan-grant", ExpiresAt = now.AddDays(-1),
            },
            new PlatformCreditEntry
            {
                TenantId = _tenantId, CreditType = PlatformCreditTypes.Spotlight,
                Delta = 3, Remaining = 3, Reason = "purchase", ExpiresAt = now.AddDays(90),
            });
        await db.SaveChangesAsync();

        Assert.Equal(3, (await entitlements.GetAsync(_tenantId)).Credit(PlatformCreditTypes.Spotlight));
    }

    [Fact]
    public async Task Spending_more_than_the_balance_reports_what_it_could_not_cover()
    {
        var (db, entitlements) = await NewAsync();
        db.PlatformCreditEntries.Add(new PlatformCreditEntry
        {
            TenantId = _tenantId, CreditType = PlatformCreditTypes.Sms,
            Delta = 2, Remaining = 2, Reason = "purchase",
        });
        await db.SaveChangesAsync();

        var unmet = await entitlements.SpendCreditsAsync(_tenantId, PlatformCreditTypes.Sms, 5, "test");

        Assert.Equal(3, unmet);
        Assert.Equal(0, (await entitlements.GetAsync(_tenantId)).Credit(PlatformCreditTypes.Sms));
    }

    // ── Lapsing ─────────────────────────────────────────────────────────

    [Fact]
    public async Task A_past_due_tenant_keeps_everything_while_the_grace_window_is_open()
    {
        var (db, entitlements) = await NewAsync();
        await PutOnPlanAsync(db, entitlements, PlatformPlanCodes.Pro,
            status: PlatformSubscriptionStatuses.PastDue,
            periodEnd: DateTime.UtcNow.AddDays(-2),
            graceEnd: DateTime.UtcNow.AddDays(12));

        var snapshot = await entitlements.GetAsync(_tenantId);

        Assert.True(snapshot.HasAccess);
        Assert.True(snapshot.Has(PlanFeatures.AiAgents));
    }

    [Fact]
    public async Task Once_the_grace_window_closes_the_tenant_is_treated_as_free()
    {
        var (db, entitlements) = await NewAsync();
        await PutOnPlanAsync(db, entitlements, PlatformPlanCodes.Pro,
            status: PlatformSubscriptionStatuses.PastDue,
            periodEnd: DateTime.UtcNow.AddDays(-30),
            graceEnd: DateTime.UtcNow.AddDays(-1));

        var snapshot = await entitlements.GetAsync(_tenantId);

        Assert.False(snapshot.HasAccess);
        Assert.Equal(PlatformPlanCodes.Starter, snapshot.PlanCode);
        Assert.False(snapshot.Has(PlanFeatures.AiAgents));
        // The free plan is still a working product, which is the point.
        Assert.True(snapshot.Limits.MaxBookingsPerMonth > 0);
    }

    [Fact]
    public async Task A_cancelled_but_unexpired_term_keeps_its_features()
    {
        var (db, entitlements) = await NewAsync();
        await PutOnPlanAsync(db, entitlements, PlatformPlanCodes.Pro,
            status: PlatformSubscriptionStatuses.Cancelling,
            periodEnd: DateTime.UtcNow.AddDays(9));

        var snapshot = await entitlements.GetAsync(_tenantId);

        Assert.True(snapshot.HasAccess);
        Assert.True(snapshot.Has(PlanFeatures.AiAgents));
    }

    // ── Limits parsing ──────────────────────────────────────────────────

    [Fact]
    public void Unreadable_limits_fall_back_to_the_most_restrictive_shape()
    {
        var limits = PlanLimits.Parse("{ this is not json");

        Assert.Equal(1, limits.MaxBranches);
        Assert.Equal(1, limits.MaxStaffSeats);
        Assert.Empty(limits.Features);
    }

    [Fact]
    public void Null_cap_is_unlimited_and_zero_cap_is_none()
    {
        Assert.False(PlanLimits.Exceeds(null, int.MaxValue));
        Assert.True(PlanLimits.Exceeds(0, 0));
        Assert.False(PlanLimits.Exceeds(5, 4));
        Assert.True(PlanLimits.Exceeds(5, 5));
    }

    [Fact]
    public void Limits_round_trip_through_json()
    {
        var limits = new PlanLimits
        {
            MaxBranches = 3,
            MaxStaffSeats = null,
            AiRunsPerMonth = 0,
            SpotlightsPerMonth = 4,
            Features = new[] { PlanFeatures.AiAgents },
        };

        var round = PlanLimits.Parse(limits.ToJson());

        Assert.Equal(3, round.MaxBranches);
        Assert.Null(round.MaxStaffSeats);
        Assert.Equal(0, round.AiRunsPerMonth);
        Assert.Equal(4, round.SpotlightsPerMonth);
        Assert.True(round.Has(PlanFeatures.AiAgents));
    }
}
