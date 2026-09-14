using System.Text.Json;

namespace SmeBackend.Shared;

/// Small readers for the raw-JSON-string jsonb columns this codebase uses
/// (Resource.CustomAttributes, BookingType.ConfigJson, Booking.Waiver, ...).
///
/// Everything here is null-tolerant and never throws on malformed JSON: the
/// columns are operator-authored free-form config (see
/// docs/tourism-business-template.md), so a typo in one tenant's config
/// must degrade that one reading to "unknown", not 500 the departure board
/// for everyone.
public static class JsonAttributes
{
    /// Parses a jsonb column into a JsonElement, or null when the column is
    /// empty or not valid JSON.
    public static JsonElement? Root(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.Clone();
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// Walks a dotted path ("pricing.adult", "season.weatherDependent")
    /// through an object graph. Returns null if any hop is missing.
    public static JsonElement? Path(JsonElement? root, string dottedPath)
    {
        if (root is not { ValueKind: JsonValueKind.Object }) return null;

        var current = root.Value;
        foreach (var segment in dottedPath.Split('.'))
        {
            if (current.ValueKind != JsonValueKind.Object) return null;
            if (!current.TryGetProperty(segment, out var next)) return null;
            current = next;
        }
        return current;
    }

    /// A number at a dotted path, accepting a JSON number or a numeric
    /// string ("7500") - PowerShell seed scripts and hand-edited config
    /// both produce the string form often enough to be worth handling.
    public static decimal? Decimal(JsonElement? root, string dottedPath)
    {
        var el = Path(root, dottedPath);
        return el switch
        {
            { ValueKind: JsonValueKind.Number } e when e.TryGetDecimal(out var d) => d,
            { ValueKind: JsonValueKind.String } e when decimal.TryParse(e.GetString(), out var d) => d,
            _ => null,
        };
    }

    public static int? Int(JsonElement? root, string dottedPath)
    {
        var d = Decimal(root, dottedPath);
        return d.HasValue ? (int)Math.Round(d.Value) : null;
    }

    public static bool? Bool(JsonElement? root, string dottedPath) => Path(root, dottedPath) switch
    {
        { ValueKind: JsonValueKind.True } => true,
        { ValueKind: JsonValueKind.False } => false,
        { ValueKind: JsonValueKind.String } e when bool.TryParse(e.GetString(), out var b) => b,
        _ => null,
    };

    public static string? String(JsonElement? root, string dottedPath) => Path(root, dottedPath) switch
    {
        { ValueKind: JsonValueKind.String } e => e.GetString(),
        _ => null,
    };

    /// The string array at a dotted path (e.g. season.months), empty when
    /// absent or not an array.
    public static IReadOnlyList<string> StringArray(JsonElement? root, string dottedPath)
    {
        var el = Path(root, dottedPath);
        if (el is not { ValueKind: JsonValueKind.Array }) return Array.Empty<string>();

        return el.Value.EnumerateArray()
            .Where(item => item.ValueKind == JsonValueKind.String)
            .Select(item => item.GetString()!)
            .ToList();
    }
}
