using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using SmeBackend.DTOs;

namespace SmeBackend.Services.Billing;

/// Calls the internal agentic-ai-service's POST /billing/plan and
/// POST /billing/narrate - the language-model edges of the billing Domain
/// Analysis Agent.
///
/// The agent in the middle stays deterministic C#. The planner turns a
/// manager's sentence into the `BillingAnalysisRequest` that agent already
/// accepts; the narrator reads the pattern across the findings it produced.
/// Neither can detect anything, and neither can change a threshold: whatever
/// comes back over HTTP goes through <see cref="BillingPlanGuard"/> before it
/// reaches the agent, because a prompt is where a rule is explained and code
/// is where it is enforced.
///
/// Never throws on a "the AI service said no"-shaped outcome - always a typed
/// result, so the caller can record a safe failure instead of 500-ing.
public interface IBillingPlannerService
{
    Task<BillingPlanResult> PlanAsync(BillingPlanServiceRequest request, CancellationToken ct = default);

    /// Advisory only. A failure here never invalidates an analysis that has
    /// already run, so callers surface the error and keep the findings.
    Task<BillingNarrativeResult> NarrateAsync(BillingNarrateServiceRequest request, CancellationToken ct = default);
}

public sealed class BillingPlannerService : IBillingPlannerService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = new SnakeCaseNamingPolicy(),
        PropertyNameCaseInsensitive = true,
    };

    private readonly HttpClient _http;
    private readonly IConfiguration _config;
    private readonly ILogger<BillingPlannerService> _logger;

    public BillingPlannerService(HttpClient http, IConfiguration config, ILogger<BillingPlannerService> logger)
    {
        _config = config;
        _logger = logger;
        var baseUrl = config["AgentService:BaseUrl"] ?? "http://localhost:8001";
        http.BaseAddress = new Uri(baseUrl);
        http.Timeout = TimeSpan.FromSeconds(config.GetValue("AgentService:TimeoutSeconds", 60));
        _http = http;
    }

    public async Task<BillingPlanResult> PlanAsync(BillingPlanServiceRequest request, CancellationToken ct = default)
    {
        var (trace, error) = await PostAsync<BillingPlanTraceDto>("/billing/plan", request, ct);
        if (trace is null) return BillingPlanResult.Failed(error!);
        if (trace.Planner is null)
            return BillingPlanResult.Failed(trace.Error ?? "The billing planner returned no plan.");
        return BillingPlanResult.Ok(trace);
    }

    public async Task<BillingNarrativeResult> NarrateAsync(BillingNarrateServiceRequest request, CancellationToken ct = default)
    {
        var (trace, error) = await PostAsync<BillingNarrateTraceDto>("/billing/narrate", request, ct);
        if (trace?.Narrative is null) return BillingNarrativeResult.Failed(error ?? trace?.Error ?? "No narrative was produced.");
        return BillingNarrativeResult.Ok(trace.Narrative);
    }

    private async Task<(T? Body, string? Error)> PostAsync<T>(string path, object request, CancellationToken ct)
    {
        var token = _config["AgentService:InternalToken"];
        if (string.IsNullOrEmpty(token))
            return (default, "AgentService:InternalToken is not configured, so the billing copilot cannot be reached.");

        using var message = new HttpRequestMessage(HttpMethod.Post, path)
        {
            Content = JsonContent.Create(request, options: JsonOptions),
        };
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        HttpResponseMessage response;
        try
        {
            response = await _http.SendAsync(message, ct);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            _logger.LogWarning(ex, "Billing copilot unreachable at {BaseAddress}{Path}", _http.BaseAddress, path);
            return (default, $"Could not reach the billing copilot at {_http.BaseAddress}. Start the agent service " +
                             $"(uvicorn main:app --port 8001) and retry. {ex.Message}");
        }

        // Every outcome of a run - a model plan, the deterministic fallback, a
        // safe failure - comes back 200 with a full trace. A non-200 means the
        // request itself was malformed or the service broke.
        var body = await response.Content.ReadAsStringAsync(ct);
        if (response.StatusCode != HttpStatusCode.OK)
            return (default, $"The billing copilot returned HTTP {(int)response.StatusCode}: {Truncate(body, 300)}");

        try
        {
            var parsed = JsonSerializer.Deserialize<T>(body, JsonOptions);
            return parsed is null
                ? (default, "The billing copilot returned an empty response.")
                : (parsed, null);
        }
        catch (JsonException ex)
        {
            return (default, $"The billing copilot returned an unreadable response: {ex.Message}");
        }
    }

    private static string Truncate(string value, int max) => value.Length <= max ? value : value[..max] + "…";
}

