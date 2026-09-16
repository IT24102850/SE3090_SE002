using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

[ApiController]
[Authorize]
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
        branchId = ResolveBranchScope(branchId);

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

    /// <summary>Returns the tenant-scoped reference data required to create a purchase order.</summary>
    [HttpGet("options")]
    public async Task<ActionResult<PurchaseOrderOptionsResponse>> GetOptions(CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService, InventoryAuthorizationPolicies.PurchaseOrderRead, tenantId, null))
        {
            return Forbid();
        }

        var branches = await db.Branches.AsNoTracking()
            .OrderBy(branch => branch.Name)
            .Select(branch => new PurchaseOrderOption(branch.Id, branch.Name))
            .ToListAsync(cancellationToken);
        var suppliers = await db.Suppliers.AsNoTracking()
            .OrderBy(supplier => supplier.Name)
            .Select(supplier => new PurchaseOrderOption(supplier.Id, supplier.Name))
            .ToListAsync(cancellationToken);
        var items = await db.InventoryItems.AsNoTracking()
            .Where(item => item.IsActive)
            .OrderBy(item => item.Name)
            .Select(item => new PurchaseOrderItemOption(item.Id, item.Name, item.Sku, item.UnitCost, item.BranchId))
            .ToListAsync(cancellationToken);

        return Ok(new PurchaseOrderOptionsResponse(branches, suppliers, items));
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
                supplier => supplier.TenantId == tenantId && supplier.Id == request.SupplierId,
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
            TenantId = tenantId,
            BranchId = request.BranchId,
            SupplierId = request.SupplierId,
            Number = number,
            Status = status,
        };

        var itemsToCreate = new List<PurchaseOrderItem>();
        if (request.Items != null && request.Items.Count > 0)
        {
            var inventoryItemIds = request.Items
                .Where(i => i.InventoryItemId.HasValue)
                .Select(i => i.InventoryItemId!.Value)
                .Distinct()
                .ToList();

            var inventoryItemMap = inventoryItemIds.Count > 0
                ? await db.InventoryItems.AsNoTracking()
                    .Where(i => i.TenantId == tenantId && i.IsActive && inventoryItemIds.Contains(i.Id))
                    .ToDictionaryAsync(i => i.Id, cancellationToken)
                : new Dictionary<Guid, InventoryItem>();

            for (int i = 0; i < request.Items.Count; i++)
            {
                var itemReq = request.Items[i];
                if (itemReq.Quantity <= 0)
                {
                    ModelState.AddModelError($"items[{i}].quantity", "Quantity must be greater than 0.");
                    return ValidationProblem(ModelState);
                }
                if (itemReq.UnitPrice < 0)
                {
                    ModelState.AddModelError($"items[{i}].unitPrice", "Unit price cannot be negative.");
                    return ValidationProblem(ModelState);
                }
                string? desc = itemReq.Description?.Trim();
                if (itemReq.InventoryItemId.HasValue)
                {
                    if (!inventoryItemMap.TryGetValue(itemReq.InventoryItemId.Value, out var invItem))
                    {
                        ModelState.AddModelError($"items[{i}].inventoryItemId", "The specified inventory item does not exist for this tenant.");
                        return ValidationProblem(ModelState);
                    }
                    if (string.IsNullOrWhiteSpace(desc))
                    {
                        desc = invItem.Name;
                    }
                }
                else if (string.IsNullOrWhiteSpace(desc))
                {
                    ModelState.AddModelError($"items[{i}].description", "Description or InventoryItemId is required.");
                    return ValidationProblem(ModelState);
                }

                itemsToCreate.Add(new PurchaseOrderItem
                {
                    TenantId = tenantId,
                    PurchaseOrderId = order.Id,
                    InventoryItemId = itemReq.InventoryItemId,
                    Description = desc,
                    Quantity = itemReq.Quantity,
                    UnitPrice = itemReq.UnitPrice,
                    ReceivedQuantity = 0,
                });
            }
        }

        order.Items = itemsToCreate;
        NotificationHelper.Queue(db, tenantId, null, "PurchaseOrderCreated", "New purchase order", $"{order.Number} was created with {itemsToCreate.Count} line items.");
        db.PurchaseOrders.Add(order);
        if (itemsToCreate.Count > 0)
        {
            db.PurchaseOrderItems.AddRange(itemsToCreate);
        }
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
        if (string.Equals(status, "Received", StringComparison.OrdinalIgnoreCase))
        {
            await ReceiveInventoryAsync(order, tenantId, cancellationToken);
        }
        NotificationHelper.Queue(db, tenantId, null, "PurchaseOrderUpdated", "Purchase order updated", $"{order.Number} moved to {status}.");

        await db.SaveChangesAsync(cancellationToken);

        var response = (await ToResponsesAsync([order], cancellationToken)).Single();
        return Ok(response);
    }

    private async Task ReceiveInventoryAsync(
        PurchaseOrder order,
        Guid tenantId,
        CancellationToken cancellationToken)
    {
        var items = await db.PurchaseOrderItems
            .Where(item => item.PurchaseOrderId == order.Id)
            .ToListAsync(cancellationToken);

        foreach (var orderItem in items)
        {
            if (!orderItem.InventoryItemId.HasValue)
            {
                continue;
            }

            var inventoryItem = await db.InventoryItems
                .SingleOrDefaultAsync(item =>
                    item.TenantId == tenantId &&
                    item.Id == orderItem.InventoryItemId.Value,
                    cancellationToken);

            if (inventoryItem is null)
            {
                continue;
            }

            var remainingQuantity = orderItem.Quantity - orderItem.ReceivedQuantity;
            if (remainingQuantity <= 0)
            {
                continue;
            }

            // Inventory SKUs are tenant-unique, so receiving moves the selected
            // catalog item into the PO's branch. If it was catalogued under
            // another branch, the received quantity becomes that branch's stock.
            var movedFromAnotherBranch = inventoryItem.BranchId != order.BranchId;
            inventoryItem.BranchId = order.BranchId;
            inventoryItem.Quantity = movedFromAnotherBranch
                ? remainingQuantity
                : inventoryItem.Quantity + remainingQuantity;
            inventoryItem.UnitCost = orderItem.UnitPrice;
            orderItem.ReceivedQuantity += remainingQuantity;

            db.StockMovements.Add(new StockMovement
            {
                TenantId = tenantId,
                BranchId = order.BranchId,
                InventoryItemId = inventoryItem.Id,
                SupplierId = order.SupplierId,
                PurchaseOrderId = order.Id,
                MovementType = "PurchaseReceived",
                Quantity = remainingQuantity,
                UnitCost = orderItem.UnitPrice,
                Reference = order.Number,
                Notes = $"Received from purchase order {order.Number}.",
            });
        }
    }

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);

    private Guid? ResolveBranchScope(Guid? requestedBranchId)
    {
        if (User.IsInRole(UserRole.Admin.ToString()) || requestedBranchId.HasValue)
        {
            return requestedBranchId;
        }

        return Guid.TryParse(User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value, out var branchId)
            ? branchId
            : null;
    }

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

        var orderItems = await db.PurchaseOrderItems.AsNoTracking()
            .Where(item => orders.Select(order => order.Id).Contains(item.PurchaseOrderId))
            .OrderBy(item => item.CreatedAt)
            .ToListAsync(cancellationToken);

        var invItemIds = orderItems
            .Where(item => item.InventoryItemId.HasValue)
            .Select(item => item.InventoryItemId!.Value)
            .Distinct()
            .ToList();

        var invItemNames = invItemIds.Count > 0
            ? await db.InventoryItems.AsNoTracking()
                .Where(item => invItemIds.Contains(item.Id))
                .ToDictionaryAsync(item => item.Id, item => item.Name, cancellationToken)
            : new Dictionary<Guid, string>();

        var itemsByOrderId = orderItems
            .GroupBy(item => item.PurchaseOrderId)
            .ToDictionary(
                group => group.Key,
                group => (IReadOnlyList<PurchaseOrderItemResponse>)group.Select(item => new PurchaseOrderItemResponse(
                    item.Id,
                    item.InventoryItemId,
                    item.InventoryItemId.HasValue ? (invItemNames.GetValueOrDefault(item.InventoryItemId.Value) ?? item.Description) : item.Description,
                    item.Description,
                    item.Quantity,
                    item.UnitPrice,
                    item.Quantity * item.UnitPrice,
                    item.ReceivedQuantity
                )).ToList());

        return orders
            .Select(order =>
            {
                var items = itemsByOrderId.GetValueOrDefault(order.Id) ?? [];
                return new PurchaseOrderResponse(
                    order.Id,
                    order.Number,
                    order.BranchId,
                    branches.GetValueOrDefault(order.BranchId),
                    order.SupplierId,
                    suppliers.GetValueOrDefault(order.SupplierId),
                    order.Status,
                    items.Sum(item => item.LineTotal),
                    items.Count,
                    order.CreatedAt,
                    order.UpdatedAt,
                    items);
            })
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

