using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize] // All endpoints require authentication
public class BookingsController : ControllerBase
{
    private readonly AppDbContext _context;
    
    public BookingsController(AppDbContext context)
    {
        _context = context;
    }
    
    // Anyone authenticated can view bookings (with tenant filter applied in service)
    [HttpGet]
    public async Task<ActionResult> GetBookings()
    {
        var tenantId = GetTenantId();
        var role = GetUserRole();
        
        var query = _context.Bookings.Where(b => b.TenantId == tenantId);
        
        // Managers and Staff only see their branch
        if (role == "Manager" || role == "Staff")
        {
            var branchId = GetBranchId();
            if (branchId.HasValue)
                query = query.Where(b => b.BranchId == branchId);
        }
        
        // Customers only see their own bookings
        if (role == "Customer")
        {
            var userId = GetUserId();
            query = query.Where(b => b.CustomerId == userId);
        }
        
        var bookings = await query.ToListAsync();
        return Ok(bookings);
    }
    
    // Only Staff, Manager, Admin can create bookings
    [HttpPost]
    [Authorize(Roles = "Admin,Manager,Staff")]
    public async Task<ActionResult> CreateBooking([FromBody] CreateBookingDto dto)
    {
        // Implementation...
        return Ok(new { message = "Booking created" });
    }
    
    // Only Admin and Manager can delete
    [HttpDelete("{id}")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<ActionResult> DeleteBooking(Guid id)
    {
        // Implementation...
        return NoContent();
    }
    
    // Bulk schedule — high impact, Manager+ only
    [HttpPost("bulk-schedule")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<ActionResult> BulkSchedule([FromBody] List<CreateBookingDto> dtos)
    {
        // Implementation...
        return Ok(new { message = "Bulk schedule created" });
    }
    
    // Helper methods to extract values from JWT claims
    private Guid GetTenantId() => 
        Guid.Parse(User.FindFirst("tenantId")?.Value ?? throw new UnauthorizedAccessException());
    
    private string GetUserRole() => 
        User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value ?? "Customer";
    
    private Guid GetUserId() => 
        Guid.Parse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value!);
    
    private Guid? GetBranchId()
    {
        var branchClaim = User.FindFirst("branchId")?.Value;
        return branchClaim != null ? Guid.Parse(branchClaim) : null;
    }
}