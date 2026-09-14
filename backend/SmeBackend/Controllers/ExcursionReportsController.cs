using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// The reporting half of the departure-operations dashboard: the headline
/// KPI cards, plus the breakdowns the Reports page adds for a fixed-departure
/// excursion operator.
///
/// A separate controller rather than more methods on ReportsController
/// because the two authorize completely differently: ReportsController's
/// endpoints all run through the Inventory module's
/// InventoryAuthorizationPolicies, which has nothing to do with whether
/// someone may see a sailing's revenue. These use the same
/// Admin/Manager/Staff role checks and the same tenantId claim as
/// BookingsController, the component they actually report on.
[ApiController]
[Route("api/reports/excursions")]
// Roles are set per action, not here: multiple [Authorize] attributes are
// ANDed, so a class-level Admin,Manager would silently override the Staff
// allowance on the KPI endpoint that the shared dashboard needs.
[Authorize]
public class ExcursionReportsController : ControllerBase
{
    private readonly AppDbContext _db;

    public ExcursionReportsController(AppDbContext db)
    {
        _db = db;
    }

    /// <summary>The dashboard KPI cards: departures and pax today, sighting success rate, revenue, weather cancellations, waiver completion and forward occupancy.</summary>
    [HttpGet("kpis")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> GetKpis([FromQuery] DateTime? on, [FromQuery] int forwardDays = 7)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        forwardDays = Math.Clamp(forwardDays, 1, 60);
        var today = DateTimeUtil.AsUtc(on ?? DateTime.UtcNow).Date;
        var tomorrow = today.AddDays(1);
        var monthStart = new DateTime(today.Year, today.Month, 1, 0, 0, 0, DateTimeKind.Utc);
        var forwardEnd = today.AddDays(forwardDays);

        // Season-to-date for the sighting rate: the operator's own declared
        // season if there is one (season.months on the booking type config),
        // else the last 12 months. A calendar year would cut a Nov-Apr whale
        // season in half and make every January look like a fresh start.
        var seasonStart = await ResolveSeasonStartAsync(tenantId, today);

        var departures = await _db.Departures.AsNoTracking()
            .Include(d => d.Resource)
            .Include(d => d.BookingType)
            .Where(d => d.TenantId == tenantId && d.ScheduledDeparture >= seasonStart && d.ScheduledDeparture < forwardEnd)
            .ToListAsync();

        var departureIds = departures.Select(d => d.Id).ToList();
        var bookings = await _db.Bookings.AsNoTracking()
            .Where(b => b.TenantId == tenantId
                && b.DepartureId != null
                && departureIds.Contains(b.DepartureId.Value))
            .Select(b => new
            {
                b.DepartureId, b.Status, b.TicketBreakdown, b.AttendeeCount, b.TotalCost, b.Waiver, b.CheckInAt,
            })
            .ToListAsync();

        bool IsLive(string? _, BookingStatus status) =>
            status != BookingStatus.Cancelled
            && status != BookingStatus.WeatherCancelled
            && status != BookingStatus.Rejected;

        var todayDepartures = departures.Where(d => d.ScheduledDeparture >= today && d.ScheduledDeparture < tomorrow).ToList();
        var todayIds = todayDepartures.Select(d => d.Id).ToHashSet();
        var todayBookings = bookings.Where(b => todayIds.Contains(b.DepartureId!.Value) && IsLive(null, b.Status)).ToList();

        var paxToday = todayBookings.Sum(b => TicketPricing.SeatsUsed(b.TicketBreakdown, b.AttendeeCount));
        var capacityToday = todayDepartures
            .Where(d => d.Status != DepartureStatus.CancelledWeather && d.Status != DepartureStatus.CancelledOther)
            .Sum(d => CapacityRules.Resolve(d.Resource, d.BookingType, d) ?? 0);

        // Sighting success rate, season to date. Cancelled sailings are out
        // of the denominator - the sea being too rough to leave harbour is
        // not a failure to find whales.
        var sailed = departures
            .Where(d => d.ScheduledDeparture < tomorrow
                && d.Status != DepartureStatus.CancelledWeather
                && d.Status != DepartureStatus.CancelledOther)
            .Select(d => d.Id)
            .ToList();

        var departuresWithSighting = await _db.SightingsLogs.AsNoTracking()
            .Where(s => s.TenantId == tenantId && s.DepartureId != null && sailed.Contains(s.DepartureId.Value))
            .Select(s => s.DepartureId!.Value)
            .Distinct()
            .CountAsync();

        var weatherCancelledThisMonth = departures.Count(d =>
            d.Status == DepartureStatus.CancelledWeather
            && d.ScheduledDeparture >= monthStart
            && d.ScheduledDeparture < tomorrow);

        var liveBookings = bookings.Where(b => IsLive(null, b.Status)).ToList();
        var waiverSigned = liveBookings.Count(b => JsonAttributes.String(JsonAttributes.Root(b.Waiver), "signedAt") != null);

        var forwardDepartures = departures
            .Where(d => d.ScheduledDeparture >= today
                && d.ScheduledDeparture < forwardEnd
                && d.Status != DepartureStatus.CancelledWeather
                && d.Status != DepartureStatus.CancelledOther)
            .ToList();
        var forwardIds = forwardDepartures.Select(d => d.Id).ToHashSet();
        var forwardPax = bookings
            .Where(b => forwardIds.Contains(b.DepartureId!.Value) && IsLive(null, b.Status))
            .Sum(b => TicketPricing.SeatsUsed(b.TicketBreakdown, b.AttendeeCount));
        var forwardCapacity = forwardDepartures.Sum(d => CapacityRules.Resolve(d.Resource, d.BookingType, d) ?? 0);

        return Ok(new
        {
            asOf = today,
            seasonStart,
            departuresToday = todayDepartures.Count,
            departuresTodayByStatus = todayDepartures
                .GroupBy(d => d.Status.ToString())
                .ToDictionary(g => g.Key, g => g.Count()),
            paxBookedToday = paxToday,
            capacityToday,
            occupancyTodayPercent = capacityToday > 0 ? Math.Round(paxToday / (double)capacityToday * 100, 1) : 0,
            sightingSuccessRate = sailed.Count > 0 ? Math.Round(departuresWithSighting / (double)sailed.Count * 100, 1) : 0,
            departuresSailedSeasonToDate = sailed.Count,
            departuresWithSightingSeasonToDate = departuresWithSighting,
            revenueToday = todayBookings.Sum(b => b.TotalCost ?? 0m),
            weatherCancelledThisMonth,
            waiverCompletionPercent = liveBookings.Count > 0
                ? Math.Round(waiverSigned / (double)liveBookings.Count * 100, 1)
                : 0,
            checkedInToday = todayBookings.Count(b => b.CheckInAt != null),
            forwardDays,
            nextDaysOccupancyPercent = forwardCapacity > 0
                ? Math.Round(forwardPax / (double)forwardCapacity * 100, 1)
                : 0,
            nextDaysPax = forwardPax,
            nextDaysCapacity = forwardCapacity,
        });
    }

