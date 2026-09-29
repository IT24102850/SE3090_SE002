using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace SmeBackend.Services;

public sealed record TravelTime(double Minutes, double DistanceKm, bool IsEstimate, string Source, string Basis);

public interface ITravelTimeService
{
    Task<TravelTime> GetTravelTimeAsync(double fromLat, double fromLon, double toLat, double toLon, CancellationToken ct = default);
}

/// Driving time between two points, from OpenRouteService when it is
/// configured and a straight-line estimate when it is not.
///
/// It never fails: a scheduler asking "can an agent get from this viewing to
/// the next one" needs an answer, and an honest estimate is more useful than
/// an error. What it must not do is pass an estimate off as a routed time, so
/// `IsEstimate` is part of the contract and is carried all the way into the
/// agent's proposal text.
///
/// The fallback is a straight line inflated by a winding factor - roads are
/// not straight - at a conservative urban speed. For Mirissa-to-Galle it lands
/// within a few minutes of the real answer, which is enough to decide whether
/// two viewings can be back to back.
public sealed class OpenRouteTravelTimeService : ITravelTimeService
{
    public const string ClientName = "openrouteservice";
    private const string DirectionsUrl = "https://api.openrouteservice.org/v2/directions/driving-car";

    /// Road distance is typically ~1.3x the straight line in mixed terrain.
    private const double WindingFactor = 1.3;
    private const double FallbackSpeedKmh = 35;

    private readonly IHttpClientFactory _http;
    private readonly IConfiguration _config;
    private readonly ILogger<OpenRouteTravelTimeService> _logger;

    public OpenRouteTravelTimeService(IHttpClientFactory http, IConfiguration config, ILogger<OpenRouteTravelTimeService> logger)
    {
        _http = http;
        _config = config;
        _logger = logger;
    }

    public async Task<TravelTime> GetTravelTimeAsync(
        double fromLat, double fromLon, double toLat, double toLon, CancellationToken ct = default)
    {
        var straightLineKm = HaversineKm(fromLat, fromLon, toLat, toLon);
        var apiKey = _config["Integrations:OpenRouteService:ApiKey"];

        if (string.IsNullOrWhiteSpace(apiKey))
            return Estimate(straightLineKm, "OpenRouteService is not configured; this is a straight-line estimate.");

        // ORS takes [longitude, latitude] - the reverse of every other API
        // here, and an easy way to route someone into the sea.
        var payload = JsonSerializer.Serialize(new
        {
            coordinates = new[]
            {
                new[] { Round(fromLon), Round(fromLat) },
                new[] { Round(toLon), Round(toLat) },
            },
        });

        using var request = new HttpRequestMessage(HttpMethod.Post, DirectionsUrl)
        {
            Content = new StringContent(payload, Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue(apiKey);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        try
        {
            using var response = await _http.CreateClient(ClientName).SendAsync(request, ct);
            var body = await response.Content.ReadAsStringAsync(ct);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("OpenRouteService returned {Status}: {Body}", (int)response.StatusCode, body);
                return Estimate(straightLineKm, $"OpenRouteService returned {(int)response.StatusCode}; using a straight-line estimate.");
            }

            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("routes", out var routes) && routes.GetArrayLength() > 0
                && routes[0].TryGetProperty("summary", out var summary))
            {
                var seconds = summary.TryGetProperty("duration", out var d) ? d.GetDouble() : 0;
                var metres = summary.TryGetProperty("distance", out var m) ? m.GetDouble() : straightLineKm * 1000;
                return new TravelTime(
                    Math.Round(seconds / 60, 1), Math.Round(metres / 1000, 2),
                    IsEstimate: false, Source: "OpenRouteService", Basis: "Road route for a car.");
            }

            return Estimate(straightLineKm, "OpenRouteService returned no route; using a straight-line estimate.");
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            _logger.LogWarning(ex, "OpenRouteService could not be reached.");
            return Estimate(straightLineKm, "OpenRouteService could not be reached; using a straight-line estimate.");
        }
    }

    private static TravelTime Estimate(double straightLineKm, string why)
    {
        var roadKm = straightLineKm * WindingFactor;
        return new TravelTime(
            Math.Round(roadKm / FallbackSpeedKmh * 60, 1),
            Math.Round(roadKm, 2),
            IsEstimate: true,
            Source: "Estimate",
            Basis: $"{why} {straightLineKm:0.#} km straight line, x{WindingFactor} for roads, at {FallbackSpeedKmh} km/h.");
    }

    private static double Round(double value) => Math.Round(value, 6);

    internal static double HaversineKm(double lat1, double lon1, double lat2, double lon2)
    {
        const double earthRadiusKm = 6371;
        double ToRad(double d) => d * Math.PI / 180;

        var dLat = ToRad(lat2 - lat1);
        var dLon = ToRad(lon2 - lon1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2)
              + Math.Cos(ToRad(lat1)) * Math.Cos(ToRad(lat2)) * Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        return 2 * earthRadiusKm * Math.Asin(Math.Sqrt(a));
    }
}
