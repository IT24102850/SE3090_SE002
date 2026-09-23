using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Services.Billing;

namespace SmeBackend.Controllers;

/// Payment gateway settings (Stripe / PayPal credentials per tenant).
[ApiController]
[Route("api/payment-gateways")]
[Authorize]
[Produces("application/json")]
public class PaymentGatewaysController : BillingControllerBase
{
    private readonly IBillingSettingsService _settings;
    private readonly AppDbContext _db;

    public PaymentGatewaysController(IBillingSettingsService settings, AppDbContext db)
    {
        _settings = settings;
        _db = db;
    }

    [HttpGet]
    [Authorize(Policy = "AdminOnly")]
    [ProducesResponseType(typeof(IReadOnlyList<PaymentGatewayResponse>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<PaymentGatewayResponse>>> GetGateways(CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return Ok(await _settings.GetGatewaysAsync(actor.TenantId, ct));
    }

    /// <summary>
    /// The payment options a payer can pick - provider and publishable key
    /// only, never a secret. Always includes the sandbox.
    /// </summary>
    [HttpGet("available")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> GetAvailable(CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var active = await _db.PaymentGateways.AsNoTracking()
            .Where(g => g.TenantId == actor.TenantId && g.IsActive && g.Provider != PaymentProviders.Manual)
            .OrderBy(g => g.CreatedAt)
            .Select(g => new { g.Provider, g.Name, g.PublicKey, g.IsTestMode, g.Currency })
            .ToListAsync(ct);
        return Ok(new
        {
            providers = active,
            sandboxAvailable = true,
        });
    }

    [HttpPost]
    [Authorize(Policy = "AdminOnly")]
    [ProducesResponseType(typeof(PaymentGatewayResponse), StatusCodes.Status201Created)]
    public async Task<ActionResult<PaymentGatewayResponse>> Create([FromBody] UpsertPaymentGatewayRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _settings.UpsertGatewayAsync(actor.TenantId, null, request, PublicBaseUrl(), ct));
    }

    [HttpPut("{id:guid}")]
    [Authorize(Policy = "AdminOnly")]
    [ProducesResponseType(typeof(PaymentGatewayResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<PaymentGatewayResponse>> Update(Guid id, [FromBody] UpsertPaymentGatewayRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _settings.UpsertGatewayAsync(actor.TenantId, id, request, PublicBaseUrl(), ct));
    }

    [HttpDelete("{id:guid}")]
    [Authorize(Policy = "AdminOnly")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var result = await _settings.DeleteGatewayAsync(actor.TenantId, id, ct);
        return result.Success ? NoContent() : FromResult(result);
    }

    /// <summary>Checks the stored credentials against the provider.</summary>
    [HttpPost("{id:guid}/test")]
    [Authorize(Policy = "AdminOnly")]
    [ProducesResponseType(typeof(GatewayTestResult), StatusCodes.Status200OK)]
    public async Task<ActionResult<GatewayTestResult>> Test(Guid id, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return FromResult(await _settings.TestGatewayAsync(actor.TenantId, id, ct));
    }
}

/// The customer picker for invoices, subscriptions and schedules. Staff
/// need it, and /api/users is Admin-only (it exposes staff accounts too).
[ApiController]
[Route("api/billing/customers")]
[Authorize(Policy = "StaffPlus")]
[Produces("application/json")]
public class BillingCustomersController : BillingControllerBase
{
    private readonly AppDbContext _db;

    public BillingCustomersController(AppDbContext db) => _db = db;

    [HttpGet]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> Search([FromQuery] string? search = null, [FromQuery] int take = 50, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var q = _db.Users.IgnoreQueryFilters().AsNoTracking()
            .Where(u => u.TenantId == actor.TenantId && u.Role == Models.UserRole.Customer && u.IsActive);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim().ToLower();
            q = q.Where(u => u.FullName.ToLower().Contains(term) || u.Email.ToLower().Contains(term) || u.Phone.Contains(term));
        }
        var rows = await q.OrderBy(u => u.FullName).Take(Math.Clamp(take, 1, 200))
            .Select(u => new { u.Id, u.FullName, u.Email, u.Phone, u.InsuranceProvider, u.InsuranceNumber })
            .ToListAsync(ct);
        return Ok(rows);
    }
}

/// Provider webhooks and payment confirmation.
[ApiController]
[Route("api/payments")]
[Produces("application/json")]
public class PaymentsController : BillingControllerBase
{
    private readonly IPaymentCheckoutService _checkout;

    public PaymentsController(IPaymentCheckoutService checkout) => _checkout = checkout;

    /// <summary>
    /// Confirms a checkout: reads the payment's status back from the
    /// provider (or, in the sandbox, completes it).
    /// </summary>
    [HttpPost("confirm")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> Confirm([FromBody] ConfirmCheckoutRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var result = await _checkout.ConfirmCheckoutAsync(actor, request, ct);
        return FromResult(result, r => new { payment = r.Payment, invoice = r.Invoice });
    }

    /// <summary>
    /// Stripe / PayPal webhook endpoint. Anonymous, but every event's
    /// signature is verified against the tenant's stored secret.
    /// </summary>
    [HttpPost("webhooks/{provider}/{tenantId:guid}")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Webhook(string provider, Guid tenantId, CancellationToken ct = default)
    {
        using var reader = new StreamReader(Request.Body);
        var body = await reader.ReadToEndAsync(ct);
        if (body.Length > 512 * 1024) return BadRequest(new { message = "Payload too large." });

        var headers = Request.Headers.ToDictionary(h => h.Key, h => h.Value.ToString(), StringComparer.OrdinalIgnoreCase);
        var result = await _checkout.HandleWebhookAsync(provider, tenantId, body, headers, ct);
        return result.Success ? Ok(new { received = true, status = result.Value }) : StatusCode(result.StatusCode, new { message = result.Error });
    }
}

/// Commission rules (real estate, agents, referrals) and splits.
[ApiController]
[Route("api/commission-rules")]
[Authorize(Policy = "StaffPlus")]
[Produces("application/json")]
public class CommissionRulesController : BillingControllerBase
{
    private readonly IBillingSettingsService _settings;

    public CommissionRulesController(IBillingSettingsService settings) => _settings = settings;

    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<CommissionRuleResponse>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<CommissionRuleResponse>>> Get([FromQuery] bool activeOnly = false, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return Ok(await _settings.GetCommissionRulesAsync(actor.TenantId, activeOnly, ct));
    }

    [HttpPost]
    [Authorize(Policy = "ManagerPlus")]
    [ProducesResponseType(typeof(CommissionRuleResponse), StatusCodes.Status201Created)]
    public async Task<ActionResult<CommissionRuleResponse>> Create([FromBody] UpsertCommissionRuleRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _settings.UpsertCommissionRuleAsync(actor.TenantId, null, request, ct));
    }

    [HttpPut("{id:guid}")]
    [Authorize(Policy = "ManagerPlus")]
    [ProducesResponseType(typeof(CommissionRuleResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<CommissionRuleResponse>> Update(Guid id, [FromBody] UpsertCommissionRuleRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _settings.UpsertCommissionRuleAsync(actor.TenantId, id, request, ct));
    }

    [HttpDelete("{id:guid}")]
    [Authorize(Policy = "ManagerPlus")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var result = await _settings.DeleteCommissionRuleAsync(actor.TenantId, id, ct);
        return result.Success ? NoContent() : FromResult(result);
    }

    /// <summary>How a deal's commission splits across the active rules.</summary>
    [HttpPost("calculate")]
    [ProducesResponseType(typeof(CommissionSplitResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<CommissionSplitResponse>> Calculate([FromBody] CommissionSplitRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _settings.CalculateCommissionSplitAsync(actor.TenantId, request, ct));
    }
}

/// Invoice templates built in the Invoice Designer.
[ApiController]
[Route("api/invoice-templates")]
[Authorize(Policy = "StaffPlus")]
[Produces("application/json")]
public class InvoiceTemplatesController : BillingControllerBase
{
    private readonly IBillingSettingsService _settings;

    public InvoiceTemplatesController(IBillingSettingsService settings) => _settings = settings;

    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<InvoiceTemplateResponse>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<InvoiceTemplateResponse>>> Get(CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return Ok(await _settings.GetTemplatesAsync(actor.TenantId, ct));
    }

    [HttpPost]
    [Authorize(Policy = "ManagerPlus")]
    [ProducesResponseType(typeof(InvoiceTemplateResponse), StatusCodes.Status201Created)]
    public async Task<ActionResult<InvoiceTemplateResponse>> Create([FromBody] UpsertInvoiceTemplateRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _settings.UpsertTemplateAsync(actor.TenantId, null, request, ct));
    }

    [HttpPut("{id:guid}")]
    [Authorize(Policy = "ManagerPlus")]
    [ProducesResponseType(typeof(InvoiceTemplateResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<InvoiceTemplateResponse>> Update(Guid id, [FromBody] UpsertInvoiceTemplateRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _settings.UpsertTemplateAsync(actor.TenantId, id, request, ct));
    }

    [HttpDelete("{id:guid}")]
    [Authorize(Policy = "ManagerPlus")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var result = await _settings.DeleteTemplateAsync(actor.TenantId, id, ct);
        return result.Success ? NoContent() : FromResult(result);
    }
}
