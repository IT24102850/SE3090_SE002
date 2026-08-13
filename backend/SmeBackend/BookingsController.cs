using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/[controller]")]
public class BookingsController : ControllerBase
{
    private readonly AppDbContext _db;

    public BookingsController(AppDbContext db)
    {
        _db = db;
    }

    // GET: api/bookings
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var bookings = await _db.Bookings
            .AsNoTracking()
            .Include(b => b.Resource)
            .Include(b => b.BookingType)
            .Where(b => b.DeletedAt == null)
            .Select(b => new
            {
                b.Id,
                b.TenantId,
                ResourceName = b.Resource.Name,
                BookingTypeName = b.BookingType.Name,
                b.BookedBy,
                b.BookedFor,
                b.Title,
                b.StartTime,
                b.EndTime,
                b.Status,
                b.Priority,
                b.TotalCost,
                b.CreatedAt
            })
            .ToListAsync();

        return Ok(bookings);
    }

    // GET: api/bookings/{id}
    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var booking = await _db.Bookings
            .AsNoTracking()
            .Include(b => b.Resource)
            .Include(b => b.BookingType)
            .FirstOrDefaultAsync(b => b.Id == id && b.DeletedAt == null);

        if (booking == null) return NotFound();

        return Ok(new
        {
            booking.Id,
            booking.TenantId,
            ResourceName = booking.Resource.Name,
            BookingTypeName = booking.BookingType.Name,
            booking.BookedBy,
            booking.BookedFor,
            booking.Title,
            booking.Notes,
            booking.StartTime,
            booking.EndTime,
            booking.Status,
            booking.Priority,
            booking.AttendeeCount,
            booking.TotalCost,
            booking.CreatedAt
        });
    }

    // POST: api/bookings
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateBookingDto dto)
    {
        var resource = await _db.Resources.FindAsync(dto.ResourceId);
        if (resource == null) return BadRequest(new { message = "Resource not found" });

        var bookingType = await _db.BookingTypes.FindAsync(dto.BookingTypeId);
        if (bookingType == null) return BadRequest(new { message = "Booking type not found" });

        if (dto.EndTime <= dto.StartTime)
            return BadRequest(new { message = "End time must be after start time" });

        var booking = new Booking
        {
            TenantId = dto.TenantId,
            ResourceId = dto.ResourceId,
            BookingTypeId = dto.BookingTypeId,
            BookedBy = dto.BookedBy,
            BookedFor = dto.BookedFor,
            Title = dto.Title,
            Notes = dto.Notes,
            StartTime = dto.StartTime,
            EndTime = dto.EndTime,
            Status = BookingStatus.Pending,
            Priority = dto.Priority,
            AttendeeCount = dto.AttendeeCount
        };

        _db.Bookings.Add(booking);
        await _db.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = booking.Id }, booking);
    }

    // PUT: api/bookings/{id}
    [HttpPut("{id}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateBookingDto dto)
    {
        var booking = await _db.Bookings.FindAsync(id);
        if (booking == null || booking.DeletedAt != null) return NotFound();

        if (dto.ResourceId.HasValue)
        {
            var res = await _db.Resources.FindAsync(dto.ResourceId.Value);
            if (res == null) return BadRequest(new { message = "Resource not found" });
            booking.ResourceId = dto.ResourceId.Value;
        }

        if (dto.BookingTypeId.HasValue)
        {
            var bt = await _db.BookingTypes.FindAsync(dto.BookingTypeId.Value);
            if (bt == null) return BadRequest(new { message = "Booking type not found" });
            booking.BookingTypeId = dto.BookingTypeId.Value;
        }

        if (dto.StartTime.HasValue) booking.StartTime = dto.StartTime.Value;
        if (dto.EndTime.HasValue) booking.EndTime = dto.EndTime.Value;
        if (dto.EndTime <= dto.StartTime)
            return BadRequest(new { message = "End time must be after start time" });

        if (!string.IsNullOrEmpty(dto.Title)) booking.Title = dto.Title;
        if (dto.Notes != null) booking.Notes = dto.Notes;
        if (dto.Status.HasValue) booking.Status = dto.Status.Value;
        if (dto.Priority.HasValue) booking.Priority = dto.Priority.Value;
        if (dto.AttendeeCount.HasValue) booking.AttendeeCount = dto.AttendeeCount.Value;

        booking.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        return Ok(booking);
    }

    // DELETE: api/bookings/{id} (Soft delete)
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

// DTOs
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
    Guid? ResourceId,
    Guid? BookingTypeId,
    DateTime? StartTime,
    DateTime? EndTime,
    string? Title,
    string? Notes,
    BookingStatus? Status,
    BookingPriority? Priority,
    int? AttendeeCount
);