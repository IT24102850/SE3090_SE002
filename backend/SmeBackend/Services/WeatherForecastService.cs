using System.Globalization;
using System.Text.Json;

namespace SmeBackend.Services;

/// One hour of forecast for one place, in the units this app already stores.
public sealed record MarineForecast(
    DateTime ForecastedFor,
    decimal? WindSpeedKnots,
    decimal? WindGustKnots,
    decimal? WaveHeightMetres,
    decimal? VisibilityKm,
    string Source);

/// Why a sailing is or is not safe, in terms an operator can act on.
public sealed record SailingRisk(
    string Level,                       // ok | caution | unsafe
    bool SuggestCancellation,
    IReadOnlyList<string> Reasons,
    MarineForecast Forecast);

/// The thresholds a sailing is judged against. Defaults are the small-craft
/// figures a whale-watching operator would use; a tenant can tighten them.
public sealed record SailingThresholds(
    decimal MaxWindKnots = 20m,
    decimal MaxGustKnots = 28m,
    decimal MaxWaveMetres = 2.5m,
    decimal MinVisibilityKm = 2m)
{
    public static SailingThresholds Default { get; } = new();
}

public interface IWeatherForecastService
{
    /// Forecast for one place and hour. Null when the service cannot be
    /// reached - the caller decides what that means, rather than being handed
    /// invented numbers.
    Task<MarineForecast?> GetForecastAsync(double latitude, double longitude, DateTime whenUtc, CancellationToken ct = default);

    SailingRisk Assess(MarineForecast forecast, SailingThresholds? thresholds = null);
}

/// Marine and wind forecasts from Open-Meteo.
///
/// Chosen because it needs no API key and no account, which matters for a
/// project that has to run on free tiers and be reproducible by an examiner
/// from a clean clone: there is no secret to distribute and nothing to expire.
/// Two endpoints are combined because wave height lives on the marine API
/// while wind and visibility live on the forecast API.
///
/// Everything is requested in the units WeatherObservation already stores -
/// knots for wind, metres for waves - so no conversion guesswork sits between
/// the forecast and the reading an operator sees. Visibility is the exception:
/// Open-Meteo returns metres and the column is kilometres.
public sealed class OpenMeteoForecastService : IWeatherForecastService
{
    public const string ClientName = "open-meteo";
    public const string SourceName = "Open-Meteo";

    private readonly IHttpClientFactory _http;
    private readonly ILogger<OpenMeteoForecastService> _logger;

    public OpenMeteoForecastService(IHttpClientFactory http, ILogger<OpenMeteoForecastService> logger)
    {
        _http = http;
        _logger = logger;
    }

    public async Task<MarineForecast?> GetForecastAsync(
        double latitude, double longitude, DateTime whenUtc, CancellationToken ct = default)
    {
        var when = DateTime.SpecifyKind(whenUtc, DateTimeKind.Utc);
        // Open-Meteo serves hourly steps, so the hour containing the sailing is
        // the most precise answer available.
        var hour = new DateTime(when.Year, when.Month, when.Day, when.Hour, 0, 0, DateTimeKind.Utc);
        var date = hour.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var lat = latitude.ToString("0.####", CultureInfo.InvariantCulture);
        var lon = longitude.ToString("0.####", CultureInfo.InvariantCulture);

        var client = _http.CreateClient(ClientName);

        // The two calls are independent: a marine outage should still leave
        // wind and visibility usable, and vice versa.
        var windTask = ReadHourAsync(client,
            $"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}" +
            $"&hourly=wind_speed_10m,wind_gusts_10m,visibility&wind_speed_unit=kn" +
            $"&start_date={date}&end_date={date}&timezone=UTC", hour, ct);

        var marineTask = ReadHourAsync(client,
            $"https://marine-api.open-meteo.com/v1/marine?latitude={lat}&longitude={lon}" +
            $"&hourly=wave_height&start_date={date}&end_date={date}&timezone=UTC", hour, ct);

        var wind = await windTask;
        var marine = await marineTask;
        if (wind is null && marine is null) return null;

        return new MarineForecast(
            ForecastedFor: hour,
            WindSpeedKnots: Round(wind?.GetValueOrDefault("wind_speed_10m")),
            WindGustKnots: Round(wind?.GetValueOrDefault("wind_gusts_10m")),
            WaveHeightMetres: Round(marine?.GetValueOrDefault("wave_height")),
            // metres -> kilometres
            VisibilityKm: Round(wind?.GetValueOrDefault("visibility") / 1000m),
            Source: SourceName);
    }

