using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Tests.Api;

namespace SmeBackend.Tests.Bookings;

/// <summary>
/// The side of the Disruption Recovery Copilot that actually moves people's
/// bookings. The agents only propose; everything irreversible happens here,
/// so these tests cover approval, the subset a manager accepted, the
/// re-check against the live database, and that a rejected plan moves
/// nothing.
/// </summary>
public sealed class DisruptionRecoveryTests(ApiWebApplicationFactory factory) : IClassFixture<ApiWebApplicationFactory>
{
    private async Task<HttpClient> As(UserRole role)
    {
        var client = factory.CreateClient();
        var login = await client.PostAsJsonAsync("/api/auth/login",
            new { email = ApiWebApplicationFactory.EmailFor(role), password = ApiWebApplicationFactory.Password });
        login.EnsureSuccessStatusCode();
        using var body = JsonDocument.Parse(await login.Content.ReadAsStringAsync());
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", body.RootElement.GetProperty("accessToken").GetString());
        return client;
    }

    private T Db<T>(Func<AppDbContext, T> read)
    {
        using var scope = factory.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<ITenantContext>().SetTenantId(factory.TenantId);
        return read(scope.ServiceProvider.GetRequiredService<AppDbContext>());
    }

    /// <summary>Seeds a booking on a resource and a workflow proposing to move it elsewhere.</summary>
    private (Guid WorkflowId, Guid BookingId, Guid TargetResourceId, DateTime NewStart) SeedPlan(
        bool gateRejected = false, DateTime? occupyTargetAt = null)
    {
        using var scope = factory.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<ITenantContext>().SetTenantId(factory.TenantId);
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var branch = new Branch { TenantId = factory.TenantId, Name = "Main", IsActive = true };
        var broken = new Resource { TenantId = factory.TenantId, Name = "Dr Silva" };
        var cover = new Resource { TenantId = factory.TenantId, Name = "Dr Perera" };
        var type = new BookingType { TenantId = factory.TenantId, Name = "Consultation", DefaultDurationMinutes = 60 };
        db.Branches.Add(branch);
        db.Resources.AddRange(broken, cover);
        db.BookingTypes.Add(type);
        db.SaveChanges();

        var start = new DateTime(2026, 12, 1, 9, 0, 0, DateTimeKind.Utc);
        var booking = new SmeBackend.Models.Booking
        {
            TenantId = factory.TenantId,
            ResourceId = broken.Id,
            BookingTypeId = type.Id,
            BookedBy = Guid.NewGuid(),
            Title = "Consultation",
            StartTime = start,
            EndTime = start.AddHours(1),
            Status = BookingStatus.Confirmed,
        };
        db.Bookings.Add(booking);

        if (occupyTargetAt is { } occupied)
        {
            db.Bookings.Add(new SmeBackend.Models.Booking
            {
                TenantId = factory.TenantId,
                ResourceId = cover.Id,
                BookingTypeId = type.Id,
                BookedBy = Guid.NewGuid(),
                Title = "Someone else",
                StartTime = occupied,
                EndTime = occupied.AddHours(1),
                Status = BookingStatus.Confirmed,
            });
        }
        db.SaveChanges();

        var trace = new
        {
            action = new
            {
                proposals = new[]
                {
                    new
                    {
                        booking_id = booking.Id.ToString(),
                        proposed_resource_id = cover.Id.ToString(),
                        proposed_starts_at = start.ToString("O"),
                        proposed_ends_at = start.AddHours(1).ToString("O"),
                        explanation = "Same time, with Dr Perera instead of Dr Silva.",
                    },
                },
                unresolved = Array.Empty<string>(),
            },
        };

        var workflow = new AgentWorkflow
        {
            TenantId = factory.TenantId,
            Objective = DisruptionRecoveryController.ObjectivePrefix + "Dr Silva is off sick",
            Status = "AwaitingApproval",
            ApprovalStatus = "Pending",
            PlanJson = JsonSerializer.Serialize(trace),
            ValidationResults = gateRejected
                ? JsonSerializer.Serialize(new { rejected_booking_ids = new[] { booking.Id.ToString() } })
                : JsonSerializer.Serialize(new { rejected_booking_ids = Array.Empty<string>() }),
        };
        db.AgentWorkflows.Add(workflow);
        db.SaveChanges();

        return (workflow.Id, booking.Id, cover.Id, start);
    }

    [Fact]
    public async Task ApprovingARecovery_MovesTheBookingAndRecordsTheOutcome()
    {
        var plan = SeedPlan();
        var manager = await As(UserRole.Manager);

        var response = await manager.PostAsJsonAsync($"/api/agent/disruption/{plan.WorkflowId}/apply", new { });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
        Assert.Single(body.GetProperty("moved").EnumerateArray());

        var moved = Db(db => db.Bookings.IgnoreQueryFilters().Single(b => b.Id == plan.BookingId));
        Assert.Equal(plan.TargetResourceId, moved.ResourceId);

        var workflow = Db(db => db.AgentWorkflows.IgnoreQueryFilters().Single(w => w.Id == plan.WorkflowId));
        Assert.Equal("Completed", workflow.Status);
        Assert.Equal("Approved", workflow.ApprovalStatus);
        Assert.NotNull(workflow.ApprovedBy);
    }

    [Fact]
    public async Task TheCustomerIsToldTheirBookingMoved()
    {
        var plan = SeedPlan();
        var manager = await As(UserRole.Manager);

        await manager.PostAsJsonAsync($"/api/agent/disruption/{plan.WorkflowId}/apply", new { });

        Assert.True(Db(db => db.Notifications.IgnoreQueryFilters()
            .Any(n => n.Type == "BookingRescheduled" && n.Title == "Your booking was moved")));
    }

