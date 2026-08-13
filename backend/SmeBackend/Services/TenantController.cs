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
    // doctor resource to a login (so FR-B8 "my schedule" can filter by it).
    [HttpGet("staff")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> GetStaff([FromQuery] Guid tenantId)
    {
        var staff = await _db.Users.AsNoTracking()
            .Where(u => u.TenantId == tenantId && u.IsActive
                && (u.Role == UserRole.Staff || u.Role == UserRole.Manager))
            .OrderBy(u => u.FullName)
            .Select(u => new { u.Id, u.FullName, u.Email, Role = u.Role.ToString() })
            .ToListAsync();

        return Ok(staff);
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