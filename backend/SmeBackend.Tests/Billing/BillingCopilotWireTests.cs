using System.Text.Json;
using SmeBackend.DTOs;
using SmeBackend.Services;
using SmeBackend.Services.Billing;

namespace SmeBackend.Tests.Billing;

/// Cross-language contract test for the billing copilot.
///
/// The C# DTOs in `BillingPlannerService.cs` and the Pydantic models in
/// `agentic-ai-service/schemas/billing_contracts.py` describe the same two
/// HTTP bodies in two languages, and nothing in either codebase notices when
/// one drifts from the other - a renamed field just deserializes to null, and
/// a null planner looks exactly like "the model was unavailable".
///
/// So the JSON below is not hand-written. It was captured from the running
/// agent service (`POST /billing/plan` and `POST /billing/narrate`, with the
/// model forced unavailable so the capture needs no API key), with only the
/// workflow id, timestamps and the step duration pinned so the fixture does
/// not churn. Changing either contract means re-capturing it; that is the
/// point, and the recipe is in the agent service README.
public class BillingCopilotWireTests
{
    /// The same options `BillingPlannerService` uses on the wire.
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = new SnakeCaseNamingPolicy(),
        PropertyNameCaseInsensitive = true,
    };

    private const string PlanResponse = """
    {
      "workflow_type": "billing-copilot",
      "workflow_id": "9c9d5f7a-0000-4000-8000-000000000001",
      "objective": "Tighten the discount limit to 10% and check last quarter for abuse",
      "tenant_id": "11111111-1111-1111-1111-111111111111",
      "business_type": "Clinic",
      "status": "Planned",
      "planner": {
        "plan": [
          {
            "order": 1,
            "action": "Load the authorised billing snapshot",
            "assigned_agent": "BillingDomainAnalysisAgent",
            "description": "Read this tenant's invoices, payments, claims and commission rules for the period, through the caller's own permissions and no wider.",
            "tools": ["detect_billing_anomalies"]
          },
          {
            "order": 2,
            "action": "Run an anomaly scan",
            "assigned_agent": "BillingDomainAnalysisAgent",
            "description": "Apply the deterministic rules for this analysis type and record every flag with the evidence behind it: detect_billing_anomalies.",
            "tools": ["detect_billing_anomalies"]
          },
          {
            "order": 3,
            "action": "Turn the flags into recommended fixes",
            "assigned_agent": "BillingDomainAnalysisAgent",
            "description": "Propose one fix per flagged entity - adjust an unpaid invoice, review a paid one, approve or reject a claim, chase an overdue balance.",
            "tools": ["detect_billing_anomalies"]
          },
          {
            "order": 4,
            "action": "Hold high-value fixes for a human",
            "assigned_agent": "BillingApprovalGate",
            "description": "Apply the configured approval thresholds: an adjustment or claim above them becomes an approval request instead of a change, and only a person can release it.",
            "tools": []
          }
        ],
        "assigned_agents": ["BillingDomainAnalysisAgent", "BillingApprovalGate"],
        "predicted_findings": [
          {
            "kind": "excessive_discount",
            "likelihood": 0.5,
            "description": "The objective points at discounting, so invoices over the cap are the likely finding."
          }
        ],
        "confidence_score": 0.6,
        "intent": {
          "analysis_type": "anomalies",
          "days_back": 90,
          "tighten_discount_cap_to": 10.0,
          "deal_amount": null,
          "focus": "Planned an anomaly scan over the last 90 day(s).",
          "rationale": "Read from keywords in the objective (deterministic fallback)."
        },
        "summary": "Deterministic plan: the language model was unavailable (captured offline).",
        "used_fallback": true
      },
      "thresholds": {
        "max_discount_percent": 30.0,
        "adjustment_approval_amount": 100.0,
        "claim_approval_amount": 500.0,
        "min_tax_percent": 0.0,
        "max_tax_percent": 25.0,
        "revenue_drop_percent": 40.0,
        "price_deviation_percent": 50.0,
        "duplicate_window_minutes": 10,
        "high_value_invoice_amount": 1000000.0
      },
      "warnings": [
        "The language model was unavailable, so the deterministic planner read the objective from keywords. Detection, thresholds and approvals are unaffected - only the interpretation of the sentence is simpler.",
        "The objective asks for a stricter review, so the discount cap is tightened to 10% for this run (configured cap: 30%)."
      ],
      "agent_steps": [{ "agent": "BillingPlannerAgent", "duration_ms": 4, "ok": true, "error": null }],
      "llm_calls": [],
      "error": null,
      "created_at": "2026-09-25T10:00:00Z"
    }
    """;

    private const string NarrateResponse = """
    {
      "workflow_type": "billing-narrative",
      "tenant_id": "11111111-1111-1111-1111-111111111111",
      "status": "Narrated",
      "narrative": {
        "headline": "1 anomaly across 1 category.",
        "themes": [
          {
            "title": "Excessive discount",
            "detail": "1 excessive discount finding(s) worth 5.00 LKR in total, on INV-001.",
            "anomaly_ids": ["ANM-001"],
            "severity": "medium"
          }
        ],
        "suggested_next_steps": ["Start with the excessive discount findings."],
        "used_fallback": true
      },
      "warnings": ["The language model was unavailable; findings are grouped by type deterministically instead."],
      "llm_calls": [],
      "error": null,
      "created_at": "2026-09-25T10:00:01Z"
    }
    """;

    [Fact]
    public void ARealPlanResponseDeserializesFieldForField()
    {
        var trace = JsonSerializer.Deserialize<BillingPlanTraceDto>(PlanResponse, Json);

        Assert.NotNull(trace);
        Assert.Equal("billing-copilot", trace!.WorkflowType);
        Assert.Equal("Planned", trace.Status);
        Assert.Equal("Clinic", trace.BusinessType);
        Assert.Equal(2, trace.Warnings.Count);
        Assert.Equal("BillingPlannerAgent", Assert.Single(trace.AgentSteps!).Agent);
        Assert.Empty(trace.LlmCalls!);
        Assert.Null(trace.Error);

        var planner = Assert.IsType<BillingPlannerOutputDto>(trace.Planner);
        Assert.True(planner.UsedFallback);
        Assert.Equal(0.6, planner.ConfidenceScore);
        Assert.Equal(4, planner.Plan.Count);
        Assert.Equal(new[] { BillingPlanGuard.AnalysisAgent, BillingPlanGuard.ApprovalGate }, planner.AssignedAgents);

        var step = planner.Plan[1];
        Assert.Equal(2, step.Order);
        Assert.Equal("Run an anomaly scan", step.Action);
        Assert.Equal(BillingPlanGuard.AnalysisAgent, step.AssignedAgent);
        Assert.Equal(new[] { BillingDomainAnalysisAgent.DetectBillingAnomalies }, step.Tools);
        Assert.Equal(BillingPlanGuard.ApprovalGate, planner.Plan[^1].AssignedAgent);
        Assert.Empty(planner.Plan[^1].Tools);

        var finding = Assert.Single(planner.PredictedFindings);
        Assert.Equal("excessive_discount", finding.Kind);
        Assert.Equal(0.5, finding.Likelihood);
        Assert.NotEmpty(finding.Description);

        // The intent is the part the guard acts on, so every field must arrive.
        Assert.Equal(BillingAnalysisTypes.Anomalies, planner.Intent.AnalysisType);
        Assert.Equal(90, planner.Intent.DaysBack);
        Assert.Equal(10m, planner.Intent.TightenDiscountCapTo);
        Assert.Null(planner.Intent.DealAmount);
        Assert.StartsWith("Planned an anomaly scan", planner.Intent.Focus);
        Assert.Contains("deterministic fallback", planner.Intent.Rationale);

        Assert.Equal(30m, trace.Thresholds!.MaxDiscountPercent);
        Assert.Equal(500m, trace.Thresholds.ClaimApprovalAmount);
        Assert.Equal(10, trace.Thresholds.DuplicateWindowMinutes);
    }

    [Fact]
    public void TheGuardAcceptsARealPlannerOutputUnchangedWhenItAlreadyObeysTheRules()
    {
        // The Python planner clamps first. When it did its job, the second
        // clamp should be a no-op - if this starts reporting corrections, the
        // two copies of the rule have drifted apart.
        var planner = JsonSerializer.Deserialize<BillingPlanTraceDto>(PlanResponse, Json)!.Planner!;

        var (safe, notes) = BillingPlanGuard.Clamp(planner, ThresholdConfig.Default);

        Assert.Empty(notes);
        Assert.Equal(10m, safe.Intent.TightenDiscountCapTo);
        Assert.Equal(10m, BillingPlanGuard.Effective(ThresholdConfig.Default, safe).MaxDiscountPercent);
        Assert.Equal(planner.Plan.Count, safe.Plan.Count);
        Assert.Equal(planner.Plan.SelectMany(s => s.Tools), safe.Plan.SelectMany(s => s.Tools));
    }

    [Fact]
    public void ARealNarrativeResponseDeserializesFieldForField()
    {
        var trace = JsonSerializer.Deserialize<BillingNarrateTraceDto>(NarrateResponse, Json);

        Assert.NotNull(trace);
        Assert.Equal("billing-narrative", trace!.WorkflowType);
        Assert.Equal("Narrated", trace.Status);

        var narrative = Assert.IsType<BillingNarrativeDto>(trace.Narrative);
        Assert.Equal("1 anomaly across 1 category.", narrative.Headline);
        Assert.True(narrative.UsedFallback);
        Assert.Equal("Start with the excessive discount findings.", Assert.Single(narrative.SuggestedNextSteps));

        var theme = Assert.Single(narrative.Themes);
        Assert.Equal("Excessive discount", theme.Title);
        Assert.Equal("medium", theme.Severity);
        Assert.Equal(new[] { "ANM-001" }, theme.AnomalyIds);
        Assert.Contains("5.00 LKR", theme.Detail);
    }

    [Fact]
    public void TheRequestsSerializeToTheFieldNamesPydanticExpects()
    {
        var plan = JsonSerializer.SerializeToNode(new BillingPlanServiceRequest(
            "Check discounts", "t-1", "Clinic", "LKR", BillingThresholdsDto.From(ThresholdConfig.Default), "jwt"), Json)!;

        // BillingPlanRequest in billing_contracts.py.
        Assert.Equal(new[] { "objective", "tenant_id", "business_type", "currency", "thresholds", "auth_token" },
            plan.AsObject().Select(p => p.Key));
        // BillingThresholds - the caps the planner is told it may tighten towards.
        Assert.Equal(new[] { "max_discount_percent", "adjustment_approval_amount", "claim_approval_amount",
                             "min_tax_percent", "max_tax_percent", "revenue_drop_percent",
                             "price_deviation_percent", "duplicate_window_minutes", "high_value_invoice_amount" },
            plan["thresholds"]!.AsObject().Select(p => p.Key));

        var narrate = JsonSerializer.SerializeToNode(new BillingNarrateServiceRequest(
            "Check discounts", BillingAnalysisTypes.Anomalies, "t-1", "LKR",
            new List<AnomalyDigestDto> { new("ANM-001", "excessive_discount", "medium", "INV-001", "…", 5m) },
            new List<string>(), new List<string>(), 0.95, "jwt"), Json)!;

        // BillingNarrateRequest, and AnomalyDigest inside it.
        Assert.Equal(new[] { "objective", "analysis_type", "tenant_id", "currency", "anomalies", "insights",
                             "recommended_actions", "confidence_score", "auth_token" },
            narrate.AsObject().Select(p => p.Key));
        Assert.Equal(new[] { "id", "type", "severity", "entity_label", "description", "amount" },
            narrate["anomalies"]![0]!.AsObject().Select(p => p.Key));
    }

    [Fact]
    public void ATraceWithNoPlannerIsATypedFailureRatherThanACrash()
    {
        // What a safe failure on the Python side actually looks like on the
        // wire: 200, a full trace, no plan.
        const string failed = """
        {
          "workflow_type": "billing-copilot",
          "workflow_id": "9c9d5f7a-0000-4000-8000-000000000002",
          "objective": "Check discounts",
          "tenant_id": "t-1",
          "business_type": "Clinic",
          "status": "Failed",
          "planner": null,
          "warnings": [],
          "agent_steps": [{ "agent": "BillingPlannerAgent", "duration_ms": 2, "ok": false, "error": "boom" }],
          "llm_calls": [],
          "error": "boom",
          "created_at": "2026-09-25T10:00:00Z"
        }
        """;

        var trace = JsonSerializer.Deserialize<BillingPlanTraceDto>(failed, Json)!;

        Assert.Null(trace.Planner);
        Assert.Equal("Failed", trace.Status);
        Assert.Equal("boom", trace.Error);
        Assert.False(Assert.Single(trace.AgentSteps!).Ok);
    }
}
