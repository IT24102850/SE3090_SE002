using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;
using SmeBackend.Services.PlatformBilling;

namespace SmeBackend.Controllers;

[ApiController]
[Authorize]
[Route("api/purchase-orders")]
// Paid feature: the tenant's Unify plan decides whether this module is
// available at all (Authorization/RequiresPlanAttribute.cs).
[RequiresPlanFeature(PlanFeatures.InventoryPro)]
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
        "PartiallyReceived",
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
            .Where(item => item.TenantId == tenantId && item.IsActive)
            .OrderBy(item => item.Name)
            .Select(item => new PurchaseOrderItemOption(
                item.Id,
                item.Name,
                item.Sku,
                item.UnitCost,
                item.BranchId,
                item.SupplierId))
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

        if (!string.Equals(status, "Draft", StringComparison.Ordinal))
        {
            ModelState.AddModelError("status", "New purchase orders must start as Draft and be submitted for review.");
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
                    if (invItem.BranchId != request.BranchId)
                    {
                        ModelState.AddModelError(
                            $"items[{i}].inventoryItemId",
                            "Choose an inventory item assigned to the purchase order's destination branch.");
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

        if (!IsAllowedStatusTransition(order.Status, status))
        {
            return Conflict(new { message = $"A purchase order cannot move from {order.Status} to {status}." });
        }

        if (string.Equals(status, "Placed", StringComparison.Ordinal) &&
            !User.IsInRole(UserRole.Admin.ToString()) &&
            !User.IsInRole(UserRole.Manager.ToString()))
        {
            return Forbid();
        }

        order.Status = status;
        order.UpdatedAt = DateTime.UtcNow;
        var actor = User.FindFirst("fullName")?.Value ?? User.Identity?.Name ?? "An authorized user";
        NotificationHelper.Queue(db, tenantId, null, "PurchaseOrderUpdated", "Purchase order updated", $"{order.Number} moved to {status} by {actor}.");

        await db.SaveChangesAsync(cancellationToken);

        var response = (await ToResponsesAsync([order], cancellationToken)).Single();
        return Ok(response);
    }

    [HttpPost("{id:guid}/receive")]
    public async Task<ActionResult<PurchaseOrderResponse>> ReceivePurchaseOrder(
        Guid id,
        ReceivePurchaseOrderRequest request,
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
                InventoryAuthorizationPolicies.InventoryWrite,
                tenantId,
                order.BranchId))
        {
            return Forbid();
        }

        if (order.Status is not ("Placed" or "InTransit" or "PartiallyReceived"))
        {
            return Conflict(new { message = "Only placed or in-transit purchase orders can be received." });
        }

        if (request.Items is null || request.Items.Count == 0)
        {
            ModelState.AddModelError("items", "Enter receiving details for at least one purchase order item.");
            return ValidationProblem(ModelState);
        }

        if (request.Items.GroupBy(item => item.PurchaseOrderItemId).Any(group => group.Count() > 1))
        {
            ModelState.AddModelError("items", "Each purchase order line can be submitted only once per receipt.");
            return ValidationProblem(ModelState);
        }

        var orderItems = await db.PurchaseOrderItems
            .Where(item => item.PurchaseOrderId == order.Id)
            .ToListAsync(cancellationToken);
        var orderItemsById = orderItems.ToDictionary(item => item.Id);
        var receipt = new PurchaseOrderReceipt
        {
            TenantId = tenantId,
            PurchaseOrderId = order.Id,
            ReceivedAt = DateTime.UtcNow,
            ReceivedBy = CurrentActorName(),
        };
        var inventoryItemIds = new HashSet<Guid>();
        var receiptInventoryItemIds = new Dictionary<Guid, Guid>();

        for (var index = 0; index < request.Items.Count; index++)
        {
            var received = request.Items[index];
            if (!orderItemsById.TryGetValue(received.PurchaseOrderItemId, out var orderItem))
            {
                ModelState.AddModelError($"items[{index}].purchaseOrderItemId", "This line does not belong to the purchase order.");
                continue;
            }

            if (received.DeliveredQuantity < 0 || received.DamagedQuantity < 0)
            {
                ModelState.AddModelError($"items[{index}]", "Delivered and damaged quantities cannot be negative.");
                continue;
            }
            if (received.Notes is { Length: > 1000 })
            {
                ModelState.AddModelError($"items[{index}].notes", "Notes cannot exceed 1000 characters.");
                continue;
            }
            if (received.DamagedQuantity > received.DeliveredQuantity)
            {
                ModelState.AddModelError($"items[{index}].damagedQuantity", "Damaged quantity cannot exceed delivered quantity.");
                continue;
            }
            if (received.DeliveredQuantity == 0 && received.DamagedQuantity > 0)
            {
                ModelState.AddModelError($"items[{index}].deliveredQuantity", "Enter the delivered quantity before recording damage.");
                continue;
            }
            if (received.DeliveredQuantity == 0 && !received.CloseRemainingAsShort)
            {
                continue;
            }
            if (orderItem.ReceivingClosed)
            {
                ModelState.AddModelError($"items[{index}]", "This purchase order line has already been fully accounted for.");
                continue;
            }

            var accountedQuantity = orderItem.ReceivedQuantity +
                                    orderItem.DamagedQuantity +
                                    orderItem.ShortageQuantity;
            var remainingQuantity = orderItem.Quantity - accountedQuantity;
            if (received.DeliveredQuantity > remainingQuantity)
            {
                ModelState.AddModelError(
                    $"items[{index}].deliveredQuantity",
                    $"Delivered quantity cannot exceed the remaining {remainingQuantity:0.###} units.");
                continue;
            }

            var acceptedQuantity = received.DeliveredQuantity - received.DamagedQuantity;
            if (received.InventoryItemId.HasValue &&
                orderItem.InventoryItemId.HasValue &&
                received.InventoryItemId != orderItem.InventoryItemId)
            {
                ModelState.AddModelError(
                    $"items[{index}].inventoryItemId",
                    "This purchase order line is already linked to a different inventory item.");
                continue;
            }

            var inventoryItemId = orderItem.InventoryItemId ?? received.InventoryItemId;
            if (acceptedQuantity > 0 && !inventoryItemId.HasValue)
            {
                ModelState.AddModelError(
                    $"items[{index}].inventoryItemId",
                    "Select an inventory item in the destination branch before accepting stock from this line.");
                continue;
            }

            if (inventoryItemId.HasValue)
            {
                inventoryItemIds.Add(inventoryItemId.Value);
                receiptInventoryItemIds[orderItem.Id] = inventoryItemId.Value;
            }

            var shortageQuantity = received.CloseRemainingAsShort
                ? remainingQuantity - received.DeliveredQuantity
                : 0m;
            orderItem.ReceivedQuantity += acceptedQuantity;
            orderItem.DamagedQuantity += received.DamagedQuantity;
            orderItem.ShortageQuantity += shortageQuantity;
            orderItem.ReceivingClosed =
                orderItem.ReceivedQuantity + orderItem.DamagedQuantity + orderItem.ShortageQuantity >= orderItem.Quantity;

            receipt.Items.Add(new PurchaseOrderReceiptItem
            {
                TenantId = tenantId,
                PurchaseOrderItemId = orderItem.Id,
                DeliveredQuantity = received.DeliveredQuantity,
                AcceptedQuantity = acceptedQuantity,
                DamagedQuantity = received.DamagedQuantity,
                ShortageQuantity = shortageQuantity,
                Notes = string.IsNullOrWhiteSpace(received.Notes) ? null : received.Notes.Trim(),
            });
        }

        if (!ModelState.IsValid)
        {
            return ValidationProblem(ModelState);
        }
        if (receipt.Items.Count == 0)
        {
            ModelState.AddModelError("items", "Enter a delivered quantity or close a line by recording its remaining units as short.");
            return ValidationProblem(ModelState);
        }

        var inventoryItems = inventoryItemIds.Count == 0
            ? new Dictionary<Guid, InventoryItem>()
            : await db.InventoryItems
                .Where(item => item.TenantId == tenantId && item.IsActive && inventoryItemIds.Contains(item.Id))
                .ToDictionaryAsync(item => item.Id, cancellationToken);

        foreach (var receiptItem in receipt.Items)
        {
            if (receiptItem.AcceptedQuantity <= 0) continue;

            var orderItem = orderItemsById[receiptItem.PurchaseOrderItemId];
            if (!receiptInventoryItemIds.TryGetValue(orderItem.Id, out var inventoryItemId)) continue;
            if (!inventoryItems.TryGetValue(inventoryItemId, out var inventoryItem))
            {
                ModelState.AddModelError("items", $"Inventory item for '{orderItem.Description}' is unavailable or inactive.");
                return ValidationProblem(ModelState);
            }
            if (!inventoryItem.BranchId.HasValue)
            {
                ModelState.AddModelError("items", $"Inventory item '{inventoryItem.Name}' must be assigned to a branch before receiving.");
                return ValidationProblem(ModelState);
            }
            if (inventoryItem.BranchId != order.BranchId)
            {
                ModelState.AddModelError(
                    "items",
                    $"Inventory item '{inventoryItem.Name}' belongs to another branch and cannot receive this purchase order.");
                return ValidationProblem(ModelState);
            }

            orderItem.InventoryItemId = inventoryItem.Id;
            var previousQuantity = inventoryItem.Quantity;
            var previousCost = inventoryItem.UnitCost;
            inventoryItem.Quantity += receiptItem.AcceptedQuantity;
            inventoryItem.UnitCost = previousQuantity <= 0
                ? orderItem.UnitPrice
                : previousCost.HasValue
                    ? decimal.Round(
                        (previousQuantity * previousCost.Value +
                         receiptItem.AcceptedQuantity * orderItem.UnitPrice) /
                        inventoryItem.Quantity,
                        2,
                        MidpointRounding.AwayFromZero)
                    : null;

            var receiptNotes = new List<string> { $"Received from purchase order {order.Number}." };
            if (receiptItem.DamagedQuantity > 0)
                receiptNotes.Add($"Damaged: {receiptItem.DamagedQuantity:0.###}.");
            if (receiptItem.ShortageQuantity > 0)
                receiptNotes.Add($"Short: {receiptItem.ShortageQuantity:0.###}.");
            if (!string.IsNullOrWhiteSpace(receiptItem.Notes))
                receiptNotes.Add(receiptItem.Notes);

            db.StockMovements.Add(new StockMovement
            {
                TenantId = tenantId,
                BranchId = order.BranchId,
                InventoryItemId = inventoryItem.Id,
                SupplierId = order.SupplierId,
                PurchaseOrderId = order.Id,
                MovementType = "PurchaseReceived",
                Quantity = receiptItem.AcceptedQuantity,
                UnitCost = orderItem.UnitPrice,
                Reference = order.Number,
                Notes = string.Join(" ", receiptNotes),
                OccurredAt = receipt.ReceivedAt,
                PerformedBy = receipt.ReceivedBy,
            });
        }

        // Added through the set, not through order.Receipts: BaseEntity assigns Id in
        // its initialiser, so a new child discovered on a tracked parent's collection
        // already has a key and change detection files it as an update of a row that
        // was never inserted. An explicit Add states the intent and cascades to Items.
        db.PurchaseOrderReceipts.Add(receipt);
        order.Status = orderItems.All(item => item.ReceivingClosed)
            ? "Received"
            : "PartiallyReceived";
        order.UpdatedAt = receipt.ReceivedAt;
        NotificationHelper.Queue(
            db,
            tenantId,
            null,
            "PurchaseOrderReceived",
            "Purchase order receipt recorded",
            $"{order.Number}: {receipt.Items.Sum(item => item.AcceptedQuantity):0.###} accepted, " +
            $"{receipt.Items.Sum(item => item.DamagedQuantity):0.###} damaged, " +
            $"{receipt.Items.Sum(item => item.ShortageQuantity):0.###} short.");

        await db.SaveChangesAsync(cancellationToken);
        var response = (await ToResponsesAsync([order], cancellationToken)).Single();
        return Ok(response);
    }

    private string CurrentActorName() =>
        User.FindFirst("fullName")?.Value ??
        User.Identity?.Name ??
        "Authorized user";

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
        var orderIds = orders.Select(order => order.Id).ToList();
        var receipts = await db.PurchaseOrderReceipts.AsNoTracking()
            .Where(receipt => orderIds.Contains(receipt.PurchaseOrderId))
            .OrderByDescending(receipt => receipt.ReceivedAt)
            .ToListAsync(cancellationToken);
        var receiptIds = receipts.Select(receipt => receipt.Id).ToList();
        var receiptItems = await db.PurchaseOrderReceiptItems.AsNoTracking()
            .Where(item => receiptIds.Contains(item.PurchaseOrderReceiptId))
            .ToListAsync(cancellationToken);
        var receiptsByOrderId = receipts
            .GroupJoin(
                receiptItems,
                receipt => receipt.Id,
                item => item.PurchaseOrderReceiptId,
                (receipt, items) => (receipt.PurchaseOrderId, Receipt: new PurchaseOrderReceiptResponse(
                    receipt.Id,
                    receipt.ReceivedAt,
                    receipt.ReceivedBy,
                    items.Select(item => new PurchaseOrderReceiptItemResponse(
                        item.PurchaseOrderItemId,
                        item.DeliveredQuantity,
                        item.AcceptedQuantity,
                        item.DamagedQuantity,
                        item.ShortageQuantity,
                        item.Notes)).ToList())))
            .GroupBy(entry => entry.PurchaseOrderId)
            .ToDictionary(group => group.Key, group => (IReadOnlyList<PurchaseOrderReceiptResponse>)group.Select(entry => entry.Receipt).ToList());

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
                    item.ReceivedQuantity,
                    item.DamagedQuantity,
                    item.ShortageQuantity,
                    item.ReceivingClosed
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
                    items,
                    receiptsByOrderId.GetValueOrDefault(order.Id) ?? []);
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

    private static bool IsAllowedStatusTransition(string current, string next)
    {
        if (string.Equals(next, "Cancelled", StringComparison.Ordinal))
            return current is "Draft" or "InReview" or "Placed" or "InTransit" or "PartiallyReceived";

        return current switch
        {
            "Draft" => next == "InReview",
            "InReview" => next == "Placed",
            "Placed" => next == "InTransit",
            "InTransit" => false,
            _ => false,
        };
    }
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
    decimal ReceivedQuantity,
    decimal DamagedQuantity,
    decimal ShortageQuantity,
    bool ReceivingClosed);

