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

    // ── FR-B12: AI Planner Agent — auto-proposes a schedule ────────────────
    // Deterministic heuristic (no LLM configured in this project): greedily
    // fills the earliest open slots across the tenant's resources within the
    // requested window, using the same SlotCalculator the availability
    // endpoints use, then routes the resulting plan through the same
    // approval threshold as everything else in this controller.
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

        if (resources.Count == 0)
            return Ok(new { message = "No resources available to schedule against.", steps = Array.Empty<object>() });

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

        var plan = new PlanDto(proposedSteps, 0);
        var workflow = await PersistWorkflowAsync(dto.TenantId, dto.Objective, plan);
        return CreatedAtAction(nameof(GetWorkflow), new { id = workflow.Id }, workflow);
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
                };
                _db.AgentWorkflows.Add(workflow);
                await _db.SaveChangesAsync();
                return Ok(new { workflowId = workflow.Id, status = workflow.Status, bookingId = trace.ValidationOutput?.BookingId });
            }
            case "AwaitingApproval":
            {
                var workflow = await PersistWorkflowAsync(tenant.Id, dto.Objective, plan, requiresApprovalOverride: true, requestedByUserId: customer.Id);
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

    private async Task<AgentWorkflow> PersistWorkflowAsync(
        Guid tenantId, string objective, PlanDto plan, bool? requiresApprovalOverride = null, Guid? requestedByUserId = null)
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
            RequestedByUserId = requestedByUserId
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
public record ProposeScheduleDto(Guid TenantId, string Objective, int Count, Guid BookingTypeId, Guid? BranchId, int? WithinDays);
public record FindAndBookDto(string Objective, DateTime? DateFrom, DateTime? DateTo, Dictionary<string, object>? ExtraConstraints);
