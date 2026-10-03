using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;

namespace SmeBackend.Services.Billing;

public interface IBillingAgentService
{
    Task<BillingResult<BillingAnalysisResponse>> AnalyzeAsync(BillingActor actor, BillingAnalysisRequest request, CancellationToken ct = default);

    /// Billing Copilot: plan an analysis from a plain-English objective, run
    /// it, then read the pattern back over the findings. `callerToken` is the
    /// manager's own JWT, forwarded to the agent service for symmetry with the
    /// other two workflows.
    Task<BillingResult<BillingPlannedAnalysisResponse>> PlanAnalysisAsync(
        BillingActor actor, PlanAnalysisRequest request, string callerToken, CancellationToken ct = default);
    InvoiceValidationResult ValidateInvoiceDraft(CreateInvoiceRequest draft, ThresholdConfig? thresholds = null);
    Task<IReadOnlyList<BillingWorkflowResponse>> GetWorkflowsAsync(Guid tenantId, string? kind, string? status, int take, CancellationToken ct = default);
    Task<BillingResult<BillingWorkflowResponse>> GetWorkflowAsync(Guid tenantId, Guid id, CancellationToken ct = default);
}

public sealed class BillingAgentService : IBillingAgentService
{
    /// Recommendations that become approval requests. The rest (chasing a
    /// payment, eyeballing a price) stay advisory in the analysis output.
    private static readonly HashSet<string> ActionableTypes = new()
    {
        BillingActionTypes.AdjustInvoice,
        BillingActionTypes.ApproveInsuranceClaim,
        BillingActionTypes.RejectInsuranceClaim,
        BillingActionTypes.ReviewInvoice,
    };

    private const int MaxInvoices = 5000;

    private readonly AppDbContext _db;
    private readonly IBillingApprovalService _approvals;
    private readonly IBillingPlannerService? _planner;
    private readonly BillingDomainAnalysisAgent _agent = new();

    public BillingAgentService(AppDbContext db, IBillingApprovalService approvals, IBillingPlannerService? planner = null)
    {
        _db = db;
        _approvals = approvals;
        // Optional: the direct /analyze path is the component's core and must
        // keep working with no agent service running at all. Only the copilot
        // needs it.
        _planner = planner;
    }

