using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.DTOs;
using SmeBackend.Services;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/[controller]")]
public class TenantController : ControllerBase
{
    private readonly ITenantService _tenantService;
    
    public TenantController(ITenantService tenantService)
    {
        _tenantService = tenantService;
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