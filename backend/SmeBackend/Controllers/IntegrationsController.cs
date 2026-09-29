using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.Services;

namespace SmeBackend.Controllers;

/// Outward-facing third-party calls, routed through ASP.NET Core.
///
/// The Python agent service never calls these providers itself. The spec
/// requires external access to go through the backend, and it is also where
/// the keys live - putting an OpenRouteService key inside the agent container
/// would mean a second place to rotate it and a second place to leak it.
[ApiController]
[Route("api/integrations")]
[Authorize]
public class IntegrationsController : ControllerBase
{
    private readonly ITravelTimeService _travel;
    private readonly IPublicHolidayService _holidays;

    public IntegrationsController(ITravelTimeService travel, IPublicHolidayService holidays)
    {
        _travel = travel;
        _holidays = holidays;
    }

    /// <summary>Road travel time between two points, for scheduling back-to-back appointments.</summary>
    /// <remarks>
    /// Real driving time from OpenRouteService when a key is configured, and a
    /// clearly-labelled straight-line estimate when it is not. The response
    /// always says which it gave, so a schedule built on an estimate can be
    /// read as such rather than trusted as a routed time.
    /// </remarks>
    [HttpGet("travel-time")]
    public async Task<IActionResult> GetTravelTime(
        [FromQuery] double fromLat, [FromQuery] double fromLon,
        [FromQuery] double toLat, [FromQuery] double toLon,
        CancellationToken ct)
    {
        foreach (var (name, value, min, max) in new[]
                 {
                     ("fromLat", fromLat, -90d, 90d), ("toLat", toLat, -90d, 90d),
                     ("fromLon", fromLon, -180d, 180d), ("toLon", toLon, -180d, 180d),
                 })
        {
            if (double.IsNaN(value) || value < min || value > max)
                return BadRequest(new { message = $"{name} must be between {min} and {max}." });
        }

        var result = await _travel.GetTravelTimeAsync(fromLat, fromLon, toLat, toLon, ct);
        return Ok(new
        {
            estimatedMinutes = result.Minutes,
            distanceKm = result.DistanceKm,
            isEstimate = result.IsEstimate,
            source = result.Source,
            basis = result.Basis,
        });
    }

    /// <summary>Public holidays for a country and year, used to close booking slots.</summary>
    [HttpGet("holidays")]
    public async Task<IActionResult> GetHolidays(
        [FromQuery] string country = "LK", [FromQuery] int? year = null, CancellationToken ct = default)
    {
        var target = year ?? DateTime.UtcNow.Year;
        if (target < 2000 || target > 2100) return BadRequest(new { message = "year must be between 2000 and 2100." });

        var holidays = await _holidays.GetHolidaysAsync(country, target, ct);
        return Ok(new
        {
            country = country.ToUpperInvariant(),
            year = target,
            count = holidays.Count,
            items = holidays.OrderBy(h => h.Date).Select(h => new { date = h.Date.ToString("yyyy-MM-dd"), name = h.Name }),
        });
    }
}