    public async Task<BillingResult<BillingAnalysisResponse>> AnalyzeAsync(BillingActor actor, BillingAnalysisRequest request, CancellationToken ct = default)
    {
        if (request.TenantId is { } requested && requested != actor.TenantId)
            return BillingResult<BillingAnalysisResponse>.Forbidden("The agent can only analyse your own business.");

        var type = request.AnalysisType?.Trim().ToLowerInvariant() ?? "";
        if (!BillingAnalysisTypes.All.Contains(type))
            return BillingResult<BillingAnalysisResponse>.BadRequest($"AnalysisType must be one of: {string.Join(", ", BillingAnalysisTypes.All)}.");
        if (type == BillingAnalysisTypes.Commission && request.DealAmount is not > 0)
            return BillingResult<BillingAnalysisResponse>.BadRequest("A commission analysis needs a DealAmount above 0.");

        var now = DateTime.UtcNow;
        var to = request.DataRange?.To is { } t ? Utc(t) : now;
        var from = request.DataRange?.From is { } f ? Utc(f) : to.AddDays(-30);
        if (from >= to) return BillingResult<BillingAnalysisResponse>.BadRequest("DataRange.From must be before DataRange.To.");
        if ((to - from).TotalDays > 366) return BillingResult<BillingAnalysisResponse>.BadRequest("DataRange can span at most one year.");

        var thresholds = request.Thresholds ?? ThresholdConfig.Default;
        var range = new DateRangeDto(from, to);
        var snapshot = await LoadSnapshotAsync(actor.TenantId, range, type, ct);

        var result = _agent.Run(type, range, snapshot, thresholds, request.DealAmount);

        // Observability: the run itself, then one approval request per
        // actionable recommendation (skipping any already pending).
        var plan = new BillingWorkflowPlan
        {
            Kind = "analysis",
            AnalysisType = type,
            DataRange = range,
            Thresholds = thresholds,
            Tools = BillingDomainAnalysisAgent.PlanFor(type).ToList(),
            AnomalyCount = result.Anomalies.Count,
            ConfidenceScore = result.ConfidenceScore,
            Source = "agent",
            RequestedBy = actor.UserId,
        };

        var workflow = new AgentWorkflow
        {
            TenantId = actor.TenantId,
            Objective = $"{BillingWorkflowPlan.ObjectivePrefix}Domain analysis ({type}) {from:dd MMM} - {to:dd MMM yyyy}",
            PlanJson = plan.Serialize(),
            Status = "Completed",
            ApprovalStatus = "NotRequired",
            CurrentStep = result.ToolCalls.Count,
            ToolResultsJson = JsonSerializer.Serialize(new
            {
                toolCalls = result.ToolCalls,
                anomalies = result.Anomalies,
                insights = result.Insights,
                recommendedActions = result.RecommendedActions,
            }, BillingWorkflowPlan.Json),
            ValidationResults = JsonSerializer.Serialize(
                result.Anomalies.GroupBy(a => a.Type).ToDictionary(g => g.Key, g => g.Count()), BillingWorkflowPlan.Json),
            FinalOutcome = $"{result.Anomalies.Count} anomalies, {result.Insights.Count} insights, {result.RecommendedActions.Count} recommended actions (confidence {result.ConfidenceScore:0.00}).",
            CompletedAt = DateTime.UtcNow,
            RequestedByUserId = actor.UserId,
        };
        _db.AgentWorkflows.Add(workflow);
        await _db.SaveChangesAsync(ct);

        var approvalIds = new List<Guid>();
        foreach (var action in result.RecommendedActions.Where(a => ActionableTypes.Contains(a.ActionType) && a.EntityId.HasValue))
        {
            var existing = await _approvals.FindPendingApprovalAsync(actor.TenantId, action.ActionType, action.EntityId!.Value, ct);
            if (existing is { } id)
            {
                approvalIds.Add(id);
                continue;
            }

            var wf = await _approvals.RequestApprovalAsync(actor.TenantId, action.ActionType, action.EntityType, action.EntityId,
                action.Description, action.Amount, action.RequiresApproval,
                action.ApprovalReason ?? $"Recommended by the billing agent (analysis {workflow.Id.ToString()[..8]}).",
                action.Parameters, "agent", actor.UserId, ct);
            approvalIds.Add(wf.Id);
        }

        return BillingResult<BillingAnalysisResponse>.Ok(new BillingAnalysisResponse(workflow.Id, type, range,
            result.Anomalies, result.Insights, result.RecommendedActions, result.ConfidenceScore, result.ToolCalls, approvalIds));
    }

