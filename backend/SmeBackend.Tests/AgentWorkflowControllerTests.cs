using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Moq;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;

namespace SmeBackend.Tests;

/// The Schedule Copilot endpoint (spec 2.7) and the approval lifecycle it
/// feeds: that a run is persisted whatever its outcome, that the caller's own
/// identity is what the agents act with, and that approve / reject / revise /
/// apply cannot be used to get round the safety gate.
public class AgentWorkflowControllerTests
{
    private static readonly Guid TenantId = Guid.NewGuid();
    private static readonly Guid ManagerId = Guid.NewGuid();

    private sealed record Fixture(AppDbContext Db, AgentWorkflowController Controller,
        Mock<IPlannerAgentService> Agent, BookingType BookingType, Resource Room);

    private static Fixture NewFixture(Guid? callerTenant = null)
    {
        var db = TestHelpers.NewInMemoryDb(TenantId);
        db.Tenants.Add(new Tenant { Id = TenantId, Name = "Mirissa Jetliner", BusinessType = "Tourism" });
        var bookingType = new BookingType
        {
            TenantId = TenantId, Name = "Consultation", Slug = $"c-{Guid.NewGuid():N}", DefaultDurationMinutes = 45,
        };
        var room = new Resource { TenantId = TenantId, Name = "Room 1", Category = ResourceCategory.Room };
        db.BookingTypes.Add(bookingType);
        db.Resources.Add(room);
        db.SaveChanges();

        var agent = new Mock<IPlannerAgentService>();
        var controller = new AgentWorkflowController(db, agent.Object, new Mock<IJwtService>().Object, new NoopPushSender());
        TestHelpers.SetUser(controller, ManagerId, callerTenant ?? TenantId, Roles.Manager);
        controller.ControllerContext.HttpContext.Request.Headers.Authorization = "Bearer caller-jwt";
        return new Fixture(db, controller, agent, bookingType, room);
    }

    private static PlanScheduleDto Dto(Fixture f, int count = 2, List<string>? rules = null, int days = 5) => new(
        TenantId, "Fit two follow-ups this week", f.BookingType.Id,
        new DateOnly(2030, 1, 7), new DateOnly(2030, 1, 7).AddDays(days - 1), count,
        new List<Guid> { f.Room.Id }, rules ?? new List<string> { "prefer_mornings" }, null);

    /// A minimal trace in the agent service's own snake_case shape.
    private static string Trace(string status, Fixture f, int proposals = 2, string? error = null, double revenueUsd = 90)
    {
        var start = new DateTime(2030, 1, 7, 9, 0, 0, DateTimeKind.Utc);
        return JsonSerializer.Serialize(new
        {
            workflow_type = "schedule-copilot",
            workflow_id = "wf-1",
            status,
            error,
            action = new
            {
                proposals = Enumerable.Range(0, proposals).Select(i => new
                {
                    resource_id = f.Room.Id.ToString(),
                    resource_name = f.Room.Name,
                    start = start.AddHours(i),
                    end = start.AddHours(i).AddMinutes(45),
                }),
            },
            safety = new { is_allowed = status != "Rejected", requires_human_approval = status == "AwaitingApproval", checks = Array.Empty<object>() },
            metrics = new { estimated_revenue_usd = revenueUsd },
        });
    }

