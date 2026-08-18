using System;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/agents")]
public sealed class AgentProxyController(
    AppDbContext db) : ControllerBase
{
    // POST /api/agents/create-po
    // Agent must provide X-Agent-Secret header matching AGENT_SERVICE_SECRET env var
    [HttpPost("create-po")]
    public async Task<ActionResult<PurchaseOrderResponse>> CreatePurchaseOrderFromAgent(
        AgentCreatePoRequest request,
        CancellationToken cancellationToken)
    {
        // Validate secret
        var secretHeader = Request.Headers.TryGetValue("X-Agent-Secret", out var provided) ? provided.ToString() : null;
        var expected = Environment.GetEnvironmentVariable("AGENT_SERVICE_SECRET");
        if (string.IsNullOrEmpty(expected) || string.IsNullOrEmpty(secretHeader) || !string.Equals(expected, secretHeader, StringComparison.Ordinal))
        {
            return Unauthorized(new { message = "Invalid agent secret." });
        }

        if (request.TenantId == Guid.Empty)
        {
            ModelState.AddModelError("tenantId", "tenantId is required.");
            return ValidationProblem(ModelState);
        }

        if (request.BranchId == Guid.Empty)
        {
            ModelState.AddModelError("branchId", "branchId is required.");
            return ValidationProblem(ModelState);
        }

        if (request.SupplierId == Guid.Empty)
        {
            ModelState.AddModelError("supplierId", "supplierId is required.");
            return ValidationProblem(ModelState);
        }

        if (!await db.Branches.AnyAsync(branch => branch.TenantId == request.TenantId && branch.Id == request.BranchId, cancellationToken))
        {
            ModelState.AddModelError("branchId", "The branch does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        if (!await db.Suppliers.AnyAsync(supplier => supplier.Id == request.SupplierId, cancellationToken))
        {
            ModelState.AddModelError("supplierId", "The supplier does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        var number = request.Number?.Trim();
        if (string.IsNullOrWhiteSpace(number))
        {
            number = $"AI-PO-{Guid.NewGuid().ToString().Substring(0,8)}";
        }

        // Check duplicate number for the tenant
        if (await db.PurchaseOrders.IgnoreQueryFilters().AnyAsync(order => order.TenantId == request.TenantId && order.Number == number, cancellationToken))
        {
            return Conflict(new { message = $"A purchase order with number '{number}' already exists." });
        }

        var status = "Placed";
        if (!string.IsNullOrWhiteSpace(request.Status)) status = request.Status;

        var order = new PurchaseOrder
        {
            TenantId = request.TenantId,
            BranchId = request.BranchId,
            SupplierId = request.SupplierId,
            Number = number,
            Status = status,
        };

        db.PurchaseOrders.Add(order);
        await db.SaveChangesAsync(cancellationToken);

        // If line items provided, add them
        if (request.Items is not null && request.Items.Count > 0)
        {
            var items = request.Items.Select(i => new PurchaseOrderItem
            {
                TenantId = request.TenantId,
                PurchaseOrderId = order.Id,
                InventoryItemId = i.InventoryItemId ?? null,
                Description = i.Description,
                Quantity = i.Quantity,
                UnitPrice = i.UnitPrice,
                ReceivedQuantity = 0m,
            }).ToList();

            db.PurchaseOrderItems.AddRange(items);
            await db.SaveChangesAsync(cancellationToken);
        }

        var response = (await ToResponsesAsync(new[] { order }, cancellationToken)).Single();
        return CreatedAtAction(nameof(CreatePurchaseOrderFromAgent), new { }, response);
    }

    // Reuse helper from PurchaseOrdersController (copied minimal implementation)
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
}

public sealed record AgentCreatePoRequest(Guid TenantId, Guid BranchId, Guid SupplierId, IReadOnlyList<AgentCreatePoItem>? Items = null, string? Number = null, string? Status = null);

public sealed record AgentCreatePoItem(Guid? InventoryItemId, string? Description, decimal Quantity, decimal UnitPrice);
