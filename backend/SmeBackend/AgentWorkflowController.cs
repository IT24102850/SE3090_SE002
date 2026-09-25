using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;
using System.Text.Json;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/agent/workflow")]
[Authorize]
public class AgentWorkflowController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IPlannerAgentService _plannerAgentService;
    private readonly IJwtService _jwtService;
    private readonly IPushNotificationSender _pushSender;

    public AgentWorkflowController(AppDbContext db, IPlannerAgentService plannerAgentService, IJwtService jwtService, IPushNotificationSender pushSender)
    {
        _db = db;
        _plannerAgentService = plannerAgentService;
        _jwtService = jwtService;
        _pushSender = pushSender;
    }

    [HttpPost]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> CreateWorkflow([FromBody] CreateWorkflowDto dto)
    {
        var workflow = await PersistWorkflowAsync(dto.TenantId, dto.Objective, dto.Plan);
        return CreatedAtAction(nameof(GetWorkflow), new { id = workflow.Id }, workflow);
    }

    // ── FR-B12: quick schedule proposal (no agents involved) ───────────────
    // A deterministic heuristic: greedily fills the earliest open slots across
    // the tenant's resources within the requested window, using the same
    // SlotCalculator the availability endpoints use, then routes the plan
    // through the same approval threshold as everything else here.
    //
    // Kept alongside plan-schedule because it is instant and needs no model,
    // which makes it the right tool for "just fill the next N open slots".
    // Anything that has to interpret an objective, weigh resources or honour
    // priority rules goes to the Schedule Copilot (POST plan-schedule), where
    // the four agents actually run.
    [HttpPost("propose")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> ProposeSchedule([FromBody] ProposeScheduleDto dto)
    {
        if (dto.Count <= 0) return BadRequest(new { message = "Count must be positive." });
        var withinDays = dto.WithinDays is > 0 ? dto.WithinDays.Value : 7;

        var bookingType = await _db.BookingTypes.AsNoTracking().FirstOrDefaultAsync(bt => bt.Id == dto.BookingTypeId);
        if (bookingType == null) return NotFound(new { message = "Booking type not found." });
        var duration = bookingType.DefaultDurationMinutes;

        var resources = await _db.Resources.AsNoTracking()
            .Where(r => r.TenantId == dto.TenantId && r.Status == ResourceStatus.Available)
            .Where(r => !dto.BranchId.HasValue || r.BranchId == dto.BranchId)
            .ToListAsync();

        var resourceIds = resources.Select(r => r.Id).ToList();
        var today = DateTime.UtcNow.Date;
        var horizonEnd = today.AddDays(withinDays);

        var schedulesByResource = (await _db.ResourceSchedules.AsNoTracking()
            .Where(s => s.ResourceId.HasValue && resourceIds.Contains(s.ResourceId.Value))
            .ToListAsync())
            .GroupBy(s => s.ResourceId!.Value)
            .ToDictionary(g => g.Key, g => g.ToDictionary(s => s.DayOfWeek));

        var bookingsByResource = (await _db.Bookings.AsNoTracking()
            .Where(b => resourceIds.Contains(b.ResourceId) && b.DeletedAt == null
                && b.Status != BookingStatus.Cancelled && b.Status != BookingStatus.Rejected
                && b.StartTime.Date >= today && b.StartTime.Date < horizonEnd)
            .Select(b => new { b.ResourceId, b.StartTime, b.EndTime })
            .ToListAsync())
            .GroupBy(b => b.ResourceId)
            .ToDictionary(g => g.Key, g => g.Select(b => (b.StartTime, b.EndTime)).ToList());

        var proposedSteps = new List<StepDto>();
        var now = DateTime.UtcNow;

        for (var dayOffset = 0; dayOffset < withinDays && proposedSteps.Count < dto.Count; dayOffset++)
        {
            var day = today.AddDays(dayOffset);
            var dow = (int)day.DayOfWeek;

            foreach (var resource in resources)
            {
                if (proposedSteps.Count >= dto.Count) break;

                schedulesByResource.TryGetValue(resource.Id, out var daySchedules);
                ResourceSchedule? schedule = null;
                daySchedules?.TryGetValue(dow, out schedule);

                if (!bookingsByResource.TryGetValue(resource.Id, out var existingForResource))
                {
                    existingForResource = new List<(DateTime, DateTime)>();
                    bookingsByResource[resource.Id] = existingForResource;
                }
                var existingForDay = existingForResource.Where(b => b.Item1.Date == day).ToList();

                var (isOpen, slots) = SlotCalculator.Calculate(
                    day, schedule, duration, bookingType.BufferMinutesBefore, bookingType.BufferMinutesAfter,
                    existingForDay, now);
                if (!isOpen) continue;

                var openSlot = slots.FirstOrDefault(s => s.IsAvailable);
                if (openSlot == null) continue;

                // Reserve it locally so a later resource/day this same pass doesn't propose it twice.
                existingForResource.Add((openSlot.StartTime, openSlot.EndTime));

                proposedSteps.Add(new StepDto(
                    "Planner",
                    "CreateBooking",
                    "bookings.create",
                    new
                    {
                        resourceId = resource.Id,
                        resourceName = resource.Name,
                        bookingTypeId = bookingType.Id,
                        startTime = openSlot.StartTime,
                        endTime = openSlot.EndTime
                    }));
            }
        }

        if (proposedSteps.Count == 0)
        {
            var branchScope = dto.BranchId.HasValue ? " in the selected branch" : " across all branches";
            return Conflict(new
            {
                message = $"No available booking slots were found{branchScope} within the next {withinDays} day(s). Try a shorter booking type, a different branch, or a wider date range."
            });
        }

        var plan = new PlanDto(proposedSteps, 0);
        var workflow = await PersistWorkflowAsync(dto.TenantId, dto.Objective, plan);
        return CreatedAtAction(nameof(GetWorkflow), new { id = workflow.Id }, workflow);
    }

    // ── Schedule Copilot (spec 2.7: Planner / Coordinator) ──────────────
    //
    // ProposeSchedule above finds open slots deterministically and involves
    // no agent. This runs the real four-agent workflow: the Planner reads the
    // objective, Domain Analysis ranks resources, Action/Tool optimises the
    // schedule, and the deterministic Validation/Safety gate decides whether
    // it is allowed and whether a manager must approve it.
    //
    // The agent service only ever *reads*, using the calling manager's own
    // JWT, so its view is exactly this manager's view. It returns a
    // proposal; it is persisted here as an AgentWorkflow and turned into
    // bookings only by /apply, after approval where the gate required it.

    public static readonly string[] CopilotPriorityRules =
    {
        "prefer_mornings", "prefer_afternoons", "balance_load", "minimise_travel",
        "avoid_high_no_show", "earliest_first", "keep_lunch_free", "cluster_same_day",
    };

    /// <summary>Runs the multi-agent Schedule Copilot for a scheduling objective and stores the auditable result.</summary>
    [HttpPost("plan-schedule")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> PlanSchedule([FromBody] PlanScheduleDto dto, CancellationToken ct)
    {
        if (!Guid.TryParse(User.FindFirst("tenantId")?.Value, out var callerTenant) || callerTenant != dto.TenantId)
            return Forbid();

        var objective = (dto.Objective ?? string.Empty).Trim();
        if (objective.Length < 3 || objective.Length > 500)
            return BadRequest(new { message = "Describe the objective in 3 to 500 characters." });
        if (dto.TargetCount is < 1 or > 50)
            return BadRequest(new { message = "Target count must be between 1 and 50." });
        if (dto.DateTo < dto.DateFrom)
            return BadRequest(new { message = "The end date must be on or after the start date." });
        if (dto.DateTo.DayNumber - dto.DateFrom.DayNumber + 1 > 31)
            return BadRequest(new { message = "Plan at most 31 days at a time." });
        var rules = (dto.PriorityRules ?? new List<string>()).Distinct().ToList();
        var unknown = rules.Except(CopilotPriorityRules).ToList();
        if (unknown.Count > 0)
            return BadRequest(new { message = $"Unknown priority rule(s): {string.Join(", ", unknown)}." });
        if ((dto.ResourceIds?.Count ?? 0) > 12)
            return BadRequest(new { message = "Choose at most 12 resources." });

        var bookingType = await _db.BookingTypes.AsNoTracking()
            .FirstOrDefaultAsync(bt => bt.Id == dto.BookingTypeId && bt.TenantId == dto.TenantId, ct);
        if (bookingType == null) return NotFound(new { message = "Booking type not found." });

        var tenant = await _db.Tenants.AsNoTracking().FirstOrDefaultAsync(t => t.Id == dto.TenantId, ct);
        var currency = await _db.Invoices.AsNoTracking()
            .Where(i => i.TenantId == dto.TenantId)
            .OrderByDescending(i => i.CreatedAt)
            .Select(i => i.Currency)
            .FirstOrDefaultAsync(ct) ?? "USD";

        var bearer = Request.Headers.Authorization.ToString();
        var callerToken = bearer.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? bearer[7..].Trim() : string.Empty;
        if (string.IsNullOrEmpty(callerToken)) return Unauthorized();

        var request = new ScheduleCopilotRequest(
            Objective: objective,
            TenantId: dto.TenantId.ToString(),
            BusinessType: tenant?.BusinessType ?? "General",
            Constraints: new ScheduleConstraintsDto(
                new ScheduleDateRangeDto(dto.DateFrom, dto.DateTo),
                (dto.ResourceIds ?? new List<Guid>()).Select(r => r.ToString()).ToList(),
                rules,
                dto.BookingTypeId.ToString(),
                dto.TargetCount,
                bookingType.DefaultDurationMinutes,
                dto.BranchId?.ToString()),
            Currency: currency,
            AuthToken: callerToken);

        var result = await _plannerAgentService.PlanScheduleAsync(request, ct);
        var requester = Guid.TryParse(User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var uid)
            ? uid : (Guid?)null;

        if (!result.Success)
        {
            // A safe, clearly recorded failure (spec 9.1): the attempt is kept
            // in the audit trail with its reason, not lost with the request.
            var failed = new AgentWorkflow
            {
                TenantId = dto.TenantId,
                Objective = objective,
                Status = "Failed",
                ApprovalStatus = "NotRequired",
                ErrorLog = result.ErrorMessage,
                FinalOutcome = "Schedule Copilot could not run.",
                CompletedAt = DateTime.UtcNow,
                RequestedByUserId = requester,
            };
            _db.AgentWorkflows.Add(failed);
            await _db.SaveChangesAsync(ct);
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new { message = result.ErrorMessage, workflowId = failed.Id });
        }

        using var trace = JsonDocument.Parse(result.TraceJson!);
        var root = trace.RootElement;
        var steps = new List<StepDto>();
        if (root.TryGetProperty("action", out var action) && action.ValueKind == JsonValueKind.Object
            && action.TryGetProperty("proposals", out var proposals))
        {
            foreach (var p in proposals.EnumerateArray())
            {
                steps.Add(new StepDto("ActionToolAgent", "CreateBooking", "bookings.create", new
                {
                    resourceId = p.GetProperty("resource_id").GetString(),
                    resourceName = p.GetProperty("resource_name").GetString(),
                    bookingTypeId = dto.BookingTypeId,
                    startTime = p.GetProperty("start").GetDateTime(),
                    endTime = p.GetProperty("end").GetDateTime(),
                }));
            }
        }

        double revenueUsd = 0;
        if (root.TryGetProperty("metrics", out var metrics) && metrics.ValueKind == JsonValueKind.Object
            && metrics.TryGetProperty("estimated_revenue_usd", out var rev) && rev.ValueKind == JsonValueKind.Number)
            revenueUsd = rev.GetDouble();

        string? error = root.TryGetProperty("error", out var e) && e.ValueKind == JsonValueKind.String ? e.GetString() : null;
        string? validation = root.TryGetProperty("safety", out var safety) && safety.ValueKind == JsonValueKind.Object
            ? safety.GetRawText() : null;

        var (status, approval) = result.Status switch
        {
            "Completed" => ("Approved", "NotRequired"),       // passed the gate; ready to apply
            "AwaitingApproval" => ("AwaitingApproval", "Pending"),
            "Rejected" => ("Rejected", "NotRequired"),
            _ => ("Failed", "NotRequired"),
        };

        var workflow = new AgentWorkflow
        {
            TenantId = dto.TenantId,
            Objective = objective,
            PlanJson = JsonSerializer.Serialize(new PlanDto(steps, revenueUsd)),
            Status = status,
            ApprovalStatus = approval,
            CurrentStep = 0,
            ToolResultsJson = result.TraceJson,
            ValidationResults = validation,
            ErrorLog = error,
            FinalOutcome = status switch
            {
                "Rejected" => "The safety gate returned this plan for revision.",
                "Failed" => "The agents stopped safely before producing a plan.",
                _ => null,
            },
            CompletedAt = status is "Rejected" or "Failed" ? DateTime.UtcNow : null,
            RequestedByUserId = requester,
        };
        _db.AgentWorkflows.Add(workflow);

        if (status == "AwaitingApproval")
        {
            NotificationHelper.Queue(_db, dto.TenantId, null, "WorkflowApproval", "Schedule needs approval",
                $"The Schedule Copilot proposed {steps.Count} booking(s) for \"{objective}\" and needs a manager's approval.");
        }
        await _db.SaveChangesAsync(ct);

        return CreatedAtAction(nameof(GetWorkflow), new { id = workflow.Id }, new
        {
            workflow,
            trace = root.Clone(),
        });
    }

    // Materializes an approved (or approval-not-required) workflow's proposed
    // CreateBooking steps into real Bookings. Also closes the gap where the
    // >20-item BulkSchedule/CreateRecurring approval branch never applied
    // anything after being approved.
    [HttpPost("{id}/apply")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> Apply(Guid id)
    {
        var wf = await _db.AgentWorkflows.FindAsync(id);
        if (wf == null) return NotFound();

        // A plan the safety gate rejected, or one that failed, is stored with
        // ApprovalStatus "NotRequired" (no human decision was ever asked for),
        // so the approval check alone would let it through. Status decides.
        if (wf.Status is "Rejected" or "Failed")
            return Conflict(new { message = "This plan was rejected or failed and cannot be applied. Run the planner again." });
        if (wf.ApprovalStatus != "Approved" && wf.ApprovalStatus != "NotRequired")
            return BadRequest(new { message = "This workflow must be approved before it can be applied." });
        if (wf.Status == "Completed")
            return BadRequest(new { message = "This workflow has already been applied." });
        if (string.IsNullOrEmpty(wf.PlanJson))
            return BadRequest(new { message = "This workflow has no plan to apply." });

        PlanDto? plan;
        try
        {
            plan = JsonSerializer.Deserialize<PlanDto>(wf.PlanJson);
        }
        catch (JsonException)
        {
            return BadRequest(new { message = "This workflow's plan could not be parsed." });
        }

        if (plan == null || plan.Steps.Count == 0)
            return BadRequest(new { message = "This workflow's plan has no steps to apply." });

        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        var appliedBy = Guid.TryParse(userIdClaim, out var uid) ? uid : (Guid?)null;

        var created = 0;
        var skipped = 0;
        foreach (var step in plan.Steps)
        {
            if (step.Action != "CreateBooking" || step.Parameters is not JsonElement root)
            {
                skipped++;
                continue;
            }

            if (!root.TryGetProperty("resourceId", out var resourceIdEl) ||
                !root.TryGetProperty("bookingTypeId", out var bookingTypeIdEl) ||
                !root.TryGetProperty("startTime", out var startEl) ||
                !root.TryGetProperty("endTime", out var endEl))
            {
                skipped++;
                continue;
            }

            var resourceId = resourceIdEl.GetGuid();
            var bookingTypeId = bookingTypeIdEl.GetGuid();
            var startTime = DateTimeUtil.AsUtc(startEl.GetDateTime());
            var endTime = DateTimeUtil.AsUtc(endEl.GetDateTime());

            var conflict = await _db.Bookings.AnyAsync(b =>
                b.ResourceId == resourceId && b.DeletedAt == null
                && b.Status != BookingStatus.Cancelled && b.Status != BookingStatus.Rejected
                && b.StartTime < endTime && b.EndTime > startTime);
            if (conflict) { skipped++; continue; }

            _db.Bookings.Add(new Booking
            {
                TenantId = wf.TenantId,
                ResourceId = resourceId,
                BookingTypeId = bookingTypeId,
                BookedBy = appliedBy ?? wf.ApprovedBy ?? Guid.Empty,
                Title = $"Auto-scheduled: {wf.Objective}",
                StartTime = startTime,
                EndTime = endTime,
                Status = BookingStatus.Confirmed,
                Priority = BookingPriority.Normal
            });
            created++;
        }

        wf.Status = "Completed";
        wf.CompletedAt = DateTime.UtcNow;
        wf.FinalOutcome = $"Applied: {created} booking(s) created, {skipped} skipped.";
        wf.ToolResultsJson = JsonSerializer.Serialize(new
        {
            workflowType = "schedule",
            plannedBookings = plan.Steps.Count,
            createdBookings = created,
            skippedBookings = skipped,
            notes = wf.FinalOutcome,
            planning = PreservePlanningTrace(wf.ToolResultsJson),
        });
        wf.ValidationResults = JsonSerializer.Serialize(new
        {
            valid = skipped == 0,
            checkedBookings = plan.Steps.Count,
            conflictsSkipped = skipped,
            confidence = skipped == 0 ? 1 : (double)created / plan.Steps.Count
        });
        wf.UpdatedAt = DateTime.UtcNow;

        if (wf.RequestedByUserId.HasValue && created > 0)
        {
            NotificationHelper.Queue(_db, wf.TenantId, wf.RequestedByUserId, "WorkflowApplied",
                "Booking confirmed", $"Your request \"{wf.Objective}\" is now confirmed.");
        }

        await _db.SaveChangesAsync();

        if (wf.RequestedByUserId.HasValue && created > 0)
        {
            await _pushSender.SendAsync(wf.TenantId, wf.RequestedByUserId.Value, "Booking confirmed",
                $"Your request \"{wf.Objective}\" is now confirmed.");
        }

        return Ok(new { message = wf.FinalOutcome, created, skipped });
    }

    // ── Gemini-powered pipeline (agentic-ai-service) ────────────────────────
    // Customer-facing front door: "find and book the best dentist this week".
    // Different trigger/role than ProposeSchedule above (staff bulk-filling
    // slots) but converges on the same AgentWorkflow table, PlanDto shape,
    // and approve/reject/apply endpoints.
    [HttpPost("~/api/agent/find-and-book")]
    [Authorize(Roles = Roles.Customer)]
    public async Task<IActionResult> FindAndBook([FromBody] FindAndBookDto dto)
    {
        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (!Guid.TryParse(userIdClaim, out var customerId)) return Unauthorized();

        var customer = await _db.Users.FindAsync(customerId);
        if (customer == null) return Unauthorized();

        var tenant = await _db.Tenants.FindAsync(customer.TenantId);
        if (tenant == null || !tenant.IsActive) return BadRequest(new { message = "Tenant not found or inactive." });

        // Short-lived token minted for the actual customer — every tool the
        // Python service calls uses this, so it gets exactly the same
        // tenant-scoping and role checks a real app request would get.
        var authToken = _jwtService.GenerateAccessToken(customer);

        var planResult = await _plannerAgentService.PlanAsync(new AgentPlanRequest(
            Objective: dto.Objective,
            TenantId: tenant.Id,
            BusinessType: tenant.BusinessType,
            BranchId: customer.BranchId,
            CustomerId: customer.Id,
            DateFrom: dto.DateFrom,
            DateTo: dto.DateTo,
            ExtraConstraints: dto.ExtraConstraints ?? new Dictionary<string, object>(),
            AuthToken: authToken
        ));

        if (!planResult.Success)
            return UnprocessableEntity(new { message = planResult.ErrorMessage ?? "The AI planner could not complete this request." });

        var trace = planResult.Trace!;
        var plan = BuildPlanFromTrace(trace);

        switch (trace.Status)
        {
            case "Completed":
            {
                // The Validation/Safety agent already created the booking
                // using the customer's own token — record it for audit/trace
                // (FR-AS23) without going through PersistWorkflowAsync's
                // approval branching (already decided) or /apply (would
                // create a second booking).
                var workflow = new AgentWorkflow
                {
                    TenantId = tenant.Id,
                    Objective = dto.Objective,
                    PlanJson = JsonSerializer.Serialize(plan),
                    Status = "Completed",
                    ApprovalStatus = "NotRequired",
                    CurrentStep = plan.Steps.Count,
                    FinalOutcome = $"Booking created: {trace.ValidationOutput?.BookingId}",
                    CompletedAt = DateTime.UtcNow,
                    RequestedByUserId = customer.Id,
                    ToolResultsJson = SerializeExecutionTrace(trace),
                    ValidationResults = SerializeValidationResults(trace),
                };
                _db.AgentWorkflows.Add(workflow);
                await _db.SaveChangesAsync();
                return Ok(new { workflowId = workflow.Id, status = workflow.Status, bookingId = trace.ValidationOutput?.BookingId });
            }
            case "AwaitingApproval":
            {
                var workflow = await PersistWorkflowAsync(tenant.Id, dto.Objective, plan, requiresApprovalOverride: true, requestedByUserId: customer.Id, trace: trace);
                return Accepted(new
                {
                    message = "This booking needs manager approval before it's confirmed.",
                    workflowId = workflow.Id,
                });
            }
            default: // Rejected / Failed
            {
                var workflow = new AgentWorkflow
                {
                    TenantId = tenant.Id,
                    Objective = dto.Objective,
                    PlanJson = plan.Steps.Count > 0 ? JsonSerializer.Serialize(plan) : null,
                    Status = "Rejected",
                    ApprovalStatus = "NotRequired",
                    ErrorLog = trace.ValidationOutput?.RejectionReason ?? trace.Error,
                    CompletedAt = DateTime.UtcNow,
                    RequestedByUserId = customer.Id,
                    ToolResultsJson = SerializeExecutionTrace(trace),
                    ValidationResults = SerializeValidationResults(trace),
                };
                _db.AgentWorkflows.Add(workflow);
                await _db.SaveChangesAsync();
                return UnprocessableEntity(new { message = workflow.ErrorLog ?? "Could not find an available booking for this request.", workflowId = workflow.Id });
            }
        }
    }

    private static PlanDto BuildPlanFromTrace(WorkflowTraceDto trace)
    {
        var steps = (trace.ActionToolOutput?.ProposedBookings ?? new List<ProposedBookingDto>())
            .Select(b => new StepDto(
                "ActionToolAgent",
                "CreateBooking",
                "bookings.create",
                new
                {
                    resourceId = b.ResourceId,
                    resourceName = b.ResourceName,
                    bookingTypeId = b.BookingTypeId,
                    startTime = b.ScheduledDatetime,
                    endTime = b.ScheduledDatetime.AddMinutes(b.DurationMinutes),
                }))
            .ToList();
        return new PlanDto(steps, 0);
    }

    // The execution trace is the auditable record of HOW a plan was produced:
    // which allow-listed tools ran and for how long, which model answered and
    // after how many retries, and which agent owns each step. The plan alone
    // records what was decided but never how, so a workflow persisted without
    // this cannot answer the questions an audit actually asks.
    private static string SerializeExecutionTrace(WorkflowTraceDto trace) =>
        JsonSerializer.Serialize(new
        {
            workflowType = "booking",
            agentWorkflowId = trace.WorkflowId,
            agentSteps = trace.AgentSteps ?? new List<AgentStepRecordDto>(),
            toolCalls = trace.ToolCalls ?? new List<ToolCallRecordDto>(),
            llmCalls = trace.LlmCalls ?? new List<LlmCallRecordDto>(),
            plannerConfidence = trace.PlannerOutput?.ConfidenceScore,
            predictedConflicts = trace.PlannerOutput?.PredictedConflicts,
            rankingCriteria = trace.DomainAnalysisOutput?.RankingCriteriaUsed,
            error = trace.Error,
            completedAt = trace.CompletedAt,
        });

    // Identity of a proposed booking for revision checks: which resource,
    // when. Compared as text so a round-trip through the client cannot make
    // an unchanged step look new.
    private static string StepKey(StepDto step)
    {
        var p = step.Parameters is JsonElement el ? el : JsonSerializer.SerializeToElement(step.Parameters);
        string Read(string name) => p.ValueKind == JsonValueKind.Object && p.TryGetProperty(name, out var v)
            ? (v.ValueKind == JsonValueKind.String && DateTime.TryParse(v.GetString(), null,
                System.Globalization.DateTimeStyles.AdjustToUniversal | System.Globalization.DateTimeStyles.AssumeUniversal, out var dt)
                ? dt.ToString("O") : v.ToString())
            : string.Empty;
        return $"{step.Action}|{Read("resourceId").ToLowerInvariant()}|{Read("startTime")}|{Read("endTime")}";
    }

    private static string SerializeValidationResults(WorkflowTraceDto trace) =>
        JsonSerializer.Serialize(new
        {
            isAllowed = trace.ValidationOutput?.IsAllowed,
            requiresHumanApproval = trace.ValidationOutput?.RequiresHumanApproval,
            rejectionReason = trace.ValidationOutput?.RejectionReason,
            notes = trace.ValidationOutput?.ValidationNotes ?? new List<string>(),
        });

    // Applying a plan must not erase how that plan was produced, so the
    // planning trace is carried forward under its own key instead of being
    // overwritten by the application results.
    private static JsonElement? PreservePlanningTrace(string? existing)
    {
        if (string.IsNullOrWhiteSpace(existing)) return null;
        try { return JsonDocument.Parse(existing).RootElement.Clone(); }
        catch (JsonException) { return null; }
    }

    private async Task<AgentWorkflow> PersistWorkflowAsync(
        Guid tenantId, string objective, PlanDto plan, bool? requiresApprovalOverride = null,
        Guid? requestedByUserId = null, WorkflowTraceDto? trace = null)
    {
        var requiresApproval = requiresApprovalOverride ?? (plan.Steps.Count > 20 || plan.EstimatedRevenueImpact > 500);

        var workflow = new AgentWorkflow
        {
            TenantId = tenantId,
            Objective = objective,
            PlanJson = JsonSerializer.Serialize(plan),
            Status = requiresApproval ? "AwaitingApproval" : "Approved",
            ApprovalStatus = requiresApproval ? "Pending" : "NotRequired",
            CurrentStep = 0,
            RequestedByUserId = requestedByUserId,
            ToolResultsJson = trace is null ? null : SerializeExecutionTrace(trace),
            ValidationResults = trace is null ? null : SerializeValidationResults(trace),
        };

        _db.AgentWorkflows.Add(workflow);

        if (requiresApproval)
        {
            NotificationHelper.Queue(_db, tenantId, null, "WorkflowApproval",
                "Plan needs approval", $"\"{objective}\" affects {plan.Steps.Count} booking(s) and needs your approval.");
        }

        await _db.SaveChangesAsync();
        return workflow;
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetWorkflow(Guid id)
    {
        var wf = await _db.AgentWorkflows.AsNoTracking().FirstOrDefaultAsync(w => w.Id == id);
        if (wf == null) return NotFound();
        return Ok(wf);
    }

    // Customer-facing status tracking (FR-AS: agentic pipeline) - the
    // requesting customer's own AI booking requests, across every status.
    // Backs the mobile "My AI Requests" screen.
    [HttpGet("mine")]
    public async Task<IActionResult> GetMyWorkflows()
    {
        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (!Guid.TryParse(userIdClaim, out var userId)) return Unauthorized();

        var workflows = await _db.AgentWorkflows.AsNoTracking()
            .Where(w => w.RequestedByUserId == userId)
            .OrderByDescending(w => w.CreatedAt)
            .ToListAsync();
        return Ok(workflows);
    }

    [HttpGet]
    public async Task<IActionResult> GetWorkflows([FromQuery] Guid tenantId, [FromQuery] string? status)
    {
        var query = _db.AgentWorkflows.AsNoTracking().Where(w => w.TenantId == tenantId);
        if (!string.IsNullOrEmpty(status)) query = query.Where(w => w.Status == status);

        var workflows = await query
            .OrderByDescending(w => w.CreatedAt)
            .ToListAsync();
        return Ok(workflows);
    }

    [HttpPost("{id}/approve")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> Approve(Guid id)
    {
        var wf = await _db.AgentWorkflows.FindAsync(id);
        if (wf == null) return NotFound();

        // Approval is an answer to a question the safety gate asked. Without
        // this check a manager could "approve" a plan the gate rejected and
        // /apply would then book it - the gate bypassed by one click.
        if (wf.ApprovalStatus != "Pending")
            return Conflict(new { message = $"Only a workflow awaiting approval can be approved (this one is {wf.Status})." });

        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;

        wf.ApprovalStatus = "Approved";
        wf.Status = "Approved";
        wf.ApprovedBy = Guid.TryParse(userId, out var uid) ? uid : null;
        wf.ApprovedAt = DateTime.UtcNow;
        wf.UpdatedAt = DateTime.UtcNow;

        if (wf.RequestedByUserId.HasValue)
        {
            NotificationHelper.Queue(_db, wf.TenantId, wf.RequestedByUserId, "WorkflowApproved",
                "Booking request approved", $"Your request \"{wf.Objective}\" was approved. It'll be confirmed shortly.");
        }

        await _db.SaveChangesAsync();

        if (wf.RequestedByUserId.HasValue)
        {
            await _pushSender.SendAsync(wf.TenantId, wf.RequestedByUserId.Value, "Booking request approved",
                $"Your request \"{wf.Objective}\" was approved.");
        }

        return Ok(new { message = "Workflow approved.", wf.Id, wf.Status });
    }

    [HttpPost("{id}/reject")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> Reject(Guid id, [FromBody] RejectWorkflowDto dto)
    {
        var wf = await _db.AgentWorkflows.FindAsync(id);
        if (wf == null) return NotFound();

        if (wf.Status is "Completed" or "Rejected" or "Failed")
            return Conflict(new { message = $"This workflow is already {wf.Status.ToLowerInvariant()} and cannot be rejected." });

        wf.ApprovalStatus = "Rejected";
        wf.Status = "Rejected";
        wf.ErrorLog = dto.Reason;
        wf.UpdatedAt = DateTime.UtcNow;

        if (wf.RequestedByUserId.HasValue)
        {
            NotificationHelper.Queue(_db, wf.TenantId, wf.RequestedByUserId, "WorkflowRejected",
                "Booking request declined", $"Your request \"{wf.Objective}\" was declined.{(string.IsNullOrEmpty(dto.Reason) ? "" : $" Reason: {dto.Reason}")}");
        }

        await _db.SaveChangesAsync();

        if (wf.RequestedByUserId.HasValue)
        {
            await _pushSender.SendAsync(wf.TenantId, wf.RequestedByUserId.Value, "Booking request declined",
                $"Your request \"{wf.Objective}\" was declined.");
        }

        return Ok(new { message = "Workflow rejected." });
    }

    [HttpPost("{id}/revise")]
    [Authorize(Roles = "Admin,Manager")]
    public async Task<IActionResult> Revise(Guid id, [FromBody] ReviseWorkflowDto dto)
    {
        var wf = await _db.AgentWorkflows.FindAsync(id);
        if (wf == null) return NotFound();

        if (wf.ApprovalStatus != "Pending")
            return Conflict(new { message = "Only a workflow awaiting approval can be revised." });
        if (dto.Plan?.Steps == null || dto.Plan.Steps.Count == 0)
            return BadRequest(new { message = "A revision must keep at least one step. Reject the workflow instead." });

        // Revision narrows a validated plan; it cannot extend it. Every step
        // kept must be one the agents already proposed and the gate already
        // checked, otherwise "revise" would be a way to book slots that never
        // went through validation at all.
        var original = string.IsNullOrEmpty(wf.PlanJson) ? null : JsonSerializer.Deserialize<PlanDto>(wf.PlanJson);
        var allowed = new HashSet<string>((original?.Steps ?? new List<StepDto>()).Select(StepKey));
        var foreign = dto.Plan.Steps.Where(step => !allowed.Contains(StepKey(step))).ToList();
        if (foreign.Count > 0)
            return BadRequest(new { message = $"{foreign.Count} step(s) are not part of the proposed plan. A revision can only remove steps." });

        wf.PlanJson = JsonSerializer.Serialize(dto.Plan);
        wf.Status = "AwaitingApproval";
        wf.ApprovalStatus = "Pending";
        wf.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        return Ok(wf);
    }
}

public record CreateWorkflowDto(Guid TenantId, string Objective, PlanDto Plan);
public record PlanDto(List<StepDto> Steps, double EstimatedRevenueImpact);
public record StepDto(string Agent, string Action, string Tool, object Parameters);
public record RejectWorkflowDto(string Reason);
public record ReviseWorkflowDto(PlanDto Plan);
public record PlanScheduleDto(
    Guid TenantId,
    string Objective,
    Guid BookingTypeId,
    DateOnly DateFrom,
    DateOnly DateTo,
    int TargetCount,
    List<Guid>? ResourceIds,
    List<string>? PriorityRules,
    Guid? BranchId);
public record ProposeScheduleDto(Guid TenantId, string Objective, int Count, Guid BookingTypeId, Guid? BranchId, int? WithinDays);
public record FindAndBookDto(string Objective, DateTime? DateFrom, DateTime? DateTo, Dictionary<string, object>? ExtraConstraints);
