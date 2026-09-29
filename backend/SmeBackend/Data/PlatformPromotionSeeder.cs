using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;

namespace SmeBackend.Data;

/// The three offers that run permanently, seeded once and then owned by
/// whoever edits the table.
///
/// These are the behavioural half of the Tinder playbook, minus the part
/// that got Tinder sued. An intro price for a business that has never paid,
/// a win-back for one that has lapsed, and a loyalty code for an
/// anniversary: all three are earned by something the tenant did. What is
/// deliberately absent is a price that varies by who the buyer is - Tinder's
/// age-tiered pricing produced a California class action and an ACCC finding
/// in Australia, and nothing in this system takes a demographic input.
///
/// Existing rows are left exactly as they are: this is a seed, not a sync,
/// because the owner is expected to turn these on and off and change the
/// percentages from the console without a deploy undoing it.
public static class PlatformPromotionSeeder
{
    public static async Task SeedAsync(AppDbContext db, ILogger? logger = null, CancellationToken ct = default)
    {
        var seeds = new[]
        {
            new PlatformPromotion
            {
                Code = "FIRST50",
                Name = "50% off your first term",
                Kind = PromotionKinds.Intro,
                PercentOff = 50,
                Terms = 1,
                NewTenantsOnly = true,
                AutoApply = true,
                IsActive = true,
            },
            new PlatformPromotion
            {
                Code = "COMEBACK40",
                Name = "40% off to pick up where you left off",
                Kind = PromotionKinds.WinBack,
                PercentOff = 40,
                Terms = 1,
                LapsedTenantsOnly = true,
                AutoApply = true,
                IsActive = true,
            },
            new PlatformPromotion
            {
                Code = "ANNUAL20",
                Name = "An extra 20% off a 12-month term",
                Kind = PromotionKinds.Campaign,
                PercentOff = 20,
                Period = BillingPeriods.Annual,
                Terms = 1,
                AutoApply = false,
                IsActive = true,
            },
        };

        var existing = await db.PlatformPromotions.Select(p => p.Code).ToListAsync(ct);
        var added = 0;
        foreach (var promotion in seeds)
        {
            if (existing.Contains(promotion.Code, StringComparer.OrdinalIgnoreCase)) continue;
            db.PlatformPromotions.Add(promotion);
            added++;
        }

        if (added > 0)
        {
            await db.SaveChangesAsync(ct);
            logger?.LogInformation("Seeded {Count} platform promotions.", added);
        }
    }
}
