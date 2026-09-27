using System.Text.Json;
using SmeBackend.Models;

namespace SmeBackend.Shared;

/// The restaurant-specific settings a menu item (BookingType) can carry in
/// its ConfigJson - the same config-not-code pattern as the tourism
/// sub-types, so nothing here needs a migration:
///
///   {
///     "serviceMode": "dine-in" | "takeaway" | "delivery" | "drive-thru",
///     "prepTargetMinutes": 15,
///     "recipe": [ { "sku": "RICE-001", "qty": 0.25, "perCover": true } ]
///   }
///
/// serviceMode is inferred from the type's name when absent ("Home
/// delivery" is a delivery, "Takeaway lunch" a takeaway), so an operator
/// gets a sensible channel split before they have configured anything.
public static class RestaurantConfig
{
    public const string DineIn = "Dine-in";
    public const string Takeaway = "Takeaway";
    public const string Delivery = "Delivery";
    public const string DriveThru = "Drive-thru";

    /// Kitchen SLA used when a menu type does not set its own.
    public const int DefaultPrepTargetMinutes = 20;

    public sealed record RecipeLine(string Sku, decimal Qty, bool PerCover);

    public static string ServiceModeOf(BookingType type)
    {
        var configured = ReadString(type.ConfigJson, "serviceMode");
        var fromConfig = NormalizeServiceMode(configured);
        if (fromConfig != null) return fromConfig;
        return NormalizeServiceMode(type.Name) ?? DineIn;
    }

    public static int PrepTargetMinutesOf(BookingType type)
    {
        if (string.IsNullOrWhiteSpace(type.ConfigJson)) return DefaultPrepTargetMinutes;
        try
        {
            using var doc = JsonDocument.Parse(type.ConfigJson);
            if (doc.RootElement.ValueKind == JsonValueKind.Object
                && doc.RootElement.TryGetProperty("prepTargetMinutes", out var el)
                && el.ValueKind == JsonValueKind.Number
                && el.TryGetInt32(out var minutes)
                && minutes > 0)
            {
                return minutes;
            }
        }
        catch (JsonException)
        {
            // Malformed config falls back to the default rather than breaking the board.
        }
        return DefaultPrepTargetMinutes;
    }

    public static List<RecipeLine> RecipeOf(BookingType type)
    {
        var lines = new List<RecipeLine>();
        if (string.IsNullOrWhiteSpace(type.ConfigJson)) return lines;
        try
        {
            using var doc = JsonDocument.Parse(type.ConfigJson);
            if (doc.RootElement.ValueKind != JsonValueKind.Object
                || !doc.RootElement.TryGetProperty("recipe", out var recipe)
                || recipe.ValueKind != JsonValueKind.Array)
            {
                return lines;
            }
            foreach (var line in recipe.EnumerateArray())
            {
                if (line.ValueKind != JsonValueKind.Object) continue;
                if (!line.TryGetProperty("sku", out var skuEl) || skuEl.ValueKind != JsonValueKind.String) continue;
                var sku = skuEl.GetString();
                if (string.IsNullOrWhiteSpace(sku)) continue;
                decimal qty = 1m;
                if (line.TryGetProperty("qty", out var qtyEl) && qtyEl.ValueKind == JsonValueKind.Number) qty = qtyEl.GetDecimal();
                if (qty <= 0) continue;
                var perCover = line.TryGetProperty("perCover", out var pcEl) && pcEl.ValueKind == JsonValueKind.True;
                lines.Add(new RecipeLine(sku.Trim(), qty, perCover));
            }
        }
        catch (JsonException)
        {
            // Same as above: no recipe rather than a 500 on every status change.
        }
        return lines;
    }

    /// Maps free text (a configured mode or a menu type's name) onto one of
    /// the four service modes, or null when nothing in it says which.
    public static string? NormalizeServiceMode(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var t = text.Trim().ToLowerInvariant();
        if (t.Contains("deliver")) return Delivery;
        if (t.Contains("drive")) return DriveThru;
        if (t.Contains("takeaway") || t.Contains("take-away") || t.Contains("take away")
            || t.Contains("pickup") || t.Contains("pick-up") || t.Contains("pick up")
            || t.Contains("collect") || t.Contains("to go") || t.Contains("to-go"))
        {
            return Takeaway;
        }
        if (t.Contains("dine") || t.Contains("table") || t.Contains("seat") || t.Contains("reserv"))
        {
            return DineIn;
        }
        return null;
    }

    private static string? ReadString(string? json, string property)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind == JsonValueKind.Object
                && doc.RootElement.TryGetProperty(property, out var el)
                && el.ValueKind == JsonValueKind.String)
            {
                return el.GetString();
            }
        }
        catch (JsonException)
        {
        }
        return null;
    }
}
