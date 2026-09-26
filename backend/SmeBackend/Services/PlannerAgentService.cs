using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace SmeBackend.Services;

/// snake_case &lt;-&gt; PascalCase, matching the Python service's Pydantic field
/// names (workflow_id, tenant_id, ...) without hand-annotating every DTO
/// property.
public class SnakeCaseNamingPolicy : JsonNamingPolicy
{
    public override string ConvertName(string name)
    {
        if (string.IsNullOrEmpty(name)) return name;
        var chars = name.SelectMany((c, i) => i > 0 && char.IsUpper(c) ? new[] { '_', char.ToLowerInvariant(c) } : new[] { char.ToLowerInvariant(c) });
        return new string(chars.ToArray());
    }
}

public interface IPlannerAgentService
{
    Task<AgentPlanResult> PlanAsync(AgentPlanRequest request, CancellationToken ct = default);

    /// Schedule Copilot: the staff-facing Planner/Coordinator workflow.
    Task<ScheduleCopilotResult> PlanScheduleAsync(ScheduleCopilotRequest request, CancellationToken ct = default);
}

/// Calls the internal agentic-ai-service's POST /plan, which runs the full
/// Planner -> Domain Analysis -> Action/Tool -> Validation/Safety pipeline
/// synchronously and returns one complete trace. Never throws on a
/// "the AI service said no"-shaped outcome — always returns a typed
/// AgentPlanResult so callers can fail the request safely (matches the
/// Python service's own "never crash, always a structured outcome" rule).
public partial class PlannerAgentService : IPlannerAgentService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = new SnakeCaseNamingPolicy(),
        PropertyNameCaseInsensitive = true,
    };

    private readonly HttpClient _http;
    private readonly IConfiguration _config;

    public PlannerAgentService(HttpClient http, IConfiguration config)
    {
        _config = config;
        var baseUrl = config["AgentService:BaseUrl"] ?? "http://localhost:8001";
        http.BaseAddress = new Uri(baseUrl);
        http.Timeout = TimeSpan.FromSeconds(config.GetValue("AgentService:TimeoutSeconds", 60));
        _http = http;
    }

    public async Task<AgentPlanResult> PlanAsync(AgentPlanRequest request, CancellationToken ct = default)
    {
        var token = _config["AgentService:InternalToken"];
        if (string.IsNullOrEmpty(token))
            return AgentPlanResult.Failed("AgentService:InternalToken is not configured.");

        using var message = new HttpRequestMessage(HttpMethod.Post, "/plan")
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
            return AgentPlanResult.Failed($"Could not reach the AI planning service: {ex.Message}");
        }

        // The Python service returns 422 for a legitimate, structured safe
        // failure (still a full trace with `error` set) — that's a normal
        // outcome to hand back to the caller, not an exception here.
        if (response.StatusCode != HttpStatusCode.OK && response.StatusCode != HttpStatusCode.UnprocessableEntity)
            return AgentPlanResult.Failed($"AI planning service returned HTTP {(int)response.StatusCode}.");

        WorkflowTraceDto? trace;
        try
        {
            trace = await response.Content.ReadFromJsonAsync<WorkflowTraceDto>(JsonOptions, ct);
        }
        catch (JsonException ex)
        {
            return AgentPlanResult.Failed($"AI planning service returned an unreadable response: {ex.Message}");
        }

        if (trace == null)
            return AgentPlanResult.Failed("AI planning service returned an empty response.");

        return AgentPlanResult.Ok(trace);
    }
}

public partial class PlannerAgentService
{
    public async Task<ScheduleCopilotResult> PlanScheduleAsync(ScheduleCopilotRequest request, CancellationToken ct = default)
    {
        var token = _config["AgentService:InternalToken"];
        if (string.IsNullOrEmpty(token))
            return ScheduleCopilotResult.Failed("AgentService:InternalToken is not configured.");

        using var message = new HttpRequestMessage(HttpMethod.Post, "/schedule/plan")
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
            return ScheduleCopilotResult.Failed(
                $"Could not reach the Schedule Copilot at {_http.BaseAddress}. Start the agent service " +
                $"(uvicorn main:app --port 8001) and retry. {ex.Message}");
        }

        // Every outcome of a run - ready, awaiting approval, rejected by the
        // safety gate, failed safely - comes back 200 with a full trace. A
        // non-200 means the request itself was malformed or the service broke.
        var body = await response.Content.ReadAsStringAsync(ct);
        if (response.StatusCode != HttpStatusCode.OK)
            return ScheduleCopilotResult.Failed(
                $"Schedule Copilot returned HTTP {(int)response.StatusCode}: {Truncate(body, 300)}");