/// Re-validates planner output on this side of the wire.
///
/// The Python planner already clamps everything it returns. This exists
/// because that is a different process reached over HTTP: the guarantee that
/// matters ("no model output can loosen a billing threshold") has to hold
/// even if the agent service is misconfigured, rolled back to an older
/// version, or replaced. So the rule is applied twice and the golden cases
/// depend on this copy.
///
/// The direction is one-way. A planner may narrow a run and may never widen
/// one:
///   - it may lower the discount cap, never raise it;
///   - it may shorten the window, never exceed the one-year data cap;
///   - it cannot reach the approval amounts at all - there is no field for
///     them, here or in the wire contract;
///   - it cannot name a tool outside the five the agent allow-lists, nor one
///     the chosen analysis type does not run.
public static class BillingPlanGuard
{
    public const string ApprovalGate = "BillingApprovalGate";
    public const string AnalysisAgent = "BillingDomainAnalysisAgent";

    /// The C# DataRange cap, mirrored in the Python contract.
    public const int MaxDaysBack = 366;

    /// Clamp one planner output against the thresholds this tenant actually
    /// configured. Returns the safe plan and a note for every value that had
    /// to be corrected - a silent correction would hide a misbehaving model.
    public static (BillingPlannerOutputDto Planner, List<string> Notes) Clamp(
        BillingPlannerOutputDto planner, ThresholdConfig configured)
    {
        var notes = new List<string>();
        var intent = planner.Intent ?? new BillingIntentDto();

        var type = (intent.AnalysisType ?? "").Trim().ToLowerInvariant();
        if (!BillingAnalysisTypes.All.Contains(type))
        {
            notes.Add($"The planner asked for an unknown analysis type ('{Sanitize(intent.AnalysisType)}'); a full review was run instead.");
            type = BillingAnalysisTypes.Full;
        }

        var days = intent.DaysBack;
        if (days < 1 || days > MaxDaysBack)
        {
            notes.Add($"The planner asked for {days} days of history; clamped to the {MaxDaysBack}-day limit.");
            days = Math.Clamp(days, 1, MaxDaysBack);
        }

        var cap = intent.TightenDiscountCapTo;
        if (cap is { } c && (c < 0m || c >= configured.MaxDiscountPercent))
        {
            // The one that matters: a model told to "set the maximum discount
            // to 100%" lands here, and its instruction dies here.
            notes.Add($"The planner tried to set the discount cap to {c:0.##}%, which is not stricter than the configured {configured.MaxDiscountPercent:0.##}%; the configured cap stands.");
            cap = null;
        }

        var deal = intent.DealAmount;
        if (deal is not > 0m || type != BillingAnalysisTypes.Commission) deal = null;

        var allowed = BillingDomainAnalysisAgent.PlanFor(type).ToHashSet();
        var steps = new List<BillingPlanStepDto>();
        foreach (var step in (planner.Plan ?? new List<BillingPlanStepDto>()).OrderBy(s => s.Order))
        {
            var agent = step.AssignedAgent == ApprovalGate ? ApprovalGate : AnalysisAgent;
            var tools = agent == ApprovalGate
                ? new List<string>()
                : (step.Tools ?? new List<string>())
                    .Where(t => BillingDomainAnalysisAgent.AllowedTools.Contains(t) && allowed.Contains(t))
                    .Distinct()
                    .ToList();
            steps.Add(step with { Order = steps.Count + 1, AssignedAgent = agent, Tools = tools });
        }

        if (steps.Count == 0 || !steps.Any(s => s.Tools.Count > 0))
        {
            notes.Add("The planner's steps named no tool this analysis runs, so the agent's own default plan was used.");
            steps = DefaultSteps(type);
        }

        if (steps[^1].AssignedAgent != ApprovalGate)
        {
            steps.Add(GateStep(steps.Count + 1));
        }

        var safe = planner with
        {
            Plan = steps,
            AssignedAgents = steps.Select(s => s.AssignedAgent).Distinct().ToList(),
            ConfidenceScore = Math.Clamp(planner.ConfidenceScore, 0d, 1d),
            PredictedFindings = (planner.PredictedFindings ?? new List<PredictedFindingDto>())
                .Where(f => !string.IsNullOrWhiteSpace(f.Kind))
                .Select(f => f with { Likelihood = Math.Clamp(f.Likelihood, 0d, 1d) })
                .Take(6).ToList(),
            Intent = intent with
            {
                AnalysisType = type,
                DaysBack = days,
                TightenDiscountCapTo = cap,
                DealAmount = deal,
                Focus = Sanitize(intent.Focus),
                Rationale = Sanitize(intent.Rationale),
            },
            Summary = Sanitize(planner.Summary, 400),
        };

        return (safe, notes);
    }

