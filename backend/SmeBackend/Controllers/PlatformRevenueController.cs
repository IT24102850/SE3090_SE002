using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Services.PlatformBilling;

namespace SmeBackend.Controllers;

/// The money half of the owner's console: what the platform earns, who is on
/// what, how the funnel is doing, and the two levers the owner has over an
/// individual tenant's subscription.
///
/// Same guard as the rest of /api/platform - the PlatformOwner policy on the
/// way in, and a fresh authenticator code on anything that changes what a
/// tenant is paying.
[ApiController]
[Route("api/platform/revenue")]
[Authorize(Policy = PlatformOwnerPolicy.Name)]
public sealed class PlatformRevenueController(AppDbContext db,
    IEntitlementService entitlements, IPlatformSecretProtector protector) : ControllerBase
{
    /// Figures are reported in one currency. Subscriptions sold in another
    /// are converted at the operator's configured rate, the same one the
    /// gateway settles at - see PlatformSettlement.
    private const string ReportingCurrency = "LKR";

    [HttpGet]
    public async Task<IActionResult> Overview(CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var d30 = now.Date.AddDays(-30);
        var d60 = now.Date.AddDays(-60);

        var live = await db.PlatformSubscriptions.AsNoTracking()
            .Where(s => s.Tier > 0)
            .Select(s => new { s.TenantId, s.PlanCode, s.Tier, s.Status, s.Period, s.Currency, s.Amount, s.IsComplimentary, s.CurrentPeriodEnd, s.CancelAtPeriodEnd, s.StartedAt })
            .ToListAsync(ct);

        // MRR: every paid term normalised to a month. A comped account earns
        // nothing and is excluded rather than counted at its list price.
        var paying = live.Where(s => !s.IsComplimentary
                                     && s.Status is PlatformSubscriptionStatuses.Active
                                         or PlatformSubscriptionStatuses.PastDue
                                         or PlatformSubscriptionStatuses.Cancelling).ToList();

        decimal mrr = 0m;
        foreach (var s in paying)
            mrr += Normalise(s.Amount, s.Currency) / BillingPeriods.Months(s.Period);
        mrr = Math.Round(mrr, 2, MidpointRounding.AwayFromZero);

        var planMix = live
            .GroupBy(s => s.PlanCode)
            .Select(g => new
            {
                planCode = g.Key,
                count = g.Count(),
                paying = g.Count(s => !s.IsComplimentary),
                mrr = Math.Round(g.Where(s => !s.IsComplimentary).Sum(s => Normalise(s.Amount, s.Currency) / BillingPeriods.Months(s.Period)), 2),
            })
            .OrderByDescending(g => g.mrr)
            .ToList();

        var termMix = live
            .GroupBy(s => s.Period)
            .Select(g => new { period = g.Key, label = BillingPeriods.Label(g.Key), count = g.Count() })
            .ToList();

        var totalTenants = await db.Tenants.IgnoreQueryFilters()
            .CountAsync(t => t.BusinessType != PlatformOwnerSeeder.PlatformBusinessType
                             && t.BusinessType != CustomerAccountService.PoolBusinessType, ct);

        var trialing = live.Count(s => s.Status == PlatformSubscriptionStatuses.Trialing);
        var pastDue = live.Count(s => s.Status == PlatformSubscriptionStatuses.PastDue);
        var cancelling = live.Count(s => s.CancelAtPeriodEnd);

        // Collected, not invoiced: only payments the gateway confirmed.
        var paid30 = await db.PlatformInvoices.AsNoTracking()
            .Where(i => i.Status == PlatformInvoiceStatuses.Paid && i.PaidAt >= d30)
            .Select(i => new { i.Total, i.Currency, i.Kind })
            .ToListAsync(ct);
        var collected30 = Math.Round(paid30.Sum(i => Normalise(i.Total, i.Currency)), 2);
        var addOnRevenue30 = Math.Round(paid30.Where(i => i.Kind == PlatformInvoiceKinds.AddOn)
            .Sum(i => Normalise(i.Total, i.Currency)), 2);

        var events = await db.PlatformSubscriptionEvents.AsNoTracking()
            .Where(e => e.CreatedAt >= d60)
            .Select(e => new { e.EventType, e.CreatedAt, e.TenantId })
            .ToListAsync(ct);

        var trialsStarted30 = events.Count(e => e.EventType == "trial.start" && e.CreatedAt >= d30);
        var trialsConverted30 = events.Count(e => e.EventType == "trial.convert" && e.CreatedAt >= d30);
        var trialsExpired30 = events.Count(e => e.EventType == "trial.expire" && e.CreatedAt >= d30);
        var trialsResolved = trialsConverted30 + trialsExpired30;

        var newPaid30 = events.Count(e => e.EventType is "subscribe" or "upgrade" && e.CreatedAt >= d30);
        var churned30 = events.Count(e => e.EventType == "expire" && e.CreatedAt >= d30);

        var paidAtStart = paying.Count - newPaid30 + churned30;

        var recent = await db.PlatformSubscriptionEvents.AsNoTracking()
            .OrderByDescending(e => e.CreatedAt).Take(20)
            .Select(e => new { e.Id, e.CreatedAt, e.EventType, e.FromPlanCode, e.ToPlanCode, e.Period, e.Currency, e.Amount, e.ActorEmail, e.Detail, e.TenantId })
            .ToListAsync(ct);
        var recentTenantIds = recent.Select(r => r.TenantId).Distinct().ToList();
        var recentNames = await db.Tenants.IgnoreQueryFilters().AsNoTracking()
            .Where(t => recentTenantIds.Contains(t.Id))
            .ToDictionaryAsync(t => t.Id, t => t.Name, ct);

        return Ok(new
        {
            generatedAt = now,
            currency = ReportingCurrency,
            mrr,
            arr = Math.Round(mrr * 12, 2),
            arpa = paying.Count == 0 ? 0m : Math.Round(mrr / paying.Count, 2),
            collected30d = collected30,
            addOnRevenue30d = addOnRevenue30,
            tenants = new
            {
                total = totalTenants,
                paying = paying.Count,
                free = Math.Max(0, totalTenants - live.Count),
                trialing,
                pastDue,
                cancelling,
                complimentary = live.Count(s => s.IsComplimentary),
                paidConversionRate = totalTenants == 0 ? (double?)null : Math.Round(paying.Count * 100.0 / totalTenants, 1),
            },
            funnel = new
            {
                trialsStarted30d = trialsStarted30,
                trialsConverted30d = trialsConverted30,
                trialsExpired30d = trialsExpired30,
                // Null rather than a fake zero when nothing has resolved yet.
                trialConversionRate = trialsResolved == 0 ? (double?)null : Math.Round(trialsConverted30 * 100.0 / trialsResolved, 1),
                newPaid30d = newPaid30,
                churned30d = churned30,
                churnRate = paidAtStart <= 0 ? (double?)null : Math.Round(churned30 * 100.0 / paidAtStart, 1),
            },
            planMix,
            termMix,
            recentEvents = recent.Select(e => new
            {
                e.Id, e.CreatedAt, e.EventType, e.FromPlanCode, e.ToPlanCode, e.Period, e.Currency, e.Amount, e.ActorEmail, e.Detail,
                e.TenantId,
                tenantName = recentNames.TryGetValue(e.TenantId, out var name) ? name : "(unknown)",
            }),
        });
    }

    /// Every tenant with their standing, for the console's subscriptions table.
    [HttpGet("subscriptions")]
    public async Task<IActionResult> Subscriptions([FromQuery] string? plan, [FromQuery] string? status,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 25, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 5, 100);

        var query = db.PlatformSubscriptions.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(plan)) query = query.Where(s => s.PlanCode == plan);
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(s => s.Status == status);

        var total = await query.CountAsync(ct);
        var rows = await query
            .OrderByDescending(s => s.Tier).ThenByDescending(s => s.UpdatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(s => new
            {
                s.Id, s.TenantId, tenantName = s.Tenant.Name, businessType = s.Tenant.BusinessType,
                s.PlanCode, s.Tier, s.Status, s.Period, s.Currency, s.Amount,
                s.CurrentPeriodStart, s.CurrentPeriodEnd, s.TrialEndsAt, s.GraceEndsAt,
                s.AutoRenew, s.CancelAtPeriodEnd, s.IsComplimentary, s.ExtraSeats, s.LastPaymentAt, s.StartedAt,
                openInvoices = db.PlatformInvoices.Count(i => i.TenantId == s.TenantId && i.Status == PlatformInvoiceStatuses.Issued),
            })
            .ToListAsync(ct);

        return Ok(new { items = rows, total, page, pageSize, totalPages = (int)Math.Ceiling(total / (double)pageSize) });
    }

    [HttpGet("invoices")]
    public async Task<IActionResult> Invoices([FromQuery] string? status, [FromQuery] int page = 1, [FromQuery] int pageSize = 25, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 5, 100);

        var query = db.PlatformInvoices.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(i => i.Status == status);

        var total = await query.CountAsync(ct);
        var rows = await query
            .OrderByDescending(i => i.IssuedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(i => new
            {
                i.Id, i.Number, i.Kind, i.PlanCode, i.Period, i.Currency, i.Total, i.Status,
                i.IssuedAt, i.DueAt, i.PaidAt, i.TenantId, tenantName = i.Tenant.Name,
                provider = i.Payments.OrderByDescending(p => p.CreatedAt).Select(p => p.Provider).FirstOrDefault(),
            })
            .ToListAsync(ct);

        return Ok(new { items = rows, total, page, pageSize, totalPages = (int)Math.Ceiling(total / (double)pageSize) });
    }

    // ── Levers ───────────────────────────────────────────────────────────

    public sealed class CompRequest
    {
        [Required, MaxLength(40)] public string PlanCode { get; set; } = string.Empty;
        [MaxLength(20)] public string? Period { get; set; }
        [Range(1, 60)] public int Months { get; set; } = 12;
        [Required, MaxLength(500)] public string Reason { get; set; } = string.Empty;
    }

    /// Puts a tenant on a plan for free - a pilot, a partner, an apology.
    /// It never touches a gateway and is excluded from MRR, so comping an
    /// account cannot quietly inflate the revenue figures above.
    [HttpPost("subscriptions/{tenantId:guid}/comp")]
    public async Task<IActionResult> Comp(Guid tenantId, [FromBody] CompRequest body, CancellationToken ct)
    {
        if (await RequireFreshOtpAsync(ct) is { } denied) return denied;

        var plan = await db.PlatformPlans.FirstOrDefaultAsync(p => p.Code == body.PlanCode, ct);
        if (plan is null) return NotFound(new { message = "That plan does not exist." });

        var tenant = await db.Tenants.IgnoreQueryFilters().FirstOrDefaultAsync(t => t.Id == tenantId, ct);
        if (tenant is null) return NotFound(new { message = "Tenant not found." });

        var subscription = await entitlements.EnsureSubscriptionAsync(tenantId, ct);
        var now = DateTime.UtcNow;
        var from = subscription.PlanCode;

        subscription.PlanId = plan.Id;
        subscription.PlanCode = plan.Code;
        subscription.Tier = plan.Tier;
        subscription.PriceId = null;
        subscription.Status = PlatformSubscriptionStatuses.Active;
        subscription.Period = BillingPeriods.Normalize(body.Period) ?? BillingPeriods.Monthly;
        subscription.Amount = 0m;
        subscription.CurrentPeriodStart = now;
        subscription.CurrentPeriodEnd = now.AddMonths(body.Months);
        subscription.TrialEndsAt = null;
        subscription.AutoRenew = true;
        subscription.CancelAtPeriodEnd = false;
        subscription.GraceEndsAt = null;
        subscription.IsComplimentary = true;
        subscription.ComplimentaryReason = body.Reason;
        subscription.UpdatedAt = now;

        db.PlatformSubscriptionEvents.Add(new PlatformSubscriptionEvent
        {
            TenantId = tenantId,
            SubscriptionId = subscription.Id,
            EventType = "comp",
            FromPlanCode = from,
            ToPlanCode = plan.Code,
            ActorEmail = ActorEmail,
            Detail = body.Reason,
        });

        await db.SaveChangesAsync(ct);
        entitlements.Invalidate(tenantId);
        await AuditAsync("subscription.comp", tenantId, tenant.Name, $"{plan.Code} for {body.Months} months - {body.Reason}", ct);

        return Ok(new { message = $"{tenant.Name} is on {plan.Name} free until {subscription.CurrentPeriodEnd:d MMM yyyy}." });
    }

    public sealed class ExtendRequest
    {
        [Range(1, 365)] public int Days { get; set; } = 30;
        [Required, MaxLength(500)] public string Reason { get; set; } = string.Empty;
    }

    /// Pushes a term out without charging for it - the support answer to
    /// "our card was blocked for a week".
    [HttpPost("subscriptions/{tenantId:guid}/extend")]
    public async Task<IActionResult> Extend(Guid tenantId, [FromBody] ExtendRequest body, CancellationToken ct)
    {
        if (await RequireFreshOtpAsync(ct) is { } denied) return denied;

        var subscription = await db.PlatformSubscriptions.FirstOrDefaultAsync(s => s.TenantId == tenantId, ct);
        if (subscription is null) return NotFound(new { message = "That tenant has no subscription." });
        if (subscription.Tier == 0) return BadRequest(new { message = "That tenant is on the free plan." });

        var now = DateTime.UtcNow;
        var basis = subscription.CurrentPeriodEnd is { } end && end > now ? end : now;
        subscription.CurrentPeriodEnd = basis.AddDays(body.Days);
        if (subscription.Status == PlatformSubscriptionStatuses.PastDue)
        {
            subscription.Status = PlatformSubscriptionStatuses.Active;
            subscription.GraceEndsAt = null;
        }
        subscription.UpdatedAt = now;

        db.PlatformSubscriptionEvents.Add(new PlatformSubscriptionEvent
        {
            TenantId = tenantId,
            SubscriptionId = subscription.Id,
            EventType = "extend",
            ToPlanCode = subscription.PlanCode,
            ActorEmail = ActorEmail,
            Detail = $"{body.Days} days - {body.Reason}",
        });

        await db.SaveChangesAsync(ct);
        entitlements.Invalidate(tenantId);
        await AuditAsync("subscription.extend", tenantId, null, $"{body.Days} days - {body.Reason}", ct);

        return Ok(new { subscription.CurrentPeriodEnd, message = $"Term extended to {subscription.CurrentPeriodEnd:d MMM yyyy}." });
    }

    // ── helpers ──────────────────────────────────────────────────────────

    private static decimal Normalise(decimal amount, string currency) =>
        // A single operator rate, matching the one the reporting currency is
        // quoted at everywhere else in this console. Not a live feed: a
        // revenue chart that moves because a rate moved is not a revenue
        // chart.
        string.Equals(currency, ReportingCurrency, StringComparison.OrdinalIgnoreCase)
            ? amount
            : currency.ToUpperInvariant() switch
            {
                "USD" => amount * 300m,
                _ => amount,
            };

    private Guid CurrentUserId => Guid.Parse(
        User.FindFirst(ClaimTypes.NameIdentifier)?.Value
        ?? User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)!.Value);

    private string ActorEmail => User.FindFirst(ClaimTypes.Email)?.Value ?? User.FindFirst("email")?.Value ?? string.Empty;

    private async Task<IActionResult?> RequireFreshOtpAsync(CancellationToken ct)
    {
        var code = Request.Headers[PlatformController.OtpHeader].ToString();
        var admin = await db.PlatformAdmins.FirstAsync(a => a.UserId == CurrentUserId, ct);
        if (admin.MfaSecretEncrypted == null)
            return StatusCode(StatusCodes.Status403Forbidden, new { message = "MFA is not enrolled." });
        if (string.IsNullOrWhiteSpace(code))
            return StatusCode(StatusCodes.Status428PreconditionRequired,
                new { status = "otpRequired", message = "Enter your authenticator code to confirm this action." });

        var secret = protector.Unprotect(admin.MfaSecretEncrypted);
        if (!TotpService.TryVerify(secret, code, DateTime.UtcNow, admin.LastAcceptedTotpStep, out var step))
            return StatusCode(StatusCodes.Status403Forbidden, new { status = "otpInvalid", message = "That authenticator code is not valid." });

        admin.LastAcceptedTotpStep = step;
        admin.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return null;
    }

    private async Task AuditAsync(string action, Guid targetId, string? targetLabel, string? detail, CancellationToken ct)
    {
        var ua = Request.Headers.UserAgent.ToString();
        db.PlatformAuditLogs.Add(new PlatformAuditLog
        {
            ActorUserId = CurrentUserId,
            ActorEmail = ActorEmail,
            Action = action,
            TargetType = "tenant",
            TargetId = targetId,
            TargetLabel = targetLabel,
            Detail = detail,
            Succeeded = true,
            IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            UserAgent = ua.Length > 512 ? ua[..512] : ua,
        });
        await db.SaveChangesAsync(ct);
    }
}
