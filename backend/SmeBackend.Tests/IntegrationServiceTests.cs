using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Primitives;
using SmeBackend.Services;

namespace SmeBackend.Tests;

/// The five third-party integrations, tested at the part that has to be right.
///
/// Each of these is a pure function deliberately kept separable from the code
/// that does the network call, so the rules can be checked without reaching
/// Open-Meteo, text.lk, Google or OpenRouteService. The HTTP plumbing around
/// them is thin; the judgement they encode is not, and it is the judgement
/// that decides whether a boat sails and whether a guest is told.
public class IntegrationServiceTests
{
    // ---------- Open-Meteo: the sail / no-sail call ----------

    private static MarineForecast Reading(decimal? wind = null, decimal? gust = null,
        decimal? wave = null, decimal? visibility = null) =>
        new(new DateTime(2026, 9, 26, 7, 0, 0, DateTimeKind.Utc), wind, gust, wave, visibility, "Open-Meteo");

    private static SailingRisk Assess(MarineForecast forecast) =>
        new OpenMeteoForecastService(new UnusableHttpClientFactory(), new NoopLogger<OpenMeteoForecastService>())
            .Assess(forecast);

    [Fact]
    public void Calm_conditions_are_safe_to_sail()
    {
        var risk = Assess(Reading(wind: 8m, gust: 12m, wave: 0.9m, visibility: 15m));

        Assert.Equal("ok", risk.Level);
        Assert.False(risk.SuggestCancellation);
    }

    [Fact]
    public void A_forecast_with_no_readings_is_unknown_not_safe()
    {
        // The important one. An empty forecast must never read as "go", or a
        // boat sails on the strength of a third party being down.
        var risk = Assess(Reading());

        Assert.Equal("unknown", risk.Level);
        Assert.False(risk.SuggestCancellation);
        Assert.Contains("manually", Assert.Single(risk.Reasons));
    }

    [Theory]
    [InlineData(20, false)]   // exactly the limit is still allowed
    [InlineData(20.1, true)]  // just past it is not
    public void Wind_is_unsafe_only_above_the_limit(double wind, bool expectUnsafe)
    {
        var risk = Assess(Reading(wind: (decimal)wind, wave: 0.5m, visibility: 12m));

        Assert.Equal(expectUnsafe, risk.SuggestCancellation);
    }

    [Theory]
    [InlineData(2.5, false)]
    [InlineData(2.6, true)]
    public void Waves_are_unsafe_only_above_the_limit(double wave, bool expectUnsafe)
    {
        var risk = Assess(Reading(wind: 5m, wave: (decimal)wave, visibility: 12m));

        Assert.Equal(expectUnsafe, risk.SuggestCancellation);
    }

    [Fact]
    public void Low_visibility_alone_is_enough_to_stop_a_sailing()
    {
        var risk = Assess(Reading(wind: 4m, wave: 0.4m, visibility: 1.2m));

        Assert.True(risk.SuggestCancellation);
        Assert.Contains(risk.Reasons, r => r.Contains("Visibility"));
    }

    [Fact]
    public void Gusts_can_stop_a_sailing_the_average_wind_would_allow()
    {
        // 15 kn average is comfortable; 30 kn gusts are not, and a boat only
        // has to be knocked down once.
        var risk = Assess(Reading(wind: 15m, gust: 30m, wave: 1m, visibility: 12m));

        Assert.True(risk.SuggestCancellation);
        Assert.Contains(risk.Reasons, r => r.Contains("Gusts"));
    }

    [Fact]
    public void Conditions_near_the_limit_warn_without_suggesting_cancellation()
    {
        var risk = Assess(Reading(wind: 17m, wave: 2.1m, visibility: 12m));

        Assert.Equal("caution", risk.Level);
        Assert.False(risk.SuggestCancellation);
        Assert.Contains(risk.Reasons, r => r.Contains("close to"));
    }

    // ---------- text.lk: getting the number right ----------

