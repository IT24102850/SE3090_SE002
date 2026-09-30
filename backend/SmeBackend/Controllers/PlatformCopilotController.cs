using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Services.Billing;
using SmeBackend.Services.PlatformBilling;

namespace SmeBackend.Controllers;

/// The platform owner's Agentic AI console.
///
/// The approval boundary is the whole point of this controller. Starting a
/// run and reading a trace need the PlatformOwner policy, like the rest of
/// the console. **Applying** what a run proposed additionally needs a fresh
/// authenticator code in X-Platform-Otp - the same step-up that guards
/// suspending a tenant or resetting a password.
///
/// That is what makes "pause for human approval" a real control rather than
/// a flag. The agent service has no database credentials, no write tool and
/// no way to produce a TOTP code, so there is no sequence of model outputs -
/// however confidently worded, however well injected - that moves money on
/// this platform. A person with the authenticator does that, or it does not
/// happen.
[ApiController]
[Route("api/platform/copilot")]
[Authorize(Policy = PlatformOwnerPolicy.Name)]
public sealed class PlatformCopilotController(
    AppDbContext db,
    IPlatformCopilotService copilot,
    IPlatformSecretProtector protector,
    IJwtService jwt) : ControllerBase
{
    // ── Requests ─────────────────────────────────────────────────────────

    public sealed class StartRequest
    {
        [Required, MinLength(8), MaxLength(1000)]
        public string Objective { get; set; } = string.Empty;

        [Range(1, 25)] public int MaxInterventions { get; set; } = 5;
        [Range(1, 24)] public int MaxCompMonths { get; set; } = 12;
        [MaxLength(3)] public string Currency { get; set; } = "LKR";
    }

    public sealed class DecisionRequest
    {
        [MaxLength(500)] public string? Reason { get; set; }
    }

    public sealed class ApplyRequest
    {
        /// Which businesses the owner picked. Empty means all of them.
        ///
        /// Note what this does NOT carry: what to do to each one. The
        /// interventions come from the stored validation output, so a
        /// tampered request can narrow the action set but can never widen it
        /// or turn an extension into a comp.
        public List<string> TenantIds { get; set; } = new();

        [MaxLength(500)] public string? Reason { get; set; }
    }

    // ── Running ──────────────────────────────────────────────────────────

    /// Starts a run. Read-only in effect: the pipeline ends holding
    /// proposals, and nothing has been applied when this returns.
    [HttpPost]
    public async Task<IActionResult> Start([FromBody] StartRequest body, CancellationToken ct)
    {
        // The agent's tools call back into /api/platform/* as the owner, so
        // they need an owner token. A fresh short-lived one is minted for the
        // run rather than forwarding the console's own session token: this
        // one is scoped to the agent's use, expires in minutes, and its
        // lifetime is not tied to the owner staying signed in.
        var ownerToken = await MintAgentTokenAsync(ct);
        if (ownerToken is null)
            return StatusCode(StatusCodes.Status403Forbidden, new { message = "Could not mint an agent session for this owner." });

        BillingResult<PlatformAgentWorkflow> result;
        try
        {
            result = await copilot.StartAsync(
                CurrentUserId, ActorEmail, ownerToken,
                new StartCopilotRequest(body.Objective, body.MaxInterventions, body.MaxCompMonths, body.Currency), ct);
        }
        finally
        {
            await RevokeAgentSessionAsync(ownerToken, ct);
        }

        if (!result.Success) return StatusCode(result.StatusCode, new { message = result.Error });

        await AuditAsync("copilot.run", result.Value!.Id, result.Value.Status,
            $"{body.Objective[..Math.Min(160, body.Objective.Length)]}", ct);

        return StatusCode(StatusCodes.Status201Created, Map(result.Value, full: true));
    }

    [HttpGet]
    public async Task<IActionResult> History([FromQuery] int take = 25, CancellationToken ct = default)
    {
        var rows = await copilot.HistoryAsync(take, ct);
        return Ok(rows.Select(w => Map(w, full: false)));
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct)
    {
        var workflow = await copilot.GetAsync(id, ct);
        return workflow is null ? NotFound(new { message = "Workflow not found." }) : Ok(Map(workflow, full: true));
    }

    // ── Deciding ─────────────────────────────────────────────────────────

    /// Carries out the approved interventions. **Requires a fresh
    /// authenticator code.** This is the only route in the whole feature that
    /// changes a tenant's standing.
    [HttpPost("{id:guid}/approve")]
    public async Task<IActionResult> Approve(Guid id, [FromBody] ApplyRequest body, CancellationToken ct)
    {
        if (await RequireFreshOtpAsync(ct) is { } denied) return denied;

        var result = await copilot.ApplyApprovedAsync(id, CurrentUserId, ActorEmail, body.TenantIds, body.Reason, ct);
        if (!result.Success) return StatusCode(result.StatusCode, new { message = result.Error });

        await AuditAsync("copilot.approve", id, result.Value!.Status,
            $"{body.TenantIds.Count} business(es) - {body.Reason}", ct);

        return Ok(Map(result.Value, full: true));
    }

    /// Rejecting changes nothing on any tenant, so it needs no step-up - it
    /// only records that the owner looked and declined.
    [HttpPost("{id:guid}/reject")]
    public async Task<IActionResult> Reject(Guid id, [FromBody] DecisionRequest body, CancellationToken ct)
    {
        var result = await copilot.RecordDecisionAsync(id, CurrentUserId, ActorEmail, "Rejected", body.Reason, ct);
        if (!result.Success) return StatusCode(result.StatusCode, new { message = result.Error });
        await AuditAsync("copilot.reject", id, "Rejected", body.Reason, ct);
        return Ok(Map(result.Value!, full: true));
    }

    [HttpPost("{id:guid}/revise")]
    public async Task<IActionResult> Revise(Guid id, [FromBody] DecisionRequest body, CancellationToken ct)
    {
        var result = await copilot.RecordDecisionAsync(id, CurrentUserId, ActorEmail, "Revision", body.Reason, ct);
        if (!result.Success) return StatusCode(result.StatusCode, new { message = result.Error });
        await AuditAsync("copilot.revise", id, "Revising", body.Reason, ct);
        return Ok(Map(result.Value!, full: true));
    }

    // ── helpers ──────────────────────────────────────────────────────────

    private static object Map(PlatformAgentWorkflow w, bool full) => full
        ? new
        {
            w.Id, w.TraceId, w.Objective, w.Status, w.ApprovalStatus, w.ModelDriven,
            w.EstimatedCost, w.Currency, w.CreatedAt, w.CompletedAt,
            w.DecidedByEmail, w.DecidedAt, w.DecisionReason, w.ErrorLog,
            plan = Parse(w.PlanJson),
            analysis = Parse(w.AnalysisJson),
            proposals = Parse(w.ProposalsJson),
            validation = Parse(w.ValidationJson),
            observability = Parse(w.ObservabilityJson),
            approved = Parse(w.ApprovedInterventionsJson),
            outcome = Parse(w.OutcomeJson),
        }
        : new
        {
            w.Id, w.TraceId, w.Objective, w.Status, w.ApprovalStatus, w.ModelDriven,
            w.EstimatedCost, w.Currency, w.CreatedAt, w.CompletedAt, w.DecidedByEmail,
        };

    private static System.Text.Json.JsonElement? Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(json);
            return doc.RootElement.Clone();
        }
        catch (System.Text.Json.JsonException)
        {
            return null;
        }
    }

    /// How long an agent session may live. The pipeline runs synchronously
    /// in well under a minute; ten is generous and still short enough that a
    /// leaked agent token is worth little.
    private static readonly TimeSpan AgentSessionLifetime = TimeSpan.FromMinutes(10);

    /// Mints a short-lived owner session for the agent's read-only tools.
    ///
    /// The console's own token is deliberately not forwarded. This one is a
    /// separate platform_sessions row, so it expires on its own schedule,
    /// shows up in the owner's session list as what it is, and can be revoked
    /// without signing the owner out. It carries no more authority than the
    /// owner already has - the agent's tools are read-only, and every
    /// write route still demands an authenticator code this token cannot
    /// satisfy.
    private async Task<string?> MintAgentTokenAsync(CancellationToken ct)
    {
        var user = await db.Users.IgnoreQueryFilters()
            .FirstOrDefaultAsync(u => u.Id == CurrentUserId && u.Role == UserRole.SuperAdmin, ct);
        if (user is null) return null;

        var now = DateTime.UtcNow;
        var jti = Guid.NewGuid().ToString("N");
        var expiresAt = now.Add(AgentSessionLifetime);

        db.PlatformSessions.Add(new PlatformSession
        {
            UserId = user.Id,
            Jti = jti,
            IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            UserAgent = "platform-copilot (agent session)",
            CreatedAt = now,
            LastSeenAt = now,
            ExpiresAt = expiresAt,
        });
        await db.SaveChangesAsync(ct);

        return jwt.GeneratePlatformAccessToken(user, jti, expiresAt);
    }

    /// Ends the agent's session as soon as the run returns, rather than
    /// leaving a valid owner token alive for the rest of its ten minutes.
    private async Task RevokeAgentSessionAsync(string token, CancellationToken ct)
    {
        var jti = jwt.ValidateToken(token)?.FindFirst("jti")?.Value;
        if (jti is null) return;
        var session = await db.PlatformSessions.FirstOrDefaultAsync(s => s.Jti == jti, ct);
        if (session is null || session.RevokedAt != null) return;
        session.RevokedAt = DateTime.UtcNow;
        session.RevokedReason = "copilot-run-finished";
        await db.SaveChangesAsync(ct);
    }

    private Guid CurrentUserId => Guid.Parse(
        User.FindFirst(ClaimTypes.NameIdentifier)?.Value
        ?? User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)!.Value);

    private string ActorEmail =>
        User.FindFirst(ClaimTypes.Email)?.Value ?? User.FindFirst("email")?.Value ?? string.Empty;

    /// The step-up. Identical to the one guarding tenant suspension, so the
    /// bar for "an agent changes a business's plan" is the same as the bar
    /// for the owner doing it by hand.
    private async Task<IActionResult?> RequireFreshOtpAsync(CancellationToken ct)
    {
        var code = Request.Headers[PlatformController.OtpHeader].ToString();
        var admin = await db.PlatformAdmins.FirstAsync(a => a.UserId == CurrentUserId, ct);
        if (admin.MfaSecretEncrypted == null)
            return StatusCode(StatusCodes.Status403Forbidden, new { message = "MFA is not enrolled." });
        if (string.IsNullOrWhiteSpace(code))
            return StatusCode(StatusCodes.Status428PreconditionRequired,
                new { status = "otpRequired", message = "Enter your authenticator code to apply these changes." });

        var secret = protector.Unprotect(admin.MfaSecretEncrypted);
        if (!TotpService.TryVerify(secret, code, DateTime.UtcNow, admin.LastAcceptedTotpStep, out var step))
        {
            await AuditAsync("copilot.otp.failed", null, "denied", "Wrong or reused authenticator code", ct, succeeded: false);
            return StatusCode(StatusCodes.Status403Forbidden,
                new { status = "otpInvalid", message = "That authenticator code is not valid." });
        }

        admin.LastAcceptedTotpStep = step;
        admin.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return null;
    }

    private async Task AuditAsync(string action, Guid? targetId, string? label, string? detail, CancellationToken ct, bool succeeded = true)
    {
        var ua = Request.Headers.UserAgent.ToString();
        db.PlatformAuditLogs.Add(new PlatformAuditLog
        {
            ActorUserId = CurrentUserId,
            ActorEmail = ActorEmail,
            Action = action,
            TargetType = "copilot",
            TargetId = targetId,
            TargetLabel = label,
            Detail = detail is null ? null : detail[..Math.Min(2000, detail.Length)],
            Succeeded = succeeded,
            IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            UserAgent = ua.Length > 512 ? ua[..512] : ua,
        });
        await db.SaveChangesAsync(ct);
    }
}
