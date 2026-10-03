using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;
using System.Text.Json;

namespace SmeBackend.Controllers;

/// The departure operations board for fixed-departure excursions - archetype
/// A in docs/tourism-business-template.md (whale watching boats, safari
/// jeeps). Every endpoint is tenant-scoped off the JWT tenantId claim, the
/// same way BookingsController scopes its queries.
///
/// Nothing here is reachable for a tenant that has no Departure rows, so the
/// existing generic booking flow is untouched for every other business type.
[ApiController]
[Route("api/departures")]
[Authorize]
public class DeparturesController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IPushNotificationSender _pushSender;

    public DeparturesController(AppDbContext db, IPushNotificationSender pushSender)
    {
        _db = db;
        _pushSender = pushSender;
    }

    // ── The board: today plus a forward window ────────────────────────
    /// <summary>The departure operations board: each sailing with its crew, pax vs capacity, ticket mix, waiver completion and check-in count.</summary>
    [HttpGet("board")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> GetBoard([FromQuery] DateTime? from, [FromQuery] int days = 7)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        days = Math.Clamp(days, 1, 60);
        var start = DateTimeUtil.AsUtc(from ?? DateTime.UtcNow).Date;
        var end = start.AddDays(days);

        var departures = await _db.Departures.AsNoTracking()
            .Include(d => d.Resource)
            .Include(d => d.BookingType)
            .Where(d => d.TenantId == tenantId
                && d.ScheduledDeparture >= start
                && d.ScheduledDeparture < end)
            .OrderBy(d => d.ScheduledDeparture)
            .ToListAsync();

        var ids = departures.Select(d => d.Id).ToList();
        var bookings = await _db.Bookings.AsNoTracking()
            .Where(b => b.DepartureId != null && ids.Contains(b.DepartureId.Value))
            .ToListAsync();

        var byDeparture = bookings.GroupBy(b => b.DepartureId!.Value)
            .ToDictionary(g => g.Key, g => g.ToList());

        // One query for the whole window rather than one per departure -
        // the board renders 14 sailings at a time on a busy fortnight.
        var sightingCounts = await _db.SightingsLogs.AsNoTracking()
            .Where(s => s.DepartureId != null && ids.Contains(s.DepartureId.Value))
            .GroupBy(s => s.DepartureId!.Value)
            .Select(g => new { DepartureId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.DepartureId, x => x.Count);

        var latestWeather = await _db.WeatherObservations.AsNoTracking()
            .Where(w => w.TenantId == tenantId && w.DepartureId != null && ids.Contains(w.DepartureId.Value))
            .OrderByDescending(w => w.ObservedAt)
            .ToListAsync();

        var board = departures
            .Select(d => Summarize(
                d,
                byDeparture.GetValueOrDefault(d.Id) ?? new List<Booking>(),
                sightingCounts.GetValueOrDefault(d.Id),
                latestWeather.FirstOrDefault(w => w.DepartureId == d.Id)))
            .ToList();

        return Ok(new
        {
            from = start,
            to = end,
            today = board.Where(b => b.ScheduledDeparture.Date == DateTime.UtcNow.Date).ToList(),
            upcoming = board,
        });
    }

    /// <summary>One departure with its full passenger manifest: name, ticket type, waiver state, minor count, check-in state.</summary>
    [HttpGet("{id}/manifest")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> GetManifest(Guid id)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var departure = await _db.Departures.AsNoTracking()
            .Include(d => d.Resource)
            .Include(d => d.BookingType)
            .FirstOrDefaultAsync(d => d.Id == id && d.TenantId == tenantId);
        if (departure == null) return NotFound();

        var bookings = await _db.Bookings.AsNoTracking()
            .Where(b => b.DepartureId == id)
            .OrderBy(b => b.CreatedAt)
            .ToListAsync();

        // The guest's name lives on the User row that made the booking;
        // Booking.Title is a free-text label and is often the tour name.
        var guestIds = bookings.Select(b => b.BookedFor ?? b.BookedBy).Distinct().ToList();
        var guests = await _db.Users.AsNoTracking()
            .Where(u => guestIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => new { u.FullName, u.Email, u.Phone });

        var passengers = bookings.Select(b =>
        {
            var guestId = b.BookedFor ?? b.BookedBy;
            guests.TryGetValue(guestId, out var guest);
            var waiver = JsonAttributes.Root(b.Waiver);
            var tickets = TicketPricing.Parse(b.TicketBreakdown);

            return new
            {
                bookingId = b.Id,
                guestName = guest?.FullName ?? b.Title ?? "Guest",
                guestEmail = guest?.Email,
                guestPhone = guest?.Phone,
                seats = TicketPricing.SeatsUsed(b.TicketBreakdown, b.AttendeeCount),
                tickets = tickets.Select(t => new { t.Type, t.Qty, t.UnitPrice }),
                status = b.Status.ToString(),
                source = b.Source,
                checkedIn = b.CheckInAt != null,
                checkInAt = b.CheckInAt,
                noShow = b.Status == BookingStatus.NoShow,
                waiverSigned = JsonAttributes.String(waiver, "signedAt") != null,
                waiverSignerName = JsonAttributes.String(waiver, "signerName"),
                minorCount = JsonAttributes.Int(waiver, "minorCount") ?? 0,
                totalCost = b.TotalCost,
                b.Notes,
            };
        }).ToList();

        var summary = Summarize(departure, bookings, null, null);

        return Ok(new
        {
            departure = summary,
            passengers,
            waiverCompletionPercent = summary.WaiverCompletionPercent,
            checkedInCount = summary.CheckedInCount,
            noShowCount = passengers.Count(p => p.noShow),
        });
    }

    // ── Creating and scheduling departures ────────────────────────────
    /// <summary>Creates a scheduled departure for a vessel. Idempotent per vessel and departure time.</summary>
    [HttpPost]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> Create([FromBody] CreateDepartureDto dto)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var resource = await _db.Resources.AsNoTracking()
            .FirstOrDefaultAsync(r => r.Id == dto.ResourceId && r.TenantId == tenantId);
        if (resource == null) return NotFound(new { message = "Vessel not found." });

        var scheduled = DateTimeUtil.AsUtc(dto.ScheduledDeparture);
        var scheduledReturn = dto.ScheduledReturn.HasValue
            ? DateTimeUtil.AsUtc(dto.ScheduledReturn.Value)
            : scheduled.AddMinutes(await DefaultDurationAsync(dto.BookingTypeId));

        if (scheduledReturn <= scheduled)
            return BadRequest(new { message = "ScheduledReturn must be after ScheduledDeparture." });

        // The (ResourceId, ScheduledDeparture) unique index would reject
        // this at the database, but a 409 with the existing id lets the
        // seed script and the UI both treat re-running as a no-op.
        var existing = await _db.Departures.AsNoTracking()
            .FirstOrDefaultAsync(d => d.ResourceId == dto.ResourceId && d.ScheduledDeparture == scheduled);
        if (existing != null)
            return Conflict(new { message = "This vessel already has a departure at that time.", departureId = existing.Id });

        var departure = new Departure
        {
            TenantId = tenantId,
            ResourceId = dto.ResourceId,
            BookingTypeId = dto.BookingTypeId,
            ScheduledDeparture = scheduled,
            ScheduledReturn = scheduledReturn,
            CaptainUserId = dto.CaptainUserId,
            Crew = dto.Crew,
            LicensedCapacity = dto.LicensedCapacity,
            Notes = dto.Notes,
            Status = DepartureStatus.Scheduled,
            CreatedBy = CallerId(),
        };

        _db.Departures.Add(departure);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetManifest), new { id = departure.Id }, new { departure.Id, departure.ScheduledDeparture });
    }

    /// <summary>Assigns the captain, crew, capacity override or notes for a departure.</summary>
    [HttpPut("{id}")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateDepartureDto dto)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var departure = await _db.Departures.FirstOrDefaultAsync(d => d.Id == id && d.TenantId == tenantId);
        if (departure == null) return NotFound();

        if (dto.CaptainUserId.HasValue) departure.CaptainUserId = dto.CaptainUserId;
        if (dto.Crew != null) departure.Crew = dto.Crew;
        if (dto.LicensedCapacity.HasValue) departure.LicensedCapacity = dto.LicensedCapacity;
        if (dto.Notes != null) departure.Notes = dto.Notes;
        if (dto.ScheduledReturn.HasValue) departure.ScheduledReturn = DateTimeUtil.AsUtc(dto.ScheduledReturn.Value);
        departure.UpdatedAt = DateTime.UtcNow;
        departure.UpdatedBy = CallerId();

        await _db.SaveChangesAsync();
        return Ok(new { departure.Id, departure.CaptainUserId, departure.Crew, departure.LicensedCapacity });
    }

    /// <summary>Records the pre-departure safety checklist (jackets counted, briefing done, manifest closed, weather checked).</summary>
    [HttpPut("{id}/safety-checklist")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> SetSafetyChecklist(Guid id, [FromBody] SafetyChecklistDto dto)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var departure = await _db.Departures.FirstOrDefaultAsync(d => d.Id == id && d.TenantId == tenantId);
        if (departure == null) return NotFound();

        var complete = dto.JacketsCounted && dto.BriefingDone && dto.ManifestClosed && dto.WeatherChecked;
        departure.SafetyChecklist = JsonSerializer.Serialize(new
        {
            jacketsCounted = dto.JacketsCounted,
            briefingDone = dto.BriefingDone,
            manifestClosed = dto.ManifestClosed,
            weatherChecked = dto.WeatherChecked,
            completedAt = complete ? DateTime.UtcNow : (DateTime?)null,
            completedBy = complete ? CallerId() : null,
        });
        departure.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return Ok(new { departure.Id, departure.SafetyChecklist, isComplete = complete });
    }

    // ── Status transitions ─────────────────────────────────────────────
    /// <summary>Moves a departure through Boarding / AtSea / Returned. AtSea needs a complete safety checklist unless an Admin overrides.</summary>
    [HttpPut("{id}/status")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> SetStatus(Guid id, [FromBody] SetDepartureStatusDto dto)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var departure = await _db.Departures.FirstOrDefaultAsync(d => d.Id == id && d.TenantId == tenantId);
        if (departure == null) return NotFound();

        // Weather cancellation has its own endpoint because it also has to
        // move every booking and notify every guest; routing it through the
        // plain status setter would silently skip all of that.
        if (dto.Status is DepartureStatus.CancelledWeather)
            return BadRequest(new { message = "Use POST /api/departures/{id}/cancel-weather to cancel for weather." });

        var role = CallerRole();
        if (dto.Status == DepartureStatus.AtSea && !IsChecklistComplete(departure))
        {
            // Soft warning, overridable by Admin only (section 3.5): the
            // captain cannot wave it through, the owner can.
            if (role != Roles.Admin || !dto.OverrideSafetyChecklist)
            {
                return BadRequest(new
                {
                    message = "The pre-departure safety checklist is not complete. An Admin can override this.",
                    requiresOverride = true,
                    safetyChecklist = departure.SafetyChecklist,
                });
            }
        }

        departure.Status = dto.Status;
        if (dto.Status == DepartureStatus.AtSea && departure.ActualDepartureAt == null)
            departure.ActualDepartureAt = DateTime.UtcNow;
        if (dto.Status == DepartureStatus.Returned && departure.ActualReturnAt == null)
            departure.ActualReturnAt = DateTime.UtcNow;
        if (dto.Status == DepartureStatus.CancelledOther)
            departure.CancellationReason = dto.Reason;
        departure.UpdatedAt = DateTime.UtcNow;
        departure.UpdatedBy = CallerId();

        await _db.SaveChangesAsync();
        return Ok(new
        {
            departure.Id,
            status = departure.Status.ToString(),
            departure.ActualDepartureAt,
            departure.ActualReturnAt,
        });
    }

    // ── Weather cancellation, in one action ────────────────────────────
    /// <summary>Cancels a departure for weather: marks every booking WeatherCancelled, notifies each guest, and returns the alternative departures they can be moved to.</summary>
    [HttpPost("{id}/cancel-weather")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> CancelForWeather(Guid id, [FromBody] CancelForWeatherDto? dto)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var departure = await _db.Departures
            .Include(d => d.Resource)
            .FirstOrDefaultAsync(d => d.Id == id && d.TenantId == tenantId);
        if (departure == null) return NotFound();

        if (departure.Status is DepartureStatus.CancelledWeather or DepartureStatus.CancelledOther)
            return BadRequest(new { message = "This departure is already cancelled." });

        var reason = string.IsNullOrWhiteSpace(dto?.Reason) ? "Cancelled due to sea conditions." : dto!.Reason!;

        var bookings = await _db.Bookings
            .Where(b => b.DepartureId == id
                && b.Status != BookingStatus.Cancelled
                && b.Status != BookingStatus.WeatherCancelled
                && b.Status != BookingStatus.Rejected)
            .ToListAsync();

        // The cutoff that stops a *guest* cancelling late deliberately does
        // not apply here: the operator is cancelling because it is not safe
        // to sail, and a cutoff cannot make the sea calmer.
        var notified = new List<Guid>();
        foreach (var booking in bookings)
        {
            booking.Status = BookingStatus.WeatherCancelled;
            booking.CancellationReason = reason;
            booking.UpdatedAt = DateTime.UtcNow;

            var message = $"Your {departure.ScheduledDeparture:MMM d, h:mm tt} departure on {departure.Resource.Name} was cancelled: {reason}";
            NotificationHelper.Queue(_db, booking.TenantId, booking.BookedBy, "WeatherCancellation",
                "Departure cancelled - weather", message);
            notified.Add(booking.BookedBy);
        }

        departure.Status = DepartureStatus.CancelledWeather;
        departure.CancellationReason = reason;
        departure.UpdatedAt = DateTime.UtcNow;
        departure.UpdatedBy = CallerId();

        if (dto?.Weather != null)
        {
            _db.WeatherObservations.Add(new WeatherObservation
            {
                TenantId = tenantId,
                ResourceId = departure.ResourceId,
                DepartureId = departure.Id,
                ObservedAt = DateTime.UtcNow,
                WindSpeedKnots = dto.Weather.WindSpeedKnots,
                WaveHeightMetres = dto.Weather.WaveHeightMetres,
                VisibilityKm = dto.Weather.VisibilityKm,
                SeaStateCode = dto.Weather.SeaStateCode,
                Note = dto.Weather.Note ?? reason,
                RecordedByUserId = CallerId(),
            });
        }

        await _db.SaveChangesAsync();

        foreach (var userId in notified.Distinct())
        {
            await _pushSender.SendAsync(tenantId, userId, "Departure cancelled - weather",
                $"Your {departure.ScheduledDeparture:MMM d, h:mm tt} departure was cancelled: {reason}");
        }

        var alternatives = await RescheduleOptionsAsync(tenantId, departure);

        return Ok(new
        {
            departureId = departure.Id,
            status = departure.Status.ToString(),
            bookingsCancelled = bookings.Count,
            guestsNotified = notified.Distinct().Count(),
            rescheduleOptions = alternatives,
        });
    }

    /// <summary>Lists the departures a weather-cancelled sailing's guests could be moved onto, with the seats each has free.</summary>
    [HttpGet("{id}/reschedule-options")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> GetRescheduleOptions(Guid id)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var departure = await _db.Departures.AsNoTracking()
            .Include(d => d.Resource)
            .FirstOrDefaultAsync(d => d.Id == id && d.TenantId == tenantId);
        if (departure == null) return NotFound();

        return Ok(await RescheduleOptionsAsync(tenantId, departure));
    }

    /// <summary>Moves selected bookings onto another departure, keeping each one's ticket breakdown and honoring the tenant's reschedule cutoff.</summary>
    [HttpPost("{id}/bulk-reschedule")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> BulkReschedule(Guid id, [FromBody] BulkRescheduleDto dto)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var target = await _db.Departures
            .Include(d => d.Resource)
            .Include(d => d.BookingType)
            .FirstOrDefaultAsync(d => d.Id == dto.TargetDepartureId && d.TenantId == tenantId);
        if (target == null) return NotFound(new { message = "Target departure not found." });

        if (target.Status is DepartureStatus.CancelledWeather or DepartureStatus.CancelledOther)
            return BadRequest(new { message = "Cannot reschedule onto a cancelled departure." });

        var tenant = await _db.Tenants.AsNoTracking().FirstOrDefaultAsync(t => t.Id == tenantId);
        var cutoffHours = tenant?.RescheduleCutoffHours ?? 2;
        if (DateTime.UtcNow > target.ScheduledDeparture.AddHours(-cutoffHours))
        {
            return BadRequest(new
            {
                message = $"That departure is inside this business's {cutoffHours} hour(s) reschedule cutoff.",
            });
        }

        var bookings = await _db.Bookings
            .Where(b => b.DepartureId == id && dto.BookingIds.Contains(b.Id))
            .ToListAsync();
        if (bookings.Count == 0) return BadRequest(new { message = "No matching bookings on that departure." });

        var capacity = CapacityRules.Resolve(target.Resource, target.BookingType, target);
        var seatsTaken = await SeatsTakenAsync(target.Id);
        var duration = target.ScheduledReturn - target.ScheduledDeparture;

        var moved = new List<object>();
        var skipped = new List<object>();

        foreach (var booking in bookings.OrderBy(b => b.CreatedAt))
        {
            var seats = TicketPricing.SeatsUsed(booking.TicketBreakdown, booking.AttendeeCount);

            if (capacity is > 0)
            {
                var check = CapacityRules.Check(capacity.Value, seatsTaken, seats);
                if (!check.Allowed)
                {
                    skipped.Add(new { bookingId = booking.Id, reason = check.Error });
                    continue;
                }
            }

            booking.DepartureId = target.Id;
            booking.ResourceId = target.ResourceId;
            booking.StartTime = target.ScheduledDeparture;
            booking.EndTime = target.ScheduledDeparture.Add(duration);
            booking.Status = BookingStatus.Confirmed;
            booking.CancellationReason = null;
            booking.UpdatedAt = DateTime.UtcNow;
            seatsTaken += seats;

            var message = $"Your cancelled departure was rebooked onto {target.ScheduledDeparture:MMM d, h:mm tt} on {target.Resource.Name}.";
            NotificationHelper.Queue(_db, booking.TenantId, booking.BookedBy, "BookingRescheduled",
                "Rebooked after weather cancellation", message);
            moved.Add(new { bookingId = booking.Id, seats });
        }

        await _db.SaveChangesAsync();

        return Ok(new
        {
            targetDepartureId = target.Id,
            movedCount = moved.Count,
            skippedCount = skipped.Count,
            moved,
            skipped,
        });
    }

    // ── Weather console ────────────────────────────────────────────────
    /// <summary>Records a manual wind / wave / visibility / sea-state reading.</summary>
    [HttpPost("weather")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> RecordWeather([FromBody] RecordWeatherDto dto)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        var observation = new WeatherObservation
        {
            TenantId = tenantId,
            ResourceId = dto.ResourceId,
            DepartureId = dto.DepartureId,
            ObservedAt = dto.ObservedAt.HasValue ? DateTimeUtil.AsUtc(dto.ObservedAt.Value) : DateTime.UtcNow,
            WindSpeedKnots = dto.WindSpeedKnots,
            WaveHeightMetres = dto.WaveHeightMetres,
            VisibilityKm = dto.VisibilityKm,
            SeaStateCode = dto.SeaStateCode,
            Note = dto.Note,
            RecordedByUserId = CallerId(),
        };

        _db.WeatherObservations.Add(observation);
        await _db.SaveChangesAsync();
        return Ok(Project(observation));
    }

    /// <summary>The most recent weather readings for the tenant, newest first.</summary>
    [HttpGet("weather")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> GetWeather([FromQuery] Guid? departureId, [FromQuery] int limit = 20)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        limit = Math.Clamp(limit, 1, 200);
        var query = _db.WeatherObservations.AsNoTracking().Where(w => w.TenantId == tenantId);
        if (departureId.HasValue) query = query.Where(w => w.DepartureId == departureId);

        var rows = await query.OrderByDescending(w => w.ObservedAt).Take(limit).ToListAsync();
        return Ok(new { latest = rows.Select(Project).FirstOrDefault(), items = rows.Select(Project) });
    }

    // ── Safety and compliance panel ────────────────────────────────────
    /// <summary>Per-vessel safety readiness: life jackets against licensed capacity, and expiry-dated gear that is expired or expiring soon.</summary>
    [HttpGet("safety")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> GetSafetyPanel([FromQuery] int expiringWithinDays = 60)
    {
        if (!TryTenant(out var tenantId)) return Unauthorized();

        expiringWithinDays = Math.Clamp(expiringWithinDays, 1, 365);
        var horizon = DateTime.UtcNow.Date.AddDays(expiringWithinDays);

        var vessels = await _db.Resources.AsNoTracking()
            .Where(r => r.TenantId == tenantId && r.Category == ResourceCategory.Vehicle)
            .ToListAsync();

        // Equipment is tenant-wide, not per-vessel (EquipmentItem has no
        // ResourceId), so gear is matched to a vessel by name mention -
        // "Life jackets - Sea Guardian" belongs to Sea Guardian. Gear whose
        // name mentions no vessel is reported once under sharedEquipment.
        var equipment = await _db.EquipmentItems.AsNoTracking()
            .Where(e => e.TenantId == tenantId && e.IsActive)
            .ToListAsync();

        var vesselPanels = vessels.Select(v =>
        {
            var capacity = CapacityRules.Resolve(v, null) ?? v.Capacity ?? 0;
            var mine = equipment
                .Where(e => e.Name.Contains(v.Name, StringComparison.OrdinalIgnoreCase))
                .ToList();

            var jackets = mine
                .Where(e => e.Name.Contains("jacket", StringComparison.OrdinalIgnoreCase)
                    || e.Category.Contains("jacket", StringComparison.OrdinalIgnoreCase))
                .Sum(e => e.CurrentStock);

            return new
            {
                resourceId = v.Id,
                vesselName = v.Name,
                licensedCapacity = capacity,
                lifeJacketCount = (int)jackets,
                // Red when a full boat could not be equipped. Capacity 0
                // means the operator has not declared one, so there is
                // nothing to compare against and nothing to flag.
                lifeJacketShortfall = capacity > 0 ? Math.Max(capacity - (int)jackets, 0) : 0,
                jacketsSufficient = capacity == 0 || jackets >= capacity,
                equipment = mine.Select(e => ProjectGear(e, horizon)),
            };
        }).ToList();

        var shared = equipment
            .Where(e => !vessels.Any(v => e.Name.Contains(v.Name, StringComparison.OrdinalIgnoreCase)))
            .Select(e => ProjectGear(e, horizon))
            .ToList();

        return Ok(new
        {
            vessels = vesselPanels,
            sharedEquipment = shared,
            expiredCount = equipment.Count(e => e.ExpiryDate != null && e.ExpiryDate < DateTime.UtcNow.Date),
            expiringSoonCount = equipment.Count(e => e.ExpiryDate >= DateTime.UtcNow.Date && e.ExpiryDate < horizon),
        });
    }

    // ── Helpers ────────────────────────────────────────────────────────
    private static object ProjectGear(EquipmentItem e, DateTime horizon) => new
    {
        equipmentItemId = e.Id,
        e.Name,
        e.Category,
        quantity = e.CurrentStock,
        e.ExpiryDate,
        isExpired = e.ExpiryDate != null && e.ExpiryDate < DateTime.UtcNow.Date,
        isExpiringSoon = e.ExpiryDate >= DateTime.UtcNow.Date && e.ExpiryDate < horizon,
    };

    private static object Project(WeatherObservation w) => new
    {
        w.Id,
        w.ResourceId,
        w.DepartureId,
        w.ObservedAt,
        w.WindSpeedKnots,
        w.WaveHeightMetres,
        w.VisibilityKm,
        w.SeaStateCode,
        w.Note,
        w.Source,
    };

    /// The one place a departure is turned into a board card, so the board
    /// and the manifest header can never drift apart.
    private static DepartureSummary Summarize(
        Departure d, List<Booking> bookings, int? sightingCount, WeatherObservation? weather)
    {
        var live = bookings
            .Where(b => b.Status != BookingStatus.Cancelled
                && b.Status != BookingStatus.WeatherCancelled
                && b.Status != BookingStatus.Rejected)
            .ToList();

        var capacity = CapacityRules.Resolve(d.Resource, d.BookingType, d) ?? 0;
        var pax = live.Sum(b => TicketPricing.SeatsUsed(b.TicketBreakdown, b.AttendeeCount));

        var ticketMix = live
            .SelectMany(b => TicketPricing.Parse(b.TicketBreakdown))
            .GroupBy(t => t.Type)
            .ToDictionary(g => g.Key, g => g.Sum(t => t.Qty));

        var withWaiver = live.Count(b => JsonAttributes.String(JsonAttributes.Root(b.Waiver), "signedAt") != null);

        return new DepartureSummary
        {
            Id = d.Id,
            ResourceId = d.ResourceId,
            VesselName = d.Resource?.Name ?? "Vessel",
            BookingTypeId = d.BookingTypeId,
            BookingTypeName = d.BookingType?.Name,
            ScheduledDeparture = d.ScheduledDeparture,
            ScheduledReturn = d.ScheduledReturn,
            DurationMinutes = (int)(d.ScheduledReturn - d.ScheduledDeparture).TotalMinutes,
            Status = d.Status.ToString(),
            CaptainUserId = d.CaptainUserId,
            Crew = d.Crew,
            SafetyChecklist = d.SafetyChecklist,
            SafetyChecklistComplete = IsChecklistComplete(d),
            Capacity = capacity,
            PaxBooked = pax,
            SeatsRemaining = capacity > 0 ? Math.Max(capacity - pax, 0) : 0,
            OccupancyPercent = capacity > 0 ? Math.Round(pax / (double)capacity * 100, 1) : 0,
            NearCapacity = capacity > 0 && pax >= capacity * CapacityRules.WarnThreshold,
            TicketMix = ticketMix,
            BookingCount = live.Count,
            CheckedInCount = live.Count(b => b.CheckInAt != null),
            WaiverCompletionPercent = live.Count > 0 ? Math.Round(withWaiver / (double)live.Count * 100, 1) : 0,
            Revenue = live.Sum(b => b.TotalCost ?? 0m),
            SightingCount = sightingCount ?? 0,
            CancellationReason = d.CancellationReason,
            LatestWeather = weather == null ? null : Project(weather),
        };
    }

    private static bool IsChecklistComplete(Departure d)
    {
        var checklist = JsonAttributes.Root(d.SafetyChecklist);
        return (JsonAttributes.Bool(checklist, "jacketsCounted") ?? false)
            && (JsonAttributes.Bool(checklist, "briefingDone") ?? false)
            && (JsonAttributes.Bool(checklist, "manifestClosed") ?? false)
            && (JsonAttributes.Bool(checklist, "weatherChecked") ?? false);
    }

    private async Task<int> SeatsTakenAsync(Guid departureId)
    {
        var rows = await _db.Bookings.AsNoTracking()
            .Where(b => b.DepartureId == departureId
                && b.Status != BookingStatus.Cancelled
                && b.Status != BookingStatus.WeatherCancelled
                && b.Status != BookingStatus.Rejected)
            .Select(b => new { b.TicketBreakdown, b.AttendeeCount })
            .ToListAsync();

        return rows.Sum(r => TicketPricing.SeatsUsed(r.TicketBreakdown, r.AttendeeCount));
    }

    private async Task<List<object>> RescheduleOptionsAsync(Guid tenantId, Departure cancelled)
    {
        var tenant = await _db.Tenants.AsNoTracking().FirstOrDefaultAsync(t => t.Id == tenantId);
        var earliest = DateTime.UtcNow.AddHours(tenant?.RescheduleCutoffHours ?? 2);

        var candidates = await _db.Departures.AsNoTracking()
            .Include(d => d.Resource)
            .Include(d => d.BookingType)
            .Where(d => d.TenantId == tenantId
                && d.Id != cancelled.Id
                && d.Status == DepartureStatus.Scheduled
                && d.ScheduledDeparture > earliest
                && d.ScheduledDeparture < cancelled.ScheduledDeparture.AddDays(14))
            .OrderBy(d => d.ScheduledDeparture)
            .Take(20)
            .ToListAsync();

        var options = new List<object>();
        foreach (var candidate in candidates)
        {
            var capacity = CapacityRules.Resolve(candidate.Resource, candidate.BookingType, candidate) ?? 0;
            var taken = await SeatsTakenAsync(candidate.Id);
            options.Add(new
            {
                departureId = candidate.Id,
                vesselName = candidate.Resource.Name,
                candidate.ScheduledDeparture,
                capacity,
                seatsTaken = taken,
                seatsRemaining = capacity > 0 ? Math.Max(capacity - taken, 0) : 0,
            });
        }
        return options;
    }

    private async Task<int> DefaultDurationAsync(Guid? bookingTypeId)
    {
        if (!bookingTypeId.HasValue) return 240;
        var minutes = await _db.BookingTypes.AsNoTracking()
            .Where(bt => bt.Id == bookingTypeId)
            .Select(bt => (int?)bt.DefaultDurationMinutes)
            .FirstOrDefaultAsync();
        return minutes ?? 240;
    }

    private bool TryTenant(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst("tenantId")?.Value, out tenantId);

    private Guid? CallerId() =>
        Guid.TryParse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var id)
            ? id : null;

    private string? CallerRole() => User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value;
}

