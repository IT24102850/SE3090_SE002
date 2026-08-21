using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/[controller]")]
public class TenantController : ControllerBase
{
    private readonly ITenantService _tenantService;
    private readonly AppDbContext _db;

    public TenantController(ITenantService tenantService, AppDbContext db)
    {
        _tenantService = tenantService;
        _db = db;
    }

    // Staff + Manager directory, used by the web Resource form to link a
    // doctor resource to a login (so FR-B8 "my schedule" can filter by it),
    // and by FR-AS2 staff management (includes inactive so they can be
    // reactivated).
    [HttpGet("staff")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> GetStaff([FromQuery] Guid tenantId, [FromQuery] bool includeInactive = false)
    {
        var query = _db.Users.AsNoTracking()
            .Where(u => u.TenantId == tenantId && (u.Role == UserRole.Staff || u.Role == UserRole.Manager));
        if (!includeInactive) query = query.Where(u => u.IsActive);

        var staff = await query
            .OrderBy(u => u.FullName)
            .Select(u => new { u.Id, u.FullName, u.Email, u.Phone, u.BranchId, u.IsActive, Role = u.Role.ToString() })
            .ToListAsync();

        return Ok(staff);
    }

    // FR-AS2: Admin/Manager creates a Staff or Manager account. Only an
    // Admin may create a Manager — a Manager creating staff can only ever
    // create Staff, never another Manager or an Admin.
    [HttpPost("staff")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> CreateStaff([FromBody] CreateStaffDto dto)
    {
        if (dto.Role != Roles.Staff && dto.Role != Roles.Manager)
            return BadRequest(new { message = "Role must be Staff or Manager." });
        if (dto.Role == Roles.Manager && !User.IsInRole(Roles.Admin))
            return Forbid();

        if (await _db.Users.AnyAsync(u => u.Email == dto.Email))
            return BadRequest(new { message = "Email already registered" });

        var tenantIdClaim = User.FindFirst("tenantId")?.Value;
        if (!Guid.TryParse(tenantIdClaim, out var tenantId)) return Unauthorized();

        var user = new User
        {
            TenantId = tenantId,
            BranchId = dto.BranchId,
            Email = dto.Email,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(dto.Password),
            FullName = dto.FullName,
            Phone = dto.Phone ?? string.Empty,
            Role = dto.Role == Roles.Manager ? UserRole.Manager : UserRole.Staff,
            IsActive = true
        };

        _db.Users.Add(user);
        await _db.SaveChangesAsync();
        return Ok(new { user.Id, user.FullName, user.Email, Role = user.Role.ToString() });
    }

    // FR-AS2: branch reassignment / activate-deactivate.
    [HttpPut("staff/{id}")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> UpdateStaff(Guid id, [FromBody] UpdateStaffDto dto)
    {
        var tenantIdClaim = User.FindFirst("tenantId")?.Value;
        if (!Guid.TryParse(tenantIdClaim, out var tenantId)) return Unauthorized();

        var user = await _db.Users.FirstOrDefaultAsync(u => u.Id == id && u.TenantId == tenantId
            && (u.Role == UserRole.Staff || u.Role == UserRole.Manager));
        if (user == null) return NotFound();
        if (user.Role == UserRole.Manager && !User.IsInRole(Roles.Admin)) return Forbid();

        if (dto.BranchId.HasValue) user.BranchId = dto.BranchId.Value == Guid.Empty ? null : dto.BranchId;
        if (dto.IsActive.HasValue) user.IsActive = dto.IsActive.Value;
        user.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return Ok(new { user.Id, user.FullName, user.BranchId, user.IsActive });
    }

    // FR-AS4/AS11: business details + reschedule/cancellation cutoff policy.
    [HttpPut]
    [Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> UpdateTenant([FromBody] UpdateTenantDto dto)
    {
        var tenantIdClaim = User.FindFirst("tenantId")?.Value;
        if (!Guid.TryParse(tenantIdClaim, out var tenantId)) return Unauthorized();

        var tenant = await _db.Tenants.FindAsync(tenantId);
        if (tenant == null) return NotFound();

        if (!string.IsNullOrWhiteSpace(dto.Name)) tenant.Name = dto.Name;
        if (dto.LogoUrl != null) tenant.LogoUrl = dto.LogoUrl;
        if (dto.SubType != null) tenant.SubType = dto.SubType;
        if (dto.RescheduleCutoffHours.HasValue && dto.RescheduleCutoffHours.Value >= 0)
            tenant.RescheduleCutoffHours = dto.RescheduleCutoffHours.Value;
        if (dto.CancellationCutoffHours.HasValue && dto.CancellationCutoffHours.Value >= 0)
            tenant.CancellationCutoffHours = dto.CancellationCutoffHours.Value;
        tenant.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return Ok(tenant);
    }

    [HttpGet]
    [Authorize]
    public async Task<IActionResult> GetTenant([FromQuery] Guid tenantId)
    {
        var tenant = await _db.Tenants.AsNoTracking().FirstOrDefaultAsync(t => t.Id == tenantId);
        if (tenant == null) return NotFound();
        return Ok(tenant);
    }

    [HttpPost("onboard")]
    [AllowAnonymous]
    public async Task<ActionResult<AuthResponseDto>> Onboard([FromBody] TenantOnboardingDto dto)
    {
        try
        {
            var result = await _tenantService.OnboardTenantAsync(dto);
            return Ok(result);
        }
        catch (DbUpdateException ex) when (ex.InnerException?.Message.Contains("unique") == true)
        {
            return BadRequest(new { message = "A tenant or user with this email already exists." });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = "Onboarding failed. Please try again.", detail = ex.Message });
        }
    }
}

public record CreateStaffDto(string Email, string Password, string FullName, string? Phone, Guid? BranchId, string Role);
public record UpdateStaffDto(Guid? BranchId, bool? IsActive);
public record UpdateTenantDto(string? Name, string? LogoUrl, int? RescheduleCutoffHours, int? CancellationCutoffHours, string? SubType);