public sealed record PurchaseOrderReceiptItemResponse(
    Guid PurchaseOrderItemId,
    decimal DeliveredQuantity,
    decimal AcceptedQuantity,
    decimal DamagedQuantity,
    decimal ShortageQuantity,
    string? Notes);

public sealed record PurchaseOrderReceiptResponse(
    Guid Id,
    DateTime ReceivedAt,
    string ReceivedBy,
    IReadOnlyList<PurchaseOrderReceiptItemResponse> Items);

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
    IReadOnlyList<PurchaseOrderItemResponse>? Items = null,
    IReadOnlyList<PurchaseOrderReceiptResponse>? Receipts = null);

public sealed record PurchaseOrderOption(Guid Id, string Name);

public sealed record PurchaseOrderItemOption(
    Guid Id,
    string Name,
    string Sku,
    decimal? UnitCost,
    Guid? BranchId,
    Guid? SupplierId);

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

public sealed record ReceivePurchaseOrderRequest(
    IReadOnlyList<ReceivePurchaseOrderItemRequest>? Items);

public sealed record ReceivePurchaseOrderItemRequest(
    Guid PurchaseOrderItemId,
    decimal DeliveredQuantity,
    decimal DamagedQuantity,
    bool CloseRemainingAsShort,
    string? Notes,
    Guid? InventoryItemId = null);
