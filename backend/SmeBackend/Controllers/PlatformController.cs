using System.ComponentModel.DataAnnotations;
using System.Diagnostics;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Controllers;

/// The platform owner's cross-tenant console: who is on the platform, how
/// busy it is, and the few levers the owner has (suspend a tenant, lock a
/// user, hand out a temporary password).
///
/// Every query here reads through IgnoreQueryFilters - this is the one
/// place that is meant to see every tenant - and every write is guarded
/// twice: the PlatformOwner policy on the way in, and a fresh authenticator
/// code (X-Platform-Otp header) on anything that changes someone's access.
/// The "Unify Platform" tenant that hosts the owner's own account is not a
/// business and is left out of every figure.
[ApiController]
[Route("api/platform")]
[Authorize(Policy = PlatformOwnerPolicy.Name)]
public sealed class PlatformController(AppDbContext db, IPlatformSecretProtector protector) : ControllerBase
{
    public const string OtpHeader = "X-Platform-Otp";

    // ── Overview ────────────────────────────────────────────────────────

    [HttpGet("overview")]
    public async Task<IActionResult> Overview(CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var today = now.Date;
        var d7 = today.AddDays(-7);
        var d30 = today.AddDays(-30);
        var w12 = today.AddDays(-7 * 12);

        var tenants = db.Tenants.IgnoreQueryFilters().AsNoTracking()
            .Where(t => t.BusinessType != PlatformOwnerSeeder.PlatformBusinessType && t.BusinessType != CustomerAccountService.PoolBusinessType);
        // People, not rows: a customer's per-business memberships
        // (LinkedAccountId set) are the same person as their identity.
        var users = db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(u => u.Role != UserRole.SuperAdmin && u.LinkedAccountId == null);
        var bookings = db.Bookings.IgnoreQueryFilters().AsNoTracking()
            .Where(b => b.DeletedAt == null);

        var tenantsTotal = await tenants.CountAsync(ct);
        var tenantsActive = await tenants.CountAsync(t => t.IsActive, ct);
        var tenantsNew30 = await tenants.CountAsync(t => t.CreatedAt >= d30, ct);
        var tenantsByType = await tenants
            .GroupBy(t => t.BusinessType)
            .Select(g => new { businessType = g.Key, count = g.Count(), active = g.Count(t => t.IsActive) })
            .OrderByDescending(g => g.count)
            .ToListAsync(ct);

        var usersTotal = await users.CountAsync(ct);
        var usersByRole = await users
            .GroupBy(u => u.Role)
            .Select(g => new { role = g.Key, count = g.Count() })
            .ToListAsync(ct);
        var usersNew30 = await users.CountAsync(u => u.CreatedAt >= d30, ct);

        var bookingsTotal = await bookings.CountAsync(ct);
        var bookingsToday = await bookings.CountAsync(b => b.CreatedAt >= today, ct);
        var bookings7 = await bookings.CountAsync(b => b.CreatedAt >= d7, ct);
        var bookings30 = await bookings.CountAsync(b => b.CreatedAt >= d30, ct);
        var bookingsPrev30 = await bookings.CountAsync(b => b.CreatedAt >= d30.AddDays(-30) && b.CreatedAt < d30, ct);
        var upcoming = await bookings.CountAsync(b => b.StartTime >= now && (b.Status == BookingStatus.Confirmed || b.Status == BookingStatus.Pending), ct);

        var bookingsPerDayRaw = await bookings
            .Where(b => b.CreatedAt >= d30)
            .GroupBy(b => b.CreatedAt.Date)
            .Select(g => new { day = g.Key, count = g.Count() })
            .ToListAsync(ct);
        var bookingsPerDay = Enumerable.Range(0, 31)
            .Select(i => d30.AddDays(i))
            .Select(day => new { date = day.ToString("yyyy-MM-dd"), count = bookingsPerDayRaw.FirstOrDefault(x => x.day == day)?.count ?? 0 })
            .ToList();

        var tenantsCreated = await tenants.Where(t => t.CreatedAt >= w12).Select(t => t.CreatedAt).ToListAsync(ct);
        var weekStart = w12.AddDays(-(int)w12.DayOfWeek + 1); // Monday
        var tenantsPerWeek = Enumerable.Range(0, 13)
            .Select(i => weekStart.AddDays(7 * i))
            .Where(ws => ws <= today)
            .Select(ws => new { weekStart = ws.ToString("yyyy-MM-dd"), count = tenantsCreated.Count(c => c >= ws && c < ws.AddDays(7)) })
            .ToList();

        var topTenantIds = await bookings
            .Where(b => b.CreatedAt >= d30)
            .GroupBy(b => b.TenantId)
            .Select(g => new { tenantId = g.Key, count = g.Count() })
            .OrderByDescending(g => g.count)
            .Take(8)
            .ToListAsync(ct);
        var topIds = topTenantIds.Select(x => x.tenantId).ToList();
        var topTenantNames = await tenants
            .Where(t => topIds.Contains(t.Id))
            .Select(t => new { t.Id, t.Name, t.BusinessType, t.IsActive })
            .ToListAsync(ct);
        var topTenants = topTenantIds
            .Select(x =>
            {
                var t = topTenantNames.FirstOrDefault(n => n.Id == x.tenantId);
                return new { id = x.tenantId, name = t?.Name ?? "(unknown)", businessType = t?.BusinessType ?? "", isActive = t?.IsActive ?? false, bookings30d = x.count };
            })
            .ToList();

        var recentAudit = await db.PlatformAuditLogs.AsNoTracking()
            .OrderByDescending(a => a.CreatedAt).Take(10)
            .Select(a => new { a.Id, a.CreatedAt, a.ActorEmail, a.Action, a.TargetType, a.TargetLabel, a.Detail, a.Succeeded, a.IpAddress })
            .ToListAsync(ct);

        var ownerId = CurrentUserId;
        var admin = await db.PlatformAdmins.AsNoTracking().FirstAsync(a => a.UserId == ownerId, ct);
        var liveSessions = (await db.PlatformSessions.AsNoTracking().Where(s => s.UserId == ownerId && s.RevokedAt == null).ToListAsync(ct))
            .Count(s => s.IsLive(now, PlatformOwnerPolicy.IdleTimeout));
        var failedLogins24h = await db.PlatformAuditLogs.CountAsync(a => a.Action == "auth.login.failed" && a.CreatedAt >= now.AddHours(-24), ct);
        var pendingMigrations = (await db.Database.GetPendingMigrationsAsync(ct)).Count();
        var appliedMigrations = (await db.Database.GetAppliedMigrationsAsync(ct)).Count();

        return Ok(new
        {
            generatedAt = now,
            tenants = new { total = tenantsTotal, active = tenantsActive, suspended = tenantsTotal - tenantsActive, new30d = tenantsNew30, byType = tenantsByType, perWeek = tenantsPerWeek },
            users = new { total = usersTotal, new30d = usersNew30, byRole = usersByRole.Select(r => new { role = r.role.ToString(), r.count }) },
            bookings = new { total = bookingsTotal, today = bookingsToday, last7d = bookings7, last30d = bookings30, previous30d = bookingsPrev30, upcoming, perDay = bookingsPerDay },
            topTenants,
            recentAudit,
            security = new
            {
                mfaEnabledAt = admin.MfaEnabledAt,
                lastLoginAt = admin.LastLoginAt,
                lastLoginIp = admin.LastLoginIp,
                passwordChangedAt = admin.PasswordChangedAt,
                liveSessions,
                failedLogins24h,
                lockedUntil = admin.LockoutEndUtc > now ? admin.LockoutEndUtc : null,
            },
            system = new
            {
                environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production",
                startedAt = Process.GetCurrentProcess().StartTime.ToUniversalTime(),
                uptimeSeconds = (long)(now - Process.GetCurrentProcess().StartTime.ToUniversalTime()).TotalSeconds,
                appliedMigrations,
                pendingMigrations,
                runtime = Environment.Version.ToString(),
            },
        });
    }

