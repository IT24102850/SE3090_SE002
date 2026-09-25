using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Services.Billing;

/// What a billing AgentWorkflow row's PlanJson holds. Every billing row is
/// tagged Agent = "BillingDomainAnalysis" so the monitor can tell them from
/// booking-planner and inventory workflows sharing the same table.
public sealed class BillingWorkflowPlan
{
    public const string AgentName = "BillingDomainAnalysis";
    public const string ObjectivePrefix = "[Billing] ";

    public string Agent { get; set; } = AgentName;
    /// analysis | approval
    public string Kind { get; set; } = "approval";
    public string? ActionType { get; set; }
    public string? EntityType { get; set; }
    public Guid? EntityId { get; set; }
    public decimal? Amount { get; set; }
    public bool RequiresAdmin { get; set; }
    public string? Reason { get; set; }
    /// user | agent
    public string Source { get; set; } = "user";
    public Guid? RequestedBy { get; set; }
    public Dictionary<string, JsonElement> Parameters { get; set; } = new();

    // Analysis rows only
    public string? AnalysisType { get; set; }
    public DateRangeDto? DataRange { get; set; }
    public ThresholdConfig? Thresholds { get; set; }
    public List<string>? Tools { get; set; }
    public int AnomalyCount { get; set; }
    public double? ConfidenceScore { get; set; }

    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public string Serialize() => JsonSerializer.Serialize(this, Json);

    public static BillingWorkflowPlan? TryParse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            var plan = JsonSerializer.Deserialize<BillingWorkflowPlan>(json, Json);
            return plan?.Agent == AgentName ? plan : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public static Dictionary<string, JsonElement> ToParameters(IReadOnlyDictionary<string, object?> values) =>
        values.ToDictionary(kv => kv.Key, kv => JsonSerializer.SerializeToElement(kv.Value, Json));

