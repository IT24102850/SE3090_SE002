using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class BookingsController : ControllerBase
{
    private readonly AppDbContext _context;
    
    public BookingsController(AppDbContext context)
    {
        _context = context;
    }
    
    [HttpGet]
    public async Task<ActionResult> GetBookings()
    {
        var tenantId = GetTenantId();
        var role = GetUserRole();
        
        var query = _context.Bookings.Where(b => b.TenantId == tenantId);
        
        if (role == "Manager" || role == "Staff")
        {
            var branchId = GetBranchId();
            if (branchId.HasValue)
                query = query.Where(b => b.BranchId == branchId);
        }
        
        if (role == "Customer")
        {
            var userId = GetUserId();
            query = query.Where(b => b.CustomerId == userId);
        }
        
        var bookings = await query.ToListAsync();
        return Ok(bookings);
    }
    
    [HttpPost]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<ActionResult> CreateBooking([FromBody] CreateBookingDto dto)
    {
        var tenantId = GetTenantId();
        var userId = GetUserId();
        
        var booking = new Booking
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            BranchId = dto.BranchId,
            BookingType = dto.BookingType,
            CustomerId = dto.CustomerId,
            ScheduledDateTime = dto.ScheduledDateTime,
            Duration = dto.Duration,
            Status = "Pending",
            Notes = dto.Notes,
            CreatedBy = userId,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        
        _context.Bookings.Add(booking);
        await _context.SaveChangesAsync();
        
        return Ok(new { message = "Booking created", bookingId = booking.Id });
    }
    
    [HttpDelete("{id}")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<ActionResult> DeleteBooking(Guid id)
    {
        var tenantId = GetTenantId();
        
        var booking = await _context.Bookings
            .FirstOrDefaultAsync(b => b.Id == id && b.TenantId == tenantId);
        
        if (booking == null)
            return NotFound(new { message = "Booking not found" });
        
        _context.Bookings.Remove(booking);
        await _context.SaveChangesAsync();
        
        return NoContent();
    }
    
    [HttpPost("bulk-schedule")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<ActionResult> BulkSchedule([FromBody] List<CreateBookingDto> dtos)
    {
        var tenantId = GetTenantId();
        var userId = GetUserId();
        
        var bookings = dtos.Select(dto => new Booking
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            BranchId = dto.BranchId,
            BookingType = dto.BookingType,
            CustomerId = dto.CustomerId,
            ScheduledDateTime = dto.ScheduledDateTime,
            Duration = dto.Duration,
            Status = "Pending",
            Notes = dto.Notes,
            CreatedBy = userId,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        }).ToList();
        
        _context.Bookings.AddRange(bookings);
        await _context.SaveChangesAsync();
        
        return Ok(new { message = "Bulk schedule created", count = bookings.Count });
    }
    
    private Guid GetTenantId() => 
        Guid.Parse(User.FindFirst("tenantId")?.Value ?? throw new UnauthorizedAccessException());
    
    private string GetUserRole() => 
        User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value ?? "Customer";
    
    private Guid GetUserId() => 
        Guid.Parse(User.FindFirst(System.Security.Claims.ClaimsIdentity.DefaultNameClaimType)?.Value 
            ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value!);
    
    private Guid? GetBranchId()
    {
        var branchClaim = User.FindFirst("branchId")?.Value;
        return branchClaim != null ? Guid.Parse(branchClaim) : null;
    }
}