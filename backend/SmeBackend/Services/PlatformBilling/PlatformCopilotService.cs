using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services.Billing;

namespace SmeBackend.Services.PlatformBilling;

/// The ASP.NET Core half of the Platform Operations Copilot.
///
/// It owns the two things the Python service deliberately cannot do:
/// persisting the workflow, and carrying an approved intervention out. The
/// split is the security boundary, not an accident of layering - the agent
/// service holds no database credentials and has no write tool, so the only
/// way anything it proposes reaches a tenant is through this class, called by
/// a controller that has already demanded a fresh authenticator code.
public interface IPlatformCopilotService
{
    Task<BillingResult<PlatformAgentWorkflow>> StartAsync(
        Guid actorUserId, string actorEmail, string ownerToken, StartCopilotRequest request, CancellationToken ct = default);

    Task<IReadOnlyList<PlatformAgentWorkflow>> HistoryAsync(int take = 25, CancellationToken ct = default);

    Task<PlatformAgentWorkflow?> GetAsync(Guid id, CancellationToken ct = default);

    /// Carries out the interventions the owner picked. Only ever reached from
    /// a controller action that has already verified a fresh TOTP code.
    Task<BillingResult<PlatformAgentWorkflow>> ApplyApprovedAsync(
        Guid id, Guid actorUserId, string actorEmail, IReadOnlyList<string> approvedTenantIds, string? reason,
        CancellationToken ct = default);

    Task<BillingResult<PlatformAgentWorkflow>> RecordDecisionAsync(
        Guid id, Guid actorUserId, string actorEmail, string decision, string? reason, CancellationToken ct = default);
}

public sealed record StartCopilotRequest(string Objective, int MaxInterventions = 5, int MaxCompMonths = 12, string Currency = "LKR");