    public decimal? GetDecimal(string key) =>
        Parameters.TryGetValue(key, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDecimal() : null;

    public string? GetString(string key) =>
        Parameters.TryGetValue(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
}

public static class BillingActionTypes
{
    public const string AdjustInvoice = "adjust_invoice";
    public const string ApproveInsuranceClaim = "approve_insurance_claim";
    public const string RejectInsuranceClaim = "reject_insurance_claim";
    public const string CancelSubscriptionWithRefund = "cancel_subscription_with_refund";
    public const string ReviewInvoice = "review_invoice";
    public const string ChasePayment = "chase_payment";
    public const string ReviewPricing = "review_pricing";
}

public interface IBillingApprovalService
{
    Task<AgentWorkflow> RequestApprovalAsync(
        Guid tenantId,
        string actionType,
        string entityType,
        Guid? entityId,
        string objective,
        decimal? amount,
        bool requiresAdmin,
        string? reason,
        IReadOnlyDictionary<string, object?> parameters,
        string source,
        Guid? requestedBy,
        CancellationToken ct = default);

    /// An action an Admin took directly (they are the approver): recorded as
    /// an already-approved workflow so the audit trail has no gaps.
    Task<AgentWorkflow> RecordApprovedActionAsync(
        Guid tenantId,
        string actionType,
        string entityType,
        Guid? entityId,
        string objective,
        decimal? amount,
        string? reason,
        IReadOnlyDictionary<string, object?> parameters,
        Guid approvedBy,
        string outcome,
        CancellationToken ct = default);

    Task<(bool Success, int StatusCode, string Message)> ApproveAsync(
        Guid tenantId, Guid workflowId, Guid? userId, string role, CancellationToken ct = default);

    Task<(bool Success, int StatusCode, string Message)> RejectAsync(
        Guid tenantId, Guid workflowId, Guid? userId, string? reason, CancellationToken ct = default);

    Task<Guid?> FindPendingApprovalAsync(Guid tenantId, string actionType, Guid entityId, CancellationToken ct = default);
}

public sealed class BillingApprovalService : IBillingApprovalService
{
    private readonly AppDbContext _db;

    public BillingApprovalService(AppDbContext db) => _db = db;

    public async Task<AgentWorkflow> RequestApprovalAsync(
        Guid tenantId, string actionType, string entityType, Guid? entityId, string objective, decimal? amount,
        bool requiresAdmin, string? reason, IReadOnlyDictionary<string, object?> parameters, string source,
        Guid? requestedBy, CancellationToken ct = default)
    {
        var plan = new BillingWorkflowPlan
        {
            Kind = "approval",
            ActionType = actionType,
            EntityType = entityType,
            EntityId = entityId,
            Amount = amount,
            RequiresAdmin = requiresAdmin,
            Reason = reason,
            Source = source,
            RequestedBy = requestedBy,
            Parameters = BillingWorkflowPlan.ToParameters(parameters),
        };

        var workflow = new AgentWorkflow
        {
            TenantId = tenantId,
            Objective = BillingWorkflowPlan.ObjectivePrefix + objective,
            PlanJson = plan.Serialize(),
            Status = "AwaitingApproval",
            ApprovalStatus = "Pending",
            CurrentStep = 0,
        };
        _db.AgentWorkflows.Add(workflow);

        NotificationHelper.Queue(_db, tenantId, null, "BillingApprovalRequired",
            requiresAdmin ? "Billing approval needed (Admin)" : "Billing approval needed",
            objective + (reason is null ? "" : $" - {reason}"));

        await _db.SaveChangesAsync(ct);
        return workflow;
    }

    public async Task<AgentWorkflow> RecordApprovedActionAsync(
        Guid tenantId, string actionType, string entityType, Guid? entityId, string objective, decimal? amount,
        string? reason, IReadOnlyDictionary<string, object?> parameters, Guid approvedBy, string outcome,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var plan = new BillingWorkflowPlan
        {
            Kind = "approval",
            ActionType = actionType,
            EntityType = entityType,
            EntityId = entityId,
            Amount = amount,
            RequiresAdmin = true,
            Reason = reason,
            Source = "user",
            RequestedBy = approvedBy,
            Parameters = BillingWorkflowPlan.ToParameters(parameters),
        };

        var workflow = new AgentWorkflow
        {
            TenantId = tenantId,
            Objective = BillingWorkflowPlan.ObjectivePrefix + objective,
            PlanJson = plan.Serialize(),
            Status = "Completed",
            ApprovalStatus = "Approved",
            ApprovedBy = approvedBy,
            ApprovedAt = now,
            CompletedAt = now,
            FinalOutcome = outcome,
            CurrentStep = 1,
        };
        _db.AgentWorkflows.Add(workflow);
        await _db.SaveChangesAsync(ct);
        return workflow;
    }

    public async Task<Guid?> FindPendingApprovalAsync(Guid tenantId, string actionType, Guid entityId, CancellationToken ct = default)
    {
        var pending = await _db.AgentWorkflows.AsNoTracking()
            .Where(w => w.TenantId == tenantId && w.ApprovalStatus == "Pending" && w.Objective.StartsWith(BillingWorkflowPlan.ObjectivePrefix))
            .Select(w => new { w.Id, w.PlanJson })
            .ToListAsync(ct);

        foreach (var w in pending)
        {
            var plan = BillingWorkflowPlan.TryParse(w.PlanJson);
            if (plan?.ActionType == actionType && plan.EntityId == entityId) return w.Id;
        }
        return null;
    }

    public async Task<(bool Success, int StatusCode, string Message)> ApproveAsync(
        Guid tenantId, Guid workflowId, Guid? userId, string role, CancellationToken ct = default)
    {
        var workflow = await _db.AgentWorkflows.FirstOrDefaultAsync(w => w.Id == workflowId && w.TenantId == tenantId, ct);
        var plan = BillingWorkflowPlan.TryParse(workflow?.PlanJson);
        if (workflow is null || plan is null || plan.Kind != "approval")
            return (false, 404, "Billing approval request not found.");

        if (workflow.ApprovalStatus != "Pending")
            return (false, 409, $"This request has already been {workflow.ApprovalStatus.ToLowerInvariant()}.");

        if (plan.RequiresAdmin && role != Roles.Admin)
            return (false, 403, "Only an Admin can approve this request - it is above the approval threshold.");

        var (applied, message) = await ApplyAsync(tenantId, plan, ct);
        if (!applied)
        {
            workflow.ErrorLog = message;
            workflow.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync(ct);
            return (false, 422, message);
        }

        var now = DateTime.UtcNow;
        workflow.ApprovalStatus = "Approved";
        workflow.Status = "Completed";
        workflow.ApprovedBy = userId;
        workflow.ApprovedAt = now;
        workflow.CompletedAt = now;
        workflow.CurrentStep = 1;
        workflow.FinalOutcome = message;
        workflow.UpdatedAt = now;
        await _db.SaveChangesAsync(ct);
        return (true, 200, message);
    }

    public async Task<(bool Success, int StatusCode, string Message)> RejectAsync(
        Guid tenantId, Guid workflowId, Guid? userId, string? reason, CancellationToken ct = default)
    {
        var workflow = await _db.AgentWorkflows.FirstOrDefaultAsync(w => w.Id == workflowId && w.TenantId == tenantId, ct);
        var plan = BillingWorkflowPlan.TryParse(workflow?.PlanJson);
        if (workflow is null || plan is null || plan.Kind != "approval")
            return (false, 404, "Billing approval request not found.");

        if (workflow.ApprovalStatus != "Pending")
            return (false, 409, $"This request has already been {workflow.ApprovalStatus.ToLowerInvariant()}.");

        // A rejected cancellation leaves the membership as it was.
        if (plan.ActionType == BillingActionTypes.CancelSubscriptionWithRefund && plan.EntityId.HasValue)
        {
            var sub = await _db.Subscriptions.IgnoreQueryFilters()
                .FirstOrDefaultAsync(s => s.Id == plan.EntityId && s.TenantId == tenantId, ct);
            if (sub is not null && sub.Status == SubscriptionStatuses.PendingCancel)
            {
                sub.Status = plan.GetString("previousStatus") ?? "Active";
                sub.UpdatedAt = DateTime.UtcNow;
            }
        }

        var now = DateTime.UtcNow;
        workflow.ApprovalStatus = "Rejected";
        workflow.Status = "Rejected";
        workflow.ApprovedBy = userId;
        workflow.ApprovedAt = now;
        workflow.CompletedAt = now;
        workflow.ErrorLog = string.IsNullOrWhiteSpace(reason) ? "Rejected without a reason." : reason.Trim();
        workflow.UpdatedAt = now;
        await _db.SaveChangesAsync(ct);
        return (true, 200, "Request rejected.");
    }

    private async Task<(bool Applied, string Message)> ApplyAsync(Guid tenantId, BillingWorkflowPlan plan, CancellationToken ct)
    {
        switch (plan.ActionType)
        {
            case BillingActionTypes.AdjustInvoice:
            {
                var invoice = await _db.Invoices.Include(i => i.Payments)
                    .FirstOrDefaultAsync(i => i.Id == plan.EntityId && i.TenantId == tenantId, ct);
                if (invoice is null) return (false, "The invoice no longer exists.");
                if (invoice.Status == InvoiceStatuses.Cancelled) return (false, "The invoice has been cancelled.");

                var discount = plan.GetDecimal("discount") ?? invoice.Discount;
                var tax = plan.GetDecimal("tax") ?? invoice.Tax;
                var newFinal = Math.Max(0, BillingRules.Round(invoice.TotalAmount - discount + tax));
                var paid = invoice.Payments.Where(p => p.Status == PaymentStatuses.Succeeded).Sum(p => p.Amount);
                if (newFinal < paid)
                    return (false, $"The adjusted total ({newFinal:N2}) would be below what has already been paid ({paid:N2}).");

                var before = invoice.FinalAmount;
                invoice.Discount = BillingRules.Round(discount);
                invoice.Tax = BillingRules.Round(tax);
                invoice.FinalAmount = newFinal;
                invoice.Status = InvoiceStatuses.FromBalance(newFinal, paid, invoice.Status);
                invoice.UpdatedAt = DateTime.UtcNow;
                await _db.SaveChangesAsync(ct);
                return (true, $"{invoice.InvoiceNumber} adjusted: payable {before:N2} -> {newFinal:N2}.");
            }

            case BillingActionTypes.ApproveInsuranceClaim:
            case BillingActionTypes.RejectInsuranceClaim:
            {
                var claim = await _db.InsuranceClaims.Include(c => c.Invoice)
                    .FirstOrDefaultAsync(c => c.Id == plan.EntityId && c.Invoice != null && c.Invoice.TenantId == tenantId, ct);
                if (claim is null) return (false, "The insurance claim no longer exists.");
                if (claim.Status is "Approved" or "Rejected") return (false, $"The claim is already {claim.Status.ToLowerInvariant()}.");

                if (plan.ActionType == BillingActionTypes.ApproveInsuranceClaim)
                {
                    claim.Status = "Approved";
                    claim.ApprovedAt = DateTime.UtcNow;
                    claim.RejectionReason = null;
                }
                else
                {
                    claim.Status = "Rejected";
                    claim.RejectionReason = plan.GetString("reason") ?? plan.Reason;
                }
                claim.ReviewStartedAt ??= DateTime.UtcNow;
                claim.UpdatedAt = DateTime.UtcNow;
                await _db.SaveChangesAsync(ct);
                return (true, $"Claim on {claim.Invoice?.InvoiceNumber} {claim.Status.ToLowerInvariant()}.");
            }

            case BillingActionTypes.CancelSubscriptionWithRefund:
            {
                var sub = await _db.Subscriptions.IgnoreQueryFilters()
                    .FirstOrDefaultAsync(s => s.Id == plan.EntityId && s.TenantId == tenantId, ct);
                if (sub is null) return (false, "The subscription no longer exists.");

                var refund = plan.GetDecimal("refundAmount") ?? 0;
                sub.Status = SubscriptionStatuses.Cancelled;
                sub.AutoRenew = false;
                sub.NextBillingAt = null;
                sub.UpdatedAt = DateTime.UtcNow;

                if (refund > 0)
                {
                    // The refund goes against the latest invoice the member paid.
                    var invoice = await _db.Invoices
                        .Where(i => i.TenantId == tenantId && i.SubscriptionId == sub.Id)
                        .OrderByDescending(i => i.CreatedAt)
                        .FirstOrDefaultAsync(ct);
                    _db.Payments.Add(new Payment
                    {
                        InvoiceId = invoice?.Id,
                        Amount = BillingRules.Round(refund),
                        Method = "Refund",
                        Provider = "Manual",
                        Status = PaymentStatuses.Refunded,
                        TransactionRef = $"REFUND-{sub.Id.ToString("N")[..8].ToUpperInvariant()}",
                        PaidAt = DateTime.UtcNow,
                    });
                }

                NotificationHelper.Queue(_db, tenantId, sub.CustomerId, "SubscriptionCancelled",
                    "Membership cancelled",
                    refund > 0
                        ? $"Your {sub.PlanName} membership was cancelled and a refund of {refund:N2} approved."
                        : $"Your {sub.PlanName} membership was cancelled.");

                await _db.SaveChangesAsync(ct);
                return (true, $"{sub.PlanName} membership cancelled{(refund > 0 ? $" with a {refund:N2} refund" : "")}.");
            }

            case BillingActionTypes.ReviewInvoice:
            case BillingActionTypes.ChasePayment:
            case BillingActionTypes.ReviewPricing:
                return (true, "Acknowledged - marked as reviewed.");

            default:
                return (false, $"Unknown billing action '{plan.ActionType}'.");
        }
    }
}
