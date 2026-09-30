using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services.PlatformBilling;
using Xunit;

namespace SmeBackend.Tests.PlatformBilling;

/// The execution half of the Platform Operations Copilot - the only code in
/// the feature that can change a business's standing.
///
/// The Python side proves the agents cannot propose something out of policy.
/// These prove the stronger claim: that even if they did, ASP.NET Core would
/// not carry it out. The interventions applied here are read from the stored
/// validation output, never from the request, so every test that tampers with
/// the request is asking "can a compromised client widen what was approved?"
public class PlatformCopilotTests
{
    private readonly Guid _tenantId = Guid.NewGuid();
    private readonly Guid _ownerId = Guid.NewGuid();

    private sealed record Rig(AppDbContext Db, PlatformCopilotService Copilot, EntitlementService Entitlements);

    private async Task<Rig> NewAsync()
    {
        var db = TestHelpers.NewInMemoryDb();
        await PlatformPlanCatalog.SyncAsync(db);
        db.Tenants.Add(new Tenant { Id = _tenantId, Name = "Blue Whale Tours", BusinessType = "Tourism", IsActive = true });
        await db.SaveChangesAsync();

        var entitlements = new EntitlementService(db, new MemoryCache(new MemoryCacheOptions()),
            NullLogger<EntitlementService>.Instance);

        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["AgentService:BaseUrl"] = "http://agent.invalid",
            ["AgentService:InternalToken"] = "test-token",
        }).Build();

        var copilot = new PlatformCopilotService(
            new HttpClient(), db, config, entitlements, NullLogger<PlatformCopilotService>.Instance);

        return new Rig(db, copilot, entitlements);
    }

    private async Task<PlatformSubscription> OnPaidPlanAsync(AppDbContext db, EntitlementService entitlements,
        string planCode = PlatformPlanCodes.Pro, string status = PlatformSubscriptionStatuses.PastDue)
    {
        var plan = db.PlatformPlans.First(p => p.Code == planCode);
        var subscription = await entitlements.EnsureSubscriptionAsync(_tenantId);
        subscription.PlanId = plan.Id;
        subscription.PlanCode = plan.Code;
        subscription.Tier = plan.Tier;
        subscription.Status = status;
        subscription.Amount = 14900m;
        subscription.CurrentPeriodEnd = DateTime.UtcNow.AddDays(-2);
        subscription.GraceEndsAt = DateTime.UtcNow.AddDays(12);
        await db.SaveChangesAsync();
        entitlements.Invalidate(_tenantId);
        return subscription;
    }

    /// A stored run, exactly as the agent service's trace would have been
    /// persisted, with `accepted` holding the validated interventions.
    private async Task<PlatformAgentWorkflow> StoredRunAsync(AppDbContext db, params object[] accepted)
    {
        var workflow = new PlatformAgentWorkflow
        {
            TraceId = Guid.NewGuid().ToString("N"),
            Objective = "Reduce churn risk this month",
            Status = PlatformWorkflowStatuses.AwaitingApproval,
            ValidationJson = JsonSerializer.Serialize(new
            {
                is_allowed = true,
                requires_human_approval = true,
                accepted,
                total_estimated_cost = 14900.0,
            }),
            ModelDriven = true,
        };
        db.PlatformAgentWorkflows.Add(workflow);
        await db.SaveChangesAsync();
        return workflow;
    }

    private object Extend(int days = 30) => new
    {
        tenant_id = _tenantId.ToString(),
        tenant_name = "Blue Whale Tours",
        kind = "extend_term",
        extend_days = days,
        rationale = "Active business, payment slipped",
    };

    private object Comp(string plan = "pro", int months = 3) => new
    {
        tenant_id = _tenantId.ToString(),
        tenant_name = "Blue Whale Tours",
        kind = "comp_plan",
        comp_plan_code = plan,
        comp_months = months,
        rationale = "Outage on our side",
    };

    // ── The happy paths ──────────────────────────────────────────────────

    [Fact]
    public async Task Approving_an_extension_pushes_the_term_out_and_clears_past_due()
    {
        var rig = await NewAsync();
        var subscription = await OnPaidPlanAsync(rig.Db, rig.Entitlements);
        var before = subscription.CurrentPeriodEnd!.Value;
        var workflow = await StoredRunAsync(rig.Db, Extend(30));

        var result = await rig.Copilot.ApplyApprovedAsync(
            workflow.Id, _ownerId, "owner@unify.lk", Array.Empty<string>(), "approved");

        Assert.True(result.Success);
        Assert.Equal(PlatformWorkflowStatuses.Applied, result.Value!.Status);

        var after = await rig.Db.PlatformSubscriptions.FirstAsync(s => s.TenantId == _tenantId);
        Assert.True(after.CurrentPeriodEnd > before);
        Assert.Equal(PlatformSubscriptionStatuses.Active, after.Status);
        Assert.Null(after.GraceEndsAt);
    }

    [Fact]
    public async Task Approving_a_comp_marks_it_complimentary_and_earns_nothing()
    {
        var rig = await NewAsync();
        await OnPaidPlanAsync(rig.Db, rig.Entitlements);
        var workflow = await StoredRunAsync(rig.Db, Comp("pro", 3));

        await rig.Copilot.ApplyApprovedAsync(workflow.Id, _ownerId, "owner@unify.lk", Array.Empty<string>(), null);

        var after = await rig.Db.PlatformSubscriptions.FirstAsync(s => s.TenantId == _tenantId);
        Assert.True(after.IsComplimentary);
        Assert.Equal(0m, after.Amount);
        Assert.Contains("copilot", after.ComplimentaryReason!, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Every_applied_intervention_is_written_to_the_subscription_history()
    {
        var rig = await NewAsync();
        await OnPaidPlanAsync(rig.Db, rig.Entitlements);
        var workflow = await StoredRunAsync(rig.Db, Extend(14));

        await rig.Copilot.ApplyApprovedAsync(workflow.Id, _ownerId, "owner@unify.lk", Array.Empty<string>(), null);

        var evt = await rig.Db.PlatformSubscriptionEvents.FirstAsync(e => e.EventType == "extend");
        Assert.Equal("owner@unify.lk", evt.ActorEmail);
        Assert.Contains("copilot", evt.Detail!);
    }

    // ── What a tampered request cannot do ────────────────────────────────

    [Fact]
    public async Task The_request_can_narrow_the_approved_set_but_never_widen_it()
    {
        var rig = await NewAsync();
        await OnPaidPlanAsync(rig.Db, rig.Entitlements);
        var workflow = await StoredRunAsync(rig.Db, Extend(30));

        // A business that was never in this run at all.
        var stranger = Guid.NewGuid();
        rig.Db.Tenants.Add(new Tenant { Id = stranger, Name = "Someone Else", BusinessType = "Clinic", IsActive = true });
        await rig.Db.SaveChangesAsync();

        var result = await rig.Copilot.ApplyApprovedAsync(
            workflow.Id, _ownerId, "owner@unify.lk", new[] { stranger.ToString() }, null);

        Assert.False(result.Success);
        Assert.Contains("none of the chosen businesses", result.Error!, StringComparison.OrdinalIgnoreCase);
        Assert.False(await rig.Db.PlatformSubscriptions.AnyAsync(s => s.TenantId == stranger));
    }

    [Fact]
    public async Task Approving_a_subset_leaves_the_others_untouched()
    {
        var rig = await NewAsync();
        await OnPaidPlanAsync(rig.Db, rig.Entitlements);

        var otherTenant = Guid.NewGuid();
        rig.Db.Tenants.Add(new Tenant { Id = otherTenant, Name = "Second", BusinessType = "Gym", IsActive = true });
        await rig.Db.SaveChangesAsync();
        var otherSub = await rig.Entitlements.EnsureSubscriptionAsync(otherTenant);
        var plan = rig.Db.PlatformPlans.First(p => p.Code == PlatformPlanCodes.Grow);
        otherSub.PlanId = plan.Id; otherSub.PlanCode = plan.Code; otherSub.Tier = plan.Tier;
        otherSub.Amount = 5900m; otherSub.CurrentPeriodEnd = DateTime.UtcNow.AddDays(5);
        await rig.Db.SaveChangesAsync();

        var workflow = await StoredRunAsync(rig.Db, Extend(30), new
        {
            tenant_id = otherTenant.ToString(), tenant_name = "Second", kind = "comp_plan",
            comp_plan_code = "grow", comp_months = 6, rationale = "r",
        });

        await rig.Copilot.ApplyApprovedAsync(
            workflow.Id, _ownerId, "owner@unify.lk", new[] { _tenantId.ToString() }, null);

        var untouched = await rig.Db.PlatformSubscriptions.FirstAsync(s => s.TenantId == otherTenant);
        Assert.False(untouched.IsComplimentary);
        Assert.Equal(5900m, untouched.Amount);
    }

    /// The request carries *which* businesses, never *what to do* to them.
    /// So there is no field a caller could set to turn a cheap intervention
    /// into an expensive one.
    [Fact]
    public async Task The_intervention_comes_from_storage_not_from_the_caller()
    {
        var rig = await NewAsync();
        await OnPaidPlanAsync(rig.Db, rig.Entitlements);
        var workflow = await StoredRunAsync(rig.Db, Extend(30));

        await rig.Copilot.ApplyApprovedAsync(
            workflow.Id, _ownerId, "owner@unify.lk", new[] { _tenantId.ToString() }, null);

        var after = await rig.Db.PlatformSubscriptions.FirstAsync(s => s.TenantId == _tenantId);
        // An extension was stored, so an extension is what happened - the
        // subscription is still paid-for, not comped.
        Assert.False(after.IsComplimentary);
        Assert.Equal(14900m, after.Amount);
    }

    // ── Defence in depth: bad stored data ────────────────────────────────

    [Fact]
    public async Task An_over_long_extension_in_storage_is_still_clamped_at_execution()
    {
        var rig = await NewAsync();
        var subscription = await OnPaidPlanAsync(rig.Db, rig.Entitlements);
        var basis = DateTime.UtcNow;
        var workflow = await StoredRunAsync(rig.Db, Extend(36500));

        await rig.Copilot.ApplyApprovedAsync(workflow.Id, _ownerId, "owner@unify.lk", Array.Empty<string>(), null);

        var after = await rig.Db.PlatformSubscriptions.FirstAsync(s => s.TenantId == _tenantId);
        // 90 days is the ceiling, so a hundred-year extension lands inside
        // the year even though the stored value asked for a century.
        Assert.True(after.CurrentPeriodEnd < basis.AddDays(91));
    }

    [Fact]
    public async Task A_comp_onto_an_unknown_plan_fails_without_touching_the_subscription()
    {
        var rig = await NewAsync();
        await OnPaidPlanAsync(rig.Db, rig.Entitlements);
        var workflow = await StoredRunAsync(rig.Db, Comp("enterprise-unlimited", 12));

        var result = await rig.Copilot.ApplyApprovedAsync(workflow.Id, _ownerId, "owner@unify.lk", Array.Empty<string>(), null);

        Assert.Equal(PlatformWorkflowStatuses.Failed, result.Value!.Status);
        var after = await rig.Db.PlatformSubscriptions.FirstAsync(s => s.TenantId == _tenantId);
        Assert.False(after.IsComplimentary);
    }

    [Fact]
    public async Task One_failing_intervention_does_not_stop_the_others()
    {
        var rig = await NewAsync();
        await OnPaidPlanAsync(rig.Db, rig.Entitlements);
        var ghost = Guid.NewGuid();  // in the run, but has no subscription

        var workflow = await StoredRunAsync(rig.Db,
            new { tenant_id = ghost.ToString(), tenant_name = "Ghost", kind = "extend_term", extend_days = 10, rationale = "r" },
            Extend(30));

        var result = await rig.Copilot.ApplyApprovedAsync(workflow.Id, _ownerId, "owner@unify.lk", Array.Empty<string>(), null);

        Assert.Equal(PlatformWorkflowStatuses.PartiallyApplied, result.Value!.Status);
        var after = await rig.Db.PlatformSubscriptions.FirstAsync(s => s.TenantId == _tenantId);
        Assert.Equal(PlatformSubscriptionStatuses.Active, after.Status);

        // The failure is recorded per intervention, not swallowed.
        Assert.Contains("Ghost", result.Value.OutcomeJson!);
    }

    [Fact]
    public async Task Unreadable_validation_output_applies_nothing()
    {
        var rig = await NewAsync();
        await OnPaidPlanAsync(rig.Db, rig.Entitlements);
        var workflow = new PlatformAgentWorkflow
        {
            Objective = "x",
            Status = PlatformWorkflowStatuses.AwaitingApproval,
            ValidationJson = "{ not json at all",
        };
        rig.Db.PlatformAgentWorkflows.Add(workflow);
        await rig.Db.SaveChangesAsync();

        var result = await rig.Copilot.ApplyApprovedAsync(workflow.Id, _ownerId, "owner@unify.lk", Array.Empty<string>(), null);

        Assert.False(result.Success);
        Assert.Contains("nothing that passed validation", result.Error!);
    }

    // ── Lifecycle ────────────────────────────────────────────────────────

    [Fact]
    public async Task A_run_can_only_be_decided_once()
    {
        var rig = await NewAsync();
        await OnPaidPlanAsync(rig.Db, rig.Entitlements);
        var workflow = await StoredRunAsync(rig.Db, Extend(30));

        await rig.Copilot.ApplyApprovedAsync(workflow.Id, _ownerId, "owner@unify.lk", Array.Empty<string>(), null);
        var second = await rig.Copilot.ApplyApprovedAsync(workflow.Id, _ownerId, "owner@unify.lk", Array.Empty<string>(), null);

        Assert.False(second.Success);
        Assert.Contains("not awaiting approval", second.Error!);
    }

    [Fact]
    public async Task Rejecting_records_the_decision_and_changes_no_subscription()
    {
        var rig = await NewAsync();
        var subscription = await OnPaidPlanAsync(rig.Db, rig.Entitlements);
        var before = subscription.CurrentPeriodEnd;
        var workflow = await StoredRunAsync(rig.Db, Comp("prime", 12));

        var result = await rig.Copilot.RecordDecisionAsync(
            workflow.Id, _ownerId, "owner@unify.lk", "Rejected", "Too expensive");

        Assert.True(result.Success);
        Assert.Equal(PlatformWorkflowStatuses.Rejected, result.Value!.Status);
        Assert.Equal("Too expensive", result.Value.DecisionReason);

        var after = await rig.Db.PlatformSubscriptions.FirstAsync(s => s.TenantId == _tenantId);
        Assert.False(after.IsComplimentary);
        Assert.Equal(before, after.CurrentPeriodEnd);
    }

    [Fact]
    public async Task A_rejected_run_cannot_then_be_applied()
    {
        var rig = await NewAsync();
        await OnPaidPlanAsync(rig.Db, rig.Entitlements);
        var workflow = await StoredRunAsync(rig.Db, Extend(30));

        await rig.Copilot.RecordDecisionAsync(workflow.Id, _ownerId, "owner@unify.lk", "Rejected", null);
        var applied = await rig.Copilot.ApplyApprovedAsync(workflow.Id, _ownerId, "owner@unify.lk", Array.Empty<string>(), null);

        Assert.False(applied.Success);
    }

    [Fact]
    public async Task History_returns_the_newest_runs_first()
    {
        var rig = await NewAsync();
        for (var i = 0; i < 3; i++)
        {
            rig.Db.PlatformAgentWorkflows.Add(new PlatformAgentWorkflow
            {
                Objective = $"run {i}",
                Status = PlatformWorkflowStatuses.NothingToDo,
                CreatedAt = DateTime.UtcNow.AddMinutes(i),
            });
        }
        await rig.Db.SaveChangesAsync();

        var history = await rig.Copilot.HistoryAsync();

        Assert.Equal(3, history.Count);
        Assert.Equal("run 2", history[0].Objective);
    }
}
