using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services.PlatformBilling;
using Xunit;

namespace SmeBackend.Tests.PlatformBilling;

/// Subscribing, trialling, upgrading, cancelling and lapsing - the state
/// machine a tenant admin actually walks through.
public class SubscriptionLifecycleTests
{
    private readonly Guid _tenantId = Guid.NewGuid();

    private sealed record Rig(AppDbContext Db, EntitlementService Entitlements, PlatformSubscriptionService Subscriptions);

    private async Task<Rig> NewAsync()
    {
        var db = TestHelpers.NewInMemoryDb(_tenantId);
        await PlatformPlanCatalog.SyncAsync(db);
        await PlatformAddOnCatalog.SyncAsync(db);
        db.Tenants.Add(new Tenant { Id = _tenantId, Name = "Blue Whale Tours", BusinessType = "Tourism" });
        await db.SaveChangesAsync();

        var entitlements = new EntitlementService(db, new MemoryCache(new MemoryCacheOptions()),
            NullLogger<EntitlementService>.Instance);
        var gateways = new PlatformGatewayProvider(new ConfigurationBuilder().Build());
        var subscriptions = new PlatformSubscriptionService(db, entitlements, gateways,
            NullLogger<PlatformSubscriptionService>.Instance);

        return new Rig(db, entitlements, subscriptions);
    }

    // ── Catalogue ───────────────────────────────────────────────────────

    [Fact]
    public async Task The_catalogue_prices_the_anchor_against_the_monthly_rate()
    {
        var rig = await NewAsync();

        var catalog = await rig.Subscriptions.GetCatalogAsync(_tenantId, "LKR");

        var pro = catalog.Plans.Single(p => p.Code == PlatformPlanCodes.Pro);
        var monthly = pro.Prices.Single(p => p.Period == BillingPeriods.Monthly);
        var annual = pro.Prices.Single(p => p.Period == BillingPeriods.Annual);

        Assert.Equal(monthly.Amount * 12, annual.ComparedAtAmount);
        Assert.True(annual.Amount < annual.ComparedAtAmount);
    }

    [Fact]
    public async Task An_unknown_currency_falls_back_rather_than_returning_nothing()
    {
        var rig = await NewAsync();

        var catalog = await rig.Subscriptions.GetCatalogAsync(_tenantId, "XYZ");

        Assert.Equal(PlatformPlanCatalog.DefaultCurrency, catalog.Currency);
        Assert.All(catalog.Plans.Where(p => p.Tier > 0), p => Assert.NotEmpty(p.Prices));
    }

    // ── Quoting ─────────────────────────────────────────────────────────

    [Fact]
    public async Task A_quote_prices_the_term_and_names_the_renewal()
    {
        var rig = await NewAsync();

        var quote = await rig.Subscriptions.QuoteAsync(_tenantId, new SubscriptionQuoteRequest
        {
            PlanCode = PlatformPlanCodes.Pro,
            Period = BillingPeriods.Annual,
            Currency = "LKR",
        });

        Assert.True(quote.Success);
        Assert.Equal(quote.Value!.ListAmount, quote.Value.RenewalAmount);
        Assert.Equal(quote.Value.ListAmount, quote.Value.Total);
        Assert.Equal(quote.Value.PeriodStart.AddMonths(12).Date, quote.Value.PeriodEnd.Date);
    }

    [Fact]
    public async Task Starter_cannot_be_bought()
    {
        var rig = await NewAsync();

        var quote = await rig.Subscriptions.QuoteAsync(_tenantId, new SubscriptionQuoteRequest
        {
            PlanCode = PlatformPlanCodes.Starter,
        });

        Assert.False(quote.Success);
        Assert.Contains("Cancel", quote.Error);
    }

    [Fact]
    public async Task Quoting_the_plan_and_term_you_are_already_on_is_refused()
    {
        var rig = await NewAsync();
        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Pro, BillingPeriods.Annual, "LKR",
            98900m, null, null, null);

        var quote = await rig.Subscriptions.QuoteAsync(_tenantId, new SubscriptionQuoteRequest
        {
            PlanCode = PlatformPlanCodes.Pro,
            Period = BillingPeriods.Annual,
            Currency = "LKR",
        });

