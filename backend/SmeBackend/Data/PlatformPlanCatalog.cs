using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;
using SmeBackend.Services.PlatformBilling;

namespace SmeBackend.Data;

/// Unify's own price list, in code.
///
/// The shape is lifted from Tinder's, because it is the best-documented
/// consumer subscription funnel there is and every piece of it has a
/// business reason that survives the translation to SME software:
///
///   Free tier that actually works. Tinder's free tier swipes, matches and
///     chats - it is capped, not crippled, because a dating app with no free
///     users has nothing to sell. Starter runs a real business: bookings,
///     invoices, one branch, a public listing. It is capped where the cap
///     starts to hurt a business that is growing, which is exactly when they
///     are most willing to pay.
///
///   Three paid rungs, not two. Plus / Gold / Platinum. The top rung's job
///     is largely to make the middle one look reasonable, and the middle one
///     is the one flagged "most popular" and the one the trial is on. Ours
///     are Grow / Pro / Prime, and Pro is the target.
///
///   The middle rung sells information, not volume. Tinder Gold's hook is
///     "See Who Likes You" - something you cannot get by being patient on
///     the free tier. Pro's hook is the same trick: the AI copilots and the
///     demand analytics tell an owner something they cannot work out by
///     waiting, which is why they sit above the "unlimited" rung rather
///     than inside it.
///
///   A steep term ladder. 1 / 6 / 12 months, with the monthly price as the
///     anchor that makes the annual one read as a saving. Tinder's discounts
///     run past 60%; a B2B renewal cannot bear that, so ours are 30% and
///     45% - steep enough to move people onto a year, survivable at scale.
///
///   Consumables beside the subscription. Boosts and Super Likes, sold in
///     packs where the bigger pack is always the better unit price, and sold
///     to free users too. Ours are Spotlight (24 hours at the top of the
///     directory), AI credits and message credits - see PlatformAddOnCatalog.
///
/// Rows are matched on Code and updated in place, so a price change is a
/// commit rather than a migration. A plan the catalogue stops naming is
/// retired, never deleted: a tenant sitting on last year's price keeps
/// paying it until they choose to move.
public static class PlatformPlanCatalog
{
    public const string DefaultCurrency = "LKR";
    public static readonly string[] Currencies = { "LKR", "USD" };

    /// The term ladder, as a discount off the monthly price of the same plan.
    private static readonly (string Period, decimal Discount, bool BestValue)[] Terms =
    {
        (BillingPeriods.Monthly, 0m, false),
        (BillingPeriods.SemiAnnual, 0.30m, false),
        (BillingPeriods.Annual, 0.45m, true),
    };

    private sealed record PlanSpec(
        string Code,
        string Name,
        int Tier,
        string Tagline,
        string[] Highlights,
        PlanLimits Limits,
        decimal MonthlyLkr,
        decimal MonthlyUsd,
        bool MostPopular = false,
        int TrialDays = 0);

    private static readonly PlanSpec[] Specs =
    {
        new(
            PlatformPlanCodes.Starter, "Starter", 0,
            "Run your business on Unify, free forever.",
            new[]
            {
                "1 branch, 2 team members",
                "60 bookings a month",
                "Invoices, receipts and email reminders",
                "Your listing in the Unify directory",
                "Community support",
            },
            new PlanLimits
            {
                MaxBranches = 1,
                MaxStaffSeats = 2,
                MaxResources = 5,
                MaxBookingsPerMonth = 60,
                AiRunsPerMonth = 0,
                SmsPerMonth = 0,
                SpotlightsPerMonth = 0,
                Features = new[] { PlanFeatures.PublicDirectory },
            },
            0m, 0m),

        new(
            PlatformPlanCodes.Grow, "Grow", 1,
            "For a business that has outgrown the free caps.",
            new[]
            {
                "Unlimited bookings",
                "2 branches, 10 team members",
                "Take card payments from your own customers",
                "SMS and WhatsApp reminders",
                "Booking widget for your own website",
                "Your own invoice branding and custom forms",
                "1 Spotlight a month",
            },
            new PlanLimits
            {
                MaxBranches = 2,
                MaxStaffSeats = 10,
                MaxResources = 30,
                MaxBookingsPerMonth = null,
                AiRunsPerMonth = 50,
                SmsPerMonth = 250,
                SpotlightsPerMonth = 1,
                SupportResponseHours = 48,
                Features = new[]
                {
                    PlanFeatures.PublicDirectory,
                    PlanFeatures.EmbedWidget,
                    PlanFeatures.PaymentGateways,
                    PlanFeatures.SmsReminders,
                    PlanFeatures.CustomBranding,
                    PlanFeatures.MultiBranch,
                },
            },
            5900m, 19.99m),

        new(
            PlatformPlanCodes.Pro, "Pro", 2,
            "See what your business cannot see on its own.",
            new[]
            {
                "Everything in Grow",
                "The AI copilots: scheduling, billing and StockSense",
                "Demand analytics, forecasts and exports",
                "Purchase orders, suppliers and stock intelligence",
                "Insurance claims, commissions and payment schedules",
                "10 branches, 40 team members",
                "5 Spotlights a month",
                "24-hour support",
            },
            new PlanLimits
            {
                MaxBranches = 10,
                MaxStaffSeats = 40,
                MaxResources = 200,
                MaxBookingsPerMonth = null,
                AiRunsPerMonth = 1000,
                SmsPerMonth = 2000,
                SpotlightsPerMonth = 5,
                SupportResponseHours = 24,
                Features = new[]
                {
                    PlanFeatures.PublicDirectory,
                    PlanFeatures.EmbedWidget,
                    PlanFeatures.PaymentGateways,
                    PlanFeatures.SmsReminders,
                    PlanFeatures.CustomBranding,
                    PlanFeatures.MultiBranch,
                    PlanFeatures.AiAgents,
                    PlanFeatures.InventoryPro,
                    PlanFeatures.AdvancedAnalytics,
                    PlanFeatures.AdvancedBilling,
                },
            },
            14900m, 49.99m, MostPopular: true, TrialDays: 14),

        new(
            PlatformPlanCodes.Prime, "Prime", 3,
            "For groups, chains, and anyone building on top of us.",
            new[]
            {
                "Everything in Pro, without the ceilings",
                "Unlimited branches, team members and AI runs",
                "API access and outbound webhooks",
                "20 Spotlights a month",
                "Named account manager, 4-hour response",
                "Onboarding and data migration",
            },
            new PlanLimits
            {
                MaxBranches = null,
                MaxStaffSeats = null,
                MaxResources = null,
                MaxBookingsPerMonth = null,
                AiRunsPerMonth = null,
                SmsPerMonth = 10000,
                SpotlightsPerMonth = 20,
                SupportResponseHours = 4,
                Features = PlanFeatures.All,
            },
            34900m, 119.99m),
    };

