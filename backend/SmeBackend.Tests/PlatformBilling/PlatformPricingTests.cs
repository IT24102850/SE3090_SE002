using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services.PlatformBilling;
using Xunit;

namespace SmeBackend.Tests.PlatformBilling;

/// The price list is the product of a formula, not a spreadsheet somebody
/// retypes, so these are the tests that stop a rounding change quietly
/// turning "save 45%" into a lie on the pricing page.
public class PlatformPricingTests
{
    private static async Task<AppDbContext> SyncedCatalogueAsync()
    {
        var db = TestHelpers.NewInMemoryDb();
        await PlatformPlanCatalog.SyncAsync(db);
        await PlatformAddOnCatalog.SyncAsync(db);
        return db;
    }

    [Fact]
    public async Task Catalogue_has_the_four_rungs_in_order()
    {
        await using var db = await SyncedCatalogueAsync();

        var plans = await db.PlatformPlans.OrderBy(p => p.Tier).ToListAsync();

        Assert.Equal(
            new[] { PlatformPlanCodes.Starter, PlatformPlanCodes.Grow, PlatformPlanCodes.Pro, PlatformPlanCodes.Prime },
            plans.Select(p => p.Code));
        Assert.Equal(new[] { 0, 1, 2, 3 }, plans.Select(p => p.Tier));
    }

    [Fact]
    public async Task Exactly_one_plan_is_flagged_most_popular_and_it_is_the_one_with_the_trial()
    {
        await using var db = await SyncedCatalogueAsync();

        var featured = await db.PlatformPlans.Where(p => p.IsMostPopular).ToListAsync();

        var only = Assert.Single(featured);
        Assert.Equal(PlatformPlanCodes.Pro, only.Code);
        Assert.True(only.TrialDays > 0, "The rung the page pushes is the one worth trialling.");
    }

    [Fact]
    public async Task Free_plan_has_no_price_rows_at_all()
    {
        await using var db = await SyncedCatalogueAsync();

        var starter = await db.PlatformPlans.Include(p => p.Prices).FirstAsync(p => p.Code == PlatformPlanCodes.Starter);

        Assert.Empty(starter.Prices);
    }

    [Theory]
    [InlineData("LKR")]
    [InlineData("USD")]
    public async Task Every_paid_plan_is_sold_on_all_three_terms(string currency)
    {
        await using var db = await SyncedCatalogueAsync();

        var paid = await db.PlatformPlans.Include(p => p.Prices).Where(p => p.Tier > 0).ToListAsync();

        Assert.NotEmpty(paid);
        foreach (var plan in paid)
        {
            var terms = plan.Prices.Where(p => p.Currency == currency).Select(p => p.Period).OrderBy(p => p).ToList();
            Assert.Equal(BillingPeriods.All.OrderBy(p => p), terms);
        }
    }

    /// The headline claim on the term toggle. If charm rounding ever pushes a
    /// price far enough that the badge overstates the saving, this fails.
    [Theory]
    [InlineData("LKR")]
    [InlineData("USD")]
    public async Task Term_ladder_saves_30_then_45_percent(string currency)
    {
        await using var db = await SyncedCatalogueAsync();

        var paid = await db.PlatformPlans.Include(p => p.Prices).Where(p => p.Tier > 0).ToListAsync();

        foreach (var plan in paid)
        {
            var monthly = plan.Prices.Single(p => p.Currency == currency && p.Period == BillingPeriods.Monthly);
            var half = plan.Prices.Single(p => p.Currency == currency && p.Period == BillingPeriods.SemiAnnual);
            var annual = plan.Prices.Single(p => p.Currency == currency && p.Period == BillingPeriods.Annual);

            Assert.Equal(0, monthly.SavingsPercent);
            Assert.Equal(30, half.SavingsPercent);
            Assert.Equal(45, annual.SavingsPercent);
            Assert.True(annual.IsBestValue);

            // The badge must never claim more than the numbers deliver.
            var claimed = 1m - half.SavingsPercent / 100m;
            Assert.True(half.MonthlyEquivalent <= monthly.Amount * claimed + 0.01m,
                $"{plan.Code} {currency} 6-month price does not deliver its own badge.");
        }
    }