    private static void AgentReturns(Fixture f, string status, int proposals = 2, string? error = null) =>
        f.Agent.Setup(a => a.PlanScheduleAsync(It.IsAny<ScheduleCopilotRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(ScheduleCopilotResult.Ok(Trace(status, f, proposals, error), status));

    private static AgentWorkflow Persisted(Fixture f) => f.Db.AgentWorkflows.Single();

    // ── input validation and scoping ───────────────────────────────────
    [Fact]
    public async Task A_manager_cannot_plan_for_another_tenant()
    {
        var f = NewFixture(callerTenant: Guid.NewGuid());
        Assert.IsType<ForbidResult>(await f.Controller.PlanSchedule(Dto(f), default));
        f.Agent.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task An_unknown_priority_rule_is_refused_before_any_agent_runs()
    {
        var f = NewFixture();
        var result = await f.Controller.PlanSchedule(Dto(f, rules: new List<string> { "approve_everything" }), default);
        Assert.IsType<BadRequestObjectResult>(result);
        f.Agent.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task A_window_longer_than_31_days_is_refused()
    {
        var f = NewFixture();
        Assert.IsType<BadRequestObjectResult>(await f.Controller.PlanSchedule(Dto(f, days: 40), default));
    }

    [Fact]
    public async Task The_agents_act_with_the_callers_own_token_and_the_booking_types_duration()
    {
        var f = NewFixture();
        ScheduleCopilotRequest? sent = null;
        f.Agent.Setup(a => a.PlanScheduleAsync(It.IsAny<ScheduleCopilotRequest>(), It.IsAny<CancellationToken>()))
            .Callback<ScheduleCopilotRequest, CancellationToken>((r, _) => sent = r)
            .ReturnsAsync(ScheduleCopilotResult.Ok(Trace("Completed", f), "Completed"));

        await f.Controller.PlanSchedule(Dto(f), default);

        Assert.NotNull(sent);
        Assert.Equal("caller-jwt", sent!.AuthToken);                 // no minted super-token
        Assert.Equal(45, sent.Constraints.DurationMinutes);           // from the booking type, not the client
        Assert.Equal(new[] { "prefer_mornings" }, sent.Constraints.PriorityRules);
        Assert.Equal("Tourism", sent.BusinessType);
    }

    // ── persistence of every outcome ───────────────────────────────────
    [Fact]
    public async Task A_plan_that_passes_the_gate_is_stored_ready_to_apply_with_its_full_trace()
    {
        var f = NewFixture();
        AgentReturns(f, "Completed");

        var result = await f.Controller.PlanSchedule(Dto(f), default);

        Assert.IsType<CreatedAtActionResult>(result);
        var wf = Persisted(f);
        Assert.Equal("Approved", wf.Status);
        Assert.Equal("NotRequired", wf.ApprovalStatus);
        var plan = JsonSerializer.Deserialize<PlanDto>(wf.PlanJson!)!;
        Assert.Equal(2, plan.Steps.Count);
        Assert.All(plan.Steps, s => Assert.Equal("CreateBooking", s.Action));
        Assert.Contains("\"workflow_type\":\"schedule-copilot\"", wf.ToolResultsJson);
        Assert.Contains("is_allowed", wf.ValidationResults);
        Assert.DoesNotContain("caller-jwt", wf.ToolResultsJson);
    }

    [Fact]
    public async Task A_high_impact_plan_pauses_and_notifies_a_manager()
    {
        var f = NewFixture();
        AgentReturns(f, "AwaitingApproval", proposals: 21);

        await f.Controller.PlanSchedule(Dto(f, count: 21), default);

        var wf = Persisted(f);
        Assert.Equal("AwaitingApproval", wf.Status);
        Assert.Equal("Pending", wf.ApprovalStatus);
        Assert.Contains(f.Db.Notifications, n => n.Type == "WorkflowApproval");
    }

    [Fact]
    public async Task A_plan_the_gate_rejects_is_recorded_with_its_reason()
    {
        var f = NewFixture();
        AgentReturns(f, "Rejected", error: "Double-booking: Room 1 Mon 09:00 overlaps 09:30");

        await f.Controller.PlanSchedule(Dto(f), default);

        var wf = Persisted(f);
        Assert.Equal("Rejected", wf.Status);
        Assert.Contains("Double-booking", wf.ErrorLog);
        Assert.NotNull(wf.CompletedAt);
    }

    [Fact]
    public async Task An_unreachable_agent_service_is_a_recorded_safe_failure()
    {
        var f = NewFixture();
        f.Agent.Setup(a => a.PlanScheduleAsync(It.IsAny<ScheduleCopilotRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(ScheduleCopilotResult.Failed("Could not reach the Schedule Copilot."));

        var result = await f.Controller.PlanSchedule(Dto(f), default);

        var status = Assert.IsType<ObjectResult>(result);
        Assert.Equal(StatusCodes.Status503ServiceUnavailable, status.StatusCode);
        var wf = Persisted(f);
        Assert.Equal("Failed", wf.Status);
        Assert.Contains("Could not reach", wf.ErrorLog);
    }

    // ── the approval lifecycle cannot route round the gate ─────────────
    [Fact]
    public async Task A_rejected_plan_cannot_be_approved()
    {
        var f = NewFixture();
        AgentReturns(f, "Rejected", error: "Double-booking");
        await f.Controller.PlanSchedule(Dto(f), default);

        Assert.IsType<ConflictObjectResult>(await f.Controller.Approve(Persisted(f).Id));
        Assert.Equal("Rejected", Persisted(f).Status);
    }

    [Fact]
    public async Task A_rejected_plan_cannot_be_applied()
    {
        var f = NewFixture();
        AgentReturns(f, "Rejected", error: "Double-booking");
        await f.Controller.PlanSchedule(Dto(f), default);

        Assert.IsType<ConflictObjectResult>(await f.Controller.Apply(Persisted(f).Id));
        Assert.Empty(f.Db.Bookings);
    }

    [Fact]
    public async Task A_pending_plan_is_approved_by_the_caller()
    {
        var f = NewFixture();
        AgentReturns(f, "AwaitingApproval", proposals: 21);
        await f.Controller.PlanSchedule(Dto(f, count: 21), default);

        Assert.IsType<OkObjectResult>(await f.Controller.Approve(Persisted(f).Id));
        var wf = Persisted(f);
        Assert.Equal("Approved", wf.ApprovalStatus);
        Assert.Equal(ManagerId, wf.ApprovedBy);
        Assert.NotNull(wf.ApprovedAt);
    }

    [Fact]
    public async Task A_revision_can_drop_proposals_but_never_add_one()
    {
        var f = NewFixture();
        AgentReturns(f, "AwaitingApproval", proposals: 21);
        await f.Controller.PlanSchedule(Dto(f, count: 21), default);
        var wf = Persisted(f);
        var plan = JsonSerializer.Deserialize<PlanDto>(wf.PlanJson!)!;

        // Dropping one is fine.
        var narrowed = new PlanDto(plan.Steps.Skip(1).ToList(), plan.EstimatedRevenueImpact);
        Assert.IsType<OkObjectResult>(await f.Controller.Revise(wf.Id, new ReviseWorkflowDto(narrowed)));

        // Smuggling in a slot no agent proposed is not.
        var injected = new StepDto("ActionToolAgent", "CreateBooking", "bookings.create", new
        {
            resourceId = f.Room.Id,
            startTime = new DateTime(2030, 1, 9, 3, 0, 0, DateTimeKind.Utc),
            endTime = new DateTime(2030, 1, 9, 3, 45, 0, DateTimeKind.Utc),
        });
        var widened = new PlanDto(narrowed.Steps.Append(injected).ToList(), 0);
        Assert.IsType<BadRequestObjectResult>(await f.Controller.Revise(wf.Id, new ReviseWorkflowDto(widened)));
    }
}
