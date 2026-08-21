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
}

/// Calls the internal agentic-ai-service's POST /plan, which runs the full
/// Planner -> Domain Analysis -> Action/Tool -> Validation/Safety pipeline
/// synchronously and returns one complete trace. Never throws on a
/// "the AI service said no"-shaped outcome — always returns a typed
/// AgentPlanResult so callers can fail the request safely (matches the
/// Python service's own "never crash, always a structured outcome" rule).
public class PlannerAgentService : IPlannerAgentService
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
public record PlannerOutputDto(List<PlanStepDto> Plan, List<string> AssignedAgents, double Confidence);

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
    string? Error,
    DateTime CreatedAt,
    DateTime? CompletedAt
);
