using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// Wildlife sightings and the analytics built on them.
///
/// Not whale-specific: SightingSpecies spans marine and land wildlife, so a
/// Yala safari operator gets the same success-rate and species-frequency
/// numbers from the same endpoints as a Mirissa whale-watching operator.
[ApiController]
[Route("api/sightings")]
[Authorize]
public class SightingsController : ControllerBase
{
    private readonly AppDbContext _db;

    public SightingsController(AppDbContext db)
    {
        _db = db;
    }

    /// <summary>Logs a sighting, normally from a departure's manifest view.</summary>
    [HttpPost]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> Create([FromBody] CreateSightingDto dto)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var resourceId = dto.ResourceId;
        var departureDateTime = dto.DepartureDateTime;

        // Logging from a manifest only needs the departure id; the vessel
        // and the sailing time are taken from the departure so the two can
        // never disagree.
        if (dto.DepartureId.HasValue)
        {
            var departure = await _db.Departures.AsNoTracking()
                .FirstOrDefaultAsync(d => d.Id == dto.DepartureId && d.TenantId == tenantId);
            if (departure == null) return NotFound(new { message = "Departure not found." });

            resourceId = departure.ResourceId;
            departureDateTime = departure.ScheduledDeparture;
        }

        if (resourceId == Guid.Empty)
            return BadRequest(new { message = "Either DepartureId or ResourceId is required." });

        var resourceExists = await _db.Resources.AnyAsync(r => r.Id == resourceId && r.TenantId == tenantId);
        if (!resourceExists) return NotFound(new { message = "Resource not found." });

        if (dto.Count is <= 0)
            return BadRequest(new { message = "Count must be positive, or omitted when the pod size is unknown." });

        var sighting = new SightingsLog
        {
            TenantId = tenantId,
            ResourceId = resourceId,
            DepartureId = dto.DepartureId,
            BookingId = dto.BookingId,
            DepartureDateTime = DateTimeUtil.AsUtc(departureDateTime == default ? DateTime.UtcNow : departureDateTime),
            Species = dto.Species,
            Count = dto.Count,
            LocationLat = dto.LocationLat,
            LocationLng = dto.LocationLng,
            Behaviour = dto.Behaviour,
            Notes = dto.Notes,
            PhotoUrls = dto.PhotoUrls,
            LoggedByUserId = CallerId(),
        };

        _db.SightingsLogs.Add(sighting);
        await _db.SaveChangesAsync();

