using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.DTOs;
using SmeBackend.Services.Billing;

namespace SmeBackend.Controllers;

/// The billing Domain Analysis Agent (spec 3.7) and its approval queue.
[ApiController]
[Route("api/billing-agent")]
[Authorize(Policy = "ManagerPlus")]
[Produces("application/json")]
public class BillingAgentController : BillingControllerBase
{
    private readonly IBillingAgentService _agent;
    private readonly IBillingApprovalService _approvals;

    public BillingAgentController(IBillingAgentService agent, IBillingApprovalService approvals)
    {
        _agent = agent;
        _approvals = approvals;
    }

    /// <summary>
    /// Runs the agent. Input: { analysisType, dataRange, tenantId, thresholds }.
    /// Output: { anomalies, insights, recommendedActions, confidenceScore }.
    /// </summary>
    /// <remarks>analysisType: full | anomalies | revenue | insurance | pricing | commission.
    /// Every run is recorded in AgentWorkflows; actionable recommendations
    /// become approval requests.</remarks>
    [HttpPost("analyze")]
    [ProducesResponseType(typeof(BillingAnalysisResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<BillingAnalysisResponse>> Analyze([FromBody] BillingAnalysisRequest request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        if (!ModelState.IsValid) return BadRequest(ModelState);
        return FromResult(await _agent.AnalyzeAsync(actor, request, ct));
    }

    /// <summary>The agent's allow-listed tools.</summary>
    [HttpGet("tools")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public IActionResult Tools() => Ok(new
    {
        tools = BillingDomainAnalysisAgent.AllowedTools.OrderBy(t => t),
        analysisTypes = BillingAnalysisTypes.All.ToDictionary(t => t, t => BillingDomainAnalysisAgent.PlanFor(t)),
        defaultThresholds = ThresholdConfig.Default,
    });

    /// <summary>Billing workflows: analysis runs and approval requests.</summary>
    [HttpGet("workflows")]
    [ProducesResponseType(typeof(IReadOnlyList<BillingWorkflowResponse>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<BillingWorkflowResponse>>> Workflows(
        [FromQuery] string? kind = null, [FromQuery] string? status = null, [FromQuery] int take = 100, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return Ok(await _agent.GetWorkflowsAsync(actor.TenantId, kind, status, take, ct));
    }

    [HttpGet("workflows/{id:guid}")]
    [ProducesResponseType(typeof(BillingWorkflowResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<BillingWorkflowResponse>> Workflow(Guid id, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        return FromResult(await _agent.GetWorkflowAsync(actor.TenantId, id, ct));
    }

    /// <summary>
    /// Approves and applies a request. Requests above the thresholds
    /// (adjustment &gt; 100, claim &gt; 500, cancellation with refund) need an Admin.
    /// </summary>
    [HttpPost("workflows/{id:guid}/approve")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Approve(Guid id, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var (_, status, message) = await _approvals.ApproveAsync(actor.TenantId, id, actor.UserId, actor.Role, ct);
        return StatusCode(status, new { message, id });
    }

    [HttpPost("workflows/{id:guid}/reject")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> Reject(Guid id, [FromBody] RejectBillingWorkflowRequest? request, CancellationToken ct = default)
    {
        if (Actor is not { } actor) return MissingTenant();
        var (_, status, message) = await _approvals.RejectAsync(actor.TenantId, id, actor.UserId, request?.Reason, ct);
        return StatusCode(status, new { message, id });
    }
}
