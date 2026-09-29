using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.Authorization;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services.Billing;
using SmeBackend.Services.PlatformBilling;

namespace SmeBackend.Controllers;

/// A tenant admin's side of their Unify subscription: what is on sale, what
/// they are on, what a change costs, and paying for it.
///
/// Reading is open to anyone signed in (a manager should be able to see why
/// a screen is locked), but every write is Admin-only: nobody but the owner
/// of the business commits it to a bill.
[ApiController]
[Route("api/subscription")]
[Authorize]
public sealed class SubscriptionPlansController : ControllerBase
{
    private readonly IPlatformSubscriptionService _subscriptions;
    private readonly IPlatformCheckoutService _checkout;
    private readonly IPlatformGatewayProvider _gateways;
    private readonly IEntitlementService _entitlements;

    public SubscriptionPlansController(IPlatformSubscriptionService subscriptions, IPlatformCheckoutService checkout,
        IPlatformGatewayProvider gateways, IEntitlementService entitlements)
    {
        _subscriptions = subscriptions;
        _checkout = checkout;
        _gateways = gateways;
        _entitlements = entitlements;
    }

    private Guid? TenantId => PlanGate.TenantId(User);
    private string? ActorEmail => User.FindFirst(ClaimTypes.Email)?.Value ?? User.FindFirst("email")?.Value;

    private ActionResult MissingTenant() =>
        Unauthorized(new { message = "Unauthorized: Missing tenant context in token." });

    private ActionResult FromResult<T>(BillingResult<T> result) =>
        result.Success
            ? result.StatusCode == 201 ? StatusCode(StatusCodes.Status201Created, result.Value) : Ok(result.Value)
            : StatusCode(result.StatusCode, new { message = result.Error });

    // ── The pricing page ─────────────────────────────────────────────────

    /// The catalogue. Anonymous so the marketing page can render real prices
    /// rather than a hardcoded copy that drifts from what checkout charges.
    [HttpGet("plans")]
    [AllowAnonymous]
    public async Task<ActionResult<PricingCatalogResponse>> Plans([FromQuery] string? currency, CancellationToken ct) =>
        Ok(await _subscriptions.GetCatalogAsync(TenantId, currency, ct));

    /// Which gateways the platform can actually take money through right
    /// now. The checkout screen uses this rather than offering a provider
    /// that has no credentials behind it.
    [HttpGet("providers")]
    public ActionResult Providers() => Ok(new
    {
        providers = _gateways.Available.Select(p => new
        {
            provider = p,
            live = p != PaymentProviders.Manual,
            label = p switch
            {
                PaymentProviders.Stripe => "Card (Stripe)",
                PaymentProviders.PayPal => "PayPal",
                _ => "Sandbox (no real charge)",
            },
        }),
        defaultProvider = _gateways.Default,
        defaultCurrency = _gateways.DefaultCurrency,
    });

    // ── This business ────────────────────────────────────────────────────

    [HttpGet]
    public async Task<ActionResult<PlatformSubscriptionResponse>> Current(CancellationToken ct) =>
        TenantId is not { } tenantId ? MissingTenant() : Ok(await _subscriptions.GetSubscriptionAsync(tenantId, ct));

