using System.Globalization;
using System.Text;
using Microsoft.Extensions.Caching.Memory;

namespace SmeBackend.Services;

/// One public holiday.
public sealed record PublicHoliday(DateOnly Date, string Name);

public interface IPublicHolidayService
{
    /// Holidays for a country over a date range. Empty when the feed cannot be
    /// reached - a slot generator must not refuse to run because a third party
    /// is down, it should just stop marking holidays.
    Task<IReadOnlyList<PublicHoliday>> GetHolidaysAsync(string countryCode, int year, CancellationToken ct = default);

    Task<IReadOnlySet<DateOnly>> GetHolidayDatesAsync(string countryCode, DateOnly from, DateOnly to, CancellationToken ct = default);
}

/// Public holidays from Google's public holiday calendars, read as iCalendar.
///
/// Nager.Date was the obvious first choice and does not work here: it has no
/// Sri Lanka entry at all (HTTP 204, and LK is absent from its country list),
/// so Poya days - the ones that actually close a Sri Lankan business - would
/// have been silently missing. Calendarific covers LK but needs an account and
/// an API key. Google's feed needs neither, and carries the full Poya calendar.
///
/// Cached for a day: holidays for a year do not change, and an operator
/// regenerating slots should not re-download 87 KB each time.
public sealed class GoogleCalendarHolidayService : IPublicHolidayService
{
    public const string ClientName = "public-holidays";

    private static readonly TimeSpan CacheFor = TimeSpan.FromHours(24);

    private readonly IHttpClientFactory _http;
    private readonly IMemoryCache _cache;
    private readonly ILogger<GoogleCalendarHolidayService> _logger;

    public GoogleCalendarHolidayService(IHttpClientFactory http, IMemoryCache cache, ILogger<GoogleCalendarHolidayService> logger)
    {
        _http = http;
        _cache = cache;
        _logger = logger;
    }