public sealed record PurchaseOrderItemResponse(
    Guid Id,
    Guid? InventoryItemId,
    string? ItemName,
    string? Description,
    decimal Quantity,
    decimal UnitPrice,
    decimal LineTotal,
    decimal ReceivedQuantity);

public sealed record PurchaseOrderResponse(
    Guid Id,
    string Number,
    Guid BranchId,
    string? Branch,
    Guid SupplierId,
    string? Supplier,
    string Status,
    decimal TotalAmount,
    int LineItems,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    IReadOnlyList<PurchaseOrderItemResponse>? Items = null);

public sealed record PurchaseOrderOption(Guid Id, string Name);

public sealed record PurchaseOrderItemOption(
    Guid Id,
    string Name,
    string Sku,
    decimal? UnitCost,
    Guid? BranchId);

public sealed record PurchaseOrderOptionsResponse(
    IReadOnlyList<PurchaseOrderOption> Branches,
    IReadOnlyList<PurchaseOrderOption> Suppliers,
    IReadOnlyList<PurchaseOrderItemOption> Items);

public sealed record PurchaseOrderItemRequest(
    Guid? InventoryItemId,
    string? Description,
    decimal Quantity,
    decimal UnitPrice);

public sealed record CreatePurchaseOrderRequest(
    Guid BranchId,
    Guid SupplierId,
    string? Number,
    string? Status = null,
    IReadOnlyList<PurchaseOrderItemRequest>? Items = null);

public sealed record UpdatePurchaseOrderStatusRequest(string? Status);
