using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Controllers;

// FR-C11 / FR-AS21: in-app notification center. "Mine" = addressed to me
// personally, plus tenant-wide ones (UserId == null) when I'm Admin/Manager.
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class NotificationsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly INotificationStream _stream;

    public NotificationsController(AppDbContext db, INotificationStream stream)
    {
        _db = db;
        _stream = stream;
    }

    [HttpGet]
    public async Task<IActionResult> GetMine([FromQuery] int page = 1, [FromQuery] int pageSize = 30)
    {
        var (userId, tenantId, isStaff) = CallerContext();
        if (userId == null || tenantId == null) return Unauthorized();

        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var query = _db.Notifications.AsNoTracking()
            .Where(n => n.TenantId == tenantId && (n.UserId == userId || (isStaff && n.UserId == null)));

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
        var (userId, tenantId, isStaff) = CallerContext();
        if (userId == null || tenantId == null) return Unauthorized();

        var count = await _db.Notifications.AsNoTracking()
            .CountAsync(n => n.TenantId == tenantId && !n.IsRead && (n.UserId == userId || (isStaff && n.UserId == null)));

        return Ok(new { count });
    }

    [HttpPut("{id}/read")]
    public async Task<IActionResult> MarkRead(Guid id)
    {
        var (userId, tenantId, isStaff) = CallerContext();
        if (userId == null || tenantId == null) return Unauthorized();

        var notification = await _db.Notifications.FirstOrDefaultAsync(n => n.Id == id && n.TenantId == tenantId);
        if (notification == null) return NotFound();
        if (notification.UserId != userId && !(isStaff && notification.UserId == null)) return Forbid();

        notification.IsRead = true;
        notification.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>Live notification stream (Server-Sent Events). Stays open and pushes each notification as it is committed.</summary>
    /// <remarks>
    /// SSE rather than WebSockets: notifications only ever travel server to
    /// client, so a one-way stream is the whole requirement, and it rides on
    /// plain HTTP - no extra package on any of the three clients, and no
    /// second protocol to secure. The durable record stays the Notifications
    /// table; this only removes the delay between a row being written and the
    /// client hearing about it. A client that misses events while disconnected
    /// refetches on reconnect and loses nothing.
    /// </remarks>
    [HttpGet("stream")]
    public async Task Stream(CancellationToken cancellationToken)
    {
        var (userId, tenantId, isStaff) = CallerContext();
        if (userId is null || tenantId is null)
        {
            Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }

        Response.ContentType = "text/event-stream";
        Response.Headers.CacheControl = "no-cache, no-transform";
        Response.Headers.Connection = "keep-alive";
        // Nginx and similar buffer by default, which would hold events back
        // until the buffer filled - the exact delay this endpoint removes.
        Response.Headers["X-Accel-Buffering"] = "no";

        using var subscription = _stream.Subscribe(new StreamAudience(tenantId.Value, userId.Value, isStaff));

        // Tell the client it is connected before anything happens, so the UI
        // can show a live indicator rather than guessing.
        await WriteEventAsync("ready", new { connectedAt = DateTime.UtcNow }, cancellationToken);

        // A heartbeat keeps proxies and phone radios from closing an idle
        // connection, and gives the client a way to notice a silent death.
        using var heartbeat = new PeriodicTimer(TimeSpan.FromSeconds(20));
        var beating = Task.Run(async () =>
        {
            try
            {
                while (await heartbeat.WaitForNextTickAsync(cancellationToken))
                {
                    await Response.WriteAsync(": keep-alive\n\n", cancellationToken);
                    await Response.Body.FlushAsync(cancellationToken);
                }
            }
            catch (OperationCanceledException) { /* client went away */ }
            catch (ObjectDisposedException) { /* response already closed */ }
        }, cancellationToken);

        try
        {
            await foreach (var notification in subscription.ReadAllAsync(cancellationToken))
            {
                await WriteEventAsync("notification", new
                {
                    id = notification.Id,
                    type = notification.Type,
                    title = notification.Title,
                    message = notification.Message,
                    createdAt = notification.CreatedAt,
                    isRead = false,
                }, cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
            // Normal: the browser tab closed or the phone lost signal.
        }
        finally
        {
            heartbeat.Dispose();
            await Task.WhenAny(beating, Task.Delay(TimeSpan.FromSeconds(1), CancellationToken.None));
        }
    }

    private async Task WriteEventAsync(string name, object payload, CancellationToken ct)
    {
        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        });
        await Response.WriteAsync($"event: {name}\ndata: {json}\n\n", ct);
        await Response.Body.FlushAsync(ct);
    }

    private (Guid? UserId, Guid? TenantId, bool IsStaff) CallerContext()
    {
        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        var tenantIdClaim = User.FindFirst("tenantId")?.Value;
        var role = User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value;

        var userId = Guid.TryParse(userIdClaim, out var uid) ? (Guid?)uid : null;
        var tenantId = Guid.TryParse(tenantIdClaim, out var tid) ? (Guid?)tid : null;
        var isStaff = role is "Admin" or "Manager";

        return (userId, tenantId, isStaff);
    }
}