    // ── Tenants ─────────────────────────────────────────────────────────

    [HttpGet("tenants")]
    public async Task<IActionResult> Tenants([FromQuery] string? search, [FromQuery] string? status, [FromQuery] string? businessType,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 5, 100);
        var d30 = DateTime.UtcNow.Date.AddDays(-30);

        var query = db.Tenants.IgnoreQueryFilters().AsNoTracking()
            .Where(t => t.BusinessType != PlatformOwnerSeeder.PlatformBusinessType && t.BusinessType != CustomerAccountService.PoolBusinessType);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim().ToLower();
            query = query.Where(t => t.Name.ToLower().Contains(term) || (t.ContactEmail != null && t.ContactEmail.ToLower().Contains(term)));
        }
        if (status == "active") query = query.Where(t => t.IsActive);
        else if (status == "suspended") query = query.Where(t => !t.IsActive);
        if (!string.IsNullOrWhiteSpace(businessType)) query = query.Where(t => t.BusinessType == businessType);

        var total = await query.CountAsync(ct);
        var rows = await query
            .OrderByDescending(t => t.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(t => new
            {
                t.Id, t.Name, t.BusinessType, t.SubType, t.IsActive, t.CreatedAt, t.ContactEmail, t.LogoUrl,
                userCount = db.Users.IgnoreQueryFilters().Count(u => u.TenantId == t.Id),
                branchCount = db.Branches.IgnoreQueryFilters().Count(b => b.TenantId == t.Id && b.IsActive),
                bookingCount = db.Bookings.IgnoreQueryFilters().Count(b => b.TenantId == t.Id && b.DeletedAt == null),
                bookings30d = db.Bookings.IgnoreQueryFilters().Count(b => b.TenantId == t.Id && b.DeletedAt == null && b.CreatedAt >= d30),
                lastBookingAt = db.Bookings.IgnoreQueryFilters().Where(b => b.TenantId == t.Id && b.DeletedAt == null).Max(b => (DateTime?)b.CreatedAt),
                adminEmail = db.Users.IgnoreQueryFilters().Where(u => u.TenantId == t.Id && u.Role == UserRole.Admin).OrderBy(u => u.CreatedAt).Select(u => u.Email).FirstOrDefault(),
            })
            .ToListAsync(ct);

        var businessTypes = await db.Tenants.IgnoreQueryFilters().AsNoTracking()
            .Where(t => t.BusinessType != PlatformOwnerSeeder.PlatformBusinessType && t.BusinessType != CustomerAccountService.PoolBusinessType)
            .Select(t => t.BusinessType).Distinct().OrderBy(x => x).ToListAsync(ct);

        return Ok(new { items = rows, total, page, pageSize, totalPages = (int)Math.Ceiling(total / (double)pageSize), businessTypes });
    }

    [HttpGet("tenants/{id:guid}")]
    public async Task<IActionResult> Tenant(Guid id, CancellationToken ct)
    {
        var t = await db.Tenants.IgnoreQueryFilters().AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        if (t == null || CustomerAccountService.IsReserved(t.BusinessType)) return NotFound();
        var d30 = DateTime.UtcNow.Date.AddDays(-30);

        var users = await db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(u => u.TenantId == id)
            .OrderBy(u => u.Role).ThenBy(u => u.FullName)
            .Select(u => new { u.Id, u.FullName, u.Email, role = u.Role.ToString(), u.IsActive, u.IsApproved, u.CreatedAt })
            .ToListAsync(ct);
        var branches = await db.Branches.IgnoreQueryFilters().AsNoTracking()
            .Where(b => b.TenantId == id).Select(b => new { b.Id, b.Name, b.Address, b.IsActive }).ToListAsync(ct);
        var bookingsByStatus = await db.Bookings.IgnoreQueryFilters().AsNoTracking()
            .Where(b => b.TenantId == id && b.DeletedAt == null)
            .GroupBy(b => b.Status).Select(g => new { status = g.Key.ToString(), count = g.Count() }).ToListAsync(ct);
        var resources = await db.Resources.IgnoreQueryFilters().CountAsync(r => r.TenantId == id && r.DeletedAt == null, ct);
        var bookingTypes = await db.BookingTypes.IgnoreQueryFilters().CountAsync(b => b.TenantId == id && b.DeletedAt == null, ct);
        var bookings30d = await db.Bookings.IgnoreQueryFilters().CountAsync(b => b.TenantId == id && b.DeletedAt == null && b.CreatedAt >= d30, ct);
        var audit = await db.PlatformAuditLogs.AsNoTracking()
            .Where(a => a.TargetType == "tenant" && a.TargetId == id)
            .OrderByDescending(a => a.CreatedAt).Take(20)
            .Select(a => new { a.Id, a.CreatedAt, a.ActorEmail, a.Action, a.Detail, a.Succeeded })
            .ToListAsync(ct);

        return Ok(new
        {
            t.Id, t.Name, t.BusinessType, t.SubType, t.IsActive, t.CreatedAt, t.UpdatedAt,
            t.ContactEmail, t.ContactPhone, t.Website, t.LogoUrl, t.ShortTagline,
            users, branches, bookingsByStatus, resources, bookingTypes, bookings30d, audit,
        });
    }

    public sealed class ReasonRequest { [MaxLength(500)] public string? Reason { get; set; } }

    [HttpPost("tenants/{id:guid}/suspend")]
    public Task<IActionResult> SuspendTenant(Guid id, [FromBody] ReasonRequest body, CancellationToken ct) =>
        SetTenantActive(id, false, body.Reason, ct);

    [HttpPost("tenants/{id:guid}/reactivate")]
    public Task<IActionResult> ReactivateTenant(Guid id, [FromBody] ReasonRequest body, CancellationToken ct) =>
        SetTenantActive(id, true, body.Reason, ct);

    private async Task<IActionResult> SetTenantActive(Guid id, bool active, string? reason, CancellationToken ct)
    {
        if (await RequireFreshOtpAsync(ct) is { } denied) return denied;
        var tenant = await db.Tenants.IgnoreQueryFilters().FirstOrDefaultAsync(t => t.Id == id, ct);
        if (tenant == null || CustomerAccountService.IsReserved(tenant.BusinessType)) return NotFound();

        tenant.IsActive = active;
        tenant.UpdatedAt = DateTime.UtcNow;
        await AuditAsync(active ? "tenant.reactivate" : "tenant.suspend", "tenant", tenant.Id, tenant.Name, reason, ct);
        return Ok(new { tenant.Id, tenant.IsActive, message = active ? "Tenant reactivated." : "Tenant suspended. Its users can no longer sign in." });
    }

    // ── Users ───────────────────────────────────────────────────────────

    [HttpGet("users")]
    public async Task<IActionResult> Users([FromQuery] string? search, [FromQuery] string? role, [FromQuery] Guid? tenantId, [FromQuery] string? status,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 25, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 5, 100);

        // One row per person: a global customer appears once (their identity
        // in the customer pool), never once per business they have joined.
        var query = db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(u => u.Role != UserRole.SuperAdmin && u.LinkedAccountId == null);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim().ToLower();
            query = query.Where(u => u.Email.ToLower().Contains(term) || u.FullName.ToLower().Contains(term));
        }
        if (Enum.TryParse<UserRole>(role, true, out var parsedRole) && parsedRole != UserRole.SuperAdmin) query = query.Where(u => u.Role == parsedRole);
        if (tenantId.HasValue) query = query.Where(u => u.TenantId == tenantId.Value);
        if (status == "active") query = query.Where(u => u.IsActive);
        else if (status == "inactive") query = query.Where(u => !u.IsActive);

        var total = await query.CountAsync(ct);
        var rows = await query
            .OrderByDescending(u => u.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(u => new
            {
                u.Id, u.FullName, u.Email, u.Phone, role = u.Role.ToString(), u.IsActive, u.IsApproved, u.CreatedAt,
                u.TenantId, tenantName = u.Tenant.Name, tenantActive = u.Tenant.IsActive, tenantBusinessType = u.Tenant.BusinessType,
                isGlobalCustomer = u.Tenant.BusinessType == CustomerAccountService.PoolBusinessType,
                membershipCount = db.Users.IgnoreQueryFilters().Count(m => m.LinkedAccountId == u.Id),
            })
            .ToListAsync(ct);

        return Ok(new { items = rows, total, page, pageSize, totalPages = (int)Math.Ceiling(total / (double)pageSize) });
    }

    [HttpPost("users/{id:guid}/deactivate")]
    public Task<IActionResult> DeactivateUser(Guid id, [FromBody] ReasonRequest body, CancellationToken ct) => SetUserActive(id, false, body.Reason, ct);

    [HttpPost("users/{id:guid}/activate")]
    public Task<IActionResult> ActivateUser(Guid id, [FromBody] ReasonRequest body, CancellationToken ct) => SetUserActive(id, true, body.Reason, ct);

    private async Task<IActionResult> SetUserActive(Guid id, bool active, string? reason, CancellationToken ct)
    {
        if (await RequireFreshOtpAsync(ct) is { } denied) return denied;
        var user = await db.Users.IgnoreQueryFilters().AsNoTracking().FirstOrDefaultAsync(u => u.Id == id && u.Role != UserRole.SuperAdmin, ct);
        if (user == null) return NotFound();

        // ExecuteUpdate, not the tracker: the DbContext's save guard refuses
        // to modify a user outside the caller's tenant, which is exactly what
        // the platform console does. The policy on this controller is the
        // authorisation; this is just the write.
        var now = DateTime.UtcNow;
        // A customer's memberships follow the identity.
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == id || u.LinkedAccountId == id)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsActive, active).SetProperty(u => u.UpdatedAt, now), ct);
        await AuditAsync(active ? "user.activate" : "user.deactivate", "user", id, user.Email, reason, ct);
        return Ok(new { id, isActive = active, message = active ? "User reactivated." : "User deactivated. They can no longer sign in." });
    }

    /// Issues a one-off temporary password, returned exactly once to the
    /// owner to pass on out-of-band. Never stored in plain text anywhere.
    [HttpPost("users/{id:guid}/reset-password")]
    public async Task<IActionResult> ResetUserPassword(Guid id, [FromBody] ReasonRequest body, CancellationToken ct)
    {
        if (await RequireFreshOtpAsync(ct) is { } denied) return denied;
        var user = await db.Users.IgnoreQueryFilters().AsNoTracking().FirstOrDefaultAsync(u => u.Id == id && u.Role != UserRole.SuperAdmin, ct);
        if (user == null) return NotFound();

        var temporary = GenerateTemporaryPassword();
        var hash = BCrypt.Net.BCrypt.HashPassword(temporary);
        var now = DateTime.UtcNow;
        await db.Users.IgnoreQueryFilters().Where(u => u.Id == id || u.LinkedAccountId == id)
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.PasswordHash, hash).SetProperty(u => u.UpdatedAt, now), ct);
        await AuditAsync("user.password.reset", "user", id, user.Email, body.Reason, ct);
        return Ok(new { id, temporaryPassword = temporary, message = "Temporary password issued. Share it out-of-band and ask them to change it after signing in." });
    }

    // ── Audit ───────────────────────────────────────────────────────────

    [HttpGet("audit")]
    public async Task<IActionResult> Audit([FromQuery] string? action, [FromQuery] bool? succeeded, [FromQuery] string? search,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 200);

        var query = db.PlatformAuditLogs.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(action)) query = query.Where(a => a.Action.StartsWith(action));
        if (succeeded.HasValue) query = query.Where(a => a.Succeeded == succeeded.Value);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim().ToLower();
            query = query.Where(a => a.ActorEmail.ToLower().Contains(term)
                                     || (a.TargetLabel != null && a.TargetLabel.ToLower().Contains(term))
                                     || (a.Detail != null && a.Detail.ToLower().Contains(term))
                                     || a.IpAddress.Contains(term));
        }

        var total = await query.CountAsync(ct);
        var rows = await query.OrderByDescending(a => a.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(a => new { a.Id, a.CreatedAt, a.ActorEmail, a.Action, a.TargetType, a.TargetId, a.TargetLabel, a.Detail, a.Succeeded, a.IpAddress, a.UserAgent })
            .ToListAsync(ct);
        var actions = await db.PlatformAuditLogs.Select(a => a.Action).Distinct().OrderBy(a => a).ToListAsync(ct);

        return Ok(new { items = rows, total, page, pageSize, totalPages = (int)Math.Ceiling(total / (double)pageSize), actions });
    }

    // ── helpers ────────────────────────────────────────────────────────

    private Guid CurrentUserId => Guid.Parse(
        User.FindFirst(ClaimTypes.NameIdentifier)?.Value
        ?? User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)!.Value);

    /// Step-up: a valid, unused authenticator code in the X-Platform-Otp
    /// header. Returns the response to send when it is missing or wrong.
    private async Task<IActionResult?> RequireFreshOtpAsync(CancellationToken ct)
    {
        var code = Request.Headers[OtpHeader].ToString();
        var admin = await db.PlatformAdmins.FirstAsync(a => a.UserId == CurrentUserId, ct);
        if (admin.MfaSecretEncrypted == null) return StatusCode(StatusCodes.Status403Forbidden, new { message = "MFA is not enrolled." });
        if (string.IsNullOrWhiteSpace(code))
            return StatusCode(StatusCodes.Status428PreconditionRequired, new { status = "otpRequired", message = "Enter your authenticator code to confirm this action." });

        var secret = protector.Unprotect(admin.MfaSecretEncrypted);
        if (!TotpService.TryVerify(secret, code, DateTime.UtcNow, admin.LastAcceptedTotpStep, out var step))
        {
            await AuditAsync("action.otp.failed", null, null, null, "Wrong or reused authenticator code on a protected action", ct, succeeded: false);
            return StatusCode(StatusCodes.Status403Forbidden, new { status = "otpInvalid", message = "That authenticator code is not valid." });
        }
        admin.LastAcceptedTotpStep = step;
        admin.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return null;
    }

    private async Task AuditAsync(string action, string? targetType, Guid? targetId, string? targetLabel, string? detail, CancellationToken ct, bool succeeded = true)
    {
        var ua = Request.Headers.UserAgent.ToString();
        db.PlatformAuditLogs.Add(new PlatformAuditLog
        {
            ActorUserId = CurrentUserId,
            ActorEmail = User.FindFirst(ClaimTypes.Email)?.Value ?? User.FindFirst("email")?.Value ?? string.Empty,
            Action = action,
            TargetType = targetType,
            TargetId = targetId,
            TargetLabel = targetLabel,
            Detail = detail,
            Succeeded = succeeded,
            IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            UserAgent = ua.Length > 512 ? ua[..512] : ua,
        });
        await db.SaveChangesAsync(ct);
    }

    private static string GenerateTemporaryPassword()
    {
        // Unambiguous alphabet (no 0/O, 1/l/I) - this gets read out loud.
        const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789";
        var chars = new char[12];
        for (var i = 0; i < chars.Length; i++) chars[i] = alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)];
        return $"{new string(chars, 0, 4)}-{new string(chars, 4, 4)}-{new string(chars, 8, 4)}";
    }
}