    [Fact]
    public async Task ASlotTakenWhileThePlanWaited_IsSkippedRatherThanDoubleBooked()
    {
        // Someone else books the destination before the manager approves.
        var plan = SeedPlan(occupyTargetAt: new DateTime(2026, 12, 1, 9, 0, 0, DateTimeKind.Utc));
        var manager = await As(UserRole.Manager);

        var response = await manager.PostAsJsonAsync($"/api/agent/disruption/{plan.WorkflowId}/apply", new { });

        var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
        Assert.Empty(body.GetProperty("moved").EnumerateArray());
        var skipped = Assert.Single(body.GetProperty("skipped").EnumerateArray());
        Assert.Contains("taken while the plan waited", skipped.GetProperty("reason").GetString());

        // The original booking is untouched.
        var untouched = Db(db => db.Bookings.IgnoreQueryFilters().Single(b => b.Id == plan.BookingId));
        Assert.NotEqual(plan.TargetResourceId, untouched.ResourceId);
    }

    [Fact]
    public async Task AProposalTheGateStruckOut_IsNeverApplied()
    {
        var plan = SeedPlan(gateRejected: true);
        var manager = await As(UserRole.Manager);

        var response = await manager.PostAsJsonAsync($"/api/agent/disruption/{plan.WorkflowId}/apply", new { });

        var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;
        Assert.Empty(body.GetProperty("moved").EnumerateArray());
        var untouched = Db(db => db.Bookings.IgnoreQueryFilters().Single(b => b.Id == plan.BookingId));
        Assert.NotEqual(plan.TargetResourceId, untouched.ResourceId);
    }

    [Fact]
    public async Task AManagerCanAcceptOnlySomeOfThePlan()
    {
        var plan = SeedPlan();
        var manager = await As(UserRole.Manager);

        // Accepting a different booking id leaves this one alone.
        var response = await manager.PostAsJsonAsync($"/api/agent/disruption/{plan.WorkflowId}/apply",
            new { acceptedBookingIds = new[] { Guid.NewGuid() } });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var untouched = Db(db => db.Bookings.IgnoreQueryFilters().Single(b => b.Id == plan.BookingId));
        Assert.NotEqual(plan.TargetResourceId, untouched.ResourceId);
    }

    [Fact]
    public async Task RejectingARecovery_MovesNothingAndKeepsTheReason()
    {
        var plan = SeedPlan();
        var manager = await As(UserRole.Manager);

        var response = await manager.PostAsJsonAsync($"/api/agent/disruption/{plan.WorkflowId}/reject",
            new { reason = "I will call the patients myself" });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var workflow = Db(db => db.AgentWorkflows.IgnoreQueryFilters().Single(w => w.Id == plan.WorkflowId));
        Assert.Equal("Rejected", workflow.Status);
        Assert.Contains("I will call the patients myself", workflow.FinalOutcome);

        var untouched = Db(db => db.Bookings.IgnoreQueryFilters().Single(b => b.Id == plan.BookingId));
        Assert.NotEqual(plan.TargetResourceId, untouched.ResourceId);
    }

    [Fact]
    public async Task ApplyingTwice_IsRefused()
    {
        var plan = SeedPlan();
        var manager = await As(UserRole.Manager);

        await manager.PostAsJsonAsync($"/api/agent/disruption/{plan.WorkflowId}/apply", new { });
        var again = await manager.PostAsJsonAsync($"/api/agent/disruption/{plan.WorkflowId}/apply", new { });

        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);
    }

    [Fact]
    public async Task StaffCannotApplyARecovery()
    {
        var plan = SeedPlan();
        var staff = await As(UserRole.Staff);

        var response = await staff.PostAsJsonAsync($"/api/agent/disruption/{plan.WorkflowId}/apply", new { });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task RejectingWithoutAReason_Returns400()
    {
        var plan = SeedPlan();
        var manager = await As(UserRole.Manager);

        var response = await manager.PostAsJsonAsync($"/api/agent/disruption/{plan.WorkflowId}/reject",
            new { reason = "no" });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task PlanningIsGatedByTheTenantsPlan_LikeEveryOtherAiSurface()
    {
        // The Disruption Copilot is an AI run, so [MetersPlanQuota] answers
        // 402 with the plan that clears it before the request is even read.
        // That gate firing first is the point: a tenant without the AI
        // feature cannot spend a model call by sending a malformed body.
        var manager = await As(UserRole.Manager);

        var response = await manager.PostAsJsonAsync("/api/agent/disruption/plan", new
        {
            objective = "Dr Silva is off sick",
            resourceId = Guid.NewGuid(),
            dateFrom = "2026-12-10",
            dateTo = "2026-12-01",
        });

        Assert.Equal(HttpStatusCode.PaymentRequired, response.StatusCode);
    }

    [Fact]
    public async Task TheListOnlyShowsDisruptionWorkflows()
    {
        SeedPlan();
        using (var scope = factory.Services.CreateScope())
        {
            scope.ServiceProvider.GetRequiredService<ITenantContext>().SetTenantId(factory.TenantId);
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.AgentWorkflows.Add(new AgentWorkflow
            {
                TenantId = factory.TenantId,
                Objective = "[StockSense reorder] 2 item(s) from MediSupply",
                Status = "AwaitingApproval",
            });
            db.SaveChanges();
        }
        var manager = await As(UserRole.Manager);

        var rows = await manager.GetFromJsonAsync<List<JsonElement>>("/api/agent/disruption");

        Assert.NotNull(rows);
        Assert.All(rows!, r => Assert.DoesNotContain("StockSense", r.GetProperty("objective").GetString()));
    }
}