    public static async Task SyncAsync(AppDbContext db, ILogger? logger = null, CancellationToken ct = default)
    {
        var plans = await db.PlatformPlans.Include(p => p.Prices).ToListAsync(ct);
        var codes = Specs.Select(s => s.Code).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var now = DateTime.UtcNow;

        foreach (var spec in Specs)
        {
            var plan = plans.FirstOrDefault(p => string.Equals(p.Code, spec.Code, StringComparison.OrdinalIgnoreCase));
            if (plan is null)
            {
                plan = new PlatformPlan { Code = spec.Code };
                db.PlatformPlans.Add(plan);
                plans.Add(plan);
            }

            plan.Name = spec.Name;
            plan.Tier = spec.Tier;
            plan.Tagline = spec.Tagline;
            plan.HighlightsJson = JsonSerializer.Serialize(spec.Highlights);
            plan.LimitsJson = spec.Limits.ToJson();
            plan.IsMostPopular = spec.MostPopular;
            plan.TrialDays = spec.TrialDays;
            plan.IsPublic = true;
            plan.IsRetired = false;
            plan.UpdatedAt = now;

            if (spec.Tier == 0) continue; // free: no price rows at all

            foreach (var currency in Currencies)
            {
                var monthly = currency == "USD" ? spec.MonthlyUsd : spec.MonthlyLkr;
                foreach (var (period, discount, bestValue) in Terms)
                {
                    var months = BillingPeriods.Months(period);
                    var amount = Charm(monthly * months * (1 - discount), currency);
                    var perMonth = Math.Round(amount / months, 2, MidpointRounding.AwayFromZero);
                    var savings = monthly <= 0 ? 0 : (int)Math.Round((1 - perMonth / monthly) * 100, MidpointRounding.AwayFromZero);

                    var price = plan.Prices.FirstOrDefault(p => p.Currency == currency && p.Period == period);
                    if (price is null)
                    {
                        price = new PlatformPlanPrice { Currency = currency, Period = period, Plan = plan };
                        plan.Prices.Add(price);
                    }

                    price.Amount = amount;
                    price.MonthlyEquivalent = perMonth;
                    price.SavingsPercent = Math.Max(0, savings);
                    price.IsBestValue = bestValue;
                    price.IsActive = true;
                    price.UpdatedAt = now;
                }
            }
        }

        // Anything the catalogue no longer names stops being sold, but the
        // row stays so the subscriptions pointing at it still resolve.
        foreach (var orphan in plans.Where(p => !codes.Contains(p.Code) && !p.IsRetired))
        {
            orphan.IsRetired = true;
            orphan.IsPublic = false;
            orphan.UpdatedAt = now;
            foreach (var price in orphan.Prices) price.IsActive = false;
        }

        if (db.ChangeTracker.HasChanges())
        {
            await db.SaveChangesAsync(ct);
            logger?.LogInformation("Platform plan catalogue synced.");
        }
    }

    /// Prices that read as prices. LKR lands on a round hundred, nudged onto
    /// a x900 ending when that is within 5% of the computed figure; USD
    /// lands on .99, the way Tinder quotes every one of its own.
    public static decimal Charm(decimal raw, string currency)
    {
        if (raw <= 0) return 0m;
        if (string.Equals(currency, "USD", StringComparison.OrdinalIgnoreCase))
            return Math.Ceiling(raw) - 0.01m;

        var hundreds = Math.Round(raw / 100m, 0, MidpointRounding.AwayFromZero) * 100m;
        if (hundreds <= 0) return 100m;
        var candidate = Math.Floor(hundreds / 1000m) * 1000m + 900m;
        return Math.Abs(candidate - hundreds) <= hundreds * 0.05m ? candidate : hundreds;
    }
}
