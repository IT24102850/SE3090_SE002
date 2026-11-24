using SmeBackend.Models.Marketing;

namespace SmeBackend.Services.Marketing;

/// What the booking page saw when the visitor arrived. Every field is
/// optional and untrusted: it is used to label the booking and to help ad
/// platforms match it, never to decide anything about money or access.
public sealed class AttributionInput
{
    public string? UtmSource { get; set; }
    public string? UtmMedium { get; set; }
    public string? UtmCampaign { get; set; }
    public string? UtmContent { get; set; }
    public string? UtmTerm { get; set; }
    public string? Fbclid { get; set; }
    public string? Fbc { get; set; }
    public string? Fbp { get; set; }
    public string? Ttclid { get; set; }
    public string? Ttp { get; set; }
    public string? LandingUrl { get; set; }
    public string? Referrer { get; set; }
    /// Set by the inbox's "send booking link" (the `conv` query parameter).
    public string? ConversationId { get; set; }
}

public static class AttributionResolver
{
    public const string Website = "Website";

    private static readonly HashSet<string> PaidMediums = new(StringComparer.OrdinalIgnoreCase)
    {
        "cpc", "ppc", "paid", "paid_social", "paidsocial", "paid-social", "ads", "ad", "cpm", "display", "sponsored",
    };

    /// Builds the attribution row for a booking. Values missing from the
    /// request are filled from the query string of the landing/page URL, so
    /// a widget embedded on a page whose own URL carries the UTM tags still
    /// attributes correctly.
    public static BookingAttribution Resolve(AttributionInput? input, string? pageUrl, DateTime now)
    {
        input ??= new AttributionInput();
        var landing = Clip(input.LandingUrl, 2048) ?? Clip(pageUrl, 2048);
        var query = ParseQuery(landing);
        string? Pick(string? direct, string key, int max) => Clip(Clean(direct) ?? Clean(query.GetValueOrDefault(key)), max);

        var a = new BookingAttribution
        {
            UtmSource = Pick(input.UtmSource, "utm_source", 100),
            UtmMedium = Pick(input.UtmMedium, "utm_medium", 100),
            UtmCampaign = Pick(input.UtmCampaign, "utm_campaign", 200),
            UtmContent = Pick(input.UtmContent, "utm_content", 200),
            UtmTerm = Pick(input.UtmTerm, "utm_term", 200),
            Fbclid = Pick(input.Fbclid, "fbclid", 500),
            Ttclid = Pick(input.Ttclid, "ttclid", 500),
            Fbp = Clip(Clean(input.Fbp), 200),
            Ttp = Clip(Clean(input.Ttp), 200),
            LandingUrl = landing,
            Referrer = Clip(Clean(input.Referrer), 2048),
            CreatedAt = now,
        };

        // _fbc is "fb.1.<ms timestamp>.<fbclid>". Use the cookie when the
        // host page's pixel set one; otherwise build it from the click id,
        // which is exactly what the pixel would have done.
        var fbc = Clean(input.Fbc);
        if (fbc == null && a.Fbclid != null)
            fbc = $"fb.1.{new DateTimeOffset(now).ToUnixTimeMilliseconds()}.{a.Fbclid}";
        a.Fbc = Clip(fbc, 600);

        if (Guid.TryParse(Clean(input.ConversationId) ?? query.GetValueOrDefault("conv"), out var conv))
            a.SocialConversationId = conv;

        a.Channel = ResolveChannel(a);
        a.IsPaid = (a.UtmMedium != null && PaidMediums.Contains(a.UtmMedium)) || a.Ttclid != null;
        return a;
    }

    public static string ResolveChannel(BookingAttribution a)
    {
        var fromUtm = SocialPlatform.Normalize(a.UtmSource) ?? a.UtmSource?.Trim().ToLowerInvariant() switch
        {
            "meta" or "facebook_ads" or "fb_ads" or "messenger" => SocialPlatform.Facebook,
            "instagram_ads" or "ig_ads" or "insta" => SocialPlatform.Instagram,
            "tiktok_ads" => SocialPlatform.TikTok,
            _ => null,
        };
        if (fromUtm != null) return fromUtm;

        var host = HostOf(a.Referrer);
        if (host != null)
        {
            if (host.EndsWith("instagram.com")) return SocialPlatform.Instagram;
            if (host.EndsWith("facebook.com") || host.EndsWith("fb.com") || host.EndsWith("fb.me") || host.EndsWith("messenger.com"))
                return SocialPlatform.Facebook;
            if (host.EndsWith("tiktok.com")) return SocialPlatform.TikTok;
        }

        if (a.Ttclid != null) return SocialPlatform.TikTok;
        if (a.Fbclid != null) return SocialPlatform.Facebook;

        // An unrecognised utm_source (newsletter, google, ...) is still more
        // useful in the channel report than "Website".
        return a.UtmSource != null ? Capitalise(a.UtmSource) : Website;
    }

    private static string? HostOf(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var u) ? u.Host.ToLowerInvariant() : null;

    private static Dictionary<string, string> ParseQuery(string? url)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || string.IsNullOrEmpty(uri.Query)) return result;
        foreach (var part in uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var eq = part.IndexOf('=');
            var key = Uri.UnescapeDataString((eq < 0 ? part : part[..eq]).Replace('+', ' '));
            var value = eq < 0 ? "" : Uri.UnescapeDataString(part[(eq + 1)..].Replace('+', ' '));
            result.TryAdd(key, value);
        }
        return result;
    }

    private static string? Clean(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string? Clip(string? value, int max) => value == null ? null : value.Length <= max ? value : value[..max];

    private static string Capitalise(string value)
    {
        var v = value.Trim();
        if (v.Length > 50) v = v[..50];
        return char.ToUpperInvariant(v[0]) + v[1..];
    }
}