    public async Task<BillingResult<BillingPlannedAnalysisResponse>> PlanAnalysisAsync(
        BillingActor actor, PlanAnalysisRequest request, string callerToken, CancellationToken ct = default)
    {
        if (_planner is null)
            return BillingResult<BillingPlannedAnalysisResponse>.Unavailable("The billing copilot is not configured on this server.");
        if (request.TenantId is { } requested && requested != actor.TenantId)
            return BillingResult<BillingPlannedAnalysisResponse>.Forbidden("The agent can only analyse your own business.");

        var objective = (request.Objective ?? "").Trim();
        if (objective.Length is < 3 or > 500)
            return BillingResult<BillingPlannedAnalysisResponse>.BadRequest("Describe what to look at in 3 to 500 characters.");

        var configured = request.Thresholds ?? ThresholdConfig.Default;
        var businessType = await _db.Tenants.AsNoTracking()
            .Where(t => t.Id == actor.TenantId).Select(t => t.BusinessType).FirstOrDefaultAsync(ct) ?? "General";
        var currency = await _db.Invoices.AsNoTracking()
            .Where(i => i.TenantId == actor.TenantId).OrderByDescending(i => i.CreatedAt)
            .Select(i => i.Currency).FirstOrDefaultAsync(ct) ?? "USD";

        var planned = await _planner.PlanAsync(new BillingPlanServiceRequest(
            objective, actor.TenantId.ToString(), businessType, currency,
            BillingThresholdsDto.From(configured), callerToken), ct);

        if (!planned.Success)
        {
            // A safe, recorded failure: the attempt stays in the audit trail
            // with its reason rather than disappearing with the request.
            await RecordFailedPlanAsync(actor, objective, planned.ErrorMessage, ct);
            return BillingResult<BillingPlannedAnalysisResponse>.Unavailable(planned.ErrorMessage!);
        }

        var raw = planned.Trace!.Planner!;
        var notes = new List<string>(planned.Trace.Warnings ?? new List<string>());

        // A commission split needs a deal amount, and the planner can only
        // read one out of the objective when the manager wrote one down.
        if (raw.Intent?.AnalysisType == BillingAnalysisTypes.Commission && raw.Intent.DealAmount is not > 0m)
        {
            notes.Add("The objective asked about commission but did not say what the deal is worth, so a full review was run instead.");
            raw = raw with { Intent = raw.Intent with { AnalysisType = BillingAnalysisTypes.Full } };
        }

        // Defence in depth: the Python planner already clamped this, and it is
        // clamped again here because that is a separate process over HTTP.
        var (planner, guardNotes) = BillingPlanGuard.Clamp(raw, configured);
        notes.AddRange(guardNotes);

        var effective = BillingPlanGuard.Effective(configured, planner);
        var range = BillingPlanGuard.RangeFor(planner, DateTime.UtcNow);

        var analysis = await AnalyzeAsync(actor, new BillingAnalysisRequest(
            planner.Intent.AnalysisType, range, actor.TenantId, effective, planner.Intent.DealAmount), ct);
        if (!analysis.Success || analysis.Value is null)
            return new BillingResult<BillingPlannedAnalysisResponse>(false, analysis.StatusCode, analysis.Error, null);

        var result = analysis.Value;

        // The output edge. Advisory: a narrator that is down must never
        // invalidate findings that are already computed and stored.
        BillingNarrativeDto? narrative = null;
        string? narrativeError = null;
        var narrated = await _planner.NarrateAsync(new BillingNarrateServiceRequest(
            objective, result.AnalysisType, actor.TenantId.ToString(), currency,
            result.Anomalies.Select(a => new AnomalyDigestDto(a.Id, a.Type, a.Severity, a.EntityLabel, a.Description, a.Amount)).ToList(),
            result.Insights.Select(i => $"{i.Title}: {i.Detail}").ToList(),
            result.RecommendedActions.Select(a => a.Description).ToList(),
            result.ConfidenceScore, callerToken), ct);
        if (narrated.Success) narrative = narrated.Narrative;
        else narrativeError = narrated.ErrorMessage;

        await AttachPlannerToWorkflowAsync(result.WorkflowId, objective, planner, notes, narrative, ct);

        return BillingResult<BillingPlannedAnalysisResponse>.Ok(new BillingPlannedAnalysisResponse(
            objective, planner, notes, effective, result, narrative, narrativeError));
    }

    /// Fold the copilot's plan into the analysis row AnalyzeAsync already
    /// wrote, so one workflow records both what was asked for and what ran.
    private async Task AttachPlannerToWorkflowAsync(Guid workflowId, string objective, BillingPlannerOutputDto planner,
        List<string> notes, BillingNarrativeDto? narrative, CancellationToken ct)
    {
        var row = await _db.AgentWorkflows.FirstOrDefaultAsync(w => w.Id == workflowId, ct);
        if (row is null) return;
        var plan = BillingWorkflowPlan.TryParse(row.PlanJson);
        if (plan is null) return;

        plan.PlannerObjective = objective;
        plan.Planner = planner;
        plan.PlannerWarnings = notes.Count > 0 ? notes : null;
        plan.Narrative = narrative;
        row.PlanJson = plan.Serialize();
        row.Objective = $"{BillingWorkflowPlan.ObjectivePrefix}Copilot: {Shorten(objective, 120)}";
        if (narrative is { Headline.Length: > 0 })
            row.FinalOutcome = $"{narrative.Headline} ({row.FinalOutcome})";
        await _db.SaveChangesAsync(ct);
    }

    private async Task RecordFailedPlanAsync(BillingActor actor, string objective, string? error, CancellationToken ct)
    {
        var plan = new BillingWorkflowPlan
        {
            Kind = "analysis",
            Source = "agent",
            RequestedBy = actor.UserId,
            PlannerObjective = objective,
        };
        _db.AgentWorkflows.Add(new AgentWorkflow
        {
            TenantId = actor.TenantId,
            Objective = $"{BillingWorkflowPlan.ObjectivePrefix}Copilot: {Shorten(objective, 120)}",
            PlanJson = plan.Serialize(),
            Status = "Failed",
            ApprovalStatus = "NotRequired",
            ErrorLog = error,
            FinalOutcome = "The billing copilot could not plan this analysis.",
            CompletedAt = DateTime.UtcNow,
            RequestedByUserId = actor.UserId,
        });
        await _db.SaveChangesAsync(ct);
    }

