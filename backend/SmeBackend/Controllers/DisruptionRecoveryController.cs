using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Authorization;
using SmeBackend.Services.PlatformBilling;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// <summary>
/// Disruption Recovery Copilot: a resource goes out of service and every
/// booking on it needs somewhere to go.
///
///   plan    → four agents propose one recovery per stranded booking
///   (pause) → always AwaitingApproval; nobody's booking moves unasked
///   apply   → a manager approves and the moves happen in one transaction
///
/// The agent service proposes; this controller is the only thing that writes.
/// Applying re-checks every move against the live database, because the
/// proposal was made seconds or minutes ago and a slot may have gone since -
/// and the booking overlap constraint would refuse it anyway.
/// </summary>
[ApiController]
[Authorize(Roles = "Admin,Manager")]
[Route("api/agent/disruption")]
[Produces("application/json")]
public sealed class DisruptionRecoveryController(
    AppDbContext db,
    IPlannerAgentService planner,
    ILogger<DisruptionRecoveryController> logger) : ControllerBase
{
    /// <summary>Marks these workflows as the Disruption Copilot's, as Billing and StockSense do.</summary>
    public const string ObjectivePrefix = "[Disruption] ";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    /// <summary>
    /// Runs the recovery workflow for a resource that is out of service.
    /// Nothing is moved: the result is a proposal awaiting approval.
    /// </summary>
    /// <response code="200">The workflow id and the agents' trace.</response>
    /// <response code="503">The agent service could not be reached; the attempt is still recorded.</response>
    [HttpPost("plan")]
    [MetersPlanQuota(UsageMetrics.AiRuns)]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Plan([FromBody] PlanDisruptionDto dto, CancellationToken ct)
    {
        if (!TryGetCaller(out var tenantId, out var userId)) return Unauthorized();

        var objective = (dto.Objective ?? string.Empty).Trim();
        if (objective.Length is < 3 or > 500)
            return BadRequest(new { message = "Describe what happened in 3 to 500 characters." });
        if (dto.DateTo < dto.DateFrom)
            return BadRequest(new { message = "The end date must be on or after the start date." });
        if (dto.DateTo.DayNumber - dto.DateFrom.DayNumber + 1 > 31)
            return BadRequest(new { message = "Cover at most 31 days at a time." });

        var resource = await db.Resources.AsNoTracking()
            .FirstOrDefaultAsync(r => r.Id == dto.ResourceId && r.TenantId == tenantId, ct);
        if (resource == null) return NotFound(new { message = "Resource not found." });

        var tenant = await db.Tenants.AsNoTracking().FirstOrDefaultAsync(t => t.Id == tenantId, ct);

        var bearer = Request.Headers.Authorization.ToString();
        var callerToken = bearer.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? bearer[7..].Trim() : string.Empty;
        if (string.IsNullOrEmpty(callerToken)) return Unauthorized();

        var result = await planner.PlanDisruptionAsync(new DisruptionCopilotRequest(
            Objective: objective,
            TenantId: tenantId.ToString(),
            BusinessType: tenant?.BusinessType ?? "General",
            ResourceId: dto.ResourceId.ToString(),
            Window: new DisruptionWindowDto(
                dto.DateFrom.ToString("yyyy-MM-dd"),
                dto.DateTo.ToString("yyyy-MM-dd")),
            Reason: (dto.Reason ?? string.Empty).Trim(),
            BranchId: dto.BranchId?.ToString(),
            AuthToken: callerToken), ct);

        if (!result.Success)
        {
            // A safe, clearly recorded failure: the attempt stays in the audit
            // trail with its reason rather than vanishing with the request.
            var failed = new AgentWorkflow
            {
                TenantId = tenantId,
                Objective = ObjectivePrefix + objective,
                Status = "Failed",
                ApprovalStatus = "NotRequired",
                ErrorLog = result.ErrorMessage,
                FinalOutcome = "The Disruption Copilot could not run; nothing was changed.",
                CompletedAt = DateTime.UtcNow,
                RequestedByUserId = userId,
            };
            db.AgentWorkflows.Add(failed);
            await db.SaveChangesAsync(ct);
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new { message = result.ErrorMessage, workflowId = failed.Id });
        }

        using var trace = JsonDocument.Parse(result.TraceJson!);
        var root = trace.RootElement;

        var (status, approval) = result.Status switch
        {
            "AwaitingApproval" => ("AwaitingApproval", "Pending"),
            "Rejected" => ("Rejected", "NotRequired"),
            "NoAction" => ("Completed", "NotRequired"),
            _ => ("Failed", "NotRequired"),
        };

        var workflow = new AgentWorkflow
        {
            TenantId = tenantId,
            Objective = ObjectivePrefix + objective,
            Status = status,
            ApprovalStatus = approval,
            CurrentStep = root.TryGetProperty("agent_steps", out var steps) && steps.ValueKind == JsonValueKind.Array
                ? steps.GetArrayLength() : 0,
            PlanJson = result.TraceJson,
            ValidationResults = root.TryGetProperty("safety", out var safety) && safety.ValueKind == JsonValueKind.Object
                ? safety.GetRawText() : null,
            ErrorLog = root.TryGetProperty("error", out var err) && err.ValueKind == JsonValueKind.String
                ? err.GetString() : null,
            FinalOutcome = Describe(root, result.Status),
            CompletedAt = status is "Rejected" or "Completed" or "Failed" ? DateTime.UtcNow : null,
            RequestedByUserId = userId,
        };
        db.AgentWorkflows.Add(workflow);

        if (status == "AwaitingApproval")
        {
            NotificationHelper.Queue(db, tenantId, null, "WorkflowApproval",
                $"{resource.Name} is unavailable",
                workflow.FinalOutcome ?? "A recovery plan is waiting for your approval.");
        }

        await db.SaveChangesAsync(ct);

        return Ok(new { workflowId = workflow.Id, status = workflow.Status, trace = root.Clone() });
    }

    /// <summary>
    /// Applies an approved recovery plan: each accepted proposal moves its
    /// booking, in one transaction, re-checked against the live database.
    /// </summary>
    /// <response code="200">What was moved and what was skipped, with reasons.</response>
    /// <response code="409">The workflow is not awaiting approval.</response>
    [HttpPost("{id:guid}/apply")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Apply(Guid id, [FromBody] ApplyRecoveryDto dto, CancellationToken ct)
    {
        if (!TryGetCaller(out var tenantId, out var userId)) return Unauthorized();

        var workflow = await db.AgentWorkflows
            .FirstOrDefaultAsync(w => w.Id == id && w.TenantId == tenantId
                                      && w.Objective.StartsWith(ObjectivePrefix), ct);
        if (workflow == null) return NotFound();
        if (workflow.Status != "AwaitingApproval")
            return Conflict(new { message = $"This recovery is {workflow.Status}, not awaiting approval." });

        var proposals = ReadProposals(workflow.PlanJson);
        if (proposals.Count == 0)
            return Conflict(new { message = "This recovery has no proposals to apply." });

        // The manager may accept a subset; anything not named is left alone.
        var accepted = dto.AcceptedBookingIds is { Count: > 0 }
            ? proposals.Where(p => dto.AcceptedBookingIds.Contains(p.BookingId)).ToList()
            : proposals;

        var rejectedByGate = ReadRejectedIds(workflow.ValidationResults);
        accepted = accepted.Where(p => !rejectedByGate.Contains(p.BookingId)).ToList();

        var moved = new List<object>();
        var skipped = new List<object>();

        await using var tx = db.Database.IsRelational() ? await db.Database.BeginTransactionAsync(ct) : null;

        foreach (var proposal in accepted)
        {
            if (proposal.ResourceId is null || proposal.StartsAt is null || proposal.EndsAt is null)
            {
                skipped.Add(new { proposal.BookingId, reason = "The proposal has no destination." });
                continue;
            }

            var booking = await db.Bookings.FirstOrDefaultAsync(b => b.Id == proposal.BookingId && b.DeletedAt == null, ct);
            if (booking == null)
            {
                skipped.Add(new { proposal.BookingId, reason = "The booking no longer exists." });
                continue;
            }

            // Re-checked now: the proposal was made minutes ago, and the
            // database's own overlap constraint would refuse a stale move.
            if (await Availability.HasConflictAsync(db, proposal.ResourceId.Value,
                    proposal.StartsAt.Value, proposal.EndsAt.Value, excludeBookingId: booking.Id))
            {
                skipped.Add(new { proposal.BookingId, reason = "That slot was taken while the plan waited for approval." });
                continue;
            }

            booking.ResourceId = proposal.ResourceId.Value;
            booking.StartTime = proposal.StartsAt.Value;
            booking.EndTime = proposal.EndsAt.Value;
            booking.UpdatedAt = DateTime.UtcNow;
            await BookingExclusivity.ApplyAsync(db, booking, ct);

            NotificationHelper.Queue(db, tenantId, booking.BookedBy, "BookingRescheduled",
                "Your booking was moved",
                proposal.Explanation is { Length: > 0 }
                    ? proposal.Explanation
                    : $"Moved to {proposal.StartsAt:ddd d MMM, HH:mm}.");

            moved.Add(new { proposal.BookingId, resourceId = proposal.ResourceId, startsAt = proposal.StartsAt });
        }

        workflow.Status = "Completed";
        workflow.ApprovalStatus = "Approved";
        workflow.ApprovedBy = userId;
        workflow.ApprovedAt = DateTime.UtcNow;
        workflow.CompletedAt = DateTime.UtcNow;
        workflow.CurrentStep += 1;
        workflow.ToolResultsJson = JsonSerializer.Serialize(new { moved, skipped }, Json);
        workflow.FinalOutcome = $"{moved.Count} booking(s) moved, {skipped.Count} skipped.";

        await db.SaveChangesAsync(ct);
        if (tx is not null) await tx.CommitAsync(ct);

        logger.LogInformation("Disruption recovery {WorkflowId}: {Moved} moved, {Skipped} skipped",
            workflow.Id, moved.Count, skipped.Count);

        return Ok(new { workflowId = workflow.Id, moved, skipped, outcome = workflow.FinalOutcome });
    }

    /// <summary>Rejects a recovery plan. Nothing moves and the reason is recorded.</summary>
    [HttpPost("{id:guid}/reject")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Reject(Guid id, [FromBody] RejectRecoveryDto dto, CancellationToken ct)
    {
        if (!TryGetCaller(out var tenantId, out var userId)) return Unauthorized();

        var workflow = await db.AgentWorkflows
            .FirstOrDefaultAsync(w => w.Id == id && w.TenantId == tenantId
                                      && w.Objective.StartsWith(ObjectivePrefix), ct);
        if (workflow == null) return NotFound();
        if (workflow.Status != "AwaitingApproval")
            return Conflict(new { message = $"This recovery is {workflow.Status}, not awaiting approval." });

        var reason = (dto.Reason ?? string.Empty).Trim();
        if (reason.Length < 3) return BadRequest(new { message = "Give a reason of at least 3 characters." });

        workflow.Status = "Rejected";
        workflow.ApprovalStatus = "Rejected";
        workflow.ApprovedBy = userId;
        workflow.ApprovedAt = DateTime.UtcNow;
        workflow.CompletedAt = DateTime.UtcNow;
        workflow.FinalOutcome = $"Rejected: {reason}. Nothing was moved.";
        await db.SaveChangesAsync(ct);

        return Ok(new { workflowId = workflow.Id, status = workflow.Status, outcome = workflow.FinalOutcome });
    }

    /// <summary>The Disruption Copilot's workflows, newest first.</summary>
    [HttpGet]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> List([FromQuery] string? status, CancellationToken ct)
    {
        if (!TryGetCaller(out var tenantId, out _)) return Unauthorized();

        var query = db.AgentWorkflows.AsNoTracking()
            .Where(w => w.TenantId == tenantId && w.Objective.StartsWith(ObjectivePrefix));
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(w => w.Status == status);

        var rows = await query.OrderByDescending(w => w.CreatedAt).Take(50).ToListAsync(ct);

        return Ok(rows.Select(w => new
        {
            w.Id,
            objective = w.Objective[ObjectivePrefix.Length..],
            w.Status,
            w.ApprovalStatus,
            w.FinalOutcome,
            w.ErrorLog,
            w.CreatedAt,
            w.CompletedAt,
            trace = w.PlanJson,
        }));
    }

    private static string Describe(JsonElement root, string? status)
    {
        var affected = root.TryGetProperty("impact", out var impact) && impact.ValueKind == JsonValueKind.Object
            && impact.TryGetProperty("affected", out var a) && a.ValueKind == JsonValueKind.Array
                ? a.GetArrayLength() : 0;
        var unresolved = root.TryGetProperty("action", out var action) && action.ValueKind == JsonValueKind.Object
            && action.TryGetProperty("unresolved", out var u) && u.ValueKind == JsonValueKind.Array
                ? u.GetArrayLength() : 0;

        return status switch
        {
            "NoAction" => "Nothing is booked on that resource during the outage.",
            "Rejected" => "The safety gate refused the recovery plan; nothing was changed.",
            "Failed" => "The recovery could not be planned; nothing was changed.",
            _ => $"{affected} booking(s) affected, {affected - unresolved} with a proposed move, "
                 + $"{unresolved} needing your decision.",
        };
    }

    private static List<Proposal> ReadProposals(string? traceJson)
    {
        var proposals = new List<Proposal>();
        if (string.IsNullOrWhiteSpace(traceJson)) return proposals;

        using var doc = JsonDocument.Parse(traceJson);
        if (!doc.RootElement.TryGetProperty("action", out var action) || action.ValueKind != JsonValueKind.Object)
            return proposals;
        if (!action.TryGetProperty("proposals", out var list) || list.ValueKind != JsonValueKind.Array)
            return proposals;

        foreach (var p in list.EnumerateArray())
        {
            if (!Guid.TryParse(Str(p, "booking_id"), out var bookingId)) continue;
            Guid? resourceId = Guid.TryParse(Str(p, "proposed_resource_id"), out var r) ? r : null;
            proposals.Add(new Proposal(
                bookingId,
                resourceId,
                Date(p, "proposed_starts_at"),
                Date(p, "proposed_ends_at"),
                Str(p, "explanation") ?? string.Empty));
        }
        return proposals;
    }

    private static HashSet<Guid> ReadRejectedIds(string? safetyJson)
    {
        var rejected = new HashSet<Guid>();
        if (string.IsNullOrWhiteSpace(safetyJson)) return rejected;

        using var doc = JsonDocument.Parse(safetyJson);
        if (doc.RootElement.TryGetProperty("rejected_booking_ids", out var ids) && ids.ValueKind == JsonValueKind.Array)
            foreach (var id in ids.EnumerateArray())
                if (Guid.TryParse(id.GetString(), out var guid)) rejected.Add(guid);
        return rejected;
    }

    private static string? Str(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static DateTime? Date(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String
        && DateTime.TryParse(v.GetString(), null, System.Globalization.DateTimeStyles.AdjustToUniversal
            | System.Globalization.DateTimeStyles.AssumeUniversal, out var parsed)
            ? parsed : null;

    private bool TryGetCaller(out Guid tenantId, out Guid userId)
    {
        userId = Guid.Empty;
        return Guid.TryParse(User.FindFirst("tenantId")?.Value, out tenantId)
            && Guid.TryParse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value, out userId);
    }

    private sealed record Proposal(
        Guid BookingId, Guid? ResourceId, DateTime? StartsAt, DateTime? EndsAt, string Explanation);
}

public sealed record PlanDisruptionDto(
    string Objective,
    Guid ResourceId,
    DateOnly DateFrom,
    DateOnly DateTo,
    string? Reason = null,
    Guid? BranchId = null);

public sealed record ApplyRecoveryDto(List<Guid>? AcceptedBookingIds = null);

public sealed record RejectRecoveryDto(string Reason);