    public async Task<IReadOnlyList<PublicHoliday>> GetHolidaysAsync(string countryCode, int year, CancellationToken ct = default)
    {
        var country = (countryCode ?? "LK").Trim().ToLowerInvariant();
        if (country.Length != 2) country = "lk";

        var key = $"holidays:{country}";
        if (_cache.TryGetValue(key, out IReadOnlyList<PublicHoliday>? cached) && cached is not null)
            return cached.Where(h => h.Date.Year == year).ToList();

        var url = $"https://calendar.google.com/calendar/ical/en.{country}%23holiday%40group.v.calendar.google.com/public/basic.ics";
        try
        {
            using var response = await _http.CreateClient(ClientName).GetAsync(url, ct);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Holiday feed for {Country} returned {Status}.", country, (int)response.StatusCode);
                return Array.Empty<PublicHoliday>();
            }

            var all = ParseIcs(await response.Content.ReadAsStringAsync(ct));
            _cache.Set(key, all, CacheFor);
            return all.Where(h => h.Date.Year == year).ToList();
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            _logger.LogWarning(ex, "Could not reach the public holiday feed for {Country}.", country);
            return Array.Empty<PublicHoliday>();
        }
    }

    public async Task<IReadOnlySet<DateOnly>> GetHolidayDatesAsync(
        string countryCode, DateOnly from, DateOnly to, CancellationToken ct = default)
    {
        var dates = new HashSet<DateOnly>();
        for (var year = from.Year; year <= to.Year; year++)
        {
            foreach (var holiday in await GetHolidaysAsync(countryCode, year, ct))
            {
                if (holiday.Date >= from && holiday.Date <= to) dates.Add(holiday.Date);
            }
        }
        return dates;
    }

    /// Minimal iCalendar reader: all-day VEVENTs, which is what a holiday feed
    /// is. Deliberately not a general parser - anything it does not understand
    /// it ignores rather than guessing.
    internal static List<PublicHoliday> ParseIcs(string ics)
    {
        var holidays = new List<PublicHoliday>();
        DateOnly? date = null;
        string? summary = null;

        // Long lines are folded onto continuation lines starting with a space.
        var unfolded = ics.Replace("\r\n ", string.Empty).Replace("\n ", string.Empty);

        foreach (var raw in unfolded.Split('\n'))
        {
            var line = raw.TrimEnd('\r');
            if (line.StartsWith("BEGIN:VEVENT", StringComparison.Ordinal))
            {
                date = null;
                summary = null;
            }
            else if (line.StartsWith("DTSTART;VALUE=DATE:", StringComparison.Ordinal))
            {
                var value = line["DTSTART;VALUE=DATE:".Length..].Trim();
                if (DateOnly.TryParseExact(value, "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed))
                    date = parsed;
            }
            else if (line.StartsWith("SUMMARY:", StringComparison.Ordinal))
            {
                summary = line["SUMMARY:".Length..].Trim();
            }
            else if (line.StartsWith("END:VEVENT", StringComparison.Ordinal))
            {
                if (date is { } d && !string.IsNullOrWhiteSpace(summary))
                    holidays.Add(new PublicHoliday(d, summary));
            }
        }
        return holidays;
    }
}

/// Builds the .ics a guest adds to their own calendar.
///
/// Written by hand rather than pulled from a package: the format for a single
/// timed event is a dozen lines, and a dependency would be more to justify at
/// a viva than the thing it replaces. No API key, no rate limit, and it works
/// in Google Calendar, Apple Calendar and Outlook alike.
public static class CalendarInvite
{
    /// RFC 5545 escaping: commas, semicolons and backslashes are separators,
    /// and a literal newline would end the property.
    private static string Escape(string? value) => (value ?? string.Empty)
        .Replace("\\", "\\\\")
        .Replace(";", "\\;")
        .Replace(",", "\\,")
        .Replace("\r\n", "\\n")
        .Replace("\n", "\\n");

    private static string Stamp(DateTime utc) =>
        DateTime.SpecifyKind(utc, DateTimeKind.Utc).ToString("yyyyMMdd'T'HHmmss'Z'", CultureInfo.InvariantCulture);

    public static string Build(
        Guid bookingId,
        string summary,
        DateTime startUtc,
        DateTime endUtc,
        string? description = null,
        string? location = null,
        string? organiserName = null,
        DateTime? createdUtc = null,
        bool cancelled = false)
    {
        var builder = new StringBuilder();
        builder.Append("BEGIN:VCALENDAR\r\n");
        builder.Append("VERSION:2.0\r\n");
        builder.Append("PRODID:-//Unify SME Platform//Booking//EN\r\n");
        builder.Append("CALSCALE:GREGORIAN\r\n");
        // CANCEL lets a later file withdraw an event the guest already added,
        // instead of leaving a stale booking in their calendar forever.
        builder.Append(cancelled ? "METHOD:CANCEL\r\n" : "METHOD:PUBLISH\r\n");
        builder.Append("BEGIN:VEVENT\r\n");
        // A stable UID is what makes a re-issued file update the same entry
        // rather than create a second one.
        builder.Append($"UID:booking-{bookingId}@unify-sme\r\n");
        builder.Append($"DTSTAMP:{Stamp(createdUtc ?? DateTime.UtcNow)}\r\n");
        builder.Append($"DTSTART:{Stamp(startUtc)}\r\n");
        builder.Append($"DTEND:{Stamp(endUtc)}\r\n");
        builder.Append($"SUMMARY:{Escape(summary)}\r\n");
        if (!string.IsNullOrWhiteSpace(description)) builder.Append($"DESCRIPTION:{Escape(description)}\r\n");
        if (!string.IsNullOrWhiteSpace(location)) builder.Append($"LOCATION:{Escape(location)}\r\n");
        if (!string.IsNullOrWhiteSpace(organiserName)) builder.Append($"ORGANIZER;CN={Escape(organiserName)}:MAILTO:noreply@unify-sme.test\r\n");
        builder.Append(cancelled ? "STATUS:CANCELLED\r\n" : "STATUS:CONFIRMED\r\n");
        builder.Append("SEQUENCE:0\r\n");
        // A reminder the guest's own device raises, which works even when our
        // push and SMS do not.
        builder.Append("BEGIN:VALARM\r\nTRIGGER:-PT2H\r\nACTION:DISPLAY\r\nDESCRIPTION:Booking reminder\r\nEND:VALARM\r\n");
        builder.Append("END:VEVENT\r\n");
        builder.Append("END:VCALENDAR\r\n");
        return builder.ToString();
    }
}