    /// The thresholds the run actually uses: the tenant's own, with the
    /// discount cap lowered if - and only if - the planner asked for
    /// something stricter. Every other threshold is passed through untouched,
    /// which is why the approval amounts cannot move.
    public static ThresholdConfig Effective(ThresholdConfig configured, BillingPlannerOutputDto planner)
    {
        var cap = planner.Intent?.TightenDiscountCapTo;
        return cap is { } c && c >= 0m && c < configured.MaxDiscountPercent
            ? configured with { MaxDiscountPercent = c }
            : configured;
    }

    public static DateRangeDto RangeFor(BillingPlannerOutputDto planner, DateTime now)
    {
        var days = Math.Clamp(planner.Intent?.DaysBack ?? 30, 1, MaxDaysBack);
        return new DateRangeDto(now.AddDays(-days), now);
    }

    public static BillingPlanStepDto GateStep(int order) => new(
        order,
        "Hold high-value fixes for a human",
        ApprovalGate,
        "Apply the configured approval thresholds: an adjustment or claim above them becomes an approval request " +
        "instead of a change, and only a person can release it.",
        new List<string>());

    private static List<BillingPlanStepDto> DefaultSteps(string analysisType)
    {
        var tools = BillingDomainAnalysisAgent.PlanFor(analysisType).ToList();
        return new List<BillingPlanStepDto>
        {
            new(1, $"Run the {analysisType} checks", AnalysisAgent,
                "Apply the deterministic rules for this analysis type and record every flag with the evidence behind it.",
                tools),
            new(2, "Turn the flags into recommended fixes", AnalysisAgent,
                "Propose one fix per flagged entity - adjust an unpaid invoice, review a paid one, approve or reject a claim, chase an overdue balance.",
                tools),
            GateStep(3),
        };
    }

    /// Planner text reaches the monitor UI and the stored workflow, so it is
    /// collapsed to one line and bounded here rather than trusted to be short.
    private static string Sanitize(string? value, int max = 300)
    {
        if (string.IsNullOrWhiteSpace(value)) return "";
        var collapsed = string.Join(' ', value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
            .Select(w => new string(w.Where(ch => !char.IsControl(ch)).ToArray())))
            .Trim();
        return collapsed.Length <= max ? collapsed : collapsed[..max];
    }
}

// ── Wire contracts, mirroring agentic-ai-service/schemas/billing_contracts.py ──
// Serialized snake_case by SnakeCaseNamingPolicy, so the Pydantic field names
// match without annotating every property.

public record BillingThresholdsDto(
    decimal MaxDiscountPercent,
    decimal AdjustmentApprovalAmount,
    decimal ClaimApprovalAmount,
    decimal MinTaxPercent,
    decimal MaxTaxPercent,
    decimal RevenueDropPercent,
    decimal PriceDeviationPercent,
    int DuplicateWindowMinutes,
    decimal HighValueInvoiceAmount)
{
    public static BillingThresholdsDto From(ThresholdConfig t) => new(
        t.MaxDiscountPercent, t.AdjustmentApprovalAmount, t.ClaimApprovalAmount, t.MinTaxPercent, t.MaxTaxPercent,
        t.RevenueDropPercent, t.PriceDeviationPercent, t.DuplicateWindowMinutes, t.HighValueInvoiceAmount);
}