/// The shape one departure takes on the board and at the head of a manifest.
public sealed class DepartureSummary
{
    public Guid Id { get; set; }
    public Guid ResourceId { get; set; }
    public string VesselName { get; set; } = string.Empty;
    public Guid? BookingTypeId { get; set; }
    public string? BookingTypeName { get; set; }
    public DateTime ScheduledDeparture { get; set; }
    public DateTime ScheduledReturn { get; set; }
    public int DurationMinutes { get; set; }
    public string Status { get; set; } = string.Empty;
    public Guid? CaptainUserId { get; set; }
    public string? Crew { get; set; }
    public string? SafetyChecklist { get; set; }
    public bool SafetyChecklistComplete { get; set; }
    public int Capacity { get; set; }
    public int PaxBooked { get; set; }
    public int SeatsRemaining { get; set; }
    public double OccupancyPercent { get; set; }
    public bool NearCapacity { get; set; }
    public Dictionary<string, int> TicketMix { get; set; } = new();
    public int BookingCount { get; set; }
    public int CheckedInCount { get; set; }
    public double WaiverCompletionPercent { get; set; }
    public decimal Revenue { get; set; }
    public int SightingCount { get; set; }
    public string? CancellationReason { get; set; }
    public object? LatestWeather { get; set; }
}

