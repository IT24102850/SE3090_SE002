using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;

namespace SmeBackend.Controllers.Marketing;

public abstract class MarketingControllerBase : ControllerBase
{
    /// The tenant always comes from the token, never from the request.
    protected Guid? TenantId =>
        Guid.TryParse(User.FindFirst("tenantId")?.Value, out var id) ? id : null;

    protected Guid? UserId =>
        Guid.TryParse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var id) ? id : null;

    protected ActionResult MissingTenant() =>
        Unauthorized(new { message = "Unauthorized: missing tenant context in token." });

    protected static string? Mask(string? plain) =>
        string.IsNullOrEmpty(plain) ? null : plain.Length <= 8 ? "••••" : $"{plain[..4]}••••{plain[^4..]}";
}