    private static string Shorten(string value, int max) => value.Length <= max ? value : value[..max] + "…";

    public InvoiceValidationResult ValidateInvoiceDraft(CreateInvoiceRequest draft, ThresholdConfig? thresholds = null)
    {
        var lines = (draft.Items ?? new List<CreateInvoiceItemRequest>())
            .Select(i => new BillingRules.DraftLine(i.Quantity, BillingRules.Round(i.UnitPrice))).ToList();
        var subtotal = lines.Sum(l => BillingRules.Round(l.Quantity * l.UnitPrice));
        var discount = draft.DiscountPercent is { } dp ? BillingRules.Round(subtotal * dp / 100m) : draft.Discount;
        var tax = draft.TaxRatePercent is { } tr ? BillingRules.Round(Math.Max(0, subtotal - discount) * tr / 100m) : draft.Tax;
        return BillingRules.ValidateInvoice(lines, discount, tax, thresholds);
    }

    public async Task<IReadOnlyList<BillingWorkflowResponse>> GetWorkflowsAsync(Guid tenantId, string? kind, string? status, int take, CancellationToken ct = default)
    {
        var q = _db.AgentWorkflows.AsNoTracking()
            .Where(w => w.TenantId == tenantId && w.Objective.StartsWith(BillingWorkflowPlan.ObjectivePrefix));
        if (!string.IsNullOrWhiteSpace(status))
        {
            var s = status.Trim();
            q = s.Equals("Pending", StringComparison.OrdinalIgnoreCase)
                ? q.Where(w => w.ApprovalStatus == "Pending")
                : q.Where(w => w.Status == s || w.ApprovalStatus == s);
        }

        var rows = await q.OrderByDescending(w => w.CreatedAt).Take(Math.Clamp(take, 1, 500)).ToListAsync(ct);
        var mapped = rows.Select(Map).Where(r => r is not null).Select(r => r!);
        if (!string.IsNullOrWhiteSpace(kind)) mapped = mapped.Where(r => r.Kind.Equals(kind.Trim(), StringComparison.OrdinalIgnoreCase));
        return mapped.ToList();
    }

    public async Task<BillingResult<BillingWorkflowResponse>> GetWorkflowAsync(Guid tenantId, Guid id, CancellationToken ct = default)
    {
        var row = await _db.AgentWorkflows.AsNoTracking().FirstOrDefaultAsync(w => w.Id == id && w.TenantId == tenantId, ct);
        var mapped = row is null ? null : Map(row);
        return mapped is null
            ? BillingResult<BillingWorkflowResponse>.NotFound("Billing workflow not found.")
            : BillingResult<BillingWorkflowResponse>.Ok(mapped);
    }

    private static BillingWorkflowResponse? Map(AgentWorkflow w)
    {
        var plan = BillingWorkflowPlan.TryParse(w.PlanJson);
        if (plan is null) return null;
        return new BillingWorkflowResponse(
            w.Id,
            w.Objective.StartsWith(BillingWorkflowPlan.ObjectivePrefix) ? w.Objective[BillingWorkflowPlan.ObjectivePrefix.Length..] : w.Objective,
            plan.Kind,
            plan.ActionType,
            w.Status,
            w.ApprovalStatus,
            plan.Amount,
            plan.EntityType,
            plan.EntityId,
            plan.Reason,
            w.ApprovedBy,
            w.ApprovedAt,
            w.CreatedAt,
            w.CompletedAt,
            plan.AnomalyCount,
            plan.ConfidenceScore,
            w.FinalOutcome,
            w.ErrorLog,
            w.PlanJson,
            w.ToolResultsJson,
            w.ValidationResults);
    }

