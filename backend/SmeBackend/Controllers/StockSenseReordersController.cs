using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services.Inventory;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// <summary>
/// StockSense reorder workflow: a StockSense recommendation becomes a purchase
/// order only through this controller.
///
///   request (Flutter or React)  →  ReorderSafetyGate (deterministic)
///     → Rejected         recorded, nothing ordered
///     → AutoApproved     purchase order placed, recorded
///     → NeedsApproval    paused as AwaitingApproval; a Manager/Admin approves,
///                        rejects or asks for a revision in React; the
///                        requester is notified on their phone either way.
///
/// Every step is an AgentWorkflow row (objective prefixed with
/// <see cref="StockSenseWorkflows.ReorderPrefix"/>): the proposed lines, the gate's checks, the
/// decision, who approved it and the purchase order it produced. Prices are
/// always read from the database, never taken from the request.
/// </summary>
[ApiController]
[Authorize]
[Route("api/inventory/agent/reorders")]
[Produces("application/json")]
public sealed class StockSenseReordersController(
    AppDbContext db,
    IAuthorizationService authorizationService,
    IConfiguration configuration) : ControllerBase
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private ReorderSafetyGate.Thresholds Limits
    {
        get
        {
            var d = ReorderSafetyGate.Thresholds.Default;
            return new ReorderSafetyGate.Thresholds(
                configuration.GetValue("Inventory:ReorderApproval:MaxAutoApproveValue", d.MaxAutoApproveValue),
                configuration.GetValue("Inventory:ReorderApproval:MaxAutoApproveUnits", d.MaxAutoApproveUnits),
                configuration.GetValue("Inventory:ReorderApproval:MaxLineQuantity", d.MaxLineQuantity));
        }
    }

    /// <summary>Submits a reorder for the safety gate. Any user who may change inventory in the branch can ask.</summary>
    /// <response code="201">Recorded; the body says whether it was placed, paused for approval or rejected.</response>
    [HttpPost]
    [ProducesResponseType(typeof(ReorderWorkflowResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<ReorderWorkflowResponse>> RequestReorder(
        [FromBody] ReorderRequest request, CancellationToken ct)
    {
        if (!TryGetCaller(out var tenantId, out var userId)) return Unauthorized();
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService, InventoryAuthorizationPolicies.InventoryWrite, tenantId, request.BranchId))
            return Forbid();

        if (request.Lines.Select(l => l.InventoryItemId).Distinct().Count() != request.Lines.Count)
        {
            ModelState.AddModelError("lines", "Each item may appear only once.");
            return ValidationProblem(ModelState);
        }

        if (!await db.Branches.AnyAsync(b => b.TenantId == tenantId && b.Id == request.BranchId, ct))
        {
            ModelState.AddModelError("branchId", "The branch does not exist for this business.");
            return ValidationProblem(ModelState);
        }

        var supplier = await LoadSupplierFactsAsync(tenantId, request.SupplierId, ct);
        if (supplier is null)
        {
            ModelState.AddModelError("supplierId", "The supplier does not exist for this business.");
            return ValidationProblem(ModelState);
        }

        var itemIds = request.Lines.Select(l => l.InventoryItemId).ToList();
        var items = await db.InventoryItems.AsNoTracking()
            .Where(i => i.TenantId == tenantId && i.IsActive && itemIds.Contains(i.Id))
            .ToDictionaryAsync(i => i.Id, ct);
        var missing = itemIds.Where(id => !items.ContainsKey(id)).ToList();
        if (missing.Count > 0)
        {
            ModelState.AddModelError("lines", $"Unknown or inactive inventory item(s): {string.Join(", ", missing)}.");
            return ValidationProblem(ModelState);
        }

        var lines = request.Lines
            .Select(l => new ReorderSafetyGate.Line(l.InventoryItemId, items[l.InventoryItemId].Name,
                items[l.InventoryItemId].BranchId, l.Quantity, items[l.InventoryItemId].UnitCost))
            .ToList();
        var result = ReorderSafetyGate.Evaluate(lines, request.BranchId, supplier, Limits);

        var workflow = new AgentWorkflow
        {
            TenantId = tenantId,
            RequestedByUserId = userId,
            Objective = $"{StockSenseWorkflows.ReorderPrefix}{lines.Count} item(s) from {supplier.Name}",
            PlanJson = JsonSerializer.Serialize(new ReorderPlan(
                request.BranchId, supplier.Id, supplier.Name, request.AnalysisWorkflowId, request.Note,
                lines.Select(l => new ReorderPlanLine(l.InventoryItemId, l.Name, l.Quantity, l.UnitCost)).ToList(),
                result.TotalValue, result.TotalUnits), Json),
            ValidationResults = JsonSerializer.Serialize(result.Checks, Json),
            CurrentStep = 2,
        };

        switch (result.Decision)
        {
            case ReorderSafetyGate.Decision.Rejected:
                workflow.Status = "Rejected";
                workflow.ApprovalStatus = "NotRequired";
                workflow.ErrorLog = string.Join(" ", result.RejectionReasons);
                workflow.FinalOutcome = "Rejected by the safety gate; nothing was ordered.";
                workflow.CompletedAt = DateTime.UtcNow;
                db.AgentWorkflows.Add(workflow);
                break;

            case ReorderSafetyGate.Decision.NeedsApproval:
                workflow.Status = "AwaitingApproval";
                workflow.ApprovalStatus = "Pending";
                workflow.FinalOutcome = "Paused for approval: " + string.Join(" ", result.ApprovalReasons);
                db.AgentWorkflows.Add(workflow);
                NotificationHelper.Queue(db, tenantId, null, "WorkflowApproval", "Reorder needs approval",
                    $"{lines.Count} item(s) from {supplier.Name}, value {result.TotalValue:N2}. {string.Join(" ", result.ApprovalReasons)}");
                break;

            default:
                await using (var tx = await BeginTransactionAsync(ct))
                {
                    db.AgentWorkflows.Add(workflow);
                    var order = await PlacePurchaseOrderAsync(tenantId, request.BranchId, supplier.Id, lines, ct);
                    workflow.Status = "Completed";
                    workflow.ApprovalStatus = "NotRequired";
                    workflow.CurrentStep = 3;
                    workflow.ToolResultsJson = JsonSerializer.Serialize(new { purchaseOrderId = order.Id, purchaseOrderNumber = order.Number }, Json);
                    workflow.FinalOutcome = $"Within every limit - purchase order {order.Number} placed automatically.";
                    workflow.CompletedAt = DateTime.UtcNow;
                    NotificationHelper.Queue(db, tenantId, userId, "ReorderPlaced", "Reorder placed",
                        $"{order.Number}: {lines.Count} item(s) from {supplier.Name} were ordered.");
                    await db.SaveChangesAsync(ct);
                    if (tx is not null) await tx.CommitAsync(ct);
                }
                return CreatedAtAction(nameof(GetReorder), new { id = workflow.Id }, ToResponse(workflow));
        }

        await db.SaveChangesAsync(ct);
        return CreatedAtAction(nameof(GetReorder), new { id = workflow.Id }, ToResponse(workflow));
    }

    /// <summary>StockSense reorders, newest first. Filter by status, e.g. AwaitingApproval.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<ReorderWorkflowResponse>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<ReorderWorkflowResponse>>> ListReorders(
        [FromQuery] string? status, [FromQuery] Guid? branchId = null, [FromQuery] bool mine = false, CancellationToken ct = default)
    {
        if (!TryGetCaller(out var tenantId, out var userId)) return Unauthorized();
        // Admins see every branch unless they pick one; everyone else sees
        // their own branch - the same scope the rest of the inventory API uses.
        var scope = User.IsInRole(UserRole.Admin.ToString())
            ? branchId
            : branchId ?? (Guid.TryParse(User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value, out var own) ? own : null);
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService, InventoryAuthorizationPolicies.InventoryRead, tenantId, scope))
            return Forbid();

        var query = db.AgentWorkflows.AsNoTracking()
            .Where(w => w.TenantId == tenantId && w.Objective.StartsWith(StockSenseWorkflows.ReorderPrefix));
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(w => w.Status == status);
        if (mine) query = query.Where(w => w.RequestedByUserId == userId);

        var rows = await query.OrderByDescending(w => w.CreatedAt).Take(200).ToListAsync(ct);
        return Ok(rows.Select(ToResponse)
            .Where(r => scope is null || r.BranchId == scope)
            .Take(100)
            .ToList());
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(ReorderWorkflowResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ReorderWorkflowResponse>> GetReorder(Guid id, CancellationToken ct)
    {
        if (!TryGetCaller(out var tenantId, out _)) return Unauthorized();
        var workflow = await FindAsync(tenantId, id, ct);
        if (workflow is null) return NotFound();
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService, InventoryAuthorizationPolicies.InventoryRead, tenantId, Plan(workflow).BranchId))
            return Forbid();
        return Ok(ToResponse(workflow));
    }

    /// <summary>
    /// Approves a paused reorder and places the purchase order. The gate is run
    /// again first: a supplier deactivated or an item removed since the request
    /// turns the approval into a rejection instead of an order.
    /// </summary>
    /// <response code="409">The reorder is not awaiting approval.</response>
    [HttpPost("{id:guid}/approve")]
    [Authorize(Roles = "Admin,Manager")]
    [ProducesResponseType(typeof(ReorderWorkflowResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<ReorderWorkflowResponse>> Approve(Guid id, CancellationToken ct)
    {
        if (!TryGetCaller(out var tenantId, out var userId)) return Unauthorized();
        var workflow = await FindAsync(tenantId, id, ct);
        if (workflow is null) return NotFound();
        var plan = Plan(workflow);
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService, InventoryAuthorizationPolicies.PurchaseOrderWrite, tenantId, plan.BranchId))
            return Forbid();
        if (workflow.Status != "AwaitingApproval")
            return Conflict(new { message = $"This reorder is {workflow.Status}, not awaiting approval." });

        var supplier = await LoadSupplierFactsAsync(tenantId, plan.SupplierId, ct);
        var itemIds = plan.Lines.Select(l => l.InventoryItemId).ToList();
        var items = await db.InventoryItems.AsNoTracking()
            .Where(i => i.TenantId == tenantId && i.IsActive && itemIds.Contains(i.Id))
            .ToDictionaryAsync(i => i.Id, ct);
        var lines = plan.Lines
            .Select(l => new ReorderSafetyGate.Line(l.InventoryItemId, l.Name,
                items.TryGetValue(l.InventoryItemId, out var item) ? item.BranchId : Guid.Empty,
                items.ContainsKey(l.InventoryItemId) ? l.Quantity : 0m,
                items.TryGetValue(l.InventoryItemId, out var priced) ? priced.UnitCost : l.UnitCost))
            .ToList();
        var recheck = supplier is null
            ? null
            : ReorderSafetyGate.Evaluate(lines, plan.BranchId, supplier, Limits);

        workflow.ApprovedBy = userId;
        workflow.ApprovedAt = DateTime.UtcNow;
        workflow.ValidationResults = recheck is null ? workflow.ValidationResults : JsonSerializer.Serialize(recheck.Checks, Json);

        if (recheck is null || recheck.Decision == ReorderSafetyGate.Decision.Rejected)
        {
            workflow.Status = "Rejected";
            workflow.ApprovalStatus = "Approved";
            workflow.ErrorLog = recheck is null ? "The supplier no longer exists." : string.Join(" ", recheck.RejectionReasons);
            workflow.FinalOutcome = "Approved, but the safety gate now refuses it; nothing was ordered.";
            workflow.CompletedAt = DateTime.UtcNow;
            NotificationHelper.Queue(db, tenantId, workflow.RequestedByUserId, "WorkflowRejected", "Reorder could not be placed",
                workflow.ErrorLog);
            await db.SaveChangesAsync(ct);
            return Ok(ToResponse(workflow));
        }

        await using (var tx = await BeginTransactionAsync(ct))
        {
            var order = await PlacePurchaseOrderAsync(tenantId, plan.BranchId, plan.SupplierId, lines, ct);
            workflow.Status = "Completed";
            workflow.ApprovalStatus = "Approved";
            workflow.CurrentStep = 3;
            workflow.ToolResultsJson = JsonSerializer.Serialize(new { purchaseOrderId = order.Id, purchaseOrderNumber = order.Number }, Json);
            workflow.FinalOutcome = $"Approved - purchase order {order.Number} placed.";
            workflow.CompletedAt = DateTime.UtcNow;
            NotificationHelper.Queue(db, tenantId, workflow.RequestedByUserId, "WorkflowApproved", "Reorder approved",
                $"{order.Number} was placed with {plan.SupplierName}.");
            await db.SaveChangesAsync(ct);
            if (tx is not null) await tx.CommitAsync(ct);
        }
        return Ok(ToResponse(workflow));
    }

    /// <summary>Rejects a paused reorder. The reason is recorded and sent to the requester.</summary>
    [HttpPost("{id:guid}/reject")]
    [Authorize(Roles = "Admin,Manager")]
    [ProducesResponseType(typeof(ReorderWorkflowResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public Task<ActionResult<ReorderWorkflowResponse>> Reject(Guid id, [FromBody] ReorderDecisionRequest request, CancellationToken ct) =>
        CloseWithoutOrder(id, request, "Rejected", "Rejected", "WorkflowRejected", "Reorder rejected", ct);

    /// <summary>Sends a paused reorder back to the requester with what to change.</summary>
    [HttpPost("{id:guid}/revise")]
    [Authorize(Roles = "Admin,Manager")]
    [ProducesResponseType(typeof(ReorderWorkflowResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public Task<ActionResult<ReorderWorkflowResponse>> RequestRevision(Guid id, [FromBody] ReorderDecisionRequest request, CancellationToken ct) =>
        CloseWithoutOrder(id, request, "RevisionRequested", "RevisionRequested", "WorkflowRevision", "Reorder needs changes", ct);

    private async Task<ActionResult<ReorderWorkflowResponse>> CloseWithoutOrder(
        Guid id, ReorderDecisionRequest request, string status, string approvalStatus,
        string notificationType, string notificationTitle, CancellationToken ct)
    {
        if (!TryGetCaller(out var tenantId, out var userId)) return Unauthorized();
        var workflow = await FindAsync(tenantId, id, ct);
        if (workflow is null) return NotFound();
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService, InventoryAuthorizationPolicies.PurchaseOrderWrite, tenantId, Plan(workflow).BranchId))
            return Forbid();
        if (workflow.Status != "AwaitingApproval")
            return Conflict(new { message = $"This reorder is {workflow.Status}, not awaiting approval." });

        var reason = request.Reason.Trim();
        workflow.Status = status;
        workflow.ApprovalStatus = approvalStatus;
        workflow.ApprovedBy = userId;
        workflow.ApprovedAt = DateTime.UtcNow;
        workflow.FinalOutcome = $"{notificationTitle}: {reason}";
        workflow.CompletedAt = DateTime.UtcNow;
        NotificationHelper.Queue(db, tenantId, workflow.RequestedByUserId, notificationType, notificationTitle, reason);
        await db.SaveChangesAsync(ct);
        return Ok(ToResponse(workflow));
    }

    private async Task<PurchaseOrder> PlacePurchaseOrderAsync(
        Guid tenantId, Guid branchId, Guid supplierId, IReadOnlyList<ReorderSafetyGate.Line> lines, CancellationToken ct)
    {
        string number;
        do
        {
            number = $"SS-{DateTime.UtcNow:yyyyMMdd}-{Random.Shared.Next(1000, 9999)}";
        } while (await db.PurchaseOrders.IgnoreQueryFilters().AnyAsync(o => o.TenantId == tenantId && o.Number == number, ct));

        var order = new PurchaseOrder { TenantId = tenantId, BranchId = branchId, SupplierId = supplierId, Number = number, Status = "Placed" };
        order.Items = lines.Select(l => new PurchaseOrderItem
        {
            TenantId = tenantId,
            PurchaseOrderId = order.Id,
            InventoryItemId = l.InventoryItemId,
            Description = l.Name,
            Quantity = l.Quantity,
            UnitPrice = l.UnitCost ?? 0m,
            ReceivedQuantity = 0,
        }).ToList();
        db.PurchaseOrders.Add(order);
        db.PurchaseOrderItems.AddRange(order.Items);
        NotificationHelper.Queue(db, tenantId, null, "PurchaseOrderCreated", "New purchase order",
            $"{order.Number} was placed by StockSense with {order.Items.Count} line items.");
        return order;
    }

    private async Task<ReorderSafetyGate.SupplierFacts?> LoadSupplierFactsAsync(Guid tenantId, Guid supplierId, CancellationToken ct)
    {
        // The Supplier query filter hides inactive suppliers. The gate must see
        // them - an inactive supplier is a recorded rejection with a reason,
        // not "not found" - so the tenant check is made explicitly instead.
        var supplier = await db.Suppliers.IgnoreQueryFilters().AsNoTracking()
            .FirstOrDefaultAsync(s => s.TenantId == tenantId && s.Id == supplierId, ct);
        if (supplier is null) return null;
        var received = await db.PurchaseOrders.AsNoTracking()
            .CountAsync(o => o.TenantId == tenantId && o.SupplierId == supplierId && o.Status == "Received", ct);
        return new ReorderSafetyGate.SupplierFacts(supplier.Id, supplier.Name, supplier.IsActive, received);
    }

    // The in-memory provider the tests use has no transactions; PostgreSQL does.
    private async Task<Microsoft.EntityFrameworkCore.Storage.IDbContextTransaction?> BeginTransactionAsync(CancellationToken ct) =>
        db.Database.IsRelational() ? await db.Database.BeginTransactionAsync(ct) : null;

    private Task<AgentWorkflow?> FindAsync(Guid tenantId, Guid id, CancellationToken ct) =>
        db.AgentWorkflows.FirstOrDefaultAsync(w => w.Id == id && w.TenantId == tenantId && w.Objective.StartsWith(StockSenseWorkflows.ReorderPrefix), ct);

    internal static ReorderPlan Plan(AgentWorkflow workflow) =>
        JsonSerializer.Deserialize<ReorderPlan>(workflow.PlanJson ?? "{}", Json)!;

    internal static ReorderWorkflowResponse ToResponse(AgentWorkflow w)
    {
        var plan = Plan(w);
        var checks = JsonSerializer.Deserialize<List<ReorderSafetyGate.Check>>(w.ValidationResults ?? "[]", Json) ?? new();
        string? poNumber = null;
        Guid? poId = null;
        if (!string.IsNullOrEmpty(w.ToolResultsJson))
        {
            using var doc = JsonDocument.Parse(w.ToolResultsJson);
            if (doc.RootElement.TryGetProperty("purchaseOrderNumber", out var n)) poNumber = n.GetString();
            if (doc.RootElement.TryGetProperty("purchaseOrderId", out var p)) poId = p.GetGuid();
        }
        return new ReorderWorkflowResponse(w.Id, w.Status, w.ApprovalStatus, plan.BranchId, plan.SupplierId, plan.SupplierName,
            plan.Lines, plan.TotalValue, plan.TotalUnits, checks, w.FinalOutcome, w.ErrorLog, poId, poNumber,
            w.RequestedByUserId, w.ApprovedBy, w.ApprovedAt, w.CreatedAt, w.CompletedAt);
    }

    private bool TryGetCaller(out Guid tenantId, out Guid userId)
    {
        userId = Guid.Empty;
        return Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId)
            && Guid.TryParse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value, out userId);
    }
}

public sealed record ReorderLineRequest(
    Guid InventoryItemId,
    [Range(typeof(decimal), "0.001", "1000000")] decimal Quantity);

public sealed record ReorderRequest(
    Guid BranchId,
    Guid SupplierId,
    [Required, MinLength(1), MaxLength(50)] List<ReorderLineRequest> Lines,
    Guid? AnalysisWorkflowId = null,
    [MaxLength(500)] string? Note = null);

public sealed record ReorderDecisionRequest([Required, StringLength(500, MinimumLength = 3)] string Reason);

public sealed record ReorderPlanLine(Guid InventoryItemId, string Name, decimal Quantity, decimal? UnitCost);

public sealed record ReorderPlan(
    Guid BranchId, Guid SupplierId, string SupplierName, Guid? AnalysisWorkflowId, string? Note,
    List<ReorderPlanLine> Lines, decimal TotalValue, decimal TotalUnits);

public sealed record ReorderWorkflowResponse(
    Guid Id, string Status, string ApprovalStatus, Guid BranchId, Guid SupplierId, string SupplierName,
    IReadOnlyList<ReorderPlanLine> Lines, decimal TotalValue, decimal TotalUnits,
    IReadOnlyList<ReorderSafetyGate.Check> Checks, string? FinalOutcome, string? Error,
    Guid? PurchaseOrderId, string? PurchaseOrderNumber, Guid? RequestedBy, Guid? DecidedBy,
    DateTime? DecidedAt, DateTime CreatedAt, DateTime? CompletedAt);
