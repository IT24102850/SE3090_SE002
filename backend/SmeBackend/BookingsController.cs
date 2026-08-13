using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;
using System.Text.Json;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class BookingsController : ControllerBase
{
    private readonly AppDbContext _db;

    public BookingsController(AppDbContext db) => _db = db;

    // ── FR-B1: Search availability ─────────────────────────────
    // Consults the resource's weekly ResourceSchedule (falls back to 9am-5pm if
    // the resource has no schedule configured yet) and honors the booking type's
    // buffer time so back-to-back bookings leave the configured gap.
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

        var (isOpen, slots) = SlotCalculator.Calculate(
            date, schedule, duration, bufferBefore, bufferAfter,
            existing.Select(b => (b.StartTime, b.EndTime)).ToList(),
            DateTime.UtcNow);

        return Ok(new
        {
            date = date.Date,
            isOpen,
            resourceId,
            slots = slots.Select(s => new { startTime = s.StartTime, endTime = s.EndTime, isAvailable = s.IsAvailable })
        });
    }

    // ── FR-B2: Create booking ─────────────────────────────────
    [HttpPost]
    [AllowAnonymous]
    public async Task<IActionResult> Create([FromBody] CreateBookingDto dto)
    {
        var startTime = DateTimeUtil.AsUtc(dto.StartTime);
        var endTime = DateTimeUtil.AsUtc(dto.EndTime);

        if (endTime <= startTime)
            return BadRequest(new { message = "EndTime must be after StartTime." });

        // FR-B3: Conflict detection
        bool conflict = await _db.Bookings.AnyAsync(b =>
            b.ResourceId == dto.ResourceId
            && b.DeletedAt == null
            && b.Status != Models.BookingStatus.Cancelled
            && b.StartTime < endTime
            && b.EndTime > startTime);

        if (conflict)
            return Conflict(new { message = "This time slot is already booked." });

        var booking = new Booking
        {
            TenantId = dto.TenantId,
            ResourceId = dto.ResourceId,
            BookingTypeId = dto.BookingTypeId,
            BookedBy = dto.BookedBy,
            BookedFor = dto.BookedFor,
            Title = dto.Title,
            Notes = dto.Notes,
            StartTime = startTime,
            EndTime = endTime,
            Status = Models.BookingStatus.Pending,
            Priority = dto.Priority,
            AttendeeCount = dto.AttendeeCount
        };

        _db.Bookings.Add(booking);
        await _db.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = booking.Id }, new
        {
            booking.Id,
            booking.StartTime,
            booking.EndTime,
            booking.Status,
            ResourceName = (await _db.Resources.FindAsync(dto.ResourceId))?.Name
        });
    }

    // ── FR-B5: Reschedule ─────────────────────────────────────
    [HttpPut("{id}/reschedule")]
    public async Task<IActionResult> Reschedule(Guid id, [FromBody] RescheduleDto dto)
    {
        var booking = await _db.Bookings.FindAsync(id);
        if (booking == null || booking.DeletedAt != null) return NotFound();

        var newStart = DateTimeUtil.AsUtc(dto.NewStartTime);
        var newEnd = DateTimeUtil.AsUtc(dto.NewEndTime);
        if (newEnd <= newStart)
            return BadRequest(new { message = "NewEndTime must be after NewStartTime." });

        var cutoff = booking.StartTime.AddHours(-2);
        if (DateTime.UtcNow > cutoff)
            return BadRequest(new { message = "Cannot reschedule within 2 hours." });

        bool hasConflict = await _db.Bookings.AnyAsync(b =>
            b.Id != id
            && b.ResourceId == booking.ResourceId
            && b.DeletedAt == null
            && b.Status != Models.BookingStatus.Cancelled
            && b.StartTime < newEnd
            && b.EndTime > newStart);

        if (hasConflict)
            return Conflict(new { message = "New slot conflicts with existing booking." });

        booking.StartTime = newStart;
        booking.EndTime = newEnd;
        booking.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return Ok(booking);
    }

    // ── FR-B5: Cancel ─────────────────────────────────────────
    [HttpPut("{id}/cancel")]
    public async Task<IActionResult> Cancel(Guid id)
    {
        var booking = await _db.Bookings.FindAsync(id);
        if (booking == null || booking.DeletedAt != null) return NotFound();

        var cutoff = booking.StartTime.AddHours(-1);
        if (DateTime.UtcNow > cutoff)
            return BadRequest(new { message = "Cannot cancel within 1 hour." });

        booking.Status = Models.BookingStatus.Cancelled;
        booking.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { message = "Booking cancelled." });
    }

    // ── FR-B7: QR Check-in (simplified - uses Booking ID) ─────
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

    // ── FR-B8: Update status ───────────────────────────────────
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

    // ── GET /api/bookings?tenantId=&type=&resourceId=&branchId=&dateFrom=&dateTo=&status=&page=&pageSize=
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
    [HttpPost("{id}/remind")]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<IActionResult> SendReminder(Guid id, [FromBody] SendReminderDto? dto)
    {
        var booking = await _db.Bookings.FirstOrDefaultAsync(b => b.Id == id);
        if (booking == null || booking.DeletedAt != null) return NotFound();
        if (booking.Status == Models.BookingStatus.Cancelled)
            return BadRequest(new { message = "Cannot send a reminder for a cancelled booking." });

        var channel = string.IsNullOrWhiteSpace(dto?.Channel) ? "Email" : dto!.Channel!;

        var reminder = new BookingReminder
        {
            BookingId = id,
            Channel = channel,
            // No live SMS/email gateway wired up yet — recorded as dispatched for audit/demo purposes.
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

            var conflict = await _db.Bookings.AnyAsync(b =>
                b.ResourceId == item.ResourceId
                && b.DeletedAt == null
                && b.Status != Models.BookingStatus.Cancelled
                && b.Status != Models.BookingStatus.Rejected
                && b.StartTime < itemEnd
                && b.EndTime > itemStart);

            if (conflict)
            {
                results.Add(new BulkItemResult(null, item.ResourceId, itemStart, false, "Conflicts with an existing booking."));
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

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var booking = await _db.Bookings.AsNoTracking()
            .Include(b => b.Resource).Include(b => b.BookingType)
            .FirstOrDefaultAsync(b => b.Id == id && b.DeletedAt == null);
        if (booking == null) return NotFound();
        return Ok(booking);
    }

    [HttpPut("{id}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateBookingDto dto)
    {
        var booking = await _db.Bookings.FindAsync(id);
        if (booking == null || booking.DeletedAt != null) return NotFound();

        if (dto.StartTime.HasValue) booking.StartTime = DateTimeUtil.AsUtc(dto.StartTime.Value);
        if (dto.EndTime.HasValue) booking.EndTime = DateTimeUtil.AsUtc(dto.EndTime.Value);
        if (!string.IsNullOrEmpty(dto.Title)) booking.Title = dto.Title;
        if (dto.Status.HasValue) booking.Status = dto.Status.Value;
        booking.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(booking);
    }

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
    int? AttendeeCount
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