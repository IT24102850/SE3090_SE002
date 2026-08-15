using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

[ApiController]
[Route("api/inventory")]
public sealed class InventoryController(
    AppDbContext db,
    IAuthorizationService authorizationService) : ControllerBase
{
    private const int MaxPageSize = 100;

    [HttpGet]
    public async Task<ActionResult<InventoryListResponse>> GetInventory(
        [FromQuery] string? category,
        [FromQuery] bool lowStock = false,
        [FromQuery] Guid? branchId = null,
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
                InventoryAuthorizationPolicies.InventoryRead,
                tenantId,
                branchId))
        {
            return Forbid();
        }

        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);

        var query = db.InventoryItems
            .Include(item => item.Category)
            .Include(item => item.Unit)
            .Include(item => item.Branch)
            .AsNoTracking();

        if (!string.IsNullOrWhiteSpace(category))
        {
            var normalized = category.Trim();
            query = query.Where(item =>
                item.Category != null && EF.Functions.ILike(item.Category.Name, normalized));
        }

        if (lowStock)
        {
            query = query.Where(item => item.Quantity <= 0 || item.Quantity < item.ReorderLevel);
        }

        if (branchId.HasValue)
        {
            query = query.Where(item => item.BranchId == branchId.Value);
        }

        var totalCount = await query.CountAsync(cancellationToken);
        var items = await query
            .OrderBy(item => item.Name)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(cancellationToken);

        var totalPages = (int)Math.Ceiling(totalCount / (double)pageSize);

        return Ok(new InventoryListResponse(
            items.Select(ToResponse).ToList(),
            page,
            pageSize,
            totalCount,
            totalPages));
    }

    [HttpPost]
    public async Task<ActionResult<InventoryItemResponse>> CreateInventory(
        CreateInventoryRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var name = request.Name?.Trim();
        var sku = request.Sku?.Trim();

        if (string.IsNullOrWhiteSpace(name))
        {
            ModelState.AddModelError("name", "Name is required.");
            return ValidationProblem(ModelState);
        }

        if (string.IsNullOrWhiteSpace(sku))
        {
            ModelState.AddModelError("sku", "Sku is required.");
            return ValidationProblem(ModelState);
        }

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryWrite,
                tenantId,
                request.BranchId))
        {
            return Forbid();
        }

        if (await db.InventoryItems.IgnoreQueryFilters()
                .AnyAsync(item => item.TenantId == tenantId && item.Sku == sku, cancellationToken))
        {
            return Conflict(new { message = $"An item with SKU '{sku}' already exists." });
        }

        if (request.CategoryId.HasValue &&
            !await db.InventoryCategories.AnyAsync(
                category => category.Id == request.CategoryId.Value, cancellationToken))
        {
            ModelState.AddModelError("categoryId", "The category does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        if (request.UnitId.HasValue &&
            !await db.InventoryUnits.AnyAsync(
                unit => unit.Id == request.UnitId.Value, cancellationToken))
        {
            ModelState.AddModelError("unitId", "The unit does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        if (request.BranchId.HasValue &&
            !await db.Branches.AnyAsync(
                branch => branch.Id == request.BranchId.Value, cancellationToken))
        {
            ModelState.AddModelError("branchId", "The branch does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        var item = new InventoryItem
        {
            Name = name,
            Sku = sku,
            Description = string.IsNullOrWhiteSpace(request.Description) ? null : request.Description.Trim(),
            CategoryId = request.CategoryId,
            UnitId = request.UnitId,
            BranchId = request.BranchId,
            Quantity = request.Quantity,
            ReorderLevel = request.ReorderLevel,
            UnitCost = request.UnitCost,
        };

        db.InventoryItems.Add(item);
        await db.SaveChangesAsync(cancellationToken);

        var created = await db.InventoryItems
            .Include(createdItem => createdItem.Category)
            .Include(createdItem => createdItem.Unit)
            .Include(createdItem => createdItem.Branch)
            .AsNoTracking()
            .SingleAsync(createdItem => createdItem.Id == item.Id, cancellationToken);

        return CreatedAtAction(nameof(GetInventory), new { }, ToResponse(created));
    }

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);

    private static InventoryItemResponse ToResponse(InventoryItem item)
    {
        var status = item.Quantity <= 0
            ? "OutOfStock"
            : item.Quantity < item.ReorderLevel
                ? "LowStock"
                : "InStock";

        return new InventoryItemResponse(
            item.Id,
            item.Name,
            item.Sku,
            item.Description,
            item.CategoryId,
            item.Category?.Name,
            item.UnitId,
            item.Unit?.Code,
            item.BranchId,
            item.Branch?.Name,
            item.Quantity,
            item.ReorderLevel,
            item.UnitCost,
            status,
            item.CreatedAt);
    }
}

public sealed record InventoryListResponse(
    IReadOnlyList<InventoryItemResponse> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages);

public sealed record InventoryItemResponse(
    Guid Id,
    string Name,
    string Sku,
    string? Description,
    Guid? CategoryId,
    string? Category,
    Guid? UnitId,
    string? Unit,
    Guid? BranchId,
    string? Branch,
    decimal Quantity,
    decimal ReorderLevel,
    decimal? UnitCost,
    string Status,
    DateTime CreatedAt);

public sealed record CreateInventoryRequest(
    string Name,
    string Sku,
    string? Description,
    Guid? CategoryId,
    Guid? UnitId,
    Guid? BranchId,
    decimal Quantity = 0,
    decimal ReorderLevel = 0,
    decimal? UnitCost = null);