// ── DTOs ──────────────────────────────────────────────────────────────
public record CreateDepartureDto(
    Guid ResourceId,
    Guid? BookingTypeId,
    DateTime ScheduledDeparture,
    DateTime? ScheduledReturn,
    Guid? CaptainUserId,
    string? Crew,
    int? LicensedCapacity,
    string? Notes);

public record UpdateDepartureDto(
    Guid? CaptainUserId,
    string? Crew,
    int? LicensedCapacity,
    DateTime? ScheduledReturn,
    string? Notes);

public record SafetyChecklistDto(
    bool JacketsCounted,
    bool BriefingDone,
    bool ManifestClosed,
    bool WeatherChecked);

public record SetDepartureStatusDto(
    DepartureStatus Status,
    string? Reason,
    bool OverrideSafetyChecklist = false);

public record WeatherReadingDto(
    decimal? WindSpeedKnots,
    decimal? WaveHeightMetres,
    decimal? VisibilityKm,
    int? SeaStateCode,
    string? Note);

public record CancelForWeatherDto(string? Reason, WeatherReadingDto? Weather);

public record BulkRescheduleDto(Guid TargetDepartureId, List<Guid> BookingIds);

public record RecordWeatherDto(
    Guid? ResourceId,
    Guid? DepartureId,
    DateTime? ObservedAt,
    decimal? WindSpeedKnots,
    decimal? WaveHeightMetres,
    decimal? VisibilityKm,
    int? SeaStateCode,
    string? Note);
