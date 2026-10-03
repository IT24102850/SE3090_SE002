using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

/// Registers/unregisters a mobile device's FCM token against the logged-in
/// user, so IPushNotificationSender knows where to send. See
/// mobile/sme_mobile/lib/services/push_notification_service.dart.
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class DeviceTokensController : ControllerBase
{
    private readonly AppDbContext _db;
    public DeviceTokensController(AppDbContext db) => _db = db;

    [HttpPost]
    public async Task<IActionResult> Register([FromBody] RegisterDeviceTokenDto dto)
    {
        var (userId, tenantId) = CallerContext();
        if (userId == null || tenantId == null) return Unauthorized();

        var existing = await _db.DeviceTokens.FirstOrDefaultAsync(t => t.Token == dto.Token);
        if (existing != null)
        {
            existing.UserId = userId.Value;
            existing.TenantId = tenantId.Value;
            existing.Platform = dto.Platform;
            existing.UpdatedAt = DateTime.UtcNow;
        }
        else
        {
            _db.DeviceTokens.Add(new DeviceToken
            {
                TenantId = tenantId.Value,
                UserId = userId.Value,
                Token = dto.Token,
                Platform = dto.Platform
            });
        }

        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("{token}")]
    public async Task<IActionResult> Unregister(string token)
    {
        var (userId, _) = CallerContext();
        if (userId == null) return Unauthorized();

        var existing = await _db.DeviceTokens.FirstOrDefaultAsync(t => t.Token == token && t.UserId == userId);
        if (existing == null) return NoContent();

        _db.DeviceTokens.Remove(existing);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private (Guid? UserId, Guid? TenantId) CallerContext()
    {
        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        var tenantIdClaim = User.FindFirst("tenantId")?.Value;
        return (
            Guid.TryParse(userIdClaim, out var uid) ? (Guid?)uid : null,
            Guid.TryParse(tenantIdClaim, out var tid) ? (Guid?)tid : null
        );
    }
}

public record RegisterDeviceTokenDto(string Token, string Platform);