    [Fact]
    public async Task Longer_terms_always_cost_less_per_month()
    {
        await using var db = await SyncedCatalogueAsync();

        var paid = await db.PlatformPlans.Include(p => p.Prices).Where(p => p.Tier > 0).ToListAsync();

        foreach (var plan in paid)
        foreach (var currency in PlatformPlanCatalog.Currencies)
        {
            var ladder = plan.Prices
                .Where(p => p.Currency == currency)
                .OrderBy(p => BillingPeriods.Months(p.Period))
                .Select(p => p.MonthlyEquivalent)
                .ToList();

            Assert.Equal(ladder.OrderByDescending(x => x), ladder);
        }
    }

    [Fact]
    public async Task Higher_tiers_cost_more_on_the_same_term()
    {
        await using var db = await SyncedCatalogueAsync();

        var paid = await db.PlatformPlans.Include(p => p.Prices).Where(p => p.Tier > 0).OrderBy(p => p.Tier).ToListAsync();

        foreach (var period in BillingPeriods.All)
        {
            var ladder = paid.Select(p => p.Prices.Single(x => x.Currency == "LKR" && x.Period == period).Amount).ToList();
            Assert.Equal(ladder.OrderBy(x => x), ladder);
        }
    }

    /// A tier must never take something away from the one below it. The
    /// pricing page says "Everything in Grow", and this is what makes that
    /// sentence true rather than aspirational.
    [Fact]
    public async Task Each_tier_is_a_superset_of_the_one_below()
    {
        await using var db = await SyncedCatalogueAsync();

        var plans = await db.PlatformPlans.OrderBy(p => p.Tier).ToListAsync();

        for (var i = 1; i < plans.Count; i++)
        {
            var lower = PlanLimits.Parse(plans[i - 1].LimitsJson);
            var higher = PlanLimits.Parse(plans[i].LimitsJson);

            foreach (var feature in lower.Features)
                Assert.True(higher.Has(feature),
                    $"{plans[i].Code} drops '{feature}' that {plans[i - 1].Code} has.");

            AssertNotLower(lower.MaxBranches, higher.MaxBranches, plans[i].Code, nameof(PlanLimits.MaxBranches));
            AssertNotLower(lower.MaxStaffSeats, higher.MaxStaffSeats, plans[i].Code, nameof(PlanLimits.MaxStaffSeats));
            AssertNotLower(lower.MaxResources, higher.MaxResources, plans[i].Code, nameof(PlanLimits.MaxResources));
            AssertNotLower(lower.MaxBookingsPerMonth, higher.MaxBookingsPerMonth, plans[i].Code, nameof(PlanLimits.MaxBookingsPerMonth));
            AssertNotLower(lower.AiRunsPerMonth, higher.AiRunsPerMonth, plans[i].Code, nameof(PlanLimits.AiRunsPerMonth));
            AssertNotLower(lower.SmsPerMonth, higher.SmsPerMonth, plans[i].Code, nameof(PlanLimits.SmsPerMonth));
            Assert.True(higher.SpotlightsPerMonth >= lower.SpotlightsPerMonth);
        }
    }

    /// null is unlimited, so it can only ever be an improvement.
    private static void AssertNotLower(int? lower, int? higher, string code, string what)
    {
        if (higher is null) return;
        Assert.True(lower is not null && higher.Value >= lower.Value, $"{code} lowers {what}.");
    }

    [Fact]
    public async Task Syncing_twice_changes_nothing()
    {
        await using var db = await SyncedCatalogueAsync();
        var before = await db.PlatformPlanPrices.CountAsync();

        await PlatformPlanCatalog.SyncAsync(db);
        await PlatformAddOnCatalog.SyncAsync(db);

        Assert.Equal(before, await db.PlatformPlanPrices.CountAsync());
        Assert.Equal(4, await db.PlatformPlans.CountAsync());
    }

    // ── Add-ons ─────────────────────────────────────────────────────────