    public SailingRisk Assess(MarineForecast f, SailingThresholds? thresholds = null)
    {
        var t = thresholds ?? SailingThresholds.Default;
        var reasons = new List<string>();
        var unsafeToSail = false;

        if (f.WindSpeedKnots is { } wind)
        {
            if (wind > t.MaxWindKnots)
            {
                unsafeToSail = true;
                reasons.Add($"Wind {wind:0.#} kn is above the {t.MaxWindKnots:0.#} kn limit.");
            }
            else if (wind > t.MaxWindKnots * 0.8m)
            {
                reasons.Add($"Wind {wind:0.#} kn is close to the {t.MaxWindKnots:0.#} kn limit.");
            }
        }

        if (f.WindGustKnots is { } gust && gust > t.MaxGustKnots)
        {
            unsafeToSail = true;
            reasons.Add($"Gusts {gust:0.#} kn are above the {t.MaxGustKnots:0.#} kn limit.");
        }

        if (f.WaveHeightMetres is { } wave)
        {
            if (wave > t.MaxWaveMetres)
            {
                unsafeToSail = true;
                reasons.Add($"Wave height {wave:0.##} m is above the {t.MaxWaveMetres:0.##} m limit.");
            }
            else if (wave > t.MaxWaveMetres * 0.8m)
            {
                reasons.Add($"Wave height {wave:0.##} m is close to the {t.MaxWaveMetres:0.##} m limit.");
            }
        }

        if (f.VisibilityKm is { } vis && vis < t.MinVisibilityKm)
        {
            unsafeToSail = true;
            reasons.Add($"Visibility {vis:0.#} km is below the {t.MinVisibilityKm:0.#} km minimum.");
        }

        // A forecast that told us nothing must not read as "safe".
        if (f.WindSpeedKnots is null && f.WaveHeightMetres is null && f.VisibilityKm is null)
        {
            return new SailingRisk("unknown", false,
                new[] { "The forecast returned no usable readings; check conditions manually." }, f);
        }

        if (reasons.Count == 0) reasons.Add("Wind, waves and visibility are all within limits.");

        return new SailingRisk(
            Level: unsafeToSail ? "unsafe" : reasons.Count > 1 || reasons[0].Contains("close to") ? "caution" : "ok",
            SuggestCancellation: unsafeToSail,
            Reasons: reasons,
            Forecast: f);
    }

    /// Pulls the one hour we care about out of an hourly series.
    private async Task<Dictionary<string, decimal?>?> ReadHourAsync(
        HttpClient client, string url, DateTime hour, CancellationToken ct)
    {
        try
        {
            using var response = await client.GetAsync(url, ct);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Open-Meteo returned {Status} for {Url}", (int)response.StatusCode, url);
                return null;
            }

            using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
            if (!doc.RootElement.TryGetProperty("hourly", out var hourly)) return null;
            if (!hourly.TryGetProperty("time", out var times)) return null;

            var wanted = hour.ToString("yyyy-MM-dd'T'HH:mm", CultureInfo.InvariantCulture);
            var index = -1;
            var i = 0;
            foreach (var t in times.EnumerateArray())
            {
                if (t.GetString() == wanted) { index = i; break; }
                i++;
            }
            if (index < 0) return null;

            var values = new Dictionary<string, decimal?>();
            foreach (var property in hourly.EnumerateObject())
            {
                if (property.NameEquals("time") || property.Value.ValueKind != JsonValueKind.Array) continue;
                var array = property.Value;
                if (index >= array.GetArrayLength()) continue;
                var element = array[index];
                values[property.Name] = element.ValueKind == JsonValueKind.Number ? element.GetDecimal() : null;
            }
            return values;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            // A forecast is advisory. Losing it must never break the screen or
            // the booking flow that asked for it.
            _logger.LogWarning(ex, "Could not read an Open-Meteo forecast.");
            return null;
        }
    }

    private static decimal? Round(decimal? value) => value is null ? null : Math.Round(value.Value, 2);
}
