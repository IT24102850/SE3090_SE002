using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Authorization;

/// The one policy the platform console accepts. A request passes only when
/// the token carries the SuperAdmin role, was minted by the platform login
/// (scope=platform) after a verified TOTP code (platform_mfa=verified), AND
/// its jti still
/// names a live row in platform_sessions. The last check is what makes
/// "sign out everywhere" and the idle timeout real rather than advisory.
public static class PlatformOwnerPolicy
{
    public const string Name = "PlatformOwner";
    public const string ScopeClaim = "scope";
    public const string ScopeValue = "platform";
    // A custom name rather than the standard "amr": the JWT handler treats
    // "amr" as a JSON array and the string value never survives validation
    // as a plain claim, so RequireClaim would refuse every token.
    public const string AmrClaim = "platform_mfa";
    public const string AmrMfa = "verified";

    /// A console left untouched this long is closed server-side, whatever
    /// the token's own expiry says.
    public static readonly TimeSpan IdleTimeout = TimeSpan.FromMinutes(15);
    /// Hard ceiling on a session; after this the owner signs in again with
    /// password and a fresh code.
    public static readonly TimeSpan SessionLifetime = TimeSpan.FromMinutes(60);

    public static void Add(AuthorizationOptions options)
    {
        options.AddPolicy(Name, policy =>
        {
            policy.RequireAuthenticatedUser();
            policy.RequireRole(UserRole.SuperAdmin.ToString());
            policy.RequireClaim(ScopeClaim, ScopeValue);
            policy.RequireClaim(AmrClaim, AmrMfa);
            policy.AddRequirements(new PlatformSessionRequirement());
        });
    }
}

public sealed class PlatformSessionRequirement : IAuthorizationRequirement;

/// Scoped (it needs the DbContext), unlike InventoryAccessHandler.
public sealed class PlatformSessionHandler(AppDbContext db) : AuthorizationHandler<PlatformSessionRequirement>
{
    protected override async Task HandleRequirementAsync(AuthorizationHandlerContext context, PlatformSessionRequirement requirement)
    {
        var jti = context.User.FindFirst("jti")?.Value
                  ?? context.User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Jti)?.Value;
        var sub = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                  ?? context.User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)?.Value;
        if (string.IsNullOrEmpty(jti) || !Guid.TryParse(sub, out var userId)) return;

        var now = DateTime.UtcNow;
        var session = await db.PlatformSessions
            .FirstOrDefaultAsync(s => s.Jti == jti && s.UserId == userId);
        if (session == null) return;

        if (!session.IsLive(now, PlatformOwnerPolicy.IdleTimeout))
        {
            if (session.RevokedAt == null)
            {
                session.RevokedAt = now;
                session.RevokedReason = session.ExpiresAt <= now ? "expired" : "idle-timeout";
                await db.SaveChangesAsync();
            }
            return;
        }

        // Touch at most once a minute so a busy dashboard is not a write
        // per request.
        if (now - session.LastSeenAt > TimeSpan.FromMinutes(1))
        {
            session.LastSeenAt = now;
            await db.SaveChangesAsync();
        }
        context.Succeed(requirement);
    }
}
