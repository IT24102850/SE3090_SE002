using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Controllers;

/// Sign-in for the platform console. Separate from AuthController on
/// purpose: the owner's account is invisible to the ordinary login, and
/// this one demands a TOTP code, locks after repeated failures, rate-limits
/// by IP, binds every token to a revocable server-side session, and writes
/// every attempt - success or not - to the audit trail.
[ApiController]
[Route("api/platform/auth")]
public sealed class PlatformAuthController(
    AppDbContext db,
    IJwtService jwt,
    IPlatformSecretProtector protector,
    IConfiguration config) : ControllerBase
{
    public const string LoginRateLimitPolicy = "platform-login";
    private const int MaxFailedAttempts = 5;
    private static readonly TimeSpan LockoutDuration = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan MfaSetupWindow = TimeSpan.FromMinutes(10);

    // Verified against on an unknown email so a missing account costs the
    // same time as a wrong password - no "does this owner exist" oracle.
    private static readonly string DummyHash = BCrypt.Net.BCrypt.HashPassword(Guid.NewGuid().ToString(), workFactor: 12);

    public sealed class LoginRequest
    {
        [Required, EmailAddress] public string Email { get; set; } = string.Empty;
        [Required] public string Password { get; set; } = string.Empty;
        /// The 6-digit authenticator code. Omitted on the first call; the
        /// response says whether it is required or whether MFA still has to
        /// be enrolled.
        public string? Code { get; set; }
    }

    public sealed class MfaEnrolRequest
    {
        [Required] public string SetupToken { get; set; } = string.Empty;
        [Required] public string Code { get; set; } = string.Empty;
    }

    public sealed class ChangePasswordRequest
    {
        [Required] public string CurrentPassword { get; set; } = string.Empty;
        [Required, MinLength(14)] public string NewPassword { get; set; } = string.Empty;
        [Required] public string Code { get; set; } = string.Empty;
    }

    [HttpPost("login")]
    [AllowAnonymous]
    [EnableRateLimiting(LoginRateLimitPolicy)]
    public async Task<IActionResult> Login([FromBody] LoginRequest request, CancellationToken ct)
    {
        var email = request.Email.Trim().ToLowerInvariant();
        var now = DateTime.UtcNow;

        var user = await db.Users.IgnoreQueryFilters()
            .FirstOrDefaultAsync(u => u.Role == UserRole.SuperAdmin && u.Email == email && u.IsActive, ct);
        var admin = user == null ? null : await GetOrCreateAdminAsync(user.Id, ct);

        if (admin?.LockoutEndUtc is { } lockedUntil && lockedUntil > now)
        {
            await AuditAsync(user, "auth.login.locked", false, $"Locked until {lockedUntil:O}", ct);
            var minutes = Math.Max(1, (int)Math.Ceiling((lockedUntil - now).TotalMinutes));
            return StatusCode(StatusCodes.Status423Locked,
                new { status = "locked", message = $"Too many failed attempts. Try again in {minutes} minute(s)." });
        }

        var passwordOk = BCrypt.Net.BCrypt.Verify(request.Password, user?.PasswordHash ?? DummyHash);
        if (user == null || admin == null || !passwordOk)
        {
            if (admin != null) await RegisterFailureAsync(admin, ct);
            await AuditAsync(user, "auth.login.failed", false, user == null ? $"Unknown owner email {email}" : "Wrong password", ct);
            return Unauthorized(new { status = "invalid", message = "Invalid email, password or code." });
        }

        // Password is right. Now the second factor.
        if (admin.MfaEnabledAt == null)
        {
            // First sign-in: hand back a fresh secret to scan. Nothing is
            // trusted until the first code from the app verifies it.
            var secret = TotpService.GenerateSecret();
            var setupToken = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
            admin.PendingMfaSecretEncrypted = protector.Protect(secret);
            admin.MfaSetupTokenHash = protector.Hash(setupToken);
            admin.MfaSetupExpiresAt = now.Add(MfaSetupWindow);
            admin.UpdatedAt = now;
            await db.SaveChangesAsync(ct);
            await AuditAsync(user, "auth.mfa.setup-started", true, null, ct);

            return Ok(new
            {
                status = "mfaSetupRequired",
                setupToken,
                secret,
                otpauthUri = TotpService.BuildProvisioningUri(secret, user.Email, Issuer),
                expiresAt = admin.MfaSetupExpiresAt,
                message = "Scan the code with an authenticator app, then enter the 6-digit code to finish enrolment.",
            });
        }

        if (string.IsNullOrWhiteSpace(request.Code))
        {
            return Ok(new { status = "mfaRequired", message = "Enter the 6-digit code from your authenticator app." });
        }

        string secretPlain;
        try
        {
            secretPlain = protector.Unprotect(admin.MfaSecretEncrypted!);
        }
        catch (System.Security.Cryptography.CryptographicException)
        {
            // The secret was encrypted under a different Platform:SecretKey /
            // Jwt:Key than this deployment has. Say so - a bare 500 here
            // looks like an outage rather than a configuration change.
            await AuditAsync(user, "auth.login.failed", false, "MFA secret cannot be decrypted with this deployment's key", ct);
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new { status = "keyMismatch", message = "The authenticator secret was encrypted with a different server key. Restore Platform:SecretKey (or Jwt:Key) or reset MFA in the database." });
        }
        if (!TotpService.TryVerify(secretPlain, request.Code, now, admin.LastAcceptedTotpStep, out var step))
        {
            await RegisterFailureAsync(admin, ct);
            await AuditAsync(user, "auth.login.failed", false, "Wrong or reused authenticator code", ct);
            return Unauthorized(new { status = "invalid", message = "Invalid email, password or code." });
        }

        admin.LastAcceptedTotpStep = step;
        return Ok(await OpenSessionAsync(user, admin, ct));
    }

    [HttpPost("mfa/enrol")]
    [AllowAnonymous]
    [EnableRateLimiting(LoginRateLimitPolicy)]
    public async Task<IActionResult> EnrolMfa([FromBody] MfaEnrolRequest request, CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var tokenHash = protector.Hash(request.SetupToken);
        // IgnoreQueryFilters: this is an anonymous call, so there is no tenant
        // context and the User filter would otherwise drop the joined row.
        var admin = await db.PlatformAdmins.IgnoreQueryFilters().Include(a => a.User)
            .FirstOrDefaultAsync(a => a.MfaSetupTokenHash == tokenHash, ct);

        if (admin == null || admin.MfaSetupExpiresAt is null || admin.MfaSetupExpiresAt < now || admin.PendingMfaSecretEncrypted == null)
        {
            return Unauthorized(new { status = "invalid", message = "Enrolment expired. Sign in again to start over." });
        }

        var secret = protector.Unprotect(admin.PendingMfaSecretEncrypted);
        if (!TotpService.TryVerify(secret, request.Code, now, 0, out var step))
        {
            await AuditAsync(admin.User, "auth.mfa.enrol.failed", false, "Code did not match the new secret", ct);
            return Unauthorized(new { status = "invalid", message = "That code did not match. Check the time on your phone and try again." });
        }

        admin.MfaSecretEncrypted = admin.PendingMfaSecretEncrypted;
        admin.MfaEnabledAt = now;
        admin.PendingMfaSecretEncrypted = null;
        admin.MfaSetupTokenHash = null;
        admin.MfaSetupExpiresAt = null;
        admin.LastAcceptedTotpStep = step;
        admin.UpdatedAt = now;
        await AuditAsync(admin.User, "auth.mfa.enrolled", true, null, ct);

        return Ok(await OpenSessionAsync(admin.User, admin, ct));
    }

    [HttpGet("me")]
    [Authorize(Policy = PlatformOwnerPolicy.Name)]
    public async Task<IActionResult> Me(CancellationToken ct)
    {
        var (user, admin) = await CurrentAsync(ct);
        var session = await db.PlatformSessions.FirstAsync(s => s.Jti == CurrentJti, ct);
        return Ok(new
        {
            user.Id,
            user.Email,
            user.FullName,
            role = user.Role.ToString(),
            mfaEnabledAt = admin.MfaEnabledAt,
            lastLoginAt = admin.LastLoginAt,
            lastLoginIp = admin.LastLoginIp,
            passwordChangedAt = admin.PasswordChangedAt,
            session = new { session.Id, session.CreatedAt, session.ExpiresAt, idleTimeoutMinutes = PlatformOwnerPolicy.IdleTimeout.TotalMinutes },
        });
    }

    [HttpPost("logout")]
    [Authorize(Policy = PlatformOwnerPolicy.Name)]
    public async Task<IActionResult> Logout(CancellationToken ct)
    {
        var (user, _) = await CurrentAsync(ct);
        var session = await db.PlatformSessions.FirstOrDefaultAsync(s => s.Jti == CurrentJti, ct);
        if (session != null && session.RevokedAt == null)
        {
            session.RevokedAt = DateTime.UtcNow;
            session.RevokedReason = "logout";
        }
        await AuditAsync(user, "auth.logout", true, null, ct);
        return Ok(new { message = "Signed out." });
    }

    [HttpGet("sessions")]
    [Authorize(Policy = PlatformOwnerPolicy.Name)]
    public async Task<IActionResult> Sessions(CancellationToken ct)
    {
        var (user, _) = await CurrentAsync(ct);
        var now = DateTime.UtcNow;
        var sessions = await db.PlatformSessions.AsNoTracking()
            .Where(s => s.UserId == user.Id)
            .OrderByDescending(s => s.CreatedAt)
            .Take(50)
            .ToListAsync(ct);
        return Ok(sessions.Select(s => new
        {
            s.Id,
            s.IpAddress,
            s.UserAgent,
            s.CreatedAt,
            s.LastSeenAt,
            s.ExpiresAt,
            s.RevokedAt,
            s.RevokedReason,
            isCurrent = s.Jti == CurrentJti,
            isLive = s.IsLive(now, PlatformOwnerPolicy.IdleTimeout),
        }));
    }

    [HttpPost("sessions/{id:guid}/revoke")]
    [Authorize(Policy = PlatformOwnerPolicy.Name)]
    public async Task<IActionResult> RevokeSession(Guid id, CancellationToken ct)
    {
        var (user, _) = await CurrentAsync(ct);
        var session = await db.PlatformSessions.FirstOrDefaultAsync(s => s.Id == id && s.UserId == user.Id, ct);
        if (session == null) return NotFound();
        if (session.RevokedAt == null)
        {
            session.RevokedAt = DateTime.UtcNow;
            session.RevokedReason = "revoked";
        }
        await AuditAsync(user, "auth.session.revoked", true, $"Session {id} from {session.IpAddress}", ct);
        return Ok(new { message = "Session revoked." });
    }

    /// "Sign out everywhere else" - the current console stays open.
    [HttpPost("sessions/revoke-others")]
    [Authorize(Policy = PlatformOwnerPolicy.Name)]
    public async Task<IActionResult> RevokeOtherSessions(CancellationToken ct)
    {
        var (user, _) = await CurrentAsync(ct);
        var now = DateTime.UtcNow;
        var count = await db.PlatformSessions
            .Where(s => s.UserId == user.Id && s.RevokedAt == null && s.Jti != CurrentJti)
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.RevokedAt, now)
                .SetProperty(x => x.RevokedReason, "revoked-all"), ct);
        await AuditAsync(user, "auth.session.revoked-others", true, $"{count} session(s) closed", ct);
        return Ok(new { revoked = count });
    }

    [HttpPost("change-password")]
    [Authorize(Policy = PlatformOwnerPolicy.Name)]
    public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordRequest request, CancellationToken ct)
    {
        var (user, admin) = await CurrentAsync(ct);
        var now = DateTime.UtcNow;

        if (!BCrypt.Net.BCrypt.Verify(request.CurrentPassword, user.PasswordHash))
        {
            await AuditAsync(user, "auth.password.change.failed", false, "Current password wrong", ct);
            return BadRequest(new { message = "Current password is incorrect." });
        }
        var secret = protector.Unprotect(admin.MfaSecretEncrypted!);
        if (!TotpService.TryVerify(secret, request.Code, now, admin.LastAcceptedTotpStep, out var step))
        {
            await AuditAsync(user, "auth.password.change.failed", false, "Authenticator code wrong", ct);
            return BadRequest(new { message = "Authenticator code is incorrect." });
        }
        if (!IsStrong(request.NewPassword, out var why)) return BadRequest(new { message = why });
        if (BCrypt.Net.BCrypt.Verify(request.NewPassword, user.PasswordHash))
            return BadRequest(new { message = "The new password must differ from the current one." });

        admin.LastAcceptedTotpStep = step;
        admin.PasswordChangedAt = now;
        admin.UpdatedAt = now;
        var newHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword, workFactor: 12);
        // Through ExecuteUpdate rather than the tracker: User is tenant
        // scoped and the save guard would refuse a cross-tenant edit, but
        // this is the owner's own row.
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == user.Id)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.PasswordHash, newHash).SetProperty(u => u.UpdatedAt, now), ct);

        // Every other console is on the old password's session: close them.
        await db.PlatformSessions
            .Where(s => s.UserId == user.Id && s.RevokedAt == null && s.Jti != CurrentJti)
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.RevokedAt, now)
                .SetProperty(x => x.RevokedReason, "password-changed"), ct);

        await AuditAsync(user, "auth.password.changed", true, null, ct);
        return Ok(new { message = "Password changed. Other sessions were signed out." });
    }

    // ── helpers ────────────────────────────────────────────────────────

    private string Issuer => config["Platform:MfaIssuer"] ?? "Unify Platform";
    private string CurrentJti => User.FindFirst("jti")?.Value ?? User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Jti)?.Value ?? string.Empty;
    private string ClientIp => HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
    private string ClientAgent => Request.Headers.UserAgent.ToString() is { Length: > 0 } ua ? ua[..Math.Min(ua.Length, 512)] : "unknown";

    private async Task<(User user, PlatformAdmin admin)> CurrentAsync(CancellationToken ct)
    {
        var sub = User.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)?.Value;
        var userId = Guid.Parse(sub!);
        var user = await db.Users.IgnoreQueryFilters().AsNoTracking().FirstAsync(u => u.Id == userId, ct);
        var admin = await GetOrCreateAdminAsync(userId, ct);
        return (user, admin);
    }

    private async Task<PlatformAdmin> GetOrCreateAdminAsync(Guid userId, CancellationToken ct)
    {
        var admin = await db.PlatformAdmins.FirstOrDefaultAsync(a => a.UserId == userId, ct);
        if (admin == null)
        {
            admin = new PlatformAdmin { UserId = userId };
            db.PlatformAdmins.Add(admin);
            await db.SaveChangesAsync(ct);
        }
        return admin;
    }

    private async Task<object> OpenSessionAsync(User user, PlatformAdmin admin, CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var jti = Guid.NewGuid().ToString("N");
        var expiresAt = now.Add(PlatformOwnerPolicy.SessionLifetime);

        admin.FailedLoginAttempts = 0;
        admin.LockoutEndUtc = null;
        admin.LastLoginAt = now;
        admin.LastLoginIp = ClientIp;
        admin.UpdatedAt = now;

        db.PlatformSessions.Add(new PlatformSession
        {
            UserId = user.Id,
            Jti = jti,
            IpAddress = ClientIp,
            UserAgent = ClientAgent,
            CreatedAt = now,
            LastSeenAt = now,
            ExpiresAt = expiresAt,
        });
        await AuditAsync(user, "auth.login.succeeded", true, null, ct);

        return new
        {
            status = "ok",
            accessToken = jwt.GeneratePlatformAccessToken(user, jti, expiresAt),
            expiresAt,
            idleTimeoutMinutes = PlatformOwnerPolicy.IdleTimeout.TotalMinutes,
            user = new { user.Id, user.Email, user.FullName, role = user.Role.ToString() },
        };
    }

    private async Task RegisterFailureAsync(PlatformAdmin admin, CancellationToken ct)
    {
        admin.FailedLoginAttempts++;
        admin.UpdatedAt = DateTime.UtcNow;
        if (admin.FailedLoginAttempts >= MaxFailedAttempts)
        {
            admin.LockoutEndUtc = DateTime.UtcNow.Add(LockoutDuration);
            admin.FailedLoginAttempts = 0;
        }
        await db.SaveChangesAsync(ct);
    }

    private async Task AuditAsync(User? user, string action, bool succeeded, string? detail, CancellationToken ct)
    {
        db.PlatformAuditLogs.Add(new PlatformAuditLog
        {
            ActorUserId = user?.Id,
            ActorEmail = user?.Email ?? "anonymous",
            Action = action,
            TargetType = "user",
            TargetId = user?.Id,
            TargetLabel = user?.Email,
            Detail = detail,
            Succeeded = succeeded,
            IpAddress = ClientIp,
            UserAgent = ClientAgent,
        });
        await db.SaveChangesAsync(ct);
    }

    public static bool IsStrong(string password, out string reason)
    {
        reason = string.Empty;
        if (password.Length < 14) reason = "Use at least 14 characters.";
        else if (!password.Any(char.IsUpper) || !password.Any(char.IsLower)) reason = "Mix upper and lower case letters.";
        else if (!password.Any(char.IsDigit)) reason = "Include at least one digit.";
        else if (password.All(char.IsLetterOrDigit)) reason = "Include at least one symbol.";
        return reason.Length == 0;
    }
}