    private async Task<BillingSnapshot> LoadSnapshotAsync(Guid tenantId, DateRangeDto range, string type, CancellationToken ct)
    {
        var needsInvoices = type is BillingAnalysisTypes.Full or BillingAnalysisTypes.Anomalies or BillingAnalysisTypes.Revenue or BillingAnalysisTypes.Pricing;
        var needsPrevious = type is BillingAnalysisTypes.Full or BillingAnalysisTypes.Revenue;
        var needsClaims = type is BillingAnalysisTypes.Full or BillingAnalysisTypes.Insurance;

        var snapshot = new BillingSnapshot();

        if (needsInvoices)
            snapshot.Invoices.AddRange(await LoadInvoicesAsync(tenantId, range.From, range.To, ct));

        if (needsPrevious)
        {
            var length = range.To - range.From;
            snapshot.PreviousInvoices.AddRange(await LoadInvoicesAsync(tenantId, range.From - length, range.From, ct));
        }

        if (needsClaims)
        {
            var claims = await _db.InsuranceClaims.AsNoTracking()
                .Include(c => c.Invoice)
                .Where(c => c.Invoice != null && c.Invoice.TenantId == tenantId &&
                            (c.Status == "Submitted" || c.Status == "UnderReview" || c.Status == "Pending"))
                .ToListAsync(ct);

            var invoiceIds = claims.Select(c => c.InvoiceId).Distinct().ToList();
            var claimTotals = await _db.InsuranceClaims.AsNoTracking()
                .Where(c => invoiceIds.Contains(c.InvoiceId) && c.Status != "Rejected")
                .Select(c => new { c.Id, c.InvoiceId, c.ClaimAmount })
                .ToListAsync(ct);
            var customerIds = claims.Select(c => c.Invoice!.CustomerId).Distinct().ToList();
            var profiles = await _db.Users.IgnoreQueryFilters().AsNoTracking()
                .Where(u => u.TenantId == tenantId && customerIds.Contains(u.Id))
                .ToDictionaryAsync(u => u.Id, u => (u.InsuranceProvider, u.InsuranceNumber), ct);

            foreach (var c in claims)
            {
                profiles.TryGetValue(c.Invoice!.CustomerId, out var profile);
                snapshot.Claims.Add(new ClaimFact(c.Id, c.Invoice.Id, c.Invoice.InvoiceNumber, c.Status, c.Provider, c.PolicyNumber,
                    c.ClaimAmount, c.Invoice.FinalAmount, c.Invoice.Status,
                    claimTotals.Where(o => o.InvoiceId == c.InvoiceId && o.Id != c.Id).Sum(o => o.ClaimAmount),
                    profile.InsuranceProvider, profile.InsuranceNumber));
            }
        }

        if (type is BillingAnalysisTypes.Commission)
        {
            var now = DateTime.UtcNow;
            var rules = await _db.CommissionRules.AsNoTracking()
                .Where(r => r.TenantId == tenantId && r.IsActive &&
                            (r.EffectiveFrom == null || r.EffectiveFrom <= now) && (r.EffectiveTo == null || r.EffectiveTo >= now))
                .ToListAsync(ct);
            snapshot.CommissionRules.AddRange(rules.Select(r =>
                new CommissionRuleFact(r.Id, r.Name, r.Role, r.RuleType, r.Rate, r.FixedAmount, r.MinAmount, r.MaxAmount)));
        }

        return snapshot;
    }

    private async Task<List<InvoiceFact>> LoadInvoicesAsync(Guid tenantId, DateTime from, DateTime to, CancellationToken ct)
    {
        var invoices = await _db.Invoices.AsNoTracking()
            .Include(i => i.Items)
            .Include(i => i.Payments)
            .Where(i => i.TenantId == tenantId && i.CreatedAt >= from && i.CreatedAt < to)
            .OrderByDescending(i => i.CreatedAt)
            .Take(MaxInvoices)
            .ToListAsync(ct);

        return invoices.Select(i => new InvoiceFact(i.Id, i.InvoiceNumber, i.CustomerId, i.Status, i.Currency, i.TotalAmount,
            i.Discount, i.Tax, i.FinalAmount, i.CreatedAt, i.DueDate,
            i.Items.Select(l => new InvoiceLineFact(l.Description, l.Category, l.Quantity, l.UnitPrice, l.Amount)).ToList(),
            i.Payments.Select(p => new PaymentFact(p.Amount, p.Method, p.Status, p.PaidAt)).ToList())).ToList();
    }

    private static DateTime Utc(DateTime value) => value.Kind switch
    {
        DateTimeKind.Utc => value,
        DateTimeKind.Local => value.ToUniversalTime(),
        _ => DateTime.SpecifyKind(value, DateTimeKind.Utc),
    };
}