    [Theory]
    [InlineData("+94 77 123 4567")]
    [InlineData("0771234567")]
    [InlineData("94771234567")]
    [InlineData("771234567")]
    [InlineData("077-123 4567")]
    public void Every_way_a_guest_writes_their_number_reaches_the_same_place(string typed)
    {
        Assert.Equal("94771234567", TextLkSmsGateway.NormaliseSriLankanNumber(typed));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("not a phone")]
    [InlineData("+1 415 555 0123")]   // another country
    [InlineData("07712345")]          // too short
    public void Unusable_numbers_are_rejected_rather_than_billed(string? typed)
    {
        // Sending to a number text.lk cannot deliver is charged and silently
        // dropped, so refusing is cheaper and more honest than trying.
        Assert.Null(TextLkSmsGateway.NormaliseSriLankanNumber(typed));
    }

    // ---------- .ics: what lands in the guest's calendar ----------

    private static string Ics(bool cancelled = false, string summary = "Whale Watching Tour") =>
        CalendarInvite.Build(
            Guid.Parse("11111111-2222-3333-4444-555555555555"),
            summary,
            new DateTime(2026, 10, 2, 1, 30, 0, DateTimeKind.Utc),
            new DateTime(2026, 10, 2, 5, 30, 0, DateTimeKind.Utc),
            description: "Bring a hat",
            location: "Mirissa Harbour",
            createdUtc: new DateTime(2026, 9, 26, 12, 0, 0, DateTimeKind.Utc),
            cancelled: cancelled);

    [Fact]
    public void A_booking_becomes_a_calendar_event_at_the_right_time()
    {
        var ics = Ics();

        Assert.StartsWith("BEGIN:VCALENDAR", ics);
        Assert.Contains("END:VCALENDAR", ics);
        Assert.Contains("DTSTART:20261002T013000Z", ics);
        Assert.Contains("DTEND:20261002T053000Z", ics);
        Assert.Contains("METHOD:PUBLISH", ics);
        Assert.Contains("STATUS:CONFIRMED", ics);
    }

    [Fact]
    public void The_event_carries_an_alarm_the_guests_own_device_raises()
    {
        // This is the reminder that still arrives when our SMS does not.
        var ics = Ics();

        Assert.Contains("BEGIN:VALARM", ics);
        Assert.Contains("TRIGGER:-PT2H", ics);
    }

    [Fact]
    public void Re_issuing_a_booking_updates_the_same_entry_rather_than_adding_a_second()
    {
        // A stable UID is the whole mechanism; if it drifted, a guest who
        // pressed the button twice would have two boats in their calendar.
        const string uid = "UID:booking-11111111-2222-3333-4444-555555555555@unify-sme";

        Assert.Contains(uid, Ics());
        Assert.Contains(uid, Ics(cancelled: true));
    }

    [Fact]
    public void A_cancelled_booking_withdraws_the_event_instead_of_leaving_it()
    {
        var ics = Ics(cancelled: true);

        Assert.Contains("METHOD:CANCEL", ics);
        Assert.Contains("STATUS:CANCELLED", ics);
    }

    [Fact]
    public void Punctuation_in_a_title_cannot_break_the_file()
    {
        // Commas and semicolons are field separators in RFC 5545, so an
        // unescaped tour name would corrupt every property after it.
        var ics = Ics(summary: "Sunset trip; whales, dolphins\\sea");

        Assert.Contains("SUMMARY:Sunset trip\\; whales\\, dolphins\\\\sea", ics);
    }

    [Fact]
    public void A_newline_in_a_note_cannot_end_the_property_early()
    {
        var ics = CalendarInvite.Build(Guid.NewGuid(), "Tour",
            new DateTime(2026, 10, 2, 1, 30, 0, DateTimeKind.Utc),
            new DateTime(2026, 10, 2, 5, 30, 0, DateTimeKind.Utc),
            description: "Line one\nLine two");

        Assert.Contains("DESCRIPTION:Line one\\nLine two", ics);
    }

    // ---------- Google holiday feed: reading the real format ----------

