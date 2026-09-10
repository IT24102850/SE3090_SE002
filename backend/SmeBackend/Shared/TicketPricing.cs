using System.Text.Json;
using System.Text.Json.Serialization;
using SmeBackend.Models;

namespace SmeBackend.Shared;

/// One line of a booking's ticket breakdown: "2 adults at 7500".
public sealed class TicketLine
{
    [JsonPropertyName("type")]
    public string Type { get; set; } = "Adult";

    [JsonPropertyName("qty")]
    public int Qty { get; set; }

    /// Null on the way in (the client sends a type and a quantity and lets
    /// the server price it); always filled on the way out.
    [JsonPropertyName("unitPrice")]
    public decimal? UnitPrice { get; set; }

    [JsonPropertyName("lineTotal")]
    public decimal? LineTotal { get; set; }
}

/// The result of pricing a breakdown against a booking type's config.
public sealed record PricedTickets(
    IReadOnlyList<TicketLine> Lines,
    int TotalQuantity,
    decimal Total,
    string Currency,
    string? SeasonLabel,
    bool IsOffPeak);

/// Resolves "2 adults + 1 child" into a total, from unit prices held on
/// BookingType.ConfigJson.
///
/// This is the fix for the first known limitation in
/// docs/tourism-business-template.md section 6 ("the booking flow itself
/// still prices a slot as one unit, not 2 adults + 1 child"). The
/// pricing.adult / pricing.child / currency key names are unchanged from
/// what that document already specifies and what the Flutter app already
/// parses; pricing.infant and seasonalPricing are new keys added alongside
/// them, never replacements.
public static class TicketPricing
{
    /// Ticket types the platform prices. Free-text types outside this list
    /// still work (they price at 0 unless ConfigJson names them) - the list
    /// only drives what the admin booking form offers by default.
    public static readonly string[] KnownTypes = { "Adult", "Child", "Infant" };

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    private static readonly string[] MonthAbbreviations =
        { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

    /// Reads a Booking.TicketBreakdown column. Returns an empty list for
    /// null/blank/malformed JSON so callers can treat "no breakdown" and
    /// "unreadable breakdown" identically - both mean fall back to the
    /// legacy single-unit behaviour.
    public static List<TicketLine> Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new List<TicketLine>();
        try
        {
            var lines = JsonSerializer.Deserialize<List<TicketLine>>(json, SerializerOptions);
            return lines?.Where(l => l.Qty > 0).ToList() ?? new List<TicketLine>();
        }
        catch (JsonException)
        {
            return new List<TicketLine>();
        }
    }

    public static string Serialize(IEnumerable<TicketLine> lines) =>
        JsonSerializer.Serialize(lines, SerializerOptions);

    /// Total heads on a booking. This, not AttendeeCount, is what a
    /// departure's capacity is consumed by, because an infant on a lap
    /// still counts against a licensed passenger figure.
    ///
    /// Falls back to AttendeeCount and finally to 1, so a booking created
    /// before ticket breakdowns existed still occupies exactly one seat.
    public static int SeatsUsed(string? ticketBreakdownJson, int? attendeeCount)
    {
        var lines = Parse(ticketBreakdownJson);
        if (lines.Count > 0) return lines.Sum(l => l.Qty);
        return attendeeCount is > 0 ? attendeeCount.Value : 1;
    }

    /// Prices a breakdown against a booking type, honouring any seasonal
    /// window that covers <paramref name="on"/>.
    ///
    /// Unit prices already present on a line win over the config, so a
    /// manually discounted booking is not silently re-priced when it is
    /// later edited.
    public static PricedTickets Price(IEnumerable<TicketLine> lines, BookingType? bookingType, DateTime on)
    {
        var config = JsonAttributes.Root(bookingType?.ConfigJson);
        var (season, seasonLabel, isOffPeak) = ResolveSeason(config, on);
        var currency = JsonAttributes.String(config, "pricing.currency") ?? "LKR";

        var priced = new List<TicketLine>();
        foreach (var line in lines.Where(l => l.Qty > 0))
        {
            var unit = line.UnitPrice ?? UnitPriceFor(config, season, line.Type) ?? 0m;
            priced.Add(new TicketLine
            {
                Type = line.Type,
                Qty = line.Qty,
                UnitPrice = unit,
                LineTotal = unit * line.Qty,
            });
        }

        return new PricedTickets(
            priced,
            priced.Sum(l => l.Qty),
            priced.Sum(l => l.LineTotal ?? 0m),
            currency,
            seasonLabel,
            isOffPeak);
    }

    /// The per-head price for one ticket type, from the active seasonal
    /// window first and the base pricing block second. Returns null when
    /// the type is not priced at all (as opposed to priced at zero) so
    /// callers can tell a free infant from an unconfigured one.
    public static decimal? UnitPriceFor(JsonElement? config, JsonElement? season, string ticketType)
    {
        var lower = ticketType.ToLowerInvariant();
        return JsonAttributes.Decimal(season, $"pricing.{lower}")
            ?? JsonAttributes.Decimal(season, lower)
            ?? JsonAttributes.Decimal(config, $"pricing.{lower}");
    }

    /// Finds the seasonalPricing entry whose months cover the booking's
    /// month. Shape (all keys optional):
    ///   "seasonalPricing": [
    ///     { "label": "Peak", "months": ["Nov","Dec","Jan","Feb","Mar","Apr"],
    ///       "offPeak": false, "pricing": { "adult": 9000, "child": 5000 } }
    ///   ]
    /// A window with no months never matches, so a half-written config
    /// falls through to base pricing rather than applying everywhere.
    public static (JsonElement? Season, string? Label, bool IsOffPeak) ResolveSeason(JsonElement? config, DateTime on)
    {
        var windows = JsonAttributes.Path(config, "seasonalPricing");
        if (windows is not { ValueKind: JsonValueKind.Array }) return (null, null, false);

        var month = MonthAbbreviations[on.Month - 1];
        foreach (var window in windows.Value.EnumerateArray())
        {
            if (window.ValueKind != JsonValueKind.Object) continue;

            var months = JsonAttributes.StringArray(window, "months");
            if (!months.Any(m => string.Equals(m, month, StringComparison.OrdinalIgnoreCase))) continue;

            var label = JsonAttributes.String(window, "label");
            // Either an explicit "offPeak": true, or a label that says so -
            // seed data and hand-written config both use the label form.
            var offPeak = JsonAttributes.Bool(window, "offPeak")
                ?? (label?.Contains("off", StringComparison.OrdinalIgnoreCase) ?? false);
            return (window, label, offPeak);
        }

        return (null, null, false);
    }

    /// Whether the config's season block says this month is in season, per
    /// the season.months key documented in
    /// docs/tourism-business-template.md. Null when the business has not
    /// declared a season at all.
    public static bool? IsInSeason(JsonElement? config, DateTime on)
    {
        var months = JsonAttributes.StringArray(config, "season.months");
        if (months.Count == 0) return null;

        var month = MonthAbbreviations[on.Month - 1];
        return months.Any(m => string.Equals(m, month, StringComparison.OrdinalIgnoreCase));
    }
}
