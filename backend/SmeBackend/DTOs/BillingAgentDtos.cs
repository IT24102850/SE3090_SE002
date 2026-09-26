using System.ComponentModel.DataAnnotations;

namespace SmeBackend.DTOs;

// Contracts for the billing Domain Analysis Agent (spec 3.7):
//   Input:  { analysisType, dataRange, tenantId, thresholds }
//   Output: { anomalies, insights, recommendedActions, confidenceScore }

public record DateRangeDto(DateTime From, DateTime To);

/// Every threshold the agent applies, with the spec's defaults. Amounts are
/// in the invoice's own currency.
public record ThresholdConfig(
    decimal MaxDiscountPercent = 30m,
    decimal AdjustmentApprovalAmount = 100m,
    decimal ClaimApprovalAmount = 500m,
    decimal MinTaxPercent = 0m,
    decimal MaxTaxPercent = 25m,
    decimal RevenueDropPercent = 40m,
    decimal PriceDeviationPercent = 50m,
    int DuplicateWindowMinutes = 10,
    decimal HighValueInvoiceAmount = 1_000_000m
)
{
    public static ThresholdConfig Default { get; } = new();
}

public static class BillingAnalysisTypes
{
    public const string Full = "full";
    public const string Anomalies = "anomalies";
    public const string Revenue = "revenue";
    public const string Insurance = "insurance";
    public const string Pricing = "pricing";
    public const string Commission = "commission";

    public static readonly string[] All = { Full, Anomalies, Revenue, Insurance, Pricing, Commission };
}

public record BillingAnalysisRequest(
    [Required]
    [MaxLength(30)]
    string AnalysisType,

    DateRangeDto? DataRange = null,

    // Must match the caller's token when given - the agent never reads
    // across tenants.
    Guid? TenantId = null,

    ThresholdConfig? Thresholds = null,

    // Commission analysis only: the deal to split.
    decimal? DealAmount = null
);

/// Billing Copilot input: a plain-English objective instead of a filled-in
/// form. The planner turns it into the BillingAnalysisRequest above; the
/// thresholds stay the caller's to set, because a model is never allowed to.
public record PlanAnalysisRequest(
    [Required]
    [MinLength(3)]
    [MaxLength(500)]
    string Objective,

    // Must match the caller's token when given - as with a direct analysis,
    // the agent never reads across tenants.
    Guid? TenantId = null,

    ThresholdConfig? Thresholds = null
);

public record Anomaly(
    string Id,
    // excessive_discount | tax_out_of_range | duplicate_invoice |
    // overpayment | amount_mismatch | revenue_drop | price_outlier |
    // claim_exceeds_invoice | claim_policy_mismatch | high_value_invoice
    string Type,
    // low | medium | high | critical
    string Severity,
    string EntityType,
    Guid? EntityId,
    string? EntityLabel,
    string Description,
    decimal? Amount,
    IReadOnlyDictionary<string, object?> Evidence
);

public record Insight(
    string Type,
    string Title,
    string Detail,
    decimal? Value
);

public record RecommendedAction(
    string Id,
    // adjust_invoice | review_invoice | approve_insurance_claim |
    // reject_insurance_claim | chase_payment | review_pricing
    string ActionType,
    string EntityType,
    Guid? EntityId,
    string Description,
    decimal? Amount,
    bool RequiresApproval,
    string? ApprovalReason,
    IReadOnlyDictionary<string, object?> Parameters
);

public record AgentToolCall(
    string Tool,
    string Summary,
    int ItemsExamined,
    long DurationMs
);

public record BillingAnalysisResponse(
    Guid WorkflowId,
    string AnalysisType,
    DateRangeDto DataRange,
    IReadOnlyList<Anomaly> Anomalies,
    IReadOnlyList<Insight> Insights,
    IReadOnlyList<RecommendedAction> RecommendedActions,
    double ConfidenceScore,
    IReadOnlyList<AgentToolCall> ToolCalls,
    IReadOnlyList<Guid> ApprovalWorkflowIds
);

public record InvoiceValidationIssue(
    string Code,
    // info | warning | error
    string Severity,
    string Message
);

public record InvoiceValidationResult(
    bool IsValid,
    bool RequiresReview,
    decimal Subtotal,
    decimal DiscountPercent,
    decimal TaxPercent,
    decimal FinalAmount,
    IReadOnlyList<InvoiceValidationIssue> Issues
);

public record ClaimValidationResult(
    bool IsValid,
    bool RequiresApproval,
    IReadOnlyList<InvoiceValidationIssue> Issues
);

/// One row of the Agent Workflow Monitor's billing view.
public record BillingWorkflowResponse(
    Guid Id,
    string Objective,
    // analysis | approval
    string Kind,
    string? ActionType,
    string Status,
    string ApprovalStatus,
    decimal? Amount,
    string? EntityType,
    Guid? EntityId,
    string? Reason,
    Guid? ApprovedBy,
    DateTime? ApprovedAt,
    DateTime CreatedAt,
    DateTime? CompletedAt,
    int AnomalyCount,
    double? ConfidenceScore,
    string? FinalOutcome,
    string? ErrorLog,
    string? PlanJson,
    string? ToolResultsJson,
    string? ValidationResults
);

public record RejectBillingWorkflowRequest(
    [MaxLength(500)]
    string? Reason
);