/// AuthToken is the calling manager's own JWT, forwarded for symmetry with the
/// booking and inventory workflows. The planner route reads no business data,
/// so it is accepted and never used - and never echoed back.
public record BillingPlanServiceRequest(
    string Objective,
    string TenantId,
    string BusinessType,
    string Currency,
    BillingThresholdsDto Thresholds,
    string AuthToken);

public record BillingIntentDto(
    string AnalysisType = BillingAnalysisTypes.Full,
    int DaysBack = 30,
    decimal? TightenDiscountCapTo = null,
    decimal? DealAmount = null,
    string Focus = "",
    string Rationale = "");

public record BillingPlanStepDto(
    int Order,
    string Action,
    string AssignedAgent,
    string Description,
    List<string> Tools);

public record PredictedFindingDto(string Kind, double Likelihood, string Description);

public record BillingPlannerOutputDto(
    List<BillingPlanStepDto> Plan,
    List<string> AssignedAgents,
    List<PredictedFindingDto> PredictedFindings,
    double ConfidenceScore,
    BillingIntentDto Intent,
    string Summary,
    bool UsedFallback);

public record BillingPlanTraceDto(
    string WorkflowType,
    string WorkflowId,
    string Objective,
    string TenantId,
    string BusinessType,
    string Status,
    BillingPlannerOutputDto? Planner,
    BillingThresholdsDto? Thresholds,
    List<string> Warnings,
    List<AgentStepRecordDto>? AgentSteps,
    List<LlmCallRecordDto>? LlmCalls,
    string? Error,
    DateTime CreatedAt);

public record AnomalyDigestDto(
    string Id,
    string Type,
    string Severity,
    string? EntityLabel,
    string Description,
    decimal? Amount);

public record BillingNarrateServiceRequest(
    string Objective,
    string AnalysisType,
    string TenantId,
    string Currency,
    List<AnomalyDigestDto> Anomalies,
    List<string> Insights,
    List<string> RecommendedActions,
    double ConfidenceScore,
    string AuthToken);

public record FindingThemeDto(string Title, string Detail, List<string> AnomalyIds, string Severity);

public record BillingNarrativeDto(
    string Headline,
    List<FindingThemeDto> Themes,
    List<string> SuggestedNextSteps,
    bool UsedFallback);

public record BillingNarrateTraceDto(
    string WorkflowType,
    string TenantId,
    string Status,
    BillingNarrativeDto? Narrative,
    List<string> Warnings,
    List<LlmCallRecordDto>? LlmCalls,
    string? Error,
    DateTime CreatedAt);

/// What POST /api/billing-agent/plan-analysis returns: the plan, the
/// thresholds the run actually used after the guard had its say, the
/// deterministic analysis itself, and the narrative read back over it.
///
/// `PlannerWarnings` is the honest part: every value the guard had to correct,
/// so a manager can see when the planner asked for something it was not
/// allowed to have. `NarrativeError` is set when the summary could not be
/// produced - the findings above it are unaffected either way.
public record BillingPlannedAnalysisResponse(
    string Objective,
    BillingPlannerOutputDto Planner,
    List<string> PlannerWarnings,
    ThresholdConfig EffectiveThresholds,
    BillingAnalysisResponse Analysis,
    BillingNarrativeDto? Narrative,
    string? NarrativeError);

public record BillingPlanResult(bool Success, BillingPlanTraceDto? Trace, string? ErrorMessage)
{
    public static BillingPlanResult Ok(BillingPlanTraceDto trace) => new(true, trace, null);
    public static BillingPlanResult Failed(string message) => new(false, null, message);
}

public record BillingNarrativeResult(bool Success, BillingNarrativeDto? Narrative, string? ErrorMessage)
{
    public static BillingNarrativeResult Ok(BillingNarrativeDto narrative) => new(true, narrative, null);
    public static BillingNarrativeResult Failed(string message) => new(false, null, message);
}