        Assert.False(quote.Success);
        Assert.Contains("already", quote.Error);
    }

    /// Nobody pays twice for the same days.
    [Fact]
    public async Task Upgrading_mid_term_credits_the_time_already_paid_for()
    {
        var rig = await NewAsync();
        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Grow, BillingPeriods.Monthly, "LKR",
            5900m, null, null, null);

        var quote = await rig.Subscriptions.QuoteAsync(_tenantId, new SubscriptionQuoteRequest
        {
            PlanCode = PlatformPlanCodes.Pro,
            Period = BillingPeriods.Monthly,
            Currency = "LKR",
        });

        Assert.True(quote.Success);
        Assert.True(quote.Value!.ProrationCredit > 0, "An unused term must be credited.");
        Assert.Equal(quote.Value.ListAmount - quote.Value.ProrationCredit, quote.Value.Total);
    }

    [Fact]
    public void Proration_never_goes_negative_or_past_the_amount_paid()
    {
        var now = DateTime.UtcNow;
        var subscription = new PlatformSubscription
        {
            Amount = 1200m,
            Status = PlatformSubscriptionStatuses.Active,
            CurrentPeriodStart = now.AddDays(-15),
            CurrentPeriodEnd = now.AddDays(15),
        };

        var credit = PlatformSubscriptionService.Proration(subscription, now);

        Assert.InRange(credit, 590m, 610m);

        subscription.CurrentPeriodEnd = now.AddDays(-1);
        Assert.Equal(0m, PlatformSubscriptionService.Proration(subscription, now));

        Assert.Equal(0m, PlatformSubscriptionService.Proration(new PlatformSubscription { Amount = 0m }, now));
    }

    // ── Trials ──────────────────────────────────────────────────────────

    [Fact]
    public async Task A_trial_switches_everything_on_without_taking_a_card()
    {
        var rig = await NewAsync();

        var result = await rig.Subscriptions.StartTrialAsync(_tenantId, PlatformPlanCodes.Pro, null);

        Assert.True(result.Success);
        Assert.Equal(PlatformSubscriptionStatuses.Trialing, result.Value!.Status);
        Assert.Equal(0m, result.Value.Amount);
        Assert.False(result.Value.AutoRenew);
        Assert.NotNull(result.Value.TrialEndsAt);

        var snapshot = await rig.Entitlements.GetAsync(_tenantId);
        Assert.True(snapshot.Has(PlanFeatures.AiAgents));
    }

    [Fact]
    public async Task A_business_only_ever_gets_one_trial()
    {
        var rig = await NewAsync();
        await rig.Subscriptions.StartTrialAsync(_tenantId, PlatformPlanCodes.Pro, null);
        await rig.Subscriptions.CancelAsync(_tenantId, new CancelPlatformSubscriptionRequest { Immediate = true }, null);

        var second = await rig.Subscriptions.StartTrialAsync(_tenantId, PlatformPlanCodes.Pro, null);

        Assert.False(second.Success);
        Assert.Contains("already used", second.Error);
    }

    [Fact]
    public async Task A_plan_with_no_trial_cannot_be_trialled()
    {
        var rig = await NewAsync();

        var result = await rig.Subscriptions.StartTrialAsync(_tenantId, PlatformPlanCodes.Prime, null);

        Assert.False(result.Success);
    }

    [Fact]
    public async Task Converting_a_trial_is_recorded_as_a_conversion()
    {
        var rig = await NewAsync();
        await rig.Subscriptions.StartTrialAsync(_tenantId, PlatformPlanCodes.Pro, null);

        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Pro, BillingPeriods.Annual, "LKR",
            98900m, null, null, null);

        Assert.True(await rig.Db.PlatformSubscriptionEvents.AnyAsync(e => e.EventType == "trial.convert"));
    }

    // ── Activation ──────────────────────────────────────────────────────

    [Fact]
    public async Task Activation_sets_the_term_and_grants_the_plans_spotlights()
    {
        var rig = await NewAsync();

        var result = await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Pro, BillingPeriods.SemiAnnual,
            "LKR", 62900m, null, null, "owner@unify.lk");

        Assert.Equal(PlatformSubscriptionStatuses.Active, result.Status);
        Assert.True(result.AutoRenew);
        Assert.NotNull(result.CurrentPeriodEnd);
        Assert.Equal(result.CurrentPeriodStart.AddMonths(6).Date, result.CurrentPeriodEnd!.Value.Date);

        var spotlights = (await rig.Entitlements.GetAsync(_tenantId)).Credit(PlatformCreditTypes.Spotlight);
        Assert.Equal(5, spotlights);
    }

    /// A first-term offer must not become a permanent price by accident.
    [Fact]
    public async Task The_renewal_is_the_list_price_not_what_a_discount_brought_it_to()
    {
        var rig = await NewAsync();
        var listPrice = rig.Db.PlatformPlanPrices
            .Include(p => p.Plan)
            .First(p => p.Plan.Code == PlatformPlanCodes.Pro && p.Currency == "LKR" && p.Period == BillingPeriods.Annual)
            .Amount;

        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Pro, BillingPeriods.Annual, "LKR",
            listPrice / 2, "FIRST50", null, null);

        var subscription = await rig.Db.PlatformSubscriptions.FirstAsync();
        Assert.Equal(listPrice, subscription.Amount);
        Assert.Equal("FIRST50", subscription.PromotionCode);
    }

    [Fact]
    public async Task An_upgrade_and_a_downgrade_are_recorded_as_different_events()
    {
        var rig = await NewAsync();

        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Grow, BillingPeriods.Monthly, "LKR", 5900m, null, null, null);
        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Prime, BillingPeriods.Monthly, "LKR", 34900m, null, null, null);
        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Grow, BillingPeriods.Monthly, "LKR", 5900m, null, null, null);

        var events = await rig.Db.PlatformSubscriptionEvents.OrderBy(e => e.CreatedAt).Select(e => e.EventType).ToListAsync();

        Assert.Contains("subscribe", events);
        Assert.Contains("upgrade", events);
        Assert.Contains("downgrade", events);
    }

    // ── Cancelling ──────────────────────────────────────────────────────

    [Fact]
    public async Task Cancelling_a_paid_term_keeps_every_day_that_was_bought()
    {
        var rig = await NewAsync();
        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Pro, BillingPeriods.Annual, "LKR", 98900m, null, null, null);

        var result = await rig.Subscriptions.CancelAsync(_tenantId,
            new CancelPlatformSubscriptionRequest { Reason = "Seasonal business" }, null);

        Assert.True(result.Success);
        Assert.True(result.Value!.CancelAtPeriodEnd);
        Assert.Equal(PlatformSubscriptionStatuses.Cancelling, result.Value.Status);
        Assert.Equal(PlatformPlanCodes.Pro, result.Value.PlanCode);
        Assert.True((await rig.Entitlements.GetAsync(_tenantId)).Has(PlanFeatures.AiAgents));
    }

    /// Immediate cancellation is only for a trial, where no money moved.
    [Fact]
    public async Task Immediate_is_ignored_on_a_paid_term()
    {
        var rig = await NewAsync();
        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Pro, BillingPeriods.Annual, "LKR", 98900m, null, null, null);

        var result = await rig.Subscriptions.CancelAsync(_tenantId,
            new CancelPlatformSubscriptionRequest { Immediate = true }, null);

        Assert.True(result.Value!.CancelAtPeriodEnd);
        Assert.NotEqual(PlatformPlanCodes.Starter, result.Value.PlanCode);
    }

    [Fact]
    public async Task Cancelling_the_free_plan_is_refused()
    {
        var rig = await NewAsync();

        var result = await rig.Subscriptions.CancelAsync(_tenantId, new CancelPlatformSubscriptionRequest(), null);

        Assert.False(result.Success);
    }

    [Fact]
    public async Task Resuming_puts_the_subscription_back_on_renewal()
    {
        var rig = await NewAsync();
        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Pro, BillingPeriods.Annual, "LKR", 98900m, null, null, null);
        await rig.Subscriptions.CancelAsync(_tenantId, new CancelPlatformSubscriptionRequest(), null);

        var result = await rig.Subscriptions.ResumeAsync(_tenantId, null);

        Assert.True(result.Success);
        Assert.False(result.Value!.CancelAtPeriodEnd);
        Assert.True(result.Value.AutoRenew);
        Assert.Equal(PlatformSubscriptionStatuses.Active, result.Value.Status);
    }

    [Fact]
    public async Task Resuming_something_that_is_not_ending_is_refused()
    {
        var rig = await NewAsync();
        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Pro, BillingPeriods.Annual, "LKR", 98900m, null, null, null);

        var result = await rig.Subscriptions.ResumeAsync(_tenantId, null);

        Assert.False(result.Success);
    }

    /// Nothing is deleted when a business stops paying - the cheapest
    /// customer to win back is the one who never lost anything.
    [Fact]
    public async Task Dropping_to_starter_keeps_the_tenant_and_clears_only_paid_extras()
    {
        var rig = await NewAsync();
        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Pro, BillingPeriods.Annual, "LKR", 98900m, null, null, null);
        var subscription = await rig.Db.PlatformSubscriptions.FirstAsync();
        subscription.ExtraSeats = 4;
        await rig.Db.SaveChangesAsync();

        await rig.Subscriptions.DropToStarterAsync(subscription, "expire", null, default);

        Assert.Equal(PlatformPlanCodes.Starter, subscription.PlanCode);
        Assert.Equal(PlatformSubscriptionStatuses.Expired, subscription.Status);
        Assert.Equal(0, subscription.ExtraSeats);
        Assert.Null(subscription.CurrentPeriodEnd);
        Assert.True(await rig.Db.Tenants.AnyAsync(t => t.Id == _tenantId));
    }

    // ── Add-ons ─────────────────────────────────────────────────────────

    [Fact]
    public async Task Buying_a_credit_pack_adds_a_lot_to_the_ledger()
    {
        var rig = await NewAsync();
        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Grow, BillingPeriods.Monthly, "LKR", 5900m, null, null, null);
        var pack = await rig.Db.PlatformAddOns.FirstAsync(a => a.Code == "ai-run-500");

        await rig.Subscriptions.GrantAddOnAsync(_tenantId, pack, 1, null);

        Assert.Equal(500, (await rig.Entitlements.GetAsync(_tenantId)).Credit(PlatformCreditTypes.AiRun));
    }

    [Fact]
    public async Task Buying_a_seat_raises_the_seat_allowance_rather_than_granting_a_credit()
    {
        var rig = await NewAsync();
        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Grow, BillingPeriods.Monthly, "LKR", 5900m, null, null, null);
        var seat = await rig.Db.PlatformAddOns.FirstAsync(a => a.Code == "seat-1");

        await rig.Subscriptions.GrantAddOnAsync(_tenantId, seat, 2, null);

        var snapshot = await rig.Entitlements.GetAsync(_tenantId);
        Assert.Equal(2, snapshot.ExtraSeats);
        Assert.Equal(0, snapshot.Credit(PlatformCreditTypes.Seat));
        Assert.Equal(12, snapshot.SeatAllowance);
    }

    // ── Offers ──────────────────────────────────────────────────────────

    [Fact]
    public async Task An_intro_offer_applies_to_a_business_that_has_never_paid()
    {
        var rig = await NewAsync();
        await PlatformPromotionSeeder.SeedAsync(rig.Db);

        var quote = await rig.Subscriptions.QuoteAsync(_tenantId, new SubscriptionQuoteRequest
        {
            PlanCode = PlatformPlanCodes.Pro,
            Period = BillingPeriods.Annual,
            Currency = "LKR",
        });

        Assert.True(quote.Success);
        Assert.Equal("FIRST50", quote.Value!.PromotionCode);
        Assert.Equal(quote.Value.ListAmount / 2, quote.Value.Discount);
        Assert.Equal(quote.Value.ListAmount, quote.Value.RenewalAmount);
    }

    [Fact]
    public async Task An_intro_offer_stops_applying_once_the_business_has_paid()
    {
        var rig = await NewAsync();
        await PlatformPromotionSeeder.SeedAsync(rig.Db);
        await rig.Subscriptions.ActivateAsync(_tenantId, PlatformPlanCodes.Grow, BillingPeriods.Monthly, "LKR", 5900m, null, null, null);

        var quote = await rig.Subscriptions.QuoteAsync(_tenantId, new SubscriptionQuoteRequest
        {
            PlanCode = PlatformPlanCodes.Pro,
            Period = BillingPeriods.Annual,
            Currency = "LKR",
        });

        Assert.NotEqual("FIRST50", quote.Value!.PromotionCode);
    }

    [Fact]
    public async Task A_code_restricted_to_a_term_is_refused_on_another()
    {
        var rig = await NewAsync();
        await PlatformPromotionSeeder.SeedAsync(rig.Db);

        var listPrice = rig.Db.PlatformPlanPrices
            .Include(p => p.Plan)
            .First(p => p.Plan.Code == PlatformPlanCodes.Pro && p.Currency == "LKR" && p.Period == BillingPeriods.Annual)
            .Amount;

        var monthly = await rig.Subscriptions.ResolvePromotionAsync(
            _tenantId, "ANNUAL20", PlatformPlanCodes.Pro, BillingPeriods.Monthly, "LKR", 14900m);
        var annual = await rig.Subscriptions.ResolvePromotionAsync(
            _tenantId, "ANNUAL20", PlatformPlanCodes.Pro, BillingPeriods.Annual, "LKR", listPrice);

        Assert.Null(monthly);
        Assert.NotNull(annual);
        Assert.Equal(Math.Round(listPrice * 0.20m, 2), annual!.Value.Discount);
    }

    [Fact]
    public async Task An_unknown_code_is_simply_not_applied()
    {
        var rig = await NewAsync();
        await PlatformPromotionSeeder.SeedAsync(rig.Db);

        var result = await rig.Subscriptions.ResolvePromotionAsync(
            _tenantId, "NOPE", PlatformPlanCodes.Pro, BillingPeriods.Annual, "LKR", 98900m);

        Assert.Null(result);
    }

    [Fact]
    public async Task A_discount_can_never_exceed_the_price()
    {
        var rig = await NewAsync();
        rig.Db.PlatformPromotions.Add(new PlatformPromotion
        {
            Code = "TOOMUCH",
            Name = "Absurd",
            Kind = PromotionKinds.Campaign,
            AmountOff = 999_999m,
            AmountCurrency = "LKR",
            IsActive = true,
        });
        await rig.Db.SaveChangesAsync();

        var result = await rig.Subscriptions.ResolvePromotionAsync(
            _tenantId, "TOOMUCH", PlatformPlanCodes.Pro, BillingPeriods.Annual, "LKR", 98900m);

        Assert.Equal(98900m, result!.Value.Discount);
    }
}
