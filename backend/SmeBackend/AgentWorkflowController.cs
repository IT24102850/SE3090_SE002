using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;
using System.Text.Json;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/agent/workflow")]
[Authorize]
public class AgentWorkflowController : ControllerBase
{
    private readonly AppDbContext _db;
    public AgentWorkflowController(AppDbContext db) => _db = db;

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
        await _db.SaveChangesAsync();

        return Ok(new { message = wf.FinalOutcome, created, skipped });
    }

    private async Task<AgentWorkflow> PersistWorkflowAsync(Guid tenantId, string objective, PlanDto plan)
    {
        var requiresApproval = plan.Steps.Count > 20 || plan.EstimatedRevenueImpact > 500;

        var workflow = new AgentWorkflow
        {
            TenantId = tenantId,
            Objective = objective,
            PlanJson = JsonSerializer.Serialize(plan),
            Status = requiresApproval ? "AwaitingApproval" : "Approved",
            ApprovalStatus = requiresApproval ? "Pending" : "NotRequired",
            CurrentStep = 0
        };

        _db.AgentWorkflows.Add(workflow);
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
        await _db.SaveChangesAsync();

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
        await _db.SaveChangesAsync();

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
