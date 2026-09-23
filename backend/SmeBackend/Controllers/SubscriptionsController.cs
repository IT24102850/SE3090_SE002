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
public class SubscriptionsController : BillingControllerBase
{
    private readonly IBillingService _billingService;

    public SubscriptionsController(IBillingService billingService)
    {
        _billingService = billingService;
    }

    /// <summary>
    /// Lists subscriptions. Customers only see their own.
    /// </summary>
    /// <remarks>GET /api/subscriptions?tenantId=&amp;customerId=&amp;status=</remarks>
    [HttpGet]
    [ProducesResponseType(typeof(SubscriptionListResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<SubscriptionListResponse>> GetSubscriptions(
        [FromQuery] Guid? tenantId = null,
        [FromQuery] Guid? customerId = null,
        [FromQuery] string? status = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (RejectForeignTenant(actor, tenantId) is { } forbidden) return forbidden;
        return Ok(await _billingService.GetSubscriptionsAsync(actor, page, pageSize, status, customerId, ct));
    }

    /// <summary>The plans this business sells, for the upgrade/downgrade picker.</summary>
    [HttpGet("plans")]
    [ProducesResponseType(typeof(IReadOnlyList<SubscriptionPlanOption>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<SubscriptionPlanOption>>> GetPlans(CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return Ok(await _billingService.GetPlanOptionsAsync(actor, ct));
    }

    /// <summary>Renewals falling in a date range (the renewal calendar).</summary>
    [HttpGet("renewals")]
    [Authorize(Policy = "StaffPlus")]
    [ProducesResponseType(typeof(IReadOnlyList<RenewalCalendarEntry>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<RenewalCalendarEntry>>> GetRenewals(
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var start = from ?? DateTime.UtcNow.Date;
        var end = to ?? start.AddDays(30);
        if (end < start) return BadRequest(new { message = "'to' must be after 'from'." });
        if ((end - start).TotalDays > 400) return BadRequest(new { message = "The range can span at most 400 days." });
        return Ok(await _billingService.GetRenewalCalendarAsync(actor, start, end, ct));
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(SubscriptionResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<SubscriptionResponse>> GetSubscription(Guid id, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return FromResult(await _billingService.GetSubscriptionAsync(actor, id, ct));
    }

    /// <summary>The subscription's invoices - its payment history.</summary>
    [HttpGet("{id:guid}/invoices")]
    [ProducesResponseType(typeof(InvoiceListResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<InvoiceListResponse>> GetSubscriptionInvoices(Guid id, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return FromResult(await _billingService.GetSubscriptionInvoicesAsync(actor, id, ct));
    }

    /// <summary>Creates a subscription, optionally raising its first invoice.</summary>
    [HttpPost]
    [Authorize(Policy = "StaffPlus")]
    [ProducesResponseType(typeof(SubscriptionResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<SubscriptionResponse>> CreateSubscription([FromBody] CreateSubscriptionRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _billingService.CreateSubscriptionAsync(actor, request, ct));
    }

    /// <summary>
    /// Cancels a subscription. With a refund it needs an Admin's approval
    /// (202, status PendingCancel) unless an Admin makes the request.
    /// </summary>
    [HttpPut("{id:guid}/cancel")]
    [ProducesResponseType(typeof(CancelSubscriptionResult), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(CancelSubscriptionResult), StatusCodes.Status202Accepted)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<CancelSubscriptionResult>> CancelSubscription(Guid id, [FromBody] CancelSubscriptionRequest? request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _billingService.CancelSubscriptionAsync(actor, id, request ?? new CancelSubscriptionRequest(), ct));
    }

    /// <summary>Upgrades or downgrades the plan. Upgrades are invoiced pro rata.</summary>
    [HttpPut("{id:guid}/change-plan")]
    [ProducesResponseType(typeof(SubscriptionResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<SubscriptionResponse>> ChangePlan(Guid id, [FromBody] ChangePlanRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _billingService.ChangePlanAsync(actor, id, request, ct));
    }
}
