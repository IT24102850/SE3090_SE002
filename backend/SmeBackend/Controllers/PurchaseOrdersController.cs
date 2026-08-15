using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/purchase-orders")]
public sealed class PurchaseOrdersController(
    AppDbContext db,
    IAuthorizationService authorizationService) : ControllerBase
{
    private const int MaxPageSize = 100;
    private static readonly string[] AllowedStatuses =
    [
        "Draft",
        "InReview",
        "Placed",
        "InTransit",
        "Received",
        "Cancelled",
    ];

    [HttpGet]
    public async Task<ActionResult<PurchaseOrderListResponse>> GetPurchaseOrders(
        [FromQuery] Guid? branchId = null,
        [FromQuery] Guid? supplierId = null,
        [FromQuery] string? status = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.PurchaseOrderRead,
                tenantId,
                branchId))
        {
            return Forbid();
        }

        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);

        var query = db.PurchaseOrders.AsNoTracking();

        if (branchId.HasValue)
        {
            query = query.Where(order => order.BranchId == branchId.Value);
        }

        if (supplierId.HasValue)
        {
            query = query.Where(order => order.SupplierId == supplierId.Value);
        }

        if (!string.IsNullOrWhiteSpace(status))
        {
            if (!TryNormalizeStatus(status, out var normalizedStatus))
            {
                AddStatusValidationError();
                return ValidationProblem(ModelState);
            }

            query = query.Where(order => order.Status == normalizedStatus);
        }

        var totalCount = await query.CountAsync(cancellationToken);
        var orders = await query
            .OrderByDescending(order => order.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(cancellationToken);

        var responses = await ToResponsesAsync(orders, cancellationToken);
        var totalPages = (int)Math.Ceiling(totalCount / (double)pageSize);

        return Ok(new PurchaseOrderListResponse(
            responses,
            page,
            pageSize,
            totalCount,
            totalPages));
    }

    [HttpPost]
    public async Task<ActionResult<PurchaseOrderResponse>> CreatePurchaseOrder(
        CreatePurchaseOrderRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.PurchaseOrderWrite,
                tenantId,
                request.BranchId))
        {
            return Forbid();
        }

        var number = request.Number?.Trim();
        if (string.IsNullOrWhiteSpace(number))
        {
            ModelState.AddModelError("number", "Number is required.");
            return ValidationProblem(ModelState);
        }

        if (!await db.Branches.AnyAsync(
                branch => branch.TenantId == tenantId && branch.Id == request.BranchId,
                cancellationToken))
        {
            ModelState.AddModelError("branchId", "The branch does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        if (!await db.Suppliers.AnyAsync(
                supplier => supplier.Id == request.SupplierId,
                cancellationToken))
        {
            ModelState.AddModelError("supplierId", "The supplier does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        if (!TryNormalizeStatus(request.Status, out var status))
        {
            AddStatusValidationError();
            return ValidationProblem(ModelState);
        }

        if (await db.PurchaseOrders.IgnoreQueryFilters()
            .AnyAsync(order => order.TenantId == tenantId && order.Number == number, cancellationToken))
        {
            return Conflict(new { message = $"A purchase order with number '{number}' already exists." });
        }

        var order = new PurchaseOrder
        {
            BranchId = request.BranchId,
            SupplierId = request.SupplierId,
            Number = number,
            Status = status,
        };

        db.PurchaseOrders.Add(order);
        await db.SaveChangesAsync(cancellationToken);

        var response = (await ToResponsesAsync([order], cancellationToken)).Single();
        return CreatedAtAction(nameof(GetPurchaseOrders), new { }, response);
    }

    [HttpPut("{id:guid}/status")]
    public async Task<ActionResult<PurchaseOrderResponse>> UpdatePurchaseOrderStatus(
        Guid id,
        UpdatePurchaseOrderStatusRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var order = await db.PurchaseOrders
            .SingleOrDefaultAsync(candidate => candidate.Id == id, cancellationToken);

        if (order is null)
        {
            return NotFound();
        }

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.PurchaseOrderWrite,
                tenantId,
                order.BranchId))
        {
            return Forbid();
        }

        if (!TryNormalizeStatus(request.Status, out var status))
        {
            AddStatusValidationError();
            return ValidationProblem(ModelState);
        }

        order.Status = status;
        order.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(cancellationToken);

        var response = (await ToResponsesAsync([order], cancellationToken)).Single();
        return Ok(response);
    }

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);

    private async Task<IReadOnlyList<PurchaseOrderResponse>> ToResponsesAsync(
        IReadOnlyList<PurchaseOrder> orders,
        CancellationToken cancellationToken)
    {
        var branchIds = orders.Select(order => order.BranchId).Distinct().ToList();
        var supplierIds = orders.Select(order => order.SupplierId).Distinct().ToList();

        var branches = await db.Branches
            .AsNoTracking()
            .Where(branch => branchIds.Contains(branch.Id))
            .ToDictionaryAsync(branch => branch.Id, branch => branch.Name, cancellationToken);

        var suppliers = await db.Suppliers
            .AsNoTracking()
            .Where(supplier => supplierIds.Contains(supplier.Id))
            .ToDictionaryAsync(supplier => supplier.Id, supplier => supplier.Name, cancellationToken);

        return orders
            .Select(order => new PurchaseOrderResponse(
                order.Id,
                order.Number,
                order.BranchId,
                branches.GetValueOrDefault(order.BranchId),
                order.SupplierId,
                suppliers.GetValueOrDefault(order.SupplierId),
                order.Status,
                order.CreatedAt,
                order.UpdatedAt))
            .ToList();
    }

    private static bool TryNormalizeStatus(string? status, out string normalizedStatus)
    {
        if (string.IsNullOrWhiteSpace(status))
        {
            normalizedStatus = "Draft";
            return true;
        }

        var requested = status.Trim().Replace(" ", string.Empty).Replace("-", string.Empty);
        var match = AllowedStatuses.FirstOrDefault(allowed =>
            string.Equals(allowed, requested, StringComparison.OrdinalIgnoreCase));

        normalizedStatus = match ?? string.Empty;
        return match is not null;
    }

    private void AddStatusValidationError() =>
        ModelState.AddModelError("status", $"Status must be one of: {string.Join(", ", AllowedStatuses)}.");
}

public sealed record PurchaseOrderListResponse(
    IReadOnlyList<PurchaseOrderResponse> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages);

public sealed record PurchaseOrderResponse(
    Guid Id,
    string Number,
    Guid BranchId,
    string? Branch,
    Guid SupplierId,
    string? Supplier,
    string Status,
    DateTime CreatedAt,
    DateTime UpdatedAt);

public sealed record CreatePurchaseOrderRequest(
    Guid BranchId,
    Guid SupplierId,
    string? Number,
    string? Status = null);

public sealed record UpdatePurchaseOrderStatusRequest(string? Status);