    /// What the apps call to decide whether to show a locked state before
    /// the user walks into a 402. Same data, smaller payload.
    [HttpGet("entitlements")]
    public async Task<ActionResult> Entitlements(CancellationToken ct)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        var snapshot = await _entitlements.GetAsync(tenantId, ct);
        return Ok(new
        {
            plan = snapshot.PlanCode,
            planName = snapshot.PlanName,
            tier = snapshot.Tier,
            status = snapshot.Status,
            hasAccess = snapshot.HasAccess,
            isTrialing = snapshot.IsTrialing,
            trialEndsAt = snapshot.TrialEndsAt,
            currentPeriodEnd = snapshot.CurrentPeriodEnd,
            graceEndsAt = snapshot.GraceEndsAt,
            cancelAtPeriodEnd = snapshot.CancelAtPeriodEnd,
            features = snapshot.Limits.Features,
            limits = new
            {
                maxBranches = snapshot.Limits.MaxBranches,
                maxStaffSeats = snapshot.SeatAllowance,
                maxResources = snapshot.Limits.MaxResources,
                maxBookingsPerMonth = snapshot.Limits.MaxBookingsPerMonth,
                aiRunsPerMonth = snapshot.Limits.AiRunsPerMonth,
                smsPerMonth = snapshot.Limits.SmsPerMonth,
            },
            credits = snapshot.Credits,
        });
    }

    [HttpGet("invoices")]
    public async Task<ActionResult<IReadOnlyList<PlatformInvoiceResponse>>> Invoices(CancellationToken ct) =>
        TenantId is not { } tenantId ? MissingTenant() : Ok(await _subscriptions.InvoicesAsync(tenantId, ct));

    // ── Buying ───────────────────────────────────────────────────────────

    [HttpPost("quote")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult<SubscriptionQuoteResponse>> Quote([FromBody] SubscriptionQuoteRequest request, CancellationToken ct) =>
        TenantId is not { } tenantId ? MissingTenant() : FromResult(await _subscriptions.QuoteAsync(tenantId, request, ct));

    [HttpPost("checkout")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult<PlatformCheckoutResponse>> Checkout([FromBody] SubscriptionCheckoutRequest request, CancellationToken ct) =>
        TenantId is not { } tenantId ? MissingTenant() : FromResult(await _checkout.StartSubscriptionAsync(tenantId, ActorEmail, request, ct));

    [HttpPost("addons/checkout")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult<PlatformCheckoutResponse>> BuyAddOn([FromBody] AddOnCheckoutRequest request, CancellationToken ct) =>
        TenantId is not { } tenantId ? MissingTenant() : FromResult(await _checkout.StartAddOnAsync(tenantId, ActorEmail, request, ct));

    /// Pays an invoice that is already open - a renewal, or a retry after a
    /// card was declined.
    [HttpPost("invoices/{id:guid}/pay")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult<PlatformCheckoutResponse>> PayInvoice(Guid id, [FromBody] SubscriptionCheckoutRequest request, CancellationToken ct) =>
        TenantId is not { } tenantId ? MissingTenant() : FromResult(await _checkout.StartInvoicePaymentAsync(tenantId, id, request.Provider, request.ReturnUrl, ct));

    /// Asks the gateway where a payment got to. The answer comes from the
    /// provider, never from the caller - this is what the return URL hits.
    [HttpPost("confirm")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult<PlatformInvoiceResponse>> Confirm([FromBody] ConfirmPlatformPaymentRequest request, CancellationToken ct) =>
        TenantId is not { } tenantId ? MissingTenant() : FromResult(await _checkout.ConfirmAsync(tenantId, request, ct));

    // ── Lifecycle ────────────────────────────────────────────────────────

    public sealed class StartTrialRequest
    {
        public string? PlanCode { get; set; }
    }

    [HttpPost("trial")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult<PlatformSubscriptionResponse>> StartTrial([FromBody] StartTrialRequest? request, CancellationToken ct) =>
        TenantId is not { } tenantId
            ? MissingTenant()
            : FromResult(await _subscriptions.StartTrialAsync(tenantId,
                string.IsNullOrWhiteSpace(request?.PlanCode) ? PlatformPlanCodes.Pro : request.PlanCode.Trim(), ActorEmail, ct));

    [HttpPost("cancel")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult<PlatformSubscriptionResponse>> Cancel([FromBody] CancelPlatformSubscriptionRequest request, CancellationToken ct) =>
        TenantId is not { } tenantId ? MissingTenant() : FromResult(await _subscriptions.CancelAsync(tenantId, request, ActorEmail, ct));

    [HttpPost("resume")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult<PlatformSubscriptionResponse>> Resume(CancellationToken ct) =>
        TenantId is not { } tenantId ? MissingTenant() : FromResult(await _subscriptions.ResumeAsync(tenantId, ActorEmail, ct));

    // ── Offers ───────────────────────────────────────────────────────────

    public sealed class ValidatePromotionRequest
    {
        public string? Code { get; set; }
        public string? PlanCode { get; set; }
        public string? Period { get; set; }
        public string? Currency { get; set; }
    }

    [HttpPost("promotions/validate")]
    [Authorize(Roles = "Admin")]
    public async Task<ActionResult> ValidatePromotion([FromBody] ValidatePromotionRequest request, CancellationToken ct)
    {
        if (TenantId is not { } tenantId) return MissingTenant();
        if (string.IsNullOrWhiteSpace(request.PlanCode))
            return BadRequest(new { message = "Choose a plan first." });

        var quote = await _subscriptions.QuoteAsync(tenantId, new SubscriptionQuoteRequest
        {
            PlanCode = request.PlanCode,
            Period = request.Period,
            Currency = request.Currency,
            PromotionCode = request.Code,
        }, ct);

        if (!quote.Success) return StatusCode(quote.StatusCode, new { message = quote.Error });

        var applied = quote.Value!.PromotionCode is not null
                      && string.Equals(quote.Value.PromotionCode, request.Code?.Trim(), StringComparison.OrdinalIgnoreCase);

        return Ok(new
        {
            valid = applied,
            message = applied
                ? $"{quote.Value.PromotionCode} applied - {quote.Value.Currency} {quote.Value.Discount:N2} off."
                : "That code is not valid for this plan and term.",
            quote = quote.Value,
        });
    }
}

/// The gateways call this, so it is anonymous and lives on its own route.
/// Authentication is the provider signature, checked inside
/// PlatformCheckoutService - there is no tenant in the URL because the
/// payment row is what says who the money was for.
[ApiController]
[Route("api/subscription/webhooks")]
[AllowAnonymous]
public sealed class SubscriptionWebhookController : ControllerBase
{
    private readonly IPlatformCheckoutService _checkout;

    public SubscriptionWebhookController(IPlatformCheckoutService checkout) => _checkout = checkout;

    [HttpPost("{provider}")]
    public async Task<ActionResult> Receive(string provider, CancellationToken ct)
    {
        using var reader = new StreamReader(Request.Body);
        var body = await reader.ReadToEndAsync(ct);
        var headers = Request.Headers.ToDictionary(h => h.Key, h => h.Value.ToString(), StringComparer.OrdinalIgnoreCase);

        var result = await _checkout.HandleWebhookAsync(provider, body, headers, ct);
        return result.Success
            ? Ok(new { status = result.Value })
            : StatusCode(result.StatusCode, new { message = result.Error });
    }
}
