using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.DTOs;
using SmeBackend.Services;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/insurance-claims")]
[Authorize]
[Produces("application/json")]
public class InsuranceClaimsController : ControllerBase
{
    private readonly IBillingService _billingService;

    public InsuranceClaimsController(IBillingService billingService)
    {
        _billingService = billingService;
    }

    /// <summary>
    /// Retrieves a paginated list of insurance claims belonging to the authenticated tenant's invoices.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(InsuranceClaimListResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<InsuranceClaimListResponse>> GetInsuranceClaims(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? status = null,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });
        }

        var result = await _billingService.GetInsuranceClaimsAsync(
            tenantId,
            page,
            pageSize,
            status,
            cancellationToken);

        return Ok(result);
    }

    /// <summary>
    /// Creates a new insurance claim linked to an invoice belonging to the authenticated tenant.
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(InsuranceClaimResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<InsuranceClaimResponse>> CreateInsuranceClaim(
        [FromBody] CreateInsuranceClaimRequest request,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });
        }

        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var (success, error, claim) = await _billingService.CreateInsuranceClaimAsync(
            tenantId,
            request,
            cancellationToken);

        if (!success)
        {
            return BadRequest(new { message = error });
        }

        return StatusCode(StatusCodes.Status201Created, claim);
    }

    /// <summary>
    /// Updates the status of an insurance claim (e.g. Approved, Rejected).
    /// </summary>
    [HttpPut("{id:guid}/status")]
    [ProducesResponseType(typeof(InsuranceClaimResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<InsuranceClaimResponse>> UpdateClaimStatus(
        [FromRoute] Guid id,
        [FromBody] UpdateInsuranceClaimStatusRequest request,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });
        }

        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var (success, error, claim) = await _billingService.UpdateInsuranceClaimStatusAsync(
            tenantId,
            id,
            request,
            cancellationToken);

        if (!success)
        {
            if (error == "Insurance claim not found.")
            {
                return NotFound(new { message = error });
            }

            return BadRequest(new { message = error });
        }

        return Ok(claim);
    }

    private bool TryGetTenantId(out Guid tenantId)
    {
        var tenantClaim = User.FindFirst("tenantId")?.Value;
        return Guid.TryParse(tenantClaim, out tenantId);
    }
}
