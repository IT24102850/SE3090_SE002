namespace SmeBackend.Models;

/// One run of the Platform Operations Copilot - the owner's cross-tenant
/// agent.
///
/// Deliberately not Models/AgentWorkflow.cs, which is ITenantScoped: this
/// workflow belongs to the platform rather than to any business, reads across
/// every tenant, and proposes actions *against* tenants. Filing it under one
/// tenant's id would be wrong in both directions - it would hide the run from
/// the owner's own console and expose it to a tenant it merely mentions.
///
/// The row is the durable shared state the spec requires: objective, plan,
/// every agent's output, tool calls, validation verdicts, approval decision
/// and final outcome. It is written before the owner is asked to approve
/// anything, so a run that is never approved is still a complete record of
/// what was considered.
public class PlatformAgentWorkflow : BaseEntity
{
    /// The workflow id the agent service generated, kept so a trace can be
    /// correlated across the two services' logs.
    public string TraceId { get; set; } = string.Empty;

    public string Objective { get; set; } = string.Empty;

    /// AwaitingApproval | Approved | Rejected | Revising | Applied
    /// | PartiallyApplied | NothingToDo | Failed
    public string Status { get; set; } = PlatformWorkflowStatuses.AwaitingApproval;

    // ── The agents' own outputs, one column each ─────────────────────────
    // Kept apart rather than as one blob so the console can show which agent
    // produced what without parsing, and so a later change to one agent's
    // contract cannot silently corrupt another's record.

    /// PlatformPlannerOutput - the plan and the planner's reading of the goal.
    public string? PlanJson { get; set; }

    /// PlatformAnalysisOutput - who is at risk and on what evidence.
    public string? AnalysisJson { get; set; }

    /// PlatformActionOutput - every intervention proposed, including the
    /// ones validation went on to refuse.
    public string? ProposalsJson { get; set; }

    /// PlatformSafetyOutput - the verdicts, what survived, and the notes.
    public string? ValidationJson { get; set; }

    /// Tool calls, model calls and per-agent timings.
    public string? ObservabilityJson { get; set; }

    // ── Approval ─────────────────────────────────────────────────────────

    /// Pending | Approved | Rejected | Revision
    public string ApprovalStatus { get; set; } = "Pending";
    public Guid? DecidedByUserId { get; set; }
    public string? DecidedByEmail { get; set; }
    public DateTime? DecidedAt { get; set; }
    public string? DecisionReason { get; set; }

    /// Which of the accepted interventions the owner actually chose. The
    /// agent proposes a set; the owner may approve a subset, and approving
    /// four of five is the normal case rather than an exception.
    public string? ApprovedInterventionsJson { get; set; }

    // ── Outcome ──────────────────────────────────────────────────────────

    /// What was carried out, per intervention, once approved - including the
    /// ones that failed at execution.
    public string? OutcomeJson { get; set; }

    public string? ErrorLog { get; set; }
    public DateTime? CompletedAt { get; set; }

    /// Whether a language model actually drove this run, or the
    /// deterministic fallbacks did. Without it a trace produced during a
    /// Gemini outage is indistinguishable from one the model reasoned
    /// through, which would make every figure on it harder to trust.
    public bool ModelDriven { get; set; }

    public decimal EstimatedCost { get; set; }
    public string Currency { get; set; } = "LKR";
}

public static class PlatformWorkflowStatuses
{
    /// The success path. The pipeline has proposals and is waiting on a
    /// human with an authenticator.
    public const string AwaitingApproval = "AwaitingApproval";
    public const string Approved = "Approved";
    public const string Rejected = "Rejected";
    /// Sent back with feedback; a new run supersedes it.
    public const string Revising = "Revising";
    public const string Applied = "Applied";
    /// Some interventions were carried out and some failed. A distinct state
    /// because "Applied" would overstate it and "Failed" would understate it,
    /// and the owner needs to know which tenants actually changed.
    public const string PartiallyApplied = "PartiallyApplied";
    /// The run completed and found nothing worth doing - a good outcome on a
    /// healthy platform, not a failure.
    public const string NothingToDo = "NothingToDo";
    public const string Failed = "Failed";
}
