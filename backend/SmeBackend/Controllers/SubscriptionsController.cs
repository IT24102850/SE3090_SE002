using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.DTOs;
using SmeBackend.Services;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/subscriptions")]
[Authorize]
[Produces("application/json")]
public class SubscriptionsController : ControllerBase
{
    private readonly IBillingService _billingService;

    public SubscriptionsController(IBillingService billingService)
    {
        _billingService = billingService;
    }

    /// <summary>
    /// Retrieves a paginated list of customer subscriptions for the authenticated tenant.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(SubscriptionListResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<SubscriptionListResponse>> GetSubscriptions(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? status = null,
        [FromQuery] Guid? customerId = null,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });
        }

        var result = await _billingService.GetSubscriptionsAsync(
            tenantId,
            page,
            pageSize,
            status,
            customerId,
            cancellationToken);

        return Ok(result);
    }

    /// <summary>
    /// Creates a new subscription for a customer under the authenticated tenant.
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(SubscriptionResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<SubscriptionResponse>> CreateSubscription(
        [FromBody] CreateSubscriptionRequest request,
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

        var (success, error, subscription) = await _billingService.CreateSubscriptionAsync(
            tenantId,
            request,
            cancellationToken);

        if (!success)
        {
            return BadRequest(new { message = error });
        }

        return StatusCode(StatusCodes.Status201Created, subscription);
    }

    /// <summary>
    /// Cancels an active subscription.
    /// </summary>
    [HttpPut("{id:guid}/cancel")]
    [ProducesResponseType(typeof(SubscriptionResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<SubscriptionResponse>> CancelSubscription(
        [FromRoute] Guid id,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });
        }

        var (success, error, subscription) = await _billingService.CancelSubscriptionAsync(
            tenantId,
            id,
            cancellationToken);

        if (!success)
        {
            if (error == "Subscription not found.")
            {
                return NotFound(new { message = error });
            }

            return BadRequest(new { message = error });
        }

        return Ok(subscription);
    }

    private bool TryGetTenantId(out Guid tenantId)
    {
        var tenantClaim = User.FindFirst("tenantId")?.Value;
        return Guid.TryParse(tenantClaim, out tenantId);
    }
}