    [Fact]
    public async Task Bigger_pack_is_always_the_better_unit_price()
    {
        await using var db = await SyncedCatalogueAsync();

        var addOns = await db.PlatformAddOns.ToListAsync();
        var families = addOns.GroupBy(a => a.CreditType);

        Assert.NotEmpty(families);
        foreach (var family in families)
        {
            var byQuantity = family.OrderBy(a => a.Quantity).ToList();
            for (var i = 1; i < byQuantity.Count; i++)
            {
                var small = PlatformAddOnCatalog.ParsePrices(byQuantity[i - 1].PricesJson)["LKR"] / byQuantity[i - 1].Quantity;
                var large = PlatformAddOnCatalog.ParsePrices(byQuantity[i].PricesJson)["LKR"] / byQuantity[i].Quantity;
                Assert.True(large < small,
                    $"{byQuantity[i].Code} is not better value per unit than {byQuantity[i - 1].Code}.");
            }
        }
    }

    [Fact]
    public async Task Savings_badge_never_overstates_the_discount()
    {
        await using var db = await SyncedCatalogueAsync();

        var addOns = await db.PlatformAddOns.ToListAsync();

        foreach (var family in addOns.GroupBy(a => a.CreditType))
        {
            var single = family.OrderBy(a => a.Quantity).First();
            var unit = PlatformAddOnCatalog.ParsePrices(single.PricesJson)["LKR"] / single.Quantity;

            foreach (var pack in family)
            {
                var price = PlatformAddOnCatalog.ParsePrices(pack.PricesJson)["LKR"];
                var listPrice = unit * pack.Quantity;
                var realSaving = listPrice <= 0 ? 0m : (1 - price / listPrice) * 100m;
                Assert.True(pack.SavingsPercent <= realSaving + 0.5m,
                    $"{pack.Code} claims {pack.SavingsPercent}% but only delivers {realSaving:N1}%.");
            }
        }
    }

    /// The whole point of the free tier as a funnel: a business that cannot
    /// yet justify a subscription can still pay for visibility.
    [Fact]
    public async Task Spotlight_is_on_sale_to_free_tenants()
    {
        await using var db = await SyncedCatalogueAsync();

        var spotlights = await db.PlatformAddOns.Where(a => a.CreditType == PlatformCreditTypes.Spotlight).ToListAsync();

        Assert.NotEmpty(spotlights);
        Assert.All(spotlights, a => Assert.Equal(0, a.MinimumTier));
    }

    [Fact]
    public async Task Exactly_one_pack_per_family_is_flagged_best_value()
    {
        await using var db = await SyncedCatalogueAsync();

        var addOns = await db.PlatformAddOns.ToListAsync();

        foreach (var family in addOns.GroupBy(a => a.CreditType))
        {
            var best = family.Where(a => a.IsBestValue).ToList();
            Assert.True(best.Count == 1, $"{family.Key} flags {best.Count} packs as best value.");
            Assert.Equal(family.Max(a => a.Quantity), best[0].Quantity);
        }
    }

    // ── Charm rounding ──────────────────────────────────────────────────

    [Theory]
    [InlineData(19.99, "USD", 19.99)]
    [InlineData(83.958, "USD", 83.99)]
    [InlineData(131.934, "USD", 131.99)]
    [InlineData(0, "USD", 0)]
    public void Usd_prices_land_on_99(decimal raw, string currency, decimal expected)
    {
        Assert.Equal(expected, PlatformPlanCatalog.Charm(raw, currency));
    }

    [Theory]
    [InlineData(24780, 24900)]   // nudged onto x900
    [InlineData(5900, 5900)]     // already there
    [InlineData(2500, 2500)]     // x900 is too far, stays on the round hundred
    public void Lkr_prices_land_on_a_round_hundred(decimal raw, decimal expected)
    {
        Assert.Equal(expected, PlatformPlanCatalog.Charm(raw, "LKR"));
    }

    [Fact]
    public void Charm_never_returns_a_negative_or_zero_price_for_a_real_amount()
    {
        Assert.True(PlatformPlanCatalog.Charm(1m, "LKR") > 0);
        Assert.True(PlatformPlanCatalog.Charm(0.004m, "USD") > 0);
        Assert.Equal(0m, PlatformPlanCatalog.Charm(0m, "LKR"));
    }
}
