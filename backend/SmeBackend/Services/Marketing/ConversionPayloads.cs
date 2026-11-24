using System.Security.Cryptography;
using System.Text;
using SmeBackend.Models;
using SmeBackend.Models.Marketing;

namespace SmeBackend.Services.Marketing;

/// The person and booking behind one conversion, gathered once and turned
/// into each platform's wire format.
public sealed record ConversionContext(
    ConversionEvent Event,
    BookingAttribution? Attribution,
    string? Email,
    string? Phone,
    string? FullName,
    Guid? CustomerId,
    string? ContentName,
    Guid? ContentId,
    int Quantity);

/// Meta Conversions API and TikTok Events API payloads.
///
/// Personal data leaves only as SHA-256 of the normalised value, which is
/// what both platforms require; IP address and user agent go raw because
/// both platforms require that too, and they are only ever sent for
/// bookings that came in through a public booking link.
public static class ConversionPayloads
{
    public static string MetaEventName(string eventName) => eventName switch
    {
        ConversionEventName.BookingCompleted => "Purchase",
        _ => "Schedule",
    };

    public static string TikTokEventName(string eventName) => eventName switch
    {
        ConversionEventName.BookingCompleted => "CompletePayment",
        _ => "PlaceAnOrder",
    };

    /// event_id shared by both platforms; stable per booking and event, so
    /// a resend is deduplicated by the platform as well as by our outbox.
    public static string EventId(ConversionEvent e) => $"{e.BookingId:N}-{e.EventName}";

    public static object Meta(ConversionContext c)
    {
        var e = c.Event;
        var a = c.Attribution;
        var (first, last) = SplitName(c.FullName);

        var user = new Dictionary<string, object>();
        AddHashed(user, "em", NormaliseEmail(c.Email), asArray: true);
        AddHashed(user, "ph", NormalisePhoneDigits(c.Phone), asArray: true);
        AddHashed(user, "fn", first, asArray: true);
        AddHashed(user, "ln", last, asArray: true);
        AddHashed(user, "external_id", c.CustomerId?.ToString("N"), asArray: true);
        if (a?.ClientIp is { } ip) user["client_ip_address"] = ip;
        if (a?.UserAgent is { } ua) user["client_user_agent"] = ua;
        if (a?.Fbc is { } fbc) user["fbc"] = fbc;
        if (a?.Fbp is { } fbp) user["fbp"] = fbp;

        var custom = new Dictionary<string, object> { ["order_id"] = e.BookingId.ToString("N") };
        if (e.Value is { } value) custom["value"] = value;
        if (e.Currency is { } currency) custom["currency"] = currency;
        if (c.ContentName is { } name) custom["content_name"] = name;
        if (c.ContentId is { } cid)
        {
            custom["content_ids"] = new[] { cid.ToString("N") };
            custom["content_type"] = "product";
            custom["num_items"] = Math.Max(1, c.Quantity);
        }

        // "website" requires a user agent and source URL; a booking without
        // them (made in the app, then paid) is reported as system-generated.
        var website = a?.UserAgent != null && a.LandingUrl != null;
        var payload = new Dictionary<string, object>
        {
            ["event_name"] = MetaEventName(e.EventName),
            ["event_time"] = new DateTimeOffset(DateTime.SpecifyKind(e.EventTime, DateTimeKind.Utc)).ToUnixTimeSeconds(),
            ["event_id"] = EventId(e),
            ["action_source"] = website ? "website" : "system_generated",
            ["user_data"] = user,
            ["custom_data"] = custom,
        };
        if (website) payload["event_source_url"] = a!.LandingUrl!;
        return payload;
    }

    public static object TikTok(ConversionContext c)
    {
        var e = c.Event;
        var a = c.Attribution;

        var user = new Dictionary<string, object>();
        AddHashed(user, "email", NormaliseEmail(c.Email), asArray: false);
        AddHashed(user, "phone", NormalisePhoneE164(c.Phone), asArray: false);
        AddHashed(user, "external_id", c.CustomerId?.ToString("N"), asArray: false);
        if (a?.Ttclid is { } ttclid) user["ttclid"] = ttclid;
        if (a?.Ttp is { } ttp) user["ttp"] = ttp;
        if (a?.ClientIp is { } ip) user["ip"] = ip;
        if (a?.UserAgent is { } ua) user["user_agent"] = ua;

        var properties = new Dictionary<string, object>
        {
            ["content_type"] = "product",
            ["order_id"] = e.BookingId.ToString("N"),
        };
        if (e.Value is { } value) properties["value"] = value;
        if (e.Currency is { } currency) properties["currency"] = currency;
        if (c.ContentId is { } cid)
            properties["contents"] = new[]
            {
                new Dictionary<string, object?>
                {
                    ["content_id"] = cid.ToString("N"),
                    ["content_name"] = c.ContentName,
                    ["quantity"] = Math.Max(1, c.Quantity),
                },
            };

        var payload = new Dictionary<string, object>
        {
            ["event"] = TikTokEventName(e.EventName),
            ["event_time"] = new DateTimeOffset(DateTime.SpecifyKind(e.EventTime, DateTimeKind.Utc)).ToUnixTimeSeconds(),
            ["event_id"] = EventId(e),
            ["user"] = user,
            ["properties"] = properties,
        };
        if (a?.LandingUrl != null)
        {
            var page = new Dictionary<string, object> { ["url"] = a.LandingUrl };
            if (a.Referrer != null) page["referrer"] = a.Referrer;
            payload["page"] = page;
        }
        return payload;
    }

    // ── Normalisation (per each platform's matching spec) ──────────────────

    public static string? NormaliseEmail(string? email)
    {
        var e = email?.Trim().ToLowerInvariant();
        return string.IsNullOrEmpty(e) || !e.Contains('@') ? null : e;
    }

    /// Meta: digits only, with country code, no plus. Local Sri Lankan
    /// formats are widened to 94... - the platform's home market and the
    /// same rule the SMS gateway uses; other countries must be typed with
    /// their country code to match.
    public static string? NormalisePhoneDigits(string? phone)
    {
        if (string.IsNullOrWhiteSpace(phone)) return null;
        var lk = TextLkSmsGateway.NormaliseSriLankanNumber(phone);
        if (lk != null) return lk;
        if (!phone.TrimStart().StartsWith('+')) return null;
        var digits = new string(phone.Where(char.IsDigit).ToArray());
        return digits.Length is >= 8 and <= 15 ? digits : null;
    }

    /// TikTok: E.164, with the plus.
    public static string? NormalisePhoneE164(string? phone) =>
        NormalisePhoneDigits(phone) is { } d ? "+" + d : null;

    public static string Sha256(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();

    private static void AddHashed(Dictionary<string, object> target, string key, string? normalised, bool asArray)
    {
        if (string.IsNullOrEmpty(normalised)) return;
        var hash = Sha256(normalised);
        target[key] = asArray ? new[] { hash } : hash;
    }

    private static (string? First, string? Last) SplitName(string? fullName)
    {
        if (string.IsNullOrWhiteSpace(fullName)) return (null, null);
        var parts = fullName.Trim().ToLowerInvariant().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        return parts.Length switch
        {
            0 => (null, null),
            1 => (parts[0], null),
            _ => (parts[0], parts[^1]),
        };
    }

    public static bool IsBookingDelivered(BookingStatus status) =>
        status is BookingStatus.Completed or BookingStatus.CheckedIn or BookingStatus.InProgress;
}