    private const string FeedSample = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20260501
        DTEND;VALUE=DATE:20260502
        SUMMARY:May Day
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20260531
        DTEND;VALUE=DATE:20260601
        SUMMARY:Poson Full Moon Poya Day
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20270101
        SUMMARY:Next year
        END:VEVENT
        END:VCALENDAR
        """;

    [Fact]
    public void Holidays_are_read_out_of_the_feed()
    {
        var holidays = GoogleCalendarHolidayService.ParseIcs(FeedSample);

        Assert.Contains(holidays, h => h.Date == new DateOnly(2026, 5, 1) && h.Name == "May Day");
        Assert.Contains(holidays, h => h.Date == new DateOnly(2027, 1, 1));
    }

    [Fact]
    public void Poya_days_are_read_because_they_are_the_ones_that_close_the_business()
    {
        // The reason this feed replaced Nager.Date, which has no Sri Lanka at
        // all. A missing Poya day means boats scheduled on a public holiday.
        var holidays = GoogleCalendarHolidayService.ParseIcs(FeedSample);

        Assert.Contains(holidays, h => h.Date == new DateOnly(2026, 5, 31) && h.Name.Contains("Poya"));
    }

    [Fact]
    public void A_name_split_across_two_lines_is_joined_back_up()
    {
        // Google folds long lines at 75 octets onto a continuation line that
        // starts with a space. Unfolded wrongly, this holiday would be called
        // "Sinhala and Tamil New".
        var folded = "BEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20260414\r\n"
                   + "SUMMARY:Sinhala and Tamil New\r\n Year Day\r\nEND:VEVENT\r\n";

        var holiday = Assert.Single(GoogleCalendarHolidayService.ParseIcs(folded));
        Assert.Equal("Sinhala and Tamil NewYear Day", holiday.Name);
    }

    [Fact]
    public void An_event_with_no_date_is_skipped_rather_than_guessed()
    {
        var holidays = GoogleCalendarHolidayService.ParseIcs(
            "BEGIN:VEVENT\r\nSUMMARY:No date here\r\nEND:VEVENT\r\n");

        Assert.Empty(holidays);
    }

    [Fact]
    public void A_feed_that_could_not_be_fetched_yields_nothing_rather_than_throwing()
    {
        // Slot generation must still run when Google is unreachable; it just
        // stops marking holidays.
        Assert.Empty(GoogleCalendarHolidayService.ParseIcs(string.Empty));
    }

    // ---------- OpenRouteService: always answering ----------

    private static OpenRouteTravelTimeService UnconfiguredTravelTime() =>
        new(new UnusableHttpClientFactory(), new EmptyConfiguration(),
            new NoopLogger<OpenRouteTravelTimeService>());

    [Fact]
    public void Distance_between_two_known_points_is_about_right()
    {
        // Mirissa harbour to Galle fort, ~27 km apart in a straight line.
        var km = OpenRouteTravelTimeService.HaversineKm(5.9483, 80.4569, 6.0535, 80.2210);

        Assert.InRange(km, 22, 32);
    }

    [Fact]
    public async Task Without_a_key_it_still_answers_and_says_the_answer_is_an_estimate()
    {
        // A scheduler asking "can the crew get from here to there" needs an
        // answer. What it must never get is an estimate dressed up as a
        // routed time, so IsEstimate is part of the contract.
        var result = await UnconfiguredTravelTime().GetTravelTimeAsync(5.9483, 80.4569, 6.0535, 80.2210);

        Assert.True(result.IsEstimate);
        Assert.Equal("Estimate", result.Source);
        Assert.True(result.Minutes > 0);
        Assert.Contains("straight-line", result.Basis);
    }

    [Fact]
    public async Task The_same_point_twice_is_a_zero_length_journey()
    {
        var result = await UnconfiguredTravelTime().GetTravelTimeAsync(5.9483, 80.4569, 5.9483, 80.4569);

        Assert.Equal(0, result.Minutes);
        Assert.Equal(0, result.DistanceKm);
    }
}

// --- stand-ins, so none of the above can reach the network ---

file sealed class NoopLogger<T> : ILogger<T>
{
    public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
    public bool IsEnabled(LogLevel logLevel) => false;
    public void Log<TState>(LogLevel logLevel, EventId eventId, TState state,
        Exception? exception, Func<TState, Exception?, string> formatter) { }
}

/// Throws rather than returning a client: these tests assert on paths that
/// must not make an HTTP call, so a call is a failure, not a slow test.
file sealed class UnusableHttpClientFactory : IHttpClientFactory
{
    public HttpClient CreateClient(string name) =>
        throw new InvalidOperationException($"'{name}' should not be called on this path.");
}

file sealed class EmptyConfiguration : IConfiguration
{
    public string? this[string key] { get => null; set { } }
    public IEnumerable<IConfigurationSection> GetChildren() => Array.Empty<IConfigurationSection>();
    public IChangeToken GetReloadToken() => throw new NotSupportedException();
    public IConfigurationSection GetSection(string key) => throw new NotSupportedException();
}