        try
        {
            using var doc = JsonDocument.Parse(body);
            var status = doc.RootElement.TryGetProperty("status", out var s) ? s.GetString() : null;
            if (string.IsNullOrEmpty(status))
                return ScheduleCopilotResult.Failed("Schedule Copilot returned a trace with no status.");
            return ScheduleCopilotResult.Ok(body, status);
        }
        catch (JsonException ex)
        {
            return ScheduleCopilotResult.Failed($"Schedule Copilot returned an unreadable response: {ex.Message}");
        }
    }

    private static string Truncate(string value, int max) => value.Length <= max ? value : value[..max] + "…";
}

public record ScheduleDateRangeDto(DateOnly DateFrom, DateOnly DateTo);

public record ScheduleConstraintsDto(
    ScheduleDateRangeDto DateRange,
    List<string> ResourceIds,
    List<string> PriorityRules,
    string BookingTypeId,
    int TargetCount,
    int DurationMinutes,
    string? BranchId);

/// The spec 2.7 Planner input contract: { objective, constraints: { dateRange,
/// resources[], priorityRules[] }, tenantId }. AuthToken is the calling
/// manager's own JWT, forwarded so every read the agents make carries that
/// manager's real identity; the agent service never echoes it back.
public record ScheduleCopilotRequest(
    string Objective,
    string TenantId,
    string BusinessType,
    ScheduleConstraintsDto Constraints,
    string Currency,
    string AuthToken);

/// The trace is kept as the agent service's own JSON rather than mirrored
/// into C# types: ASP.NET Core stores and serves it, it does not interpret
/// it beyond the handful of fields read in the controller.
public record ScheduleCopilotResult(bool Success, string? TraceJson, string? Status, string? ErrorMessage)
{
    public static ScheduleCopilotResult Ok(string traceJson, string status) => new(true, traceJson, status, null);
    public static ScheduleCopilotResult Failed(string message) => new(false, null, null, message);
}

public record AgentPlanResult(bool Success, WorkflowTraceDto? Trace, string? ErrorMessage)
{
    public static AgentPlanResult Ok(WorkflowTraceDto trace) => new(true, trace, null);
    public static AgentPlanResult Failed(string message) => new(false, null, message);
}

// ── Request/response DTOs mirroring agentic-ai-service/schemas/contracts.py ──
public record AgentPlanRequest(
    string Objective,
    Guid TenantId,
    string BusinessType,
    Guid? BranchId,
    Guid CustomerId,
    DateTime? DateFrom,
    DateTime? DateTo,
    Dictionary<string, object> ExtraConstraints,
    string AuthToken
);

public record PlanStepDto(int Order, string Action, string AssignedAgent, string Description);
/// Mirrors the spec's planner output contract:
/// { plan, assignedAgents, predictedConflicts, confidenceScore }.
public record PredictedConflictDto(string Kind, string Description, string? ResourceId, double Likelihood);
public record PlannerOutputDto(
    List<PlanStepDto> Plan,
    List<string> AssignedAgents,
    List<PredictedConflictDto> PredictedConflicts,
    double ConfidenceScore);

public record RankedCandidateDto(string ResourceId, string ResourceName, double Score, string Reasoning);
public record DomainAnalysisOutputDto(List<RankedCandidateDto> RankedCandidates, List<string> RankingCriteriaUsed);

public record ProposedBookingDto(
    string ResourceId, string? ResourceName, string BookingTypeId, DateTime ScheduledDatetime,
    int DurationMinutes, bool HasConflict, string? ConflictReason
);
public record ActionToolOutputDto(List<ProposedBookingDto> ProposedBookings, double Confidence);

public record ValidationSafetyOutputDto(
    bool IsAllowed, bool RequiresHumanApproval, string? RejectionReason,
    List<string> ValidationNotes, string? BookingId
);

public record ToolCallRecordDto(string Tool, string Agent, int DurationMs, bool Success, string? Error);

// One attempt against one model. Several entries for a single logical step
// is the agent service's retry/fallback layer working, not a fault.
public record LlmCallRecordDto(string Model, int Attempt, int DurationMs, bool Ok, string? Error);

// Wall-clock cost of one agent, recorded whether or not it succeeded, so a
// failed run can say which agent it died in.
public record AgentStepRecordDto(string Agent, int DurationMs, bool Ok, string? Error);

public record WorkflowTraceDto(
    string WorkflowId,
    string Objective,
    string TenantId,
    string BusinessType,
    string Status,
    PlannerOutputDto? PlannerOutput,
    DomainAnalysisOutputDto? DomainAnalysisOutput,
    ActionToolOutputDto? ActionToolOutput,
    ValidationSafetyOutputDto? ValidationOutput,
    List<ToolCallRecordDto> ToolCalls,
    List<LlmCallRecordDto>? LlmCalls,
    List<AgentStepRecordDto>? AgentSteps,
    string? Error,
    DateTime CreatedAt,
    DateTime? CompletedAt
);
