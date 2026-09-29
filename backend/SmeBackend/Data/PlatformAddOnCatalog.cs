using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;

namespace SmeBackend.Data;

/// The consumables beside the subscription - Unify's Boosts and Super Likes.
///
/// Three things are copied from Tinder deliberately:
///
///   The bigger pack is always the better unit price, and the saving is
///     printed on the card. Nobody works out the per-unit cost in their
///     head; the badge does it for them and the 10-pack wins.
///
///   Free users can buy them. A Starter tenant who cannot yet justify LKR
///     5,900 a month will still pay LKR 1,900 to be at the top of the
///     directory on the weekend they have capacity. That purchase is the
///     first time they have paid Unify anything, which is the hard part.
///
///   Paid plans get a few for free every month (PlanLimits.SpotlightsPerMonth).
///     Tinder hands its subscribers a free Boost a month for the same
///     reason: the habit is what the pack is sold on.
///
/// Prices are declared as a single-unit base and a pack discount, so the
/// savings figure on the card is arithmetic rather than a marketing claim
/// somebody has to keep true by hand.
public static class PlatformAddOnCatalog
{
    private sealed record AddOnSpec(
        string CreditType,
        string Category,
        // Takes the quantity and a plural suffix: "{0} Spotlight{1}".
        string NameFormat,
        string Tagline,
        decimal UnitLkr,
        decimal UnitUsd,
        int ExpiryDays,
        int MinimumTier,
        (int Quantity, decimal Discount)[] Packs);

    private static readonly AddOnSpec[] Specs =
    {
        new(
            PlatformCreditTypes.Spotlight, "Visibility",
            "{0} Spotlight{1}",
            "24 hours at the top of the Unify directory for your business.",
            1900m, 5.99m, ExpiryDays: 365, MinimumTier: 0,
            new[] { (1, 0m), (5, 0.28m), (10, 0.38m) }),

        new(
            PlatformCreditTypes.AiRun, "AI",
            "{0} AI credit{1}",
            "Extra copilot runs once your plan allowance is spent.",
            29m, 0.09m, ExpiryDays: 365, MinimumTier: 1,
            new[] { (100, 0m), (500, 0.25m), (2000, 0.40m) }),

        new(
            PlatformCreditTypes.Sms, "Messaging",
            "{0} message credit{1}",
            "SMS and WhatsApp reminders beyond your plan allowance.",
            5m, 0.02m, ExpiryDays: 365, MinimumTier: 1,
            new[] { (500, 0m), (2000, 0.20m), (10000, 0.35m) }),

        new(
            PlatformCreditTypes.Seat, "Seats",
            "{0} extra team seat{1}",
            "One more person on your team, charged once and kept for as long as your plan stays active.",
            1200m, 3.99m, ExpiryDays: 0, MinimumTier: 1,
            new[] { (1, 0m), (5, 0.15m) }),
    };

    public static async Task SyncAsync(AppDbContext db, ILogger? logger = null, CancellationToken ct = default)
    {
        var existing = await db.PlatformAddOns.ToListAsync(ct);
        var now = DateTime.UtcNow;
        var live = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var sort = 0;

        foreach (var spec in Specs)
        {
            var best = spec.Packs.OrderByDescending(p => p.Discount).First();
            foreach (var (quantity, discount) in spec.Packs)
            {
                var code = $"{spec.CreditType}-{quantity}";
                live.Add(code);

                var prices = new Dictionary<string, decimal>();
                foreach (var currency in PlatformPlanCatalog.Currencies)
                {
                    var unit = string.Equals(currency, "USD", StringComparison.OrdinalIgnoreCase) ? spec.UnitUsd : spec.UnitLkr;
                    prices[currency] = PlatformPlanCatalog.Charm(unit * quantity * (1 - discount), currency);
                }

                // The badge is derived from the price that actually shipped,
                // not from the discount we asked for: charm rounding moves
                // the number, and the card must not overstate the saving.
                var listLkr = spec.UnitLkr * quantity;
                var savings = listLkr <= 0 ? 0 : (int)Math.Floor((1 - prices["LKR"] / listLkr) * 100);

                var addOn = existing.FirstOrDefault(a => string.Equals(a.Code, code, StringComparison.OrdinalIgnoreCase));
                if (addOn is null)
                {
                    addOn = new PlatformAddOn { Code = code };
                    db.PlatformAddOns.Add(addOn);
                    existing.Add(addOn);
                }

                addOn.Name = string.Format(spec.NameFormat,
                    quantity == 1 ? "1" : quantity.ToString("N0"),
                    quantity == 1 ? "" : "s");
                addOn.Tagline = spec.Tagline;
                addOn.CreditType = spec.CreditType;
                addOn.Quantity = quantity;
                addOn.ExpiryDays = spec.ExpiryDays;
                addOn.PricesJson = JsonSerializer.Serialize(prices);
                addOn.Category = spec.Category;
                addOn.IsBestValue = quantity == best.Quantity && best.Discount > 0m;
                addOn.SavingsPercent = Math.Max(0, savings);
                addOn.MinimumTier = spec.MinimumTier;
                addOn.IsPublic = true;
                addOn.SortOrder = sort++;
                addOn.UpdatedAt = now;
            }
        }

        foreach (var orphan in existing.Where(a => !live.Contains(a.Code) && a.IsPublic))
        {
            orphan.IsPublic = false;
            orphan.UpdatedAt = now;
        }

        if (db.ChangeTracker.HasChanges())
        {
            await db.SaveChangesAsync(ct);
            logger?.LogInformation("Platform add-on catalogue synced.");
        }
    }

    public static IReadOnlyDictionary<string, decimal> ParsePrices(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new Dictionary<string, decimal>();
        try
        {
            return JsonSerializer.Deserialize<Dictionary<string, decimal>>(json)
                   ?? new Dictionary<string, decimal>();
        }
        catch (JsonException)
        {
            return new Dictionary<string, decimal>();
        }
    }
}
