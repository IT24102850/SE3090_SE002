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

    /// Disruption Recovery Copilot: a resource is out of service, re-place its bookings.
    Task<ScheduleCopilotResult> PlanDisruptionAsync(DisruptionCopilotRequest request, CancellationToken ct = default);
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
        var baseUrl = config["AgentService:BaseUrl"] ?? "https://sme-agentic-ai.onrender.com";
        http.BaseAddress = new Uri(baseUrl);
        // 60s was not enough and produced a confusing failure: the pipeline
        // went on to finish and return 200 while this client had already
        // given up, so a booking the agents had planned was reported as
        // unreachable. A full run is four agents, up to six tool turns each,
        // and a Gemini call that is allowed 30s and retried across three
        // models - comfortably past a minute whenever the free tier is
        // rate-limiting.
        //
        // The budget is layered so the innermost failure is the one the user
        // sees: Gemini 30s per call < this 150s < the mobile client's 180s.
        // Raising this above the client's budget would only swap a clear
        // message for a silent client-side timeout.
        http.Timeout = TimeSpan.FromSeconds(config.GetValue("AgentService:TimeoutSeconds", 150));
        _http = http;
    }

    public async Task<AgentPlanResult> PlanAsync(AgentPlanRequest request, CancellationToken ct = default)
    {
        var token = _config["AgentService:InternalToken"];
        if (string.IsNullOrEmpty(token))
            return AgentPlanResult.Failed("AgentService:InternalToken is not configured.");

        var (response, sendError) = await SendWithWakeRetryAsync(
            () =>
            {
                var message = new HttpRequestMessage(HttpMethod.Post, "/plan")
                {
                    Content = JsonContent.Create(request, options: JsonOptions),
                };
                message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                return message;
            },
            ct);

        if (response == null)
            return AgentPlanResult.Failed($"Could not reach the AI planning service: {sendError}");

        // The Python service returns 422 for a legitimate, structured safe
        // failure (still a full trace with `error` set) — that's a normal
        // outcome to hand back to the caller, not an exception here.
        if (response.StatusCode != HttpStatusCode.OK && response.StatusCode != HttpStatusCode.UnprocessableEntity)
            return AgentPlanResult.Failed(DescribeUpstreamFailure(
                "The AI planning service",
                response.StatusCode,
                await response.Content.ReadAsStringAsync(ct)));

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

        var (response, sendError) = await SendWithWakeRetryAsync(
            () =>
            {
                var message = new HttpRequestMessage(HttpMethod.Post, "/schedule/plan")
                {
                    Content = JsonContent.Create(request, options: JsonOptions),
                };
                message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                return message;
            },
            ct);

        if (response == null)
            return ScheduleCopilotResult.Failed(
                $"Could not reach the deployed Schedule Copilot at {_http.BaseAddress}. " +
                $"Verify the agent service is running and retry. {sendError}");

        // Every outcome of a run - ready, awaiting approval, rejected by the
        // safety gate, failed safely - comes back 200 with a full trace. A
        // non-200 means the request itself was malformed or the service broke.
        var body = await response.Content.ReadAsStringAsync(ct);
        if (response.StatusCode != HttpStatusCode.OK)
            return ScheduleCopilotResult.Failed(
                DescribeUpstreamFailure("Schedule Copilot", response.StatusCode, body));

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

    /// <summary>
    /// Runs the Disruption Recovery Copilot. Identical contract to the
    /// Schedule Copilot: every outcome of a run - awaiting approval,
    /// rejected by the gate, nothing to do, or a safe failure - comes back
    /// 200 with a full trace, which the caller persists.
    /// </summary>
    public async Task<ScheduleCopilotResult> PlanDisruptionAsync(DisruptionCopilotRequest request, CancellationToken ct = default)
    {
        var token = _config["AgentService:InternalToken"];
        if (string.IsNullOrEmpty(token))
            return ScheduleCopilotResult.Failed("AgentService:InternalToken is not configured.");

        var (response, sendError) = await SendWithWakeRetryAsync(
            () =>
            {
                var message = new HttpRequestMessage(HttpMethod.Post, "/disruption/plan")
                {
                    Content = JsonContent.Create(request, options: JsonOptions),
                };
                message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                return message;
            },
            ct);

        if (response == null)
            return ScheduleCopilotResult.Failed(
                $"Could not reach the deployed Disruption Copilot at {_http.BaseAddress}. " +
                $"Verify the agent service is running and retry. {sendError}");

        var body = await response.Content.ReadAsStringAsync(ct);
        if (response.StatusCode != HttpStatusCode.OK)
            return ScheduleCopilotResult.Failed(
                DescribeUpstreamFailure("Disruption Copilot", response.StatusCode, body));

        try
        {
            using var doc = JsonDocument.Parse(body);
            var status = doc.RootElement.TryGetProperty("status", out var s) ? s.GetString() : null;
            if (string.IsNullOrEmpty(status))
                return ScheduleCopilotResult.Failed("Disruption Copilot returned a trace with no status.");
            return ScheduleCopilotResult.Ok(body, status);
        }
        catch (JsonException ex)
        {
            return ScheduleCopilotResult.Failed($"Disruption Copilot returned an unreadable response: {ex.Message}");
        }
    }

    // The free hosting tier stops the agent service after ~15 minutes of no
    // traffic and needs about 25 seconds to boot it again. Requests that land
    // during that boot are answered by the host's edge rather than by the
    // service: HTTP 502 with an HTML error page. The call that triggers the
    // wake is therefore doomed by design, and retrying is the whole fix -
    // by the second or third attempt the container is serving.
    //
    // Measured cold start was 23s, so the delays below cover ~35s of booting
    // while staying far inside this client's 150s timeout and the mobile
    // client's 180s budget.
    private static readonly TimeSpan[] WakeRetryDelays =
    {
        TimeSpan.FromSeconds(5),
        TimeSpan.FromSeconds(10),
        TimeSpan.FromSeconds(20),
    };

    // Only the gateway codes are worth retrying: they are the host saying it
    // has nothing to route to yet. A 401, 422 or 500 came from the service
    // itself and means something a retry cannot repair.
    private static bool IsGatewayError(HttpStatusCode code) =>
        code is HttpStatusCode.BadGateway
            or HttpStatusCode.ServiceUnavailable
            or HttpStatusCode.GatewayTimeout;

    /// Sends the request, re-sending it while the upstream is still waking.
    /// Returns a null response with the transport error when the service could
    /// not be reached at all, so callers keep their "never throw" contract.
    /// The request is rebuilt per attempt because an HttpRequestMessage cannot
    /// be sent twice.
    private async Task<(HttpResponseMessage? Response, string? Error)> SendWithWakeRetryAsync(
        Func<HttpRequestMessage> buildRequest,
        CancellationToken ct)
    {
        HttpResponseMessage? response = null;
        for (var attempt = 0; ; attempt++)
        {
            response?.Dispose();
            using var message = buildRequest();
            try
            {
                response = await _http.SendAsync(message, ct);
            }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
            {
                return (null, ex.Message);
            }

            if (!IsGatewayError(response.StatusCode) || attempt >= WakeRetryDelays.Length)
                return (response, null);

            try
            {
                await Task.Delay(WakeRetryDelays[attempt], ct);
            }
            catch (OperationCanceledException)
            {
                // The caller gave up mid-wait; hand back what we have rather
                // than throwing out of a service that promises not to.
                return (response, null);
            }
        }
    }

    // A gateway error is a page from the host, not a payload from our service,
    // so its body is HTML. Pasting that into the UI produced the useless
    // "returned HTTP 502: <!DOCTYPE html>" the staff app was showing; say what
    // actually happened and what to do about it instead.
    private static string DescribeUpstreamFailure(string label, HttpStatusCode code, string body)
    {
        if (IsGatewayError(code))
            return $"{label} is still starting up and did not answer in time " +
                   $"(HTTP {(int)code} from the host after {WakeRetryDelays.Length + 1} attempts). " +
                   "The free hosting tier stops it when idle and it needs about half a minute " +
                   "to come back. Please try again.";

        return body.TrimStart().StartsWith('<')
            ? $"{label} returned HTTP {(int)code} from the host rather than from the service itself."
            : $"{label} returned HTTP {(int)code}: {Truncate(body, 300)}";
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
/// What the agent service's POST /disruption/plan expects. Serialized with
/// the snake_case policy, so these names reach Python as date_from, etc.
public record DisruptionCopilotRequest(
    string Objective,
    string TenantId,
    string BusinessType,
    string ResourceId,
    DisruptionWindowDto Window,
    string Reason,
    string? BranchId,
    string AuthToken);

public record DisruptionWindowDto(
    string DateFrom,
    string DateTo,
    string? StartsAt = null,
    string? EndsAt = null);

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
