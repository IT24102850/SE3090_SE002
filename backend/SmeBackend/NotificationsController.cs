using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

// FR-C11 / FR-AS21: in-app notification center. "Mine" = addressed to me
// personally, plus tenant-wide ones (UserId == null) for tenant users.
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class NotificationsController : ControllerBase
{
    private readonly AppDbContext _db;
    public NotificationsController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<IActionResult> GetMine([FromQuery] int page = 1, [FromQuery] int pageSize = 30)
    {
        var (userId, tenantId, canViewTenantNotifications) = CallerContext();
        if (userId == null || tenantId == null) return Unauthorized();

        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var query = _db.Notifications.AsNoTracking()
            .Where(n => n.TenantId == tenantId &&
                (n.UserId == userId || (canViewTenantNotifications && n.UserId == null)));

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(n => n.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(n => new { n.Id, n.Type, n.Title, n.Message, n.IsRead, n.CreatedAt })
            .ToListAsync();

        return Ok(new { items, total });
    }

    [HttpGet("unread-count")]
    public async Task<IActionResult> GetUnreadCount()
    {
        var (userId, tenantId, canViewTenantNotifications) = CallerContext();
        if (userId == null || tenantId == null) return Unauthorized();

        var count = await _db.Notifications.AsNoTracking()
            .CountAsync(n => n.TenantId == tenantId && !n.IsRead &&
                (n.UserId == userId || (canViewTenantNotifications && n.UserId == null)));

        return Ok(new { count });
    }

    [HttpPut("{id}/read")]
    public async Task<IActionResult> MarkRead(Guid id)
    {
        var (userId, tenantId, canViewTenantNotifications) = CallerContext();
        if (userId == null || tenantId == null) return Unauthorized();

        var notification = await _db.Notifications.FirstOrDefaultAsync(n => n.Id == id && n.TenantId == tenantId);
        if (notification == null) return NotFound();
        if (notification.UserId != userId &&
            !(canViewTenantNotifications && notification.UserId == null))
        {
            return Forbid();
        }

        notification.IsRead = true;
        notification.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private (Guid? UserId, Guid? TenantId, bool CanViewTenantNotifications) CallerContext()
    {
        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        var tenantIdClaim = User.FindFirst("tenantId")?.Value;
        var role = User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value;

        var userId = Guid.TryParse(userIdClaim, out var uid) ? (Guid?)uid : null;
        var tenantId = Guid.TryParse(tenantIdClaim, out var tid) ? (Guid?)tid : null;
        var canViewTenantNotifications = role is "Admin" or "Manager" or "Staff" or "Customer";

        return (userId, tenantId, canViewTenantNotifications);
    }
}