public sealed class PlatformCopilotService : IPlatformCopilotService
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = new SnakeCaseNamingPolicy(),
        PropertyNameCaseInsensitive = true,
    };

    private readonly AppDbContext _db;
    private readonly HttpClient _http;
    private readonly IConfiguration _config;
    private readonly IEntitlementService _entitlements;
    private readonly ILogger<PlatformCopilotService> _logger;

    public PlatformCopilotService(HttpClient http, AppDbContext db, IConfiguration config,
        IEntitlementService entitlements, ILogger<PlatformCopilotService> logger)
    {
        _db = db;
        _config = config;
        _entitlements = entitlements;
        _logger = logger;

        var baseUrl = config["AgentService:BaseUrl"] ?? "https://sme-agentic-ai.onrender.com";
        http.BaseAddress = new Uri(baseUrl.TrimEnd('/'));
        // The pipeline makes several model calls in sequence; the ceiling
        // matches the other agent flows rather than inventing a new one.
        http.Timeout = TimeSpan.FromSeconds(config.GetValue("AgentService:TimeoutSeconds", 150));
        _http = http;
    }

    // ── Starting a run ───────────────────────────────────────────────────

    public async Task<BillingResult<PlatformAgentWorkflow>> StartAsync(
        Guid actorUserId, string actorEmail, string ownerToken, StartCopilotRequest request, CancellationToken ct = default)
    {
        var objective = (request.Objective ?? string.Empty).Trim();
        if (objective.Length < 8)
            return BillingResult<PlatformAgentWorkflow>.BadRequest("Describe what you want the copilot to look into.");
        if (objective.Length > 1000)
            return BillingResult<PlatformAgentWorkflow>.BadRequest("That objective is too long; keep it under 1000 characters.");

        var token = _config["AgentService:InternalToken"];
        if (string.IsNullOrEmpty(token))
            return BillingResult<PlatformAgentWorkflow>.Unavailable("AgentService:InternalToken is not configured.");

        var body = new
        {
            objective,
            actor_email = actorEmail,
            // Clamped here as well as in the agent service. The ceilings are
            // a spending control, and a spending control enforced only on the
            // far side of an HTTP call is not a control.
            max_interventions = Math.Clamp(request.MaxInterventions, 1, 25),
            max_comp_months = Math.Clamp(request.MaxCompMonths, 1, 24),
            currency = string.IsNullOrWhiteSpace(request.Currency) ? "LKR" : request.Currency.Trim().ToUpperInvariant(),
            auth_token = ownerToken,
        };

        HttpResponseMessage response;
        try
        {
            using var message = new HttpRequestMessage(HttpMethod.Post, "/platform/plan")
            {
                Content = JsonContent.Create(body),
            };
            message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            response = await _http.SendAsync(message, ct);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            return BillingResult<PlatformAgentWorkflow>.Unavailable(
                $"Could not reach the agent service: {ex.Message}");
        }

        if (response.StatusCode != HttpStatusCode.OK && response.StatusCode != HttpStatusCode.UnprocessableEntity)
        {
            var detail = await response.Content.ReadAsStringAsync(ct);
            return BillingResult<PlatformAgentWorkflow>.BadGateway(
                $"The agent service returned {(int)response.StatusCode}: {Truncate(detail, 300)}");
        }

        JsonElement trace;
        try
        {
            trace = await response.Content.ReadFromJsonAsync<JsonElement>(cancellationToken: ct);
        }
        catch (JsonException ex)
        {
            return BillingResult<PlatformAgentWorkflow>.BadGateway($"The agent service returned unreadable JSON: {ex.Message}");
        }

        var workflow = Persist(trace, actorEmail);
        _db.PlatformAgentWorkflows.Add(workflow);
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation("Platform copilot run {TraceId} finished as {Status} for {Actor}.",
            workflow.TraceId, workflow.Status, actorEmail);

        return BillingResult<PlatformAgentWorkflow>.Created(workflow);
    }

    /// Maps the agent service's trace onto the stored record.
    ///
    /// Every field is read defensively: this is a response from another
    /// service, and a contract drift should degrade one column rather than
    /// lose the whole run.
    private static PlatformAgentWorkflow Persist(JsonElement trace, string actorEmail)
    {
        string? Raw(string name) => trace.TryGetProperty(name, out var v) && v.ValueKind is not JsonValueKind.Null
            ? v.GetRawText() : null;

        var status = trace.TryGetProperty("status", out var s) ? s.GetString() ?? "Failed" : "Failed";
        var safety = trace.TryGetProperty("safety_output", out var so) && so.ValueKind == JsonValueKind.Object ? so : (JsonElement?)null;

        decimal cost = 0m;
        if (safety is { } sv && sv.TryGetProperty("total_estimated_cost", out var c) && c.ValueKind == JsonValueKind.Number)
            cost = c.GetDecimal();

        // A run where every model call failed still produces a trace, because
        // the deterministic fallbacks carry it. Recording which happened is
        // what stops a fallback run being read as a reasoned one.
        var modelDriven = trace.TryGetProperty("llm_calls", out var llm)
                          && llm.ValueKind == JsonValueKind.Array
                          && llm.EnumerateArray().Any(x => x.TryGetProperty("ok", out var ok) && ok.ValueKind == JsonValueKind.True);

        var observability = new
        {
            tool_calls = Raw("tool_calls"),
            llm_calls = Raw("llm_calls"),
            agent_steps = Raw("agent_steps"),
        };

        return new PlatformAgentWorkflow
        {
            TraceId = trace.TryGetProperty("workflow_id", out var w) ? w.GetString() ?? "" : "",
            Objective = trace.TryGetProperty("objective", out var o) ? o.GetString() ?? "" : "",
            Status = status switch
            {
                "AwaitingApproval" => PlatformWorkflowStatuses.AwaitingApproval,
                "NothingToDo" => PlatformWorkflowStatuses.NothingToDo,
                "Rejected" => PlatformWorkflowStatuses.Rejected,
                _ => PlatformWorkflowStatuses.Failed,
            },
            PlanJson = Raw("planner_output"),
            AnalysisJson = Raw("analysis_output"),
            ProposalsJson = Raw("action_output"),
            ValidationJson = Raw("safety_output"),
            ObservabilityJson = JsonSerializer.Serialize(observability),
            ErrorLog = trace.TryGetProperty("error", out var e) ? e.GetString() : null,
            ModelDriven = modelDriven,
            EstimatedCost = cost,
            CompletedAt = status is "AwaitingApproval" or "NothingToDo" or "Rejected" or "Failed" ? DateTime.UtcNow : null,
            DecidedByEmail = null,
        };
    }

    // ── Reading ──────────────────────────────────────────────────────────

    public async Task<IReadOnlyList<PlatformAgentWorkflow>> HistoryAsync(int take = 25, CancellationToken ct = default) =>
        await _db.PlatformAgentWorkflows.AsNoTracking()
            .OrderByDescending(w => w.CreatedAt)
            .Take(Math.Clamp(take, 1, 100))
            .ToListAsync(ct);

    public async Task<PlatformAgentWorkflow?> GetAsync(Guid id, CancellationToken ct = default) =>
        await _db.PlatformAgentWorkflows.AsNoTracking().FirstOrDefaultAsync(w => w.Id == id, ct);

    // ── Deciding ─────────────────────────────────────────────────────────

    public async Task<BillingResult<PlatformAgentWorkflow>> RecordDecisionAsync(
        Guid id, Guid actorUserId, string actorEmail, string decision, string? reason, CancellationToken ct = default)
    {
        var workflow = await _db.PlatformAgentWorkflows.FirstOrDefaultAsync(w => w.Id == id, ct);
        if (workflow is null) return BillingResult<PlatformAgentWorkflow>.NotFound("Workflow not found.");
        if (workflow.Status != PlatformWorkflowStatuses.AwaitingApproval)
            return BillingResult<PlatformAgentWorkflow>.BadRequest($"This run is '{workflow.Status}', not awaiting approval.");

        workflow.Status = decision == "Rejected" ? PlatformWorkflowStatuses.Rejected : PlatformWorkflowStatuses.Revising;
        workflow.ApprovalStatus = decision;
        workflow.DecidedByUserId = actorUserId;
        workflow.DecidedByEmail = actorEmail;
        workflow.DecidedAt = DateTime.UtcNow;
        workflow.DecisionReason = reason;
        workflow.CompletedAt = DateTime.UtcNow;
        workflow.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        return BillingResult<PlatformAgentWorkflow>.Ok(workflow);
    }

    // ── Applying ─────────────────────────────────────────────────────────

    private sealed record AcceptedIntervention(
        string TenantId, string TenantName, string Kind, int? ExtendDays, string? CompPlanCode, int? CompMonths, string Rationale);

    /// Carries out the interventions the owner picked.
    ///
    /// Three things this does deliberately:
    ///
    ///   It re-reads the accepted set from the stored validation output
    ///   rather than trusting the request body. The client sends which
    ///   tenants to act on, never what to do to them - so a tampered request
    ///   can narrow the action set but can never widen it or change an
    ///   intervention into a more expensive one.
    ///
    ///   It applies each intervention independently and records the failures.
    ///   A tenant that was deleted between proposal and approval should not
    ///   stop the other four from being carried out.
    ///
    ///   It never suspends or deletes anything. The only writes reachable
    ///   from here extend a term or comp a plan - both reversible, both
    ///   additive for the tenant.
    public async Task<BillingResult<PlatformAgentWorkflow>> ApplyApprovedAsync(
        Guid id, Guid actorUserId, string actorEmail, IReadOnlyList<string> approvedTenantIds, string? reason,
        CancellationToken ct = default)
    {
        var workflow = await _db.PlatformAgentWorkflows.FirstOrDefaultAsync(w => w.Id == id, ct);
        if (workflow is null) return BillingResult<PlatformAgentWorkflow>.NotFound("Workflow not found.");
        if (workflow.Status != PlatformWorkflowStatuses.AwaitingApproval)
            return BillingResult<PlatformAgentWorkflow>.BadRequest($"This run is '{workflow.Status}', not awaiting approval.");

        var accepted = ReadAccepted(workflow.ValidationJson);
        if (accepted.Count == 0)
            return BillingResult<PlatformAgentWorkflow>.BadRequest("This run has nothing that passed validation.");

        var chosen = approvedTenantIds.Count == 0
            ? accepted
            : accepted.Where(a => approvedTenantIds.Contains(a.TenantId, StringComparer.OrdinalIgnoreCase)).ToList();

        if (chosen.Count == 0)
            return BillingResult<PlatformAgentWorkflow>.BadRequest("None of the chosen businesses are in this run's approved set.");

        var outcomes = new List<object>();
        var applied = 0;
        var failed = 0;

        foreach (var intervention in chosen)
        {
            var (ok, detail) = await ApplyOneAsync(intervention, actorEmail, ct);
            if (ok) applied++; else failed++;
            outcomes.Add(new
            {
                tenantId = intervention.TenantId,
                tenantName = intervention.TenantName,
                kind = intervention.Kind,
                applied = ok,
                detail,
            });
        }

        workflow.ApprovalStatus = "Approved";
        workflow.DecidedByUserId = actorUserId;
        workflow.DecidedByEmail = actorEmail;
        workflow.DecidedAt = DateTime.UtcNow;
        workflow.DecisionReason = reason;
        workflow.ApprovedInterventionsJson = JsonSerializer.Serialize(chosen);
        workflow.OutcomeJson = JsonSerializer.Serialize(outcomes);
        workflow.Status = failed == 0
            ? PlatformWorkflowStatuses.Applied
            : applied == 0 ? PlatformWorkflowStatuses.Failed : PlatformWorkflowStatuses.PartiallyApplied;
        workflow.CompletedAt = DateTime.UtcNow;
        workflow.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation("Platform copilot {Id} applied {Applied}/{Total} interventions for {Actor}.",
            id, applied, chosen.Count, actorEmail);

        return BillingResult<PlatformAgentWorkflow>.Ok(workflow);
    }

    private async Task<(bool Ok, string Detail)> ApplyOneAsync(AcceptedIntervention intervention, string actorEmail, CancellationToken ct)
    {
        if (!Guid.TryParse(intervention.TenantId, out var tenantId))
            return (false, "Not a valid business id.");

        // contact_owner and no_action are decisions, not writes. They are
        // recorded as carried out because the record is the point of them.
        if (intervention.Kind is "contact_owner" or "no_action" or "winback_offer")
            return (true, $"Recorded: {intervention.Kind.Replace('_', ' ')}.");

        var subscription = await _db.PlatformSubscriptions.FirstOrDefaultAsync(s => s.TenantId == tenantId, ct);
        if (subscription is null) return (false, "That business no longer has a subscription.");

        var now = DateTime.UtcNow;

        switch (intervention.Kind)
        {
            case "extend_term":
            {
                var days = Math.Clamp(intervention.ExtendDays ?? 0, 1, 90);
                if (subscription.Tier == 0) return (false, "That business is on the free plan; there is no term to extend.");
                var basis = subscription.CurrentPeriodEnd is { } end && end > now ? end : now;
                subscription.CurrentPeriodEnd = basis.AddDays(days);
                if (subscription.Status == PlatformSubscriptionStatuses.PastDue)
                {
                    subscription.Status = PlatformSubscriptionStatuses.Active;
                    subscription.GraceEndsAt = null;
                }
                subscription.UpdatedAt = now;
                Record(tenantId, subscription.Id, "extend", null, subscription.PlanCode, $"{days} days - {intervention.Rationale}", actorEmail);
                await _db.SaveChangesAsync(ct);
                _entitlements.Invalidate(tenantId);
                return (true, $"Term extended {days} days to {subscription.CurrentPeriodEnd:d MMM yyyy}.");
            }

            case "comp_plan":
            {
                var months = Math.Clamp(intervention.CompMonths ?? 0, 1, 24);
                var planCode = intervention.CompPlanCode ?? "";
                var plan = await _db.PlatformPlans.FirstOrDefaultAsync(p => p.Code == planCode, ct);
                if (plan is null) return (false, $"'{planCode}' is not a plan on this platform.");
                if (plan.Tier == 0) return (false, "Starter is already free.");

                var from = subscription.PlanCode;
                subscription.PlanId = plan.Id;
                subscription.PlanCode = plan.Code;
                subscription.Tier = plan.Tier;
                subscription.PriceId = null;
                subscription.Status = PlatformSubscriptionStatuses.Active;
                subscription.Amount = 0m;
                subscription.CurrentPeriodStart = now;
                subscription.CurrentPeriodEnd = now.AddMonths(months);
                subscription.TrialEndsAt = null;
                subscription.AutoRenew = true;
                subscription.CancelAtPeriodEnd = false;
                subscription.GraceEndsAt = null;
                subscription.IsComplimentary = true;
                subscription.ComplimentaryReason = $"Platform copilot: {intervention.Rationale}";
                subscription.UpdatedAt = now;
                Record(tenantId, subscription.Id, "comp", from, plan.Code, $"{months} months - {intervention.Rationale}", actorEmail);
                await _db.SaveChangesAsync(ct);
                _entitlements.Invalidate(tenantId);
                return (true, $"{plan.Name} comped free until {subscription.CurrentPeriodEnd:d MMM yyyy}.");
            }

            default:
                // Unreachable through the safety gate, which refuses anything
                // outside the allow-list. Present because "unreachable" is a
                // claim about today's code, and this is money.
                return (false, $"'{intervention.Kind}' is not an intervention this service can carry out.");
        }
    }

    private void Record(Guid tenantId, Guid subscriptionId, string kind, string? from, string to, string detail, string actorEmail) =>
        _db.PlatformSubscriptionEvents.Add(new PlatformSubscriptionEvent
        {
            TenantId = tenantId,
            SubscriptionId = subscriptionId,
            EventType = kind,
            FromPlanCode = from,
            ToPlanCode = to,
            ActorEmail = actorEmail,
            Detail = Truncate($"copilot: {detail}", 500),
        });

    private static List<AcceptedIntervention> ReadAccepted(string? validationJson)
    {
        if (string.IsNullOrWhiteSpace(validationJson)) return new List<AcceptedIntervention>();
        try
        {
            using var doc = JsonDocument.Parse(validationJson);
            if (!doc.RootElement.TryGetProperty("accepted", out var accepted) || accepted.ValueKind != JsonValueKind.Array)
                return new List<AcceptedIntervention>();

            var list = new List<AcceptedIntervention>();
            foreach (var item in accepted.EnumerateArray())
            {
                string? Str(string n) => item.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
                int? Num(string n) => item.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetInt32() : null;

                var tenantId = Str("tenant_id");
                var kind = Str("kind");
                if (tenantId is null || kind is null) continue;

                list.Add(new AcceptedIntervention(
                    tenantId, Str("tenant_name") ?? "(unnamed)", kind,
                    Num("extend_days"), Str("comp_plan_code"), Num("comp_months"),
                    Str("rationale") ?? ""));
            }
            return list;
        }
        catch (JsonException)
        {
            return new List<AcceptedIntervention>();
        }
    }

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max];
}