        return CreatedAtAction(nameof(GetAll), new { }, Project(sighting));
    }

    /// <summary>Lists sightings, filterable by departure, vessel, species and date range.</summary>
    [HttpGet]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> GetAll(
        [FromQuery] Guid? departureId,
        [FromQuery] Guid? resourceId,
        [FromQuery] SightingSpecies? species,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = _db.SightingsLogs.AsNoTracking().Where(s => s.TenantId == tenantId);
        if (departureId.HasValue) query = query.Where(s => s.DepartureId == departureId);
        if (resourceId.HasValue) query = query.Where(s => s.ResourceId == resourceId);
        if (species.HasValue) query = query.Where(s => s.Species == species);
        if (from.HasValue) query = query.Where(s => s.DepartureDateTime >= DateTimeUtil.AsUtc(from.Value));
        if (to.HasValue) query = query.Where(s => s.DepartureDateTime < DateTimeUtil.AsUtc(to.Value));

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(s => s.DepartureDateTime)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return Ok(new
        {
            items = items.Select(Project),
            total,
            page,
            pageSize,
            totalPages = (int)Math.Ceiling(total / (double)pageSize),
        });
    }

    /// <summary>Soft-deletes a mis-logged sighting.</summary>
    [HttpDelete("{id}")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> Delete(Guid id)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var sighting = await _db.SightingsLogs.FirstOrDefaultAsync(s => s.Id == id && s.TenantId == tenantId);
        if (sighting == null) return NotFound();

        sighting.DeletedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>Just the sighting success rate and its two counts, for the dashboard KPI card.</summary>
    [HttpGet("success-rate")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> GetSuccessRate(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] SightingSpecies? species)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var start = DateTimeUtil.AsUtc(from ?? DateTime.UtcNow.Date.AddMonths(-12)).Date;
        var end = DateTimeUtil.AsUtc(to ?? DateTime.UtcNow.Date).Date.AddDays(1);
        if (end <= start) return BadRequest(new { message = "The from date must be earlier than the to date." });

        // "Returned" is the strictest reading of a departure that actually
        // went looking: it left and came back. Boarding/AtSea sailings are
        // still out at sea, so counting them would depress the rate for a
        // trip that has not finished yet, and cancelled ones never went.
        var completed = await _db.Departures.AsNoTracking()
            .Where(d => d.TenantId == tenantId
                && d.ScheduledDeparture >= start
                && d.ScheduledDeparture < end
                && d.Status == DepartureStatus.Returned)
            .Select(d => d.Id)
            .ToListAsync();

        // Older seeded data leaves departures as Scheduled after their time
        // has passed, so fall back to "its slot is in the past and it was
        // not cancelled" - otherwise a demo tenant reports 0 completed
        // departures and a 0% rate that is an artefact, not a measurement.
        if (completed.Count == 0)
        {
            completed = await _db.Departures.AsNoTracking()
                .Where(d => d.TenantId == tenantId
                    && d.ScheduledDeparture >= start
                    && d.ScheduledDeparture < end
                    && d.ScheduledDeparture < DateTime.UtcNow
                    && d.Status != DepartureStatus.CancelledWeather
                    && d.Status != DepartureStatus.CancelledOther)
                .Select(d => d.Id)
                .ToListAsync();
        }

        var query = _db.SightingsLogs.AsNoTracking()
            .Where(s => s.TenantId == tenantId && s.DepartureId != null && completed.Contains(s.DepartureId.Value));
        if (species.HasValue) query = query.Where(s => s.Species == species);

        var withSighting = await query.Select(s => s.DepartureId!.Value).Distinct().CountAsync();

        return Ok(new
        {
            from = start,
            to = end.AddDays(-1),
            speciesFilter = species?.ToString(),
            departuresCompleted = completed.Count,
            departuresWithSighting = withSighting,
            successRate = completed.Count > 0
                ? Math.Round(withSighting / (double)completed.Count * 100, 1)
                : 0,
        });
    }

    /// <summary>Sighting success rate, species frequency and a month-by-species heatmap for the range.</summary>
    [HttpGet("analytics")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> GetAnalytics(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] SightingSpecies? species)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var start = DateTimeUtil.AsUtc(from ?? DateTime.UtcNow.Date.AddMonths(-12)).Date;
        var end = DateTimeUtil.AsUtc(to ?? DateTime.UtcNow.Date).Date.AddDays(1);
        if (end <= start) return BadRequest(new { message = "The from date must be earlier than the to date." });

        // Only departures that actually sailed count in the denominator: a
        // weather cancellation is not a failed search for whales, and
        // counting it as one would make a stormy month look like bad
        // spotting rather than bad weather.
        var sailed = await _db.Departures.AsNoTracking()
            .Where(d => d.TenantId == tenantId
                && d.ScheduledDeparture >= start
                && d.ScheduledDeparture < end
                && d.Status != DepartureStatus.CancelledWeather
                && d.Status != DepartureStatus.CancelledOther)
            .Select(d => new { d.Id, d.ScheduledDeparture })
            .ToListAsync();

        var sightingQuery = _db.SightingsLogs.AsNoTracking()
            .Where(s => s.TenantId == tenantId
                && s.DepartureDateTime >= start
                && s.DepartureDateTime < end);
        if (species.HasValue) sightingQuery = sightingQuery.Where(s => s.Species == species);

        var sightings = await sightingQuery
            .Select(s => new { s.DepartureId, s.Species, s.Count, s.DepartureDateTime })
            .ToListAsync();

        var departuresWithSighting = sightings
            .Where(s => s.DepartureId != null)
            .Select(s => s.DepartureId!.Value)
            .Distinct()
            .Count();

        var successRate = sailed.Count > 0
            ? Math.Round(departuresWithSighting / (double)sailed.Count * 100, 1)
            : 0;

        var speciesFrequency = sightings
            .GroupBy(s => s.Species)
            .Select(g => new
            {
                species = g.Key.ToString(),
                sightings = g.Count(),
                individuals = g.Sum(s => s.Count ?? 0),
            })
            .OrderByDescending(x => x.sightings)
            .ToList();

        // Monthly heatmap: one row per month in range, one cell per species
        // seen that month, plus that month's own success rate.
        var sailedByMonth = sailed
            .GroupBy(d => new DateTime(d.ScheduledDeparture.Year, d.ScheduledDeparture.Month, 1))
            .ToDictionary(g => g.Key, g => g.ToList());

        var monthly = new List<object>();
        for (var month = new DateTime(start.Year, start.Month, 1); month < end; month = month.AddMonths(1))
        {
            var monthSightings = sightings
                .Where(s => s.DepartureDateTime.Year == month.Year && s.DepartureDateTime.Month == month.Month)
                .ToList();
            var monthSailed = sailedByMonth.GetValueOrDefault(month) ?? new();
            var monthHits = monthSightings
                .Where(s => s.DepartureId != null)
                .Select(s => s.DepartureId!.Value)
                .Distinct()
                .Count();

            monthly.Add(new
            {
                month = month.ToString("yyyy-MM"),
                label = month.ToString("MMM yyyy"),
                departures = monthSailed.Count,
                departuresWithSighting = monthHits,
                successRate = monthSailed.Count > 0 ? Math.Round(monthHits / (double)monthSailed.Count * 100, 1) : 0,
                totalSightings = monthSightings.Count,
                bySpecies = monthSightings
                    .GroupBy(s => s.Species)
                    .ToDictionary(g => g.Key.ToString(), g => g.Count()),
            });
        }

        return Ok(new
        {
            from = start,
            to = end.AddDays(-1),
            speciesFilter = species?.ToString(),
            departuresSailed = sailed.Count,
            departuresWithSighting,
            successRate,
            totalSightings = sightings.Count,
            totalIndividuals = sightings.Sum(s => s.Count ?? 0),
            speciesFrequency,
            monthly,
        });
    }

    /// <summary>The species and behaviour vocabularies, so the client never hard-codes them.</summary>
    [HttpGet("vocabulary")]
    public IActionResult GetVocabulary() => Ok(new
    {
        species = Enum.GetNames<SightingSpecies>(),
        behaviours = Enum.GetNames<SightingBehaviour>(),
    });

    private static object Project(SightingsLog s) => new
    {
        s.Id,
        s.ResourceId,
        s.DepartureId,
        s.BookingId,
        s.DepartureDateTime,
        species = s.Species.ToString(),
        s.Count,
        s.LocationLat,
        s.LocationLng,
        behaviour = s.Behaviour?.ToString(),
        s.Notes,
        s.PhotoUrls,
        s.LoggedByUserId,
        s.CreatedAt,
    };

    private bool TryTenant(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst("tenantId")?.Value, out tenantId);

    private Guid? CallerId() =>
        Guid.TryParse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var id)
            ? id : null;
}

public record CreateSightingDto(
    Guid? DepartureId,
    Guid ResourceId,
    Guid? BookingId,
    DateTime DepartureDateTime,
    SightingSpecies Species,
    int? Count,
    double? LocationLat,
    double? LocationLng,
    SightingBehaviour? Behaviour,
    string? Notes,
    string? PhotoUrls);
