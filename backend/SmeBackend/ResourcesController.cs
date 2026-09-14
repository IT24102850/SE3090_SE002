using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ResourcesController : ControllerBase
{
    private readonly AppDbContext _db;
    public ResourcesController(AppDbContext db) => _db = db;

    // GET /api/resources?tenantId=&branchId=&category=&status=&search=&specialty=&page=&pageSize=
    [HttpGet]
    public async Task<IActionResult> GetResources(
        [FromQuery] Guid tenantId,
        [FromQuery] Guid? branchId,
        [FromQuery] string? category,
        [FromQuery] string? status,
        [FromQuery] string? search,
        [FromQuery] string? specialty,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var query = _db.Resources.AsNoTracking().Where(r => r.TenantId == tenantId);

        if (branchId.HasValue) query = query.Where(r => r.BranchId == branchId);
        if (!string.IsNullOrEmpty(category) && Enum.TryParse<ResourceCategory>(category, true, out var cat))
            query = query.Where(r => r.Category == cat);
        if (!string.IsNullOrEmpty(status) && Enum.TryParse<ResourceStatus>(status, true, out var st))
            query = query.Where(r => r.Status == st);
        if (!string.IsNullOrEmpty(search))
            query = query.Where(r => r.Name.Contains(search) || (r.Code != null && r.Code.Contains(search)));
        if (!string.IsNullOrEmpty(specialty))
            query = query.Where(r => r.Specialty != null && r.Specialty.Contains(specialty));

        var total = await query.CountAsync();
        var items = await query
            .OrderBy(r => r.Name)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new
            {
                r.Id,
                r.TenantId,
                r.BranchId,
                r.Name,
                r.Code,
                Category = r.Category.ToString(),
                Status = r.Status.ToString(),
                r.Description,
                r.Capacity,
                r.HourlyRate,
                r.Specialty,
                r.LinkedUserId,
                r.CustomAttributes,
                r.CreatedAt
            })
            .ToListAsync();

        return Ok(new { items, total, page, pageSize, totalPages = (int)Math.Ceiling(total / (double)pageSize) });
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var resource = await _db.Resources.AsNoTracking().FirstOrDefaultAsync(r => r.Id == id);
        if (resource == null) return NotFound();
        return Ok(resource);
    }

    [HttpPost]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> CreateResource([FromBody] CreateResourceDto dto)
    {
        if (!string.IsNullOrEmpty(dto.Code))
        {
            var codeTaken = await _db.Resources.AnyAsync(r => r.Code == dto.Code);
            if (codeTaken) return Conflict(new { message = "Resource code already in use." });
        }

        var resource = new Resource
        {
            TenantId = dto.TenantId,
            BranchId = dto.BranchId,
            Name = dto.Name,
            Code = dto.Code,
            Category = dto.Category,
            Description = dto.Description,
            Capacity = dto.Capacity,
            HourlyRate = dto.HourlyRate,
            Specialty = dto.Specialty,
            LinkedUserId = dto.LinkedUserId,
            CustomAttributes = dto.CustomAttributes,
            LocationMetadata = dto.LocationMetadata,
            Status = ResourceStatus.Available
        };

        _db.Resources.Add(resource);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetById), new { id = resource.Id }, resource);
    }

    [HttpPut("{id}")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> UpdateResource(Guid id, [FromBody] UpdateResourceDto dto)
    {
        var resource = await _db.Resources.FindAsync(id);
        if (resource == null) return NotFound();

        if (!string.IsNullOrEmpty(dto.Name)) resource.Name = dto.Name;
        if (dto.BranchId.HasValue) resource.BranchId = dto.BranchId;
        if (dto.Category.HasValue) resource.Category = dto.Category.Value;
        if (dto.Status.HasValue) resource.Status = dto.Status.Value;
        if (dto.Description != null) resource.Description = dto.Description;
        if (dto.Capacity.HasValue) resource.Capacity = dto.Capacity;
        if (dto.HourlyRate.HasValue) resource.HourlyRate = dto.HourlyRate;
        if (dto.Specialty != null) resource.Specialty = dto.Specialty;
        if (dto.LinkedUserId.HasValue) resource.LinkedUserId = dto.LinkedUserId;
        if (dto.CustomAttributes != null) resource.CustomAttributes = dto.CustomAttributes;
        if (dto.LocationMetadata != null) resource.LocationMetadata = dto.LocationMetadata;
        resource.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return Ok(resource);
    }

    [HttpDelete("{id}")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> DeleteResource(Guid id)
    {
        var resource = await _db.Resources.FindAsync(id);
        if (resource == null) return NotFound();

        var hasFutureBookings = await _db.Bookings.AnyAsync(b =>
            b.ResourceId == id && b.DeletedAt == null &&
            b.Status != BookingStatus.Cancelled && b.Status != BookingStatus.Completed &&
            b.StartTime > DateTime.UtcNow);
        if (hasFutureBookings)
            return BadRequest(new { message = "Cannot delete a resource with upcoming bookings." });

        resource.DeletedAt = DateTime.UtcNow;
        resource.Status = ResourceStatus.Archived;
        resource.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // ── Weekly working-hours schedule ──────────────────────────
    [HttpGet("{id}/schedule")]
    public async Task<IActionResult> GetResourceSchedule(Guid id)
    {
        var exists = await _db.Resources.AnyAsync(r => r.Id == id);
        if (!exists) return NotFound();

        var days = await _db.ResourceSchedules.AsNoTracking()
            .Where(s => s.ResourceId == id)
            .OrderBy(s => s.DayOfWeek)
            .Select(s => new
            {
                s.DayOfWeek,
                s.StartTime,
                s.EndTime,
                s.IsAvailable,
                s.LunchBreakStart,
                s.LunchBreakEnd,
                s.MaxDailyBookedHours
            })
            .ToListAsync();

        return Ok(days);
    }

    [HttpPut("{id}/schedule")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> UpdateResourceSchedule(Guid id, [FromBody] SetScheduleDto dto)
    {
        var resource = await _db.Resources.AnyAsync(r => r.Id == id);
        if (!resource) return NotFound();

        foreach (var day in dto.Days)
        {
            if (day.DayOfWeek < 0 || day.DayOfWeek > 6)
                return BadRequest(new { message = $"Invalid DayOfWeek {day.DayOfWeek}. Must be 0-6." });
            if (day.IsAvailable && day.EndTime <= day.StartTime)
                return BadRequest(new { message = $"EndTime must be after StartTime for day {day.DayOfWeek}." });
        }

        var existing = await _db.ResourceSchedules.Where(s => s.ResourceId == id).ToListAsync();
        _db.ResourceSchedules.RemoveRange(existing);

        foreach (var day in dto.Days)
        {
            _db.ResourceSchedules.Add(new ResourceSchedule
            {
                ResourceId = id,
                DayOfWeek = day.DayOfWeek,
                StartTime = day.StartTime,
                EndTime = day.EndTime,
                IsAvailable = day.IsAvailable,
                LunchBreakStart = day.LunchBreakStart,
                LunchBreakEnd = day.LunchBreakEnd,
                MaxDailyBookedHours = day.MaxDailyBookedHours
            });
        }

        await _db.SaveChangesAsync();
        return Ok(new { message = "Schedule updated.", days = dto.Days.Count });
    }

    // ── FR-AS6: one-off closed dates (holidays/closures) ───────
    [HttpGet("{id}/schedule-exceptions")]
    public async Task<IActionResult> GetScheduleExceptions(Guid id)
    {
        var exceptions = await _db.ResourceScheduleExceptions.AsNoTracking()
            .Where(e => e.ResourceId == id)
            .OrderBy(e => e.Date)
            .Select(e => new { e.Id, e.Date, e.Reason })
            .ToListAsync();

        return Ok(exceptions);
    }

    [HttpPost("{id}/schedule-exceptions")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> AddScheduleException(Guid id, [FromBody] AddScheduleExceptionDto dto)
    {
        var resourceExists = await _db.Resources.AnyAsync(r => r.Id == id);
        if (!resourceExists) return NotFound();

        var date = DateTimeUtil.AsUtc(dto.Date).Date;
        if (await _db.ResourceScheduleExceptions.AnyAsync(e => e.ResourceId == id && e.Date == date))
            return Conflict(new { message = "A closed date already exists for this day." });

        var exception = new ResourceScheduleException { ResourceId = id, Date = date, Reason = dto.Reason };
        _db.ResourceScheduleExceptions.Add(exception);
        await _db.SaveChangesAsync();
        return Ok(exception);
    }

    [HttpDelete("{id}/schedule-exceptions/{exceptionId}")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> RemoveScheduleException(Guid id, Guid exceptionId)
    {
        var exception = await _db.ResourceScheduleExceptions.FirstOrDefaultAsync(e => e.Id == exceptionId && e.ResourceId == id);
        if (exception == null) return NotFound();

        _db.ResourceScheduleExceptions.Remove(exception);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // GET /api/resources/{id}/availability-grid?from=&to=  → per-day open/booked hour summary
    [HttpGet("{id}/availability-grid")]
    public async Task<IActionResult> GetAvailabilityGrid(Guid id, [FromQuery] DateTime from, [FromQuery] DateTime to)
    {
        from = DateTimeUtil.AsUtc(from);
        to = DateTimeUtil.AsUtc(to);

        var resource = await _db.Resources.AnyAsync(r => r.Id == id);
        if (!resource) return NotFound();
        if (to < from) return BadRequest(new { message = "'to' must be after 'from'." });
        if ((to - from).TotalDays > 62) return BadRequest(new { message = "Date range too large (max 62 days)." });

        var schedules = await _db.ResourceSchedules.AsNoTracking()
            .Where(s => s.ResourceId == id)
            .ToDictionaryAsync(s => s.DayOfWeek);

        var bookings = await _db.Bookings.AsNoTracking()
            .Where(b => b.ResourceId == id && b.DeletedAt == null && b.Status != BookingStatus.Cancelled
                && b.StartTime.Date >= from.Date && b.StartTime.Date <= to.Date)
            .Select(b => new { b.StartTime, b.EndTime })
            .ToListAsync();

        var result = new List<object>();
        for (var day = from.Date; day <= to.Date; day = day.AddDays(1))
        {
            var dow = (int)day.DayOfWeek;
            schedules.TryGetValue(dow, out var sched);

            double openHours = 0;
            if (sched != null && sched.IsAvailable)
                openHours = (sched.EndTime - sched.StartTime).TotalHours;

            var bookedHours = bookings
                .Where(b => b.StartTime.Date == day)
                .Sum(b => (b.EndTime - b.StartTime).TotalHours);

            result.Add(new
            {
                date = day,
                dayOfWeek = dow,
                isOpen = sched?.IsAvailable ?? false,
                openHours = Math.Round(openHours, 2),
                bookedHours = Math.Round(Math.Min(bookedHours, openHours), 2),
                availableHours = Math.Round(Math.Max(openHours - bookedHours, 0), 2),
                utilizationPercent = openHours > 0 ? Math.Round(Math.Min(bookedHours / openHours, 1) * 100, 1) : 0
            });
        }

        return Ok(result);
    }

    // ── FR-B1: search doctor/resource availability by branch + specialty + date ──
    [HttpGet("search-availability")]
    public async Task<IActionResult> SearchAvailability(
        [FromQuery] Guid tenantId,
        [FromQuery] Guid? branchId,
        [FromQuery] string? specialty,
        [FromQuery] DateTime date,
        [FromQuery] int duration = 60,
        [FromQuery] Guid? bookingTypeId = null)
    {
        date = DateTimeUtil.AsUtc(date);

        var candidates = await _db.Resources.AsNoTracking()
            .Where(r => r.TenantId == tenantId && r.Status == ResourceStatus.Available)
            .Where(r => !branchId.HasValue || r.BranchId == branchId)
            .Where(r => string.IsNullOrEmpty(specialty) || (r.Specialty != null && r.Specialty.Contains(specialty)))
            .ToListAsync();

        if (candidates.Count == 0) return Ok(new { date = date.Date, results = Array.Empty<object>() });

        var bufferBefore = 0;
        var bufferAfter = 0;
        if (bookingTypeId.HasValue)
        {
            var bookingType = await _db.BookingTypes.AsNoTracking().FirstOrDefaultAsync(bt => bt.Id == bookingTypeId);
            if (bookingType != null)
            {
                if (duration <= 0) duration = bookingType.DefaultDurationMinutes;
                bufferBefore = bookingType.BufferMinutesBefore;
                bufferAfter = bookingType.BufferMinutesAfter;
            }
        }

        var dayOfWeek = (int)date.DayOfWeek;
        var resourceIds = candidates.Select(r => r.Id).ToList();
        var schedules = await _db.ResourceSchedules.AsNoTracking()
            .Where(s => s.ResourceId.HasValue && resourceIds.Contains(s.ResourceId.Value) && s.DayOfWeek == dayOfWeek)
            .ToDictionaryAsync(s => s.ResourceId!.Value);
        var closedResourceIds = (await _db.ResourceScheduleExceptions.AsNoTracking()
            .Where(e => resourceIds.Contains(e.ResourceId) && e.Date == date.Date)
            .Select(e => e.ResourceId)
            .ToListAsync())
            .ToHashSet();
        var bookingsByResource = (await _db.Bookings.AsNoTracking()
            .Where(b => resourceIds.Contains(b.ResourceId) && b.StartTime.Date == date.Date && b.DeletedAt == null
                && b.Status != BookingStatus.Cancelled && b.Status != BookingStatus.Rejected)
            .Select(b => new { b.ResourceId, b.StartTime, b.EndTime })
            .ToListAsync())
            .GroupBy(b => b.ResourceId)
            .ToDictionary(g => g.Key, g => g.Select(b => (b.StartTime, b.EndTime)).ToList());

        var now = DateTime.UtcNow;
        var results = candidates.Select(r =>
        {
            schedules.TryGetValue(r.Id, out var schedule);
            bookingsByResource.TryGetValue(r.Id, out var existing);
            var (isOpen, slots) = SlotCalculator.Calculate(
                date, schedule, duration, bufferBefore, bufferAfter,
                existing ?? new List<(DateTime, DateTime)>(), now, closedResourceIds.Contains(r.Id));
            var nextSlot = slots.FirstOrDefault(s => s.IsAvailable);

            return new
            {
                resourceId = r.Id,
                resourceName = r.Name,
                specialty = r.Specialty,
                branchId = r.BranchId,
                isOpen,
                hasAvailability = nextSlot != null,
                nextAvailableSlot = nextSlot == null ? null : new { startTime = nextSlot.StartTime, endTime = nextSlot.EndTime }
            };
        }).ToList();

        return Ok(new { date = date.Date, results });
    }
}

public record AddScheduleExceptionDto(DateTime Date, string? Reason);
