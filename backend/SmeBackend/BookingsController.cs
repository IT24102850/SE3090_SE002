using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;
using System.Text.Json;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class BookingsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IReminderChannelSender _reminderSender;
    private readonly IPushNotificationSender _pushSender;

    public BookingsController(AppDbContext db, IReminderChannelSender reminderSender, IPushNotificationSender pushSender)
    {
        _db = db;
        _reminderSender = reminderSender;
        _pushSender = pushSender;
    }

    // ── FR-B1: Search availability ─────────────────────────────
    // Consults the resource's weekly ResourceSchedule (falls back to 9am-5pm if
    // the resource has no schedule configured yet) and honors the booking type's
    // buffer time so back-to-back bookings leave the configured gap.
    /// <summary>FR-B1: lists a resource's bookable slots for one day, honoring its weekly schedule and the booking type's buffer time.</summary>
    [HttpGet("available-slots")]
    [AllowAnonymous]
    public async Task<IActionResult> GetAvailableSlots(
        [FromQuery] Guid resourceId,
        [FromQuery] DateTime date,
        [FromQuery] int duration = 60,
        [FromQuery] Guid? bookingTypeId = null)
    {
        date = DateTimeUtil.AsUtc(date);

        var resourceExists = await _db.Resources.AnyAsync(r => r.Id == resourceId);
        if (!resourceExists) return NotFound(new { message = "Resource not found." });

        var dayOfWeek = (int)date.DayOfWeek;
        var schedule = await _db.ResourceSchedules.AsNoTracking()
            .FirstOrDefaultAsync(s => s.ResourceId == resourceId && s.DayOfWeek == dayOfWeek);

        var bufferBefore = 0;
        var bufferAfter = 0;
        if (bookingTypeId.HasValue)
        {
            var bookingType = await _db.BookingTypes.AsNoTracking()
                .FirstOrDefaultAsync(bt => bt.Id == bookingTypeId);
            if (bookingType != null)
            {
                if (duration <= 0) duration = bookingType.DefaultDurationMinutes;
                bufferBefore = bookingType.BufferMinutesBefore;
                bufferAfter = bookingType.BufferMinutesAfter;
            }
        }

        var existing = await _db.Bookings.AsNoTracking()
            .Where(b => b.ResourceId == resourceId
                && b.StartTime.Date == date.Date
                && b.DeletedAt == null
                && b.Status != Models.BookingStatus.Cancelled
                && b.Status != Models.BookingStatus.Rejected)
            .Select(b => new { b.StartTime, b.EndTime })
            .ToListAsync();

        var isClosedException = await _db.ResourceScheduleExceptions.AsNoTracking()
            .AnyAsync(e => e.ResourceId == resourceId && e.Date == date.Date);

        var (isOpen, slots) = SlotCalculator.Calculate(
            date, schedule, duration, bufferBefore, bufferAfter,
            existing.Select(b => (b.StartTime, b.EndTime)).ToList(),
            DateTime.UtcNow, isClosedException);

        return Ok(new
        {
            date = date.Date,
            isOpen,
            resourceId,
            slots = slots.Select(s => new { startTime = s.StartTime, endTime = s.EndTime, isAvailable = s.IsAvailable })
        });
    }

    // Night/DateRange/Package booking types (see docs/tourism-business-template.md)
    // don't have fixed-duration "slots" - the customer picks a start/end date
    // range directly, so all the picker needs is which ranges are already
    // taken. Deliberately not reusing GetAvailableSlots/SlotCalculator, which
    // is Slot-specific (fixed-duration sub-day windows within one day's
    // ResourceSchedule) and stays untouched.
    /// <summary>Lists already-booked date ranges for a resource, for Night/DateRange/Package booking types.</summary>
    [HttpGet("unavailable-ranges")]
    [AllowAnonymous]
    public async Task<IActionResult> GetUnavailableRanges(
        [FromQuery] Guid resourceId,
        [FromQuery] DateTime from,
        [FromQuery] DateTime to)
    {
        from = DateTimeUtil.AsUtc(from);
        to = DateTimeUtil.AsUtc(to);

        var resourceExists = await _db.Resources.AnyAsync(r => r.Id == resourceId);
        if (!resourceExists) return NotFound(new { message = "Resource not found." });

        var ranges = await _db.Bookings.AsNoTracking()
            .Where(b => b.ResourceId == resourceId
                && b.DeletedAt == null
                && b.Status != Models.BookingStatus.Cancelled
                && b.Status != Models.BookingStatus.Rejected
                && b.StartTime < to && b.EndTime > from)
            .Select(b => new { b.StartTime, b.EndTime })
            .ToListAsync();

        return Ok(ranges.Select(r => new { startTime = r.StartTime, endTime = r.EndTime }));
    }

    // ── FR-B2: Create booking ─────────────────────────────────
    // Requires auth (FR-C1: no anonymous booking — signing up is the point).
    // A Customer caller can only ever book for themselves: BookedBy is
    // ignored from the payload and forced to the caller's own id. Staff can
    // still book on behalf of a patient via BookedBy/BookedFor.
    /// <summary>FR-B2: creates a booking, after conflict detection and business-rule validation.</summary>
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateBookingDto dto)
    {
        var (callerId, callerRole) = CallerIdentity();
        if (callerId == null) return Unauthorized();

        var startTime = DateTimeUtil.AsUtc(dto.StartTime);
        var endTime = DateTimeUtil.AsUtc(dto.EndTime);

        if (endTime <= startTime)
            return BadRequest(new { message = "EndTime must be after StartTime." });

        // FR-B3: Conflict detection
        if (await HasConflictAsync(dto.ResourceId, startTime, endTime))
            return Conflict(new { message = "This time slot is already booked." });

        var businessRuleError = await ValidateBusinessRulesAsync(dto.ResourceId, startTime, endTime, dto.BookingTypeId);
        if (businessRuleError != null)
            return BadRequest(new { message = businessRuleError });

        var bookedBy = callerRole == Roles.Customer ? callerId.Value : dto.BookedBy;

        var booking = new Booking
        {
            TenantId = dto.TenantId,
            ResourceId = dto.ResourceId,
            BookingTypeId = dto.BookingTypeId,
            BookedBy = bookedBy,
            BookedFor = dto.BookedFor,
            Title = dto.Title,
            Notes = dto.Notes,
            StartTime = startTime,
            EndTime = endTime,
            Status = Models.BookingStatus.Pending,
            Priority = dto.Priority,
            AttendeeCount = dto.AttendeeCount,
            FormData = dto.FormData
        };

        _db.Bookings.Add(booking);

        var resourceName = (await _db.Resources.FindAsync(dto.ResourceId))?.Name;
        var confirmationMessage = $"Your booking for {resourceName} on {startTime:MMM d, h:mm tt} is confirmed.";
        NotificationHelper.Queue(_db, dto.TenantId, bookedBy, "BookingConfirmation",
            "Booking confirmed", confirmationMessage);

        await _db.SaveChangesAsync();
        await _pushSender.SendAsync(dto.TenantId, bookedBy, "Booking confirmed", confirmationMessage);

        return CreatedAtAction(nameof(GetById), new { id = booking.Id }, new
        {
            booking.Id,
            booking.StartTime,
            booking.EndTime,
            booking.Status,
            ResourceName = resourceName
        });
    }

    // ── FR-B5: Reschedule ─────────────────────────────────────
    /// <summary>FR-B5: moves a booking to a new time, subject to the cutoff window, conflict detection, and business rules.</summary>
    [HttpPut("{id}/reschedule")]
    public async Task<IActionResult> Reschedule(Guid id, [FromBody] RescheduleDto dto)
    {
        var booking = await _db.Bookings.FindAsync(id);
        if (booking == null || booking.DeletedAt != null) return NotFound();

        var ownership = CheckOwnership(booking);
        if (ownership != null) return ownership;

        var newStart = DateTimeUtil.AsUtc(dto.NewStartTime);
        var newEnd = DateTimeUtil.AsUtc(dto.NewEndTime);
        if (newEnd <= newStart)
            return BadRequest(new { message = "NewEndTime must be after NewStartTime." });

        var tenant = await _db.Tenants.AsNoTracking().FirstOrDefaultAsync(t => t.Id == booking.TenantId);
        var cutoff = booking.StartTime.AddHours(-(tenant?.RescheduleCutoffHours ?? 2));
        if (DateTime.UtcNow > cutoff)
            return BadRequest(new { message = $"Cannot reschedule within {tenant?.RescheduleCutoffHours ?? 2} hour(s) of the appointment." });

        if (await HasConflictAsync(booking.ResourceId, newStart, newEnd, excludeBookingId: id))
            return Conflict(new { message = "New slot conflicts with existing booking." });

        var businessRuleError = await ValidateBusinessRulesAsync(booking.ResourceId, newStart, newEnd, booking.BookingTypeId, excludeBookingId: id);
        if (businessRuleError != null)
            return BadRequest(new { message = businessRuleError });

        booking.StartTime = newStart;
        booking.EndTime = newEnd;
        booking.UpdatedAt = DateTime.UtcNow;

        var rescheduleMessage = $"Your booking was moved to {newStart:MMM d, h:mm tt}.";
        NotificationHelper.Queue(_db, booking.TenantId, booking.BookedBy, "BookingRescheduled",
            "Booking rescheduled", rescheduleMessage);

        await _db.SaveChangesAsync();
        await _pushSender.SendAsync(booking.TenantId, booking.BookedBy, "Booking rescheduled", rescheduleMessage);
        return Ok(booking);
    }

    // ── FR-B5: Cancel ─────────────────────────────────────────
    /// <summary>FR-B5: cancels a booking, subject to the cancellation cutoff window.</summary>
    [HttpPut("{id}/cancel")]
    public async Task<IActionResult> Cancel(Guid id)
    {
        var booking = await _db.Bookings.FindAsync(id);
        if (booking == null || booking.DeletedAt != null) return NotFound();

        var ownership = CheckOwnership(booking);
        if (ownership != null) return ownership;

        var tenant = await _db.Tenants.AsNoTracking().FirstOrDefaultAsync(t => t.Id == booking.TenantId);
        var cutoff = booking.StartTime.AddHours(-(tenant?.CancellationCutoffHours ?? 1));
        if (DateTime.UtcNow > cutoff)
            return BadRequest(new { message = $"Cannot cancel within {tenant?.CancellationCutoffHours ?? 1} hour(s) of the appointment." });

        booking.Status = Models.BookingStatus.Cancelled;
        booking.UpdatedAt = DateTime.UtcNow;

        var cancelMessage = $"Your booking for {booking.StartTime:MMM d, h:mm tt} was cancelled.";
        NotificationHelper.Queue(_db, booking.TenantId, booking.BookedBy, "BookingCancelled",
            "Booking cancelled", cancelMessage);

        await _db.SaveChangesAsync();
        await _pushSender.SendAsync(booking.TenantId, booking.BookedBy, "Booking cancelled", cancelMessage);
        return Ok(new { message = "Booking cancelled." });
    }

    // Resolves the caller's id/role from the JWT. Returns (null, null) when unauthenticated.
    private (Guid? Id, string? Role) CallerIdentity()
    {
        var idClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        var role = User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value;
        return (Guid.TryParse(idClaim, out var id) ? id : (Guid?)null, role);
    }

    // A booking can only be read/changed by the patient who made it, or by
    // Staff/Manager/Admin (front-desk / clinical staff). Returns an
    // ActionResult to short-circuit on failure, or null to proceed.
    private IActionResult? CheckOwnership(Booking booking)
    {
        var (callerId, callerRole) = CallerIdentity();
        if (callerId == null) return Unauthorized();
        if (callerRole is Roles.Admin or Roles.Manager or Roles.Staff) return null;
        if (booking.BookedBy == callerId) return null;
        return Forbid();
    }

    // Shared by Create, Reschedule and RouteOrCreateBatchAsync — was
    // duplicated 3x with a slightly different Rejected-status behavior in
    // each; excludeRejected preserves that (RouteOrCreateBatchAsync's bulk
    // path already excluded Rejected bookings from conflicting; Create and
    // Reschedule never did) rather than silently changing either.
    private async Task<bool> HasConflictAsync(
        Guid resourceId, DateTime start, DateTime end, Guid? excludeBookingId = null, bool excludeRejected = false)
    {
        return await _db.Bookings.AnyAsync(b =>
            b.ResourceId == resourceId
            && b.DeletedAt == null
            && b.Status != Models.BookingStatus.Cancelled
            && (!excludeRejected || b.Status != Models.BookingStatus.Rejected)
            && (excludeBookingId == null || b.Id != excludeBookingId)
            && b.StartTime < end
            && b.EndTime > start);
    }

    // Enforces per-resource lunch-break gaps and a max-hours/day cap, both
    // configured on ResourceSchedule (ResourcesController's schedule
    // editor). Independent of HasConflictAsync above — a booking can pass
    // conflict detection (no overlap with another booking) yet still
    // violate a business rule, e.g. it falls inside the lunch break, or the
    // resource is already fully booked for the day even with gaps between
    // bookings.
    // Only meaningful for Slot bookings (fixed-duration, sub-day). A
    // Night/DateRange/Package booking spans multiple calendar days by
    // design — "8 hours/day" and "lunch break" aren't concepts that apply
    // to a multi-day reservation, so those units skip this check entirely
    // rather than being measured against a single day's cap.
    private async Task<string?> ValidateBusinessRulesAsync(
        Guid resourceId, DateTime start, DateTime end, Guid bookingTypeId, Guid? excludeBookingId = null)
    {
        var bookingUnit = await _db.BookingTypes.AsNoTracking()
            .Where(bt => bt.Id == bookingTypeId)
            .Select(bt => bt.BookingUnit)
            .FirstOrDefaultAsync();
        if (bookingUnit != null && bookingUnit != "Slot")
            return null;

        var dayOfWeek = (int)start.DayOfWeek;
        var schedule = await _db.ResourceSchedules.AsNoTracking()
            .FirstOrDefaultAsync(s => s.ResourceId == resourceId && s.DayOfWeek == dayOfWeek);

        if (schedule?.LunchBreakStart != null && schedule.LunchBreakEnd != null)
        {
            var breakStart = start.Date.Add(schedule.LunchBreakStart.Value);
            var breakEnd = start.Date.Add(schedule.LunchBreakEnd.Value);
            if (start < breakEnd && end > breakStart)
                return $"This time falls within the resource's lunch break ({schedule.LunchBreakStart:hh\\:mm}-{schedule.LunchBreakEnd:hh\\:mm}).";
        }

        var maxHours = schedule?.MaxDailyBookedHours ?? 8m;
        var existingBookingsToday = await _db.Bookings.AsNoTracking()
            .Where(b => b.ResourceId == resourceId
                && b.DeletedAt == null
                && b.Status != Models.BookingStatus.Cancelled
                && b.Status != Models.BookingStatus.Rejected
                && b.StartTime.Date == start.Date
                && (excludeBookingId == null || b.Id != excludeBookingId))
            .Select(b => new { b.StartTime, b.EndTime })
            .ToListAsync();

        var existingMinutes = existingBookingsToday.Sum(b => (b.EndTime - b.StartTime).TotalMinutes);
        var totalHours = (decimal)(existingMinutes + (end - start).TotalMinutes) / 60m;

        if (totalHours > maxHours)
            return $"This resource is limited to {maxHours} booked hour(s) per day; this booking would bring the total to {totalHours:0.#} hour(s).";

        return null;
    }

    // ── FR-B7: QR Check-in (simplified - uses Booking ID) ─────
    /// <summary>FR-B7: checks a booking in when staff scans its QR code (the raw booking ID).</summary>
    [HttpPost("{id}/checkin")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> CheckIn(Guid id)
    {
        var booking = await _db.Bookings.FindAsync(id);
        if (booking == null || booking.DeletedAt != null) return NotFound();
        booking.Status = Models.BookingStatus.CheckedIn;
        booking.CheckInAt = DateTime.UtcNow;
        booking.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        return Ok(new { message = "Patient checked in.", booking.Status });
    }
    

    // ── Equipment reservation (cross-component link to Equipment) ─────
    // See EquipmentController.cs. Distinct from the Inventory module.
    /// <summary>Reserves equipment against a booking, decrementing stock.</summary>
    [HttpPost("{id}/equipment")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> ReserveEquipment(Guid id, [FromBody] ReserveEquipmentDto dto)
    {
        var booking = await _db.Bookings.FindAsync(id);
        if (booking == null || booking.DeletedAt != null) return NotFound();

        var item = await _db.EquipmentItems.FirstOrDefaultAsync(i => i.Id == dto.EquipmentItemId);
        if (item == null) return NotFound(new { message = "Equipment item not found." });
        if (item.CurrentStock < dto.Quantity)
            return BadRequest(new { message = $"Only {item.CurrentStock} {item.Unit} of {item.Name} in stock." });

        item.CurrentStock -= dto.Quantity;
        var reservation = new EquipmentReservation
        {
            TenantId = booking.TenantId,
            BookingId = id,
            EquipmentItemId = dto.EquipmentItemId,
            Quantity = dto.Quantity
        };
        _db.EquipmentReservations.Add(reservation);
        await _db.SaveChangesAsync();

        return Ok(new { reservation.Id, item.Name, reservation.Quantity, RemainingStock = item.CurrentStock });
    }

    /// <summary>Releases a previously reserved equipment item, restoring its stock.</summary>
    [HttpDelete("{id}/equipment/{reservationId}")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> ReleaseEquipment(Guid id, Guid reservationId)
    {
        var reservation = await _db.EquipmentReservations
            .FirstOrDefaultAsync(r => r.Id == reservationId && r.BookingId == id);
        if (reservation == null) return NotFound();

        var item = await _db.EquipmentItems.FindAsync(reservation.EquipmentItemId);
        if (item != null) item.CurrentStock += reservation.Quantity;

        _db.EquipmentReservations.Remove(reservation);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // ── FR-B8: Update status ───────────────────────────────────
    /// <summary>FR-B8: sets a booking's status (e.g. staff marking it InProgress/Completed/NoShow).</summary>
    [HttpPut("{id}/status")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> UpdateStatus(Guid id, [FromBody] UpdateStatusDto dto)
    {
        var booking = await _db.Bookings.FindAsync(id);
        if (booking == null || booking.DeletedAt != null) return NotFound();

        booking.Status = dto.Status;
        booking.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(booking);
    }

    // ── FR-B8: Doctor's schedule ──────────────────────────────
    /// <summary>FR-B8: returns the caller's own schedule (bookings on the resource(s) linked to their login).</summary>
    [HttpGet("my-schedule")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> GetMySchedule([FromQuery] DateTime? date)
    {
        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (userIdClaim == null || !Guid.TryParse(userIdClaim, out var userId)) return Unauthorized();

        // Filtered to the resource(s) linked to this login (FR-B8) — previously
        // this ignored userId entirely and returned every tenant booking.
        var query = _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Include(b => b.BookingType)
            .Where(b => b.DeletedAt == null
                && b.Status != Models.BookingStatus.Cancelled
                && b.Resource.LinkedUserId == userId)
            .AsQueryable();

        if (date.HasValue)
        {
            var day = DateTimeUtil.AsUtc(date.Value).Date;
            query = query.Where(b => b.StartTime.Date == day);
        }

        var bookings = await query
            .OrderBy(b => b.StartTime)
            .Select(b => new
            {
                b.Id,
                b.TenantId,
                b.ResourceId,
                ResourceName = b.Resource.Name,
                b.BookingTypeId,
                BookingTypeName = b.BookingType.Name,
                ColorHex = b.BookingType.ColorHex,
                BookingUnit = b.BookingType.BookingUnit,
                b.BookedBy,
                b.BookedFor,
                b.Title,
                b.Notes,
                b.StartTime,
                b.EndTime,
                Status = b.Status.ToString(),
                Priority = b.Priority.ToString(),
                b.AttendeeCount,
                b.TotalCost,
                b.CheckInAt,
                b.CreatedAt
            })
            .ToListAsync();

        return Ok(bookings);
    }

    // ── Existing CRUD ───────────────────────────────────────────
    /// <summary>Reports no-show/completion/cancellation counts and rates for a tenant over a date range.</summary>
    [HttpGet("reports/no-shows")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> GetNoShowStats([FromQuery] Guid tenantId, [FromQuery] DateTime from, [FromQuery] DateTime to)
    {
        from = DateTimeUtil.AsUtc(from);
        to = DateTimeUtil.AsUtc(to);

        var bookings = await _db.Bookings
            .Where(b => b.TenantId == tenantId && b.StartTime >= from && b.StartTime <= to && b.DeletedAt == null)
            .ToListAsync();

        var total = bookings.Count;
        var noShows = bookings.Count(b => b.Status == Models.BookingStatus.NoShow);
        var completed = bookings.Count(b => b.Status == Models.BookingStatus.Completed);
        var cancelled = bookings.Count(b => b.Status == Models.BookingStatus.Cancelled);

        return Ok(new
        {
            total,
            noShows,
            completed,
            cancelled,
            noShowRate = total > 0 ? (noShows / (double)total * 100) : 0,
            utilizationRate = total > 0 ? (completed / (double)total * 100) : 0
        });
    }

    // ── GET /api/bookings/my-no-show-rate ───────────────────────
    // Customer-scoped historical no-show rate, consumed by the agentic
    // pipeline's predict_no_show_probability tool (a real historical-rate
    // heuristic, not a trained model) as an informational validation note —
    // never used to deny a booking. Same NoShow data GetNoShowStats already
    // uses, but scoped to the caller's own bookings, matching the existing
    // "a Customer only ever sees their own" pattern (see GetAll).
    /// <summary>The calling customer's own historical no-show rate, for the agentic pipeline's informational risk note.</summary>
    [HttpGet("my-no-show-rate")]
    public async Task<IActionResult> GetMyNoShowRate()
    {
        var (callerId, _) = CallerIdentity();
        if (callerId == null) return Unauthorized();

        var past = await _db.Bookings.AsNoTracking()
            .Where(b => b.BookedBy == callerId && b.DeletedAt == null
                && (b.Status == Models.BookingStatus.Completed || b.Status == Models.BookingStatus.NoShow))
            .CountAsync();
        var noShows = await _db.Bookings.AsNoTracking()
            .Where(b => b.BookedBy == callerId && b.DeletedAt == null && b.Status == Models.BookingStatus.NoShow)
            .CountAsync();

        return Ok(new
        {
            totalPast = past,
            noShows,
            rate = past > 0 ? Math.Round(noShows / (double)past, 3) : 0.0
        });
    }

    // ── GET /api/bookings?tenantId=&type=&resourceId=&branchId=&dateFrom=&dateTo=&status=&page=&pageSize=
    /// <summary>Lists bookings with tenant/type/resource/branch/date/status filters, paginated. Customers only ever see their own.</summary>
    [HttpGet]
    public async Task<IActionResult> GetAll(
        [FromQuery] Guid? tenantId,
        [FromQuery(Name = "type")] Guid? bookingTypeId,
        [FromQuery] Guid? resourceId,
        [FromQuery] Guid? branchId,
        [FromQuery] Guid? bookedBy,
        [FromQuery] DateTime? dateFrom,
        [FromQuery] DateTime? dateTo,
        [FromQuery] string? status,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);

        // FR-C3: a Customer can only ever list their own bookings — any
        // bookedBy they pass is overridden, not just defaulted, so one
        // patient can't page through another patient's appointments.
        var (callerId, callerRole) = CallerIdentity();
        if (callerId == null) return Unauthorized();
        if (callerRole == Roles.Customer) bookedBy = callerId;

        var query = _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Include(b => b.BookingType)
            .Where(b => b.DeletedAt == null)
            .AsQueryable();

        if (tenantId.HasValue) query = query.Where(b => b.TenantId == tenantId);
        if (bookingTypeId.HasValue) query = query.Where(b => b.BookingTypeId == bookingTypeId);
        if (resourceId.HasValue) query = query.Where(b => b.ResourceId == resourceId);
        if (branchId.HasValue) query = query.Where(b => b.Resource.BranchId == branchId);
        if (bookedBy.HasValue) query = query.Where(b => b.BookedBy == bookedBy);
        if (dateFrom.HasValue) query = query.Where(b => b.StartTime >= DateTimeUtil.AsUtc(dateFrom.Value));
        if (dateTo.HasValue) query = query.Where(b => b.StartTime <= DateTimeUtil.AsUtc(dateTo.Value));
        if (!string.IsNullOrEmpty(status) && Enum.TryParse<Models.BookingStatus>(status, true, out var s))
            query = query.Where(b => b.Status == s);

        var total = await query.CountAsync();
        var items = await query
            .OrderBy(b => b.StartTime)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(b => new
            {
                b.Id,
                b.TenantId,
                b.ResourceId,
                ResourceName = b.Resource.Name,
                b.BookingTypeId,
                BookingTypeName = b.BookingType.Name,
                ColorHex = b.BookingType.ColorHex,
                BookingUnit = b.BookingType.BookingUnit,
                b.BookedBy,
                b.BookedFor,
                b.Title,
                b.Notes,
                b.StartTime,
                b.EndTime,
                Status = b.Status.ToString(),
                Priority = b.Priority.ToString(),
                b.AttendeeCount,
                b.TotalCost,
                b.CreatedAt
            })
            .ToListAsync();

        return Ok(new
        {
            items,
            total,
            page,
            pageSize,
            totalPages = (int)Math.Ceiling(total / (double)pageSize)
        });
    }

    // ── POST /api/bookings/{id}/remind ─────────────────────────
    /// <summary>Sends an on-demand reminder for a booking over the given channel (defaults to Email).</summary>
    [HttpPost("{id}/remind")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> SendReminder(Guid id, [FromBody] SendReminderDto? dto)
    {
        var booking = await _db.Bookings.FirstOrDefaultAsync(b => b.Id == id);
        if (booking == null || booking.DeletedAt != null) return NotFound();
        if (booking.Status == Models.BookingStatus.Cancelled)
            return BadRequest(new { message = "Cannot send a reminder for a cancelled booking." });

        var channel = string.IsNullOrWhiteSpace(dto?.Channel) ? "Email" : dto!.Channel!;

        await _reminderSender.SendAsync(booking, channel);

        var reminder = new BookingReminder
        {
            BookingId = id,
            Channel = channel,
            Status = "Sent",
            SentAt = DateTime.UtcNow
        };

        _db.BookingReminders.Add(reminder);
        booking.ReminderSent = true;
        booking.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        return Ok(new { message = $"Reminder sent via {channel}.", reminder.Id, reminder.SentAt });
    }

    // ── POST /api/bookings/bulk-schedule ───────────────────────
    // Batches affecting more than 20 bookings are routed to the Validation/Safety
    // Agent for human approval instead of being applied directly (per the
    // assignment's human-approval threshold for high-impact schedule changes).
    /// <summary>Creates many bookings at once; batches over 20 require manager approval via an AgentWorkflow.</summary>
    [HttpPost("bulk-schedule")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> BulkSchedule([FromBody] BulkScheduleDto dto)
    {
        if (dto.Bookings.Count == 0)
            return BadRequest(new { message = "No bookings provided." });

        var outcome = await RouteOrCreateBatchAsync(dto.TenantId, $"Bulk-schedule {dto.Bookings.Count} bookings", dto.Bookings);

        if (outcome.RequiresApproval)
        {
            return Accepted(new
            {
                message = "This change affects more than 20 bookings and requires manager approval before it is applied.",
                workflowId = outcome.WorkflowId
            });
        }

        var succeeded = outcome.Results.Count(r => r.Success);
        return Ok(new
        {
            total = dto.Bookings.Count,
            succeeded,
            failed = dto.Bookings.Count - succeeded,
            results = outcome.Results
        });
    }

    // ── FR-B9: recurring appointments (e.g. weekly physiotherapy) ─────────
    /// <summary>FR-B9: creates a recurring booking series (e.g. weekly physiotherapy) up to 60 occurrences.</summary>
    [HttpPost("recurring")]
    public async Task<IActionResult> CreateRecurring([FromBody] CreateRecurringBookingDto dto)
    {
        if (dto.DurationMinutes <= 0)
            return BadRequest(new { message = "DurationMinutes must be positive." });

        var firstStart = DateTimeUtil.AsUtc(dto.FirstStartTime);
        var endDate = DateTimeUtil.AsUtc(dto.EndDate).Date;
        if (endDate < firstStart.Date)
            return BadRequest(new { message = "EndDate must be on or after FirstStartTime." });

        var daysOfWeek = (dto.DaysOfWeek == null || dto.DaysOfWeek.Count == 0)
            ? new List<int> { (int)firstStart.DayOfWeek }
            : dto.DaysOfWeek;

        const int maxOccurrences = 60;
        var occurrences = new List<(DateTime Start, DateTime End)>();
        var cursorDate = firstStart.Date;
        while (cursorDate <= endDate && occurrences.Count < maxOccurrences)
        {
            if (daysOfWeek.Contains((int)cursorDate.DayOfWeek))
            {
                var occStart = cursorDate.Add(firstStart.TimeOfDay);
                if (occStart >= firstStart)
                    occurrences.Add((occStart, occStart.AddMinutes(dto.DurationMinutes)));
            }
            cursorDate = cursorDate.AddDays(1);
        }

        if (occurrences.Count == 0)
            return BadRequest(new { message = "No occurrences fall within the given range." });

        var items = occurrences
            .Select(o => new BulkBookingItem(dto.ResourceId, dto.BookingTypeId, dto.BookedBy, dto.Title, o.Start, o.End, dto.Notes))
            .ToList();

        var outcome = await RouteOrCreateBatchAsync(dto.TenantId, $"Recurring booking: {occurrences.Count} occurrence(s)", items);

        if (outcome.RequiresApproval)
        {
            return Accepted(new
            {
                message = "This recurring series creates more than 20 bookings and requires manager approval before it is applied.",
                workflowId = outcome.WorkflowId,
                totalOccurrences = occurrences.Count
            });
        }

        var created = outcome.Results.Where(r => r.Success && r.BookingId.HasValue).ToList();
        if (created.Count > 0)
        {
            _db.RecurringPatterns.Add(new RecurringPattern
            {
                BookingId = created[0].BookingId,
                Frequency = "Weekly",
                EndDate = endDate,
                DaysOfWeek = daysOfWeek
            });
            await _db.SaveChangesAsync();
        }

        return Ok(new
        {
            totalRequested = occurrences.Count,
            created = created.Count,
            skippedConflicts = outcome.Results.Count(r => !r.Success),
            results = outcome.Results
        });
    }

    // Shared by BulkSchedule and CreateRecurring: routes batches of more than
    // 20 bookings to manager approval (AgentWorkflow), otherwise creates them
    // directly with per-item conflict checking.
    private async Task<BatchOutcome> RouteOrCreateBatchAsync(Guid tenantId, string objective, List<BulkBookingItem> items)
    {
        if (items.Count > 20)
        {
            var workflow = new AgentWorkflow
            {
                TenantId = tenantId,
                Objective = objective,
                PlanJson = JsonSerializer.Serialize(items),
                Status = "AwaitingApproval",
                ApprovalStatus = "Pending"
            };
            _db.AgentWorkflows.Add(workflow);
            NotificationHelper.Queue(_db, tenantId, null, "WorkflowApproval",
                "Plan needs approval", $"\"{objective}\" affects {items.Count} booking(s) and needs your approval.");
            await _db.SaveChangesAsync();
            return new BatchOutcome(true, workflow.Id, new List<BulkItemResult>());
        }

        var results = new List<BulkItemResult>();
        foreach (var item in items)
        {
            var itemStart = DateTimeUtil.AsUtc(item.StartTime);
            var itemEnd = DateTimeUtil.AsUtc(item.EndTime);

            if (itemEnd <= itemStart)
            {
                results.Add(new BulkItemResult(null, item.ResourceId, itemStart, false, "EndTime must be after StartTime."));
                continue;
            }

            if (await HasConflictAsync(item.ResourceId, itemStart, itemEnd, excludeRejected: true))
            {
                results.Add(new BulkItemResult(null, item.ResourceId, itemStart, false, "Conflicts with an existing booking."));
                continue;
            }

            var itemRuleError = await ValidateBusinessRulesAsync(item.ResourceId, itemStart, itemEnd, item.BookingTypeId);
            if (itemRuleError != null)
            {
                results.Add(new BulkItemResult(null, item.ResourceId, itemStart, false, itemRuleError));
                continue;
            }

            var booking = new Booking
            {
                TenantId = tenantId,
                ResourceId = item.ResourceId,
                BookingTypeId = item.BookingTypeId,
                BookedBy = item.BookedBy,
                Title = item.Title,
                Notes = item.Notes,
                StartTime = itemStart,
                EndTime = itemEnd,
                Status = Models.BookingStatus.Confirmed,
                Priority = Models.BookingPriority.Normal
            };
            _db.Bookings.Add(booking);
            results.Add(new BulkItemResult(booking.Id, item.ResourceId, itemStart, true, null));
        }

        await _db.SaveChangesAsync();
        return new BatchOutcome(false, null, results);
    }

    private record BatchOutcome(bool RequiresApproval, Guid? WorkflowId, List<BulkItemResult> Results);

    // ── GET /api/bookings/conflicts ─────────────────────────────
    // Detects overlapping bookings on the same resource. Under normal operation
    // conflict checks at creation time prevent this, so any hits here point to a
    // data-integrity issue (e.g. a bulk import or a race condition) worth reviewing.
    /// <summary>Detects overlapping bookings on the same resource - normally empty; a data-integrity check.</summary>
    [HttpGet("conflicts")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> GetConflicts(
        [FromQuery] Guid tenantId,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to)
    {
        var query = _db.Bookings.AsNoTracking()
            .Include(b => b.Resource)
            .Where(b => b.TenantId == tenantId
                && b.DeletedAt == null
                && b.Status != Models.BookingStatus.Cancelled
                && b.Status != Models.BookingStatus.Rejected);

        if (from.HasValue) query = query.Where(b => b.EndTime >= DateTimeUtil.AsUtc(from.Value));
        if (to.HasValue) query = query.Where(b => b.StartTime <= DateTimeUtil.AsUtc(to.Value));

        var bookings = await query
            .Select(b => new
            {
                b.Id,
                b.ResourceId,
                ResourceName = b.Resource.Name,
                b.Title,
                b.StartTime,
                b.EndTime
            })
            .ToListAsync();

        var conflicts = new List<object>();
        foreach (var group in bookings.GroupBy(b => b.ResourceId))
        {
            var sorted = group.OrderBy(b => b.StartTime).ToList();
            for (var i = 0; i < sorted.Count - 1; i++)
            {
                for (var j = i + 1; j < sorted.Count; j++)
                {
                    if (sorted[j].StartTime >= sorted[i].EndTime) break; // sorted by start; no overlap possible beyond this point
                    conflicts.Add(new
                    {
                        resourceId = group.Key,
                        resourceName = sorted[i].ResourceName,
                        bookingA = new { sorted[i].Id, sorted[i].Title, sorted[i].StartTime, sorted[i].EndTime },
                        bookingB = new { sorted[j].Id, sorted[j].Title, sorted[j].StartTime, sorted[j].EndTime }
                    });
                }
            }
        }

        return Ok(new { totalConflicts = conflicts.Count, conflicts });
    }

    /// <summary>Gets a single booking by id.</summary>
    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        // Projected, not the raw entity + Include - Resource.Bookings cycles
        // back to this same booking, and System.Text.Json has no default
        // cycle handling, so returning the tracked/included entity directly
        // 500s. GetAll/GetMySchedule already avoid this the same way.
        var booking = await _db.Bookings.AsNoTracking()
            .Where(b => b.Id == id && b.DeletedAt == null)
            .Select(b => new
            {
                b.Id,
                b.TenantId,
                b.ResourceId,
                ResourceName = b.Resource.Name,
                b.BookingTypeId,
                BookingTypeName = b.BookingType.Name,
                ColorHex = b.BookingType.ColorHex,
                BookingUnit = b.BookingType.BookingUnit,
                b.BookedBy,
                b.BookedFor,
                b.Title,
                b.Notes,
                b.StartTime,
                b.EndTime,
                Status = b.Status.ToString(),
                Priority = b.Priority.ToString(),
                b.AttendeeCount,
                b.TotalCost,
                b.CheckInAt,
                b.FormData,
                b.CreatedAt
            })
            .FirstOrDefaultAsync();
        if (booking == null) return NotFound();
        return Ok(booking);
    }

    /// <summary>Partially updates a booking's time/title/notes/status/priority/attendee count.</summary>
    [HttpPut("{id}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateBookingDto dto)
    {
        var booking = await _db.Bookings.FindAsync(id);
        if (booking == null || booking.DeletedAt != null) return NotFound();

        if (dto.StartTime.HasValue) booking.StartTime = DateTimeUtil.AsUtc(dto.StartTime.Value);
        if (dto.EndTime.HasValue) booking.EndTime = DateTimeUtil.AsUtc(dto.EndTime.Value);
        if (!string.IsNullOrEmpty(dto.Title)) booking.Title = dto.Title;
        if (dto.Notes != null) booking.Notes = dto.Notes;
        if (dto.Status.HasValue) booking.Status = dto.Status.Value;
        if (dto.Priority.HasValue) booking.Priority = dto.Priority.Value;
        if (dto.AttendeeCount.HasValue) booking.AttendeeCount = dto.AttendeeCount.Value;
        booking.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(booking);
    }

    /// <summary>Soft-deletes a booking.</summary>
    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var booking = await _db.Bookings.FindAsync(id);
        if (booking == null || booking.DeletedAt != null) return NotFound();
        booking.DeletedAt = DateTime.UtcNow;
        booking.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }
}

// ── DTOs ──────────────────────────────────────────────────────
public record CreateBookingDto(
    Guid TenantId,
    Guid ResourceId,
    Guid BookingTypeId,
    Guid BookedBy,
    DateTime StartTime,
    DateTime EndTime,
    string? Title,
    string? Notes,
    Guid? BookedFor,
    BookingPriority Priority,
    int? AttendeeCount,
    // Tourism sub-type-specific fields collected by the booking wizard's
    // extra step (certificationLevel, bedCount, driverIncluded, ...) - see
    // docs/tourism-business-template.md. Raw JSON, not parsed server-side.
    string? FormData
);

public record UpdateBookingDto(
    DateTime? StartTime,
    DateTime? EndTime,
    string? Title,
    string? Notes,
    BookingStatus? Status,
    BookingPriority? Priority,
    int? AttendeeCount
);

public record RescheduleDto(DateTime NewStartTime, DateTime NewEndTime);
public record UpdateStatusDto(BookingStatus Status, string? DoctorNotes);
public record SendReminderDto(string? Channel);

public record BulkBookingItem(
    Guid ResourceId,
    Guid BookingTypeId,
    Guid BookedBy,
    string? Title,
    DateTime StartTime,
    DateTime EndTime,
    string? Notes = null
);
public record BulkScheduleDto(Guid TenantId, List<BulkBookingItem> Bookings);

public record CreateRecurringBookingDto(
    Guid TenantId,
    Guid ResourceId,
    Guid BookingTypeId,
    Guid BookedBy,
    string? Title,
    string? Notes,
    DateTime FirstStartTime,
    int DurationMinutes,
    List<int>? DaysOfWeek,
    DateTime EndDate
);
public record BulkItemResult(Guid? BookingId, Guid ResourceId, DateTime StartTime, bool Success, string? Reason);
public record ReserveEquipmentDto(Guid EquipmentItemId, decimal Quantity);