    /// <summary>Revenue split by ticket type (adult/child/infant) over a date range.</summary>
    [HttpGet("revenue-by-ticket-type")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> GetRevenueByTicketType([FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        var (start, end) = Range(from, to);

        var bookings = await LiveBookingsAsync(tenantId, start, end);

        var lines = bookings
            .SelectMany(b => TicketPricing.Parse(b.TicketBreakdown))
            .GroupBy(t => t.Type)
            .Select(g => new
            {
                ticketType = g.Key,
                quantity = g.Sum(t => t.Qty),
                revenue = g.Sum(t => t.LineTotal ?? (t.UnitPrice ?? 0m) * t.Qty),
            })
            .OrderByDescending(x => x.revenue)
            .ToList();

        // Bookings predating ticket breakdowns still carry a TotalCost, and
        // dropping them would make the report disagree with the revenue KPI.
        var untypedRevenue = bookings
            .Where(b => TicketPricing.Parse(b.TicketBreakdown).Count == 0)
            .Sum(b => b.TotalCost ?? 0m);

        return Ok(new
        {
            from = start,
            to = end.AddDays(-1),
            byTicketType = lines,
            unbrokenDownRevenue = untypedRevenue,
            totalRevenue = lines.Sum(l => l.revenue) + untypedRevenue,
            totalTickets = lines.Sum(l => l.quantity),
        });
    }

    /// <summary>Revenue, pax and occupancy for every departure in the range.</summary>
    [HttpGet("per-departure")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> GetPerDeparture([FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        var (start, end) = Range(from, to);

        var departures = await _db.Departures.AsNoTracking()
            .Include(d => d.Resource)
            .Include(d => d.BookingType)
            .Where(d => d.TenantId == tenantId && d.ScheduledDeparture >= start && d.ScheduledDeparture < end)
            .OrderBy(d => d.ScheduledDeparture)
            .ToListAsync();

        var ids = departures.Select(d => d.Id).ToList();
        var bookings = await _db.Bookings.AsNoTracking()
            .Where(b => b.DepartureId != null && ids.Contains(b.DepartureId.Value))
            .Select(b => new { b.DepartureId, b.Status, b.TicketBreakdown, b.AttendeeCount, b.TotalCost })
            .ToListAsync();

        var sightings = await _db.SightingsLogs.AsNoTracking()
            .Where(s => s.DepartureId != null && ids.Contains(s.DepartureId.Value))
            .GroupBy(s => s.DepartureId!.Value)
            .Select(g => new { DepartureId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.DepartureId, x => x.Count);

        var rows = departures.Select(d =>
        {
            var mine = bookings
                .Where(b => b.DepartureId == d.Id
                    && b.Status != BookingStatus.Cancelled
                    && b.Status != BookingStatus.WeatherCancelled
                    && b.Status != BookingStatus.Rejected)
                .ToList();
            var capacity = CapacityRules.Resolve(d.Resource, d.BookingType, d) ?? 0;
            var pax = mine.Sum(b => TicketPricing.SeatsUsed(b.TicketBreakdown, b.AttendeeCount));

            return new
            {
                departureId = d.Id,
                vesselName = d.Resource.Name,
                d.ScheduledDeparture,
                status = d.Status.ToString(),
                capacity,
                pax,
                occupancyPercent = capacity > 0 ? Math.Round(pax / (double)capacity * 100, 1) : 0,
                revenue = mine.Sum(b => b.TotalCost ?? 0m),
                revenuePerSeat = pax > 0 ? Math.Round(mine.Sum(b => b.TotalCost ?? 0m) / pax, 2) : 0m,
                bookings = mine.Count,
                sightings = sightings.GetValueOrDefault(d.Id),
            };
        }).ToList();

        return Ok(new
        {
            from = start,
            to = end.AddDays(-1),
            departures = rows,
            totalRevenue = rows.Sum(r => r.revenue),
            averageOccupancyPercent = rows.Count > 0 ? Math.Round(rows.Average(r => r.occupancyPercent), 1) : 0,
        });
    }

    /// <summary>Weather-cancellation count and the value of the bookings it took off the water.</summary>
    [HttpGet("weather-cancellations")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> GetWeatherCancellations([FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        var (start, end) = Range(from, to);

        var cancelled = await _db.Departures.AsNoTracking()
            .Include(d => d.Resource)
            .Where(d => d.TenantId == tenantId
                && d.Status == DepartureStatus.CancelledWeather
                && d.ScheduledDeparture >= start
                && d.ScheduledDeparture < end)
            .OrderBy(d => d.ScheduledDeparture)
            .ToListAsync();

        var ids = cancelled.Select(d => d.Id).ToList();
        var affected = await _db.Bookings.AsNoTracking()
            .Where(b => b.DepartureId != null && ids.Contains(b.DepartureId.Value))
            .Select(b => new { b.DepartureId, b.Status, b.TotalCost, b.TicketBreakdown, b.AttendeeCount })
            .ToListAsync();

        var rows = cancelled.Select(d =>
        {
            var mine = affected.Where(b => b.DepartureId == d.Id).ToList();
            return new
            {
                departureId = d.Id,
                vesselName = d.Resource.Name,
                d.ScheduledDeparture,
                d.CancellationReason,
                bookingsAffected = mine.Count,
                // "Refundable" rather than "refunded": there is no payment
                // gateway in this system (explicitly out of scope), so this
                // is the value at risk on those bookings, not a settled
                // refund figure - naming it refunded would be a claim the
                // data cannot support.
                refundableAmount = mine.Sum(b => b.TotalCost ?? 0m),
                paxAffected = mine.Sum(b => TicketPricing.SeatsUsed(b.TicketBreakdown, b.AttendeeCount)),
                rebookedCount = mine.Count(b => b.Status != BookingStatus.WeatherCancelled),
            };
        }).ToList();

        var byMonth = cancelled
            .GroupBy(d => new DateTime(d.ScheduledDeparture.Year, d.ScheduledDeparture.Month, 1))
            .Select(g => new { month = g.Key.ToString("yyyy-MM"), label = g.Key.ToString("MMM yyyy"), count = g.Count() })
            .OrderBy(x => x.month)
            .ToList();

        return Ok(new
        {
            from = start,
            to = end.AddDays(-1),
            totalCancelled = cancelled.Count,
            totalBookingsAffected = rows.Sum(r => r.bookingsAffected),
            totalRefundableAmount = rows.Sum(r => r.refundableAmount),
            totalRebooked = rows.Sum(r => r.rebookedCount),
            byMonth,
            departures = rows,
        });
    }

    /// <summary>Booking channel split (walk-in / online / OTA) and, where the booking form captured it, a guest nationality breakdown.</summary>
    [HttpGet("channel-split")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> GetChannelSplit([FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();
        var (start, end) = Range(from, to);

        var bookings = await LiveBookingsAsync(tenantId, start, end);

        var byChannel = bookings
            // Source is free text and optional; a booking taken before the
            // column existed is reported as Unknown rather than guessed at.
            .GroupBy(b => string.IsNullOrWhiteSpace(b.Source) ? "Unknown" : b.Source!)
            .Select(g => new
            {
                channel = g.Key,
                bookings = g.Count(),
                pax = g.Sum(b => TicketPricing.SeatsUsed(b.TicketBreakdown, b.AttendeeCount)),
                revenue = g.Sum(b => b.TotalCost ?? 0m),
            })
            .OrderByDescending(x => x.revenue)
            .ToList();

        // Nationality/guest type is only present when the sub-type's booking
        // form collected it (FormData is free-form per sub-type - see
        // docs/tourism-business-template.md), so this section is empty
        // rather than zeroed for operators who never asked.
        var byNationality = bookings
            .Select(b => JsonAttributes.String(JsonAttributes.Root(b.FormData), "nationality")
                ?? JsonAttributes.String(JsonAttributes.Root(b.FormData), "residencyStatus"))
            .Where(n => !string.IsNullOrWhiteSpace(n))
            .GroupBy(n => n!)
            .Select(g => new { nationality = g.Key, bookings = g.Count() })
            .OrderByDescending(x => x.bookings)
            .ToList();

        return Ok(new
        {
            from = start,
            to = end.AddDays(-1),
            byChannel,
            byNationality,
            nationalityCaptured = byNationality.Count > 0,
        });
    }

    // ── Helpers ────────────────────────────────────────────────────────
    private sealed record ReportBooking(
        string? TicketBreakdown, int? AttendeeCount, decimal? TotalCost, string? Source, string? FormData);

    private async Task<List<ReportBooking>> LiveBookingsAsync(Guid tenantId, DateTime start, DateTime end) =>
        await _db.Bookings.AsNoTracking()
            .Where(b => b.TenantId == tenantId
                && b.StartTime >= start
                && b.StartTime < end
                && b.Status != BookingStatus.Cancelled
                && b.Status != BookingStatus.WeatherCancelled
                && b.Status != BookingStatus.Rejected)
            .Select(b => new ReportBooking(b.TicketBreakdown, b.AttendeeCount, b.TotalCost, b.Source, b.FormData))
            .ToListAsync();

    /// The start of the operator's declared season if any booking type names
    /// one, else 12 months back. Picks the most recent season start that is
    /// not in the future, so mid-season the number is season-to-date and
    /// out of season it covers the season just finished.
    private async Task<DateTime> ResolveSeasonStartAsync(Guid tenantId, DateTime today)
    {
        var configs = await _db.BookingTypes.AsNoTracking()
            .Where(bt => bt.TenantId == tenantId && bt.ConfigJson != null)
            .Select(bt => bt.ConfigJson)
            .ToListAsync();

        var monthNames = new[] { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
        var seasonMonths = configs
            .SelectMany(c => JsonAttributes.StringArray(JsonAttributes.Root(c), "season.months"))
            .Select(m => Array.FindIndex(monthNames, n => string.Equals(n, m, StringComparison.OrdinalIgnoreCase)) + 1)
            .Where(m => m > 0)
            .Distinct()
            .ToList();

        if (seasonMonths.Count == 0) return today.AddMonths(-12);

        // Walk back month by month to the first month that is not in season;
        // the month after it is where the current (or most recent) season
        // began. Bounded at 12 months so an all-year season terminates.
        var cursor = new DateTime(today.Year, today.Month, 1, 0, 0, 0, DateTimeKind.Utc);
        for (var i = 0; i < 12; i++)
        {
            var previous = cursor.AddMonths(-1);
            if (!seasonMonths.Contains(previous.Month)) return cursor;
            cursor = previous;
        }
        return today.AddMonths(-12);
    }

    private static (DateTime Start, DateTime EndExclusive) Range(DateTime? from, DateTime? to)
    {
        var today = DateTime.UtcNow.Date;
        var start = DateTimeUtil.AsUtc(from ?? today.AddDays(-29)).Date;
        var end = DateTimeUtil.AsUtc(to ?? today).Date.AddDays(1);
        return end <= start ? (start, start.AddDays(1)) : (start, end);
    }

    private bool TryTenant(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst("tenantId")?.Value, out tenantId);
}
