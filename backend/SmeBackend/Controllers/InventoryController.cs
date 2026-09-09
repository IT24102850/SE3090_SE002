using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;

namespace SmeBackend.Controllers;

[ApiController]
[Authorize]
[Route("api/inventory")]
[Produces("application/json")]
public sealed class InventoryController(
    AppDbContext db,
    IAuthorizationService authorizationService) : ControllerBase
{
    private const int MaxPageSize = 100;

    [HttpGet]
    [ProducesResponseType(typeof(InventoryListResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
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
        branchId = ResolveBranchScope(branchId);

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

    [HttpGet("low-stock")]
    [ProducesResponseType(typeof(InventoryListResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public Task<ActionResult<InventoryListResponse>> GetLowStockInventory(
        [FromQuery] Guid? branchId = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken cancellationToken = default) =>
        GetInventory(
            category: null,
            lowStock: true,
            branchId: branchId,
            page: page,
            pageSize: pageSize,
            cancellationToken: cancellationToken);

    [HttpGet("movements")]
    public async Task<ActionResult<IReadOnlyList<InventoryMovementResponse>>> GetMovements(
        [FromQuery] Guid? branchId = null,
        [FromQuery] int pageSize = 100,
        CancellationToken cancellationToken = default)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }
        branchId = ResolveBranchScope(branchId);

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryRead,
                tenantId,
                branchId))
        {
            return Forbid();
        }

        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);
        var query = db.StockMovements
            .AsNoTracking()
            .OrderByDescending(movement => movement.OccurredAt)
            .AsQueryable();

        if (branchId.HasValue)
        {
            query = query.Where(movement => movement.BranchId == branchId.Value);
        }

        var movements = await query.Take(pageSize).ToListAsync(cancellationToken);
        var itemIds = movements.Select(movement => movement.InventoryItemId).Distinct().ToList();
        var items = await db.InventoryItems
            .AsNoTracking()
            .Where(item => itemIds.Contains(item.Id))
            .ToDictionaryAsync(item => item.Id, cancellationToken);

        return Ok(movements.Select(movement =>
        {
            items.TryGetValue(movement.InventoryItemId, out var item);
            return new InventoryMovementResponse(
                movement.Id,
                movement.OccurredAt,
                item?.Name ?? "Unknown item",
                item?.Sku ?? "Unknown SKU",
                movement.MovementType,
                movement.Quantity,
                movement.Reference,
                movement.Notes);
        }).ToList());
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(InventoryItemResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<InventoryItemResponse>> GetInventoryItem(
        Guid id,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var item = await LoadItemAsync(id, cancellationToken);
        if (item is null)
        {
            return NotFound();
        }

        if (!await RequireItemAccessAsync(
                InventoryAuthorizationPolicies.InventoryRead,
                item,
                cancellationToken))
        {
            return Forbid();
        }

        return Ok(ToResponse(item));
    }

    [HttpPut("{id:guid}")]
    [Consumes("application/json")]
    [ProducesResponseType(typeof(InventoryItemResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<InventoryItemResponse>> UpdateInventoryItem(
        Guid id,
        UpdateInventoryRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var item = await LoadItemAsync(id, cancellationToken);
        if (item is null)
        {
            return NotFound();
        }

        if (!await RequireItemAccessAsync(
                InventoryAuthorizationPolicies.InventoryWrite,
                item,
                cancellationToken))
        {
            return Forbid();
        }

        // A branch move needs access to both the source item and its destination.
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryWrite,
                tenantId,
                request.BranchId))
        {
            return Forbid();
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

        if (request.ReorderLevel < 0)
        {
            ModelState.AddModelError("reorderLevel", "Reorder level cannot be negative.");
            return ValidationProblem(ModelState);
        }

        if (request.UnitCost < 0)
        {
            ModelState.AddModelError("unitCost", "Unit cost cannot be negative.");
            return ValidationProblem(ModelState);
        }

        if (await db.InventoryItems.IgnoreQueryFilters()
            .AnyAsync(candidate => candidate.TenantId == tenantId && candidate.Sku == sku && candidate.Id != id,
                cancellationToken))
        {
            return Conflict(new { message = $"An item with SKU '{sku}' already exists." });
        }

        if (request.BranchId.HasValue &&
            !await db.Branches.AnyAsync(branch => branch.Id == request.BranchId.Value, cancellationToken))
        {
            ModelState.AddModelError("branchId", "The branch does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        if (request.CategoryId.HasValue &&
            !await db.InventoryCategories.AnyAsync(category => category.Id == request.CategoryId.Value, cancellationToken))
        {
            ModelState.AddModelError("categoryId", "The category does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        if (request.UnitId.HasValue &&
            !await db.InventoryUnits.AnyAsync(unit => unit.Id == request.UnitId.Value, cancellationToken))
        {
            ModelState.AddModelError("unitId", "The unit does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        item.Name = name;
        item.Sku = sku;
        item.Description = string.IsNullOrWhiteSpace(request.Description) ? null : request.Description.Trim();
        item.CategoryId = request.CategoryId;
        item.UnitId = request.UnitId;
        item.BranchId = request.BranchId;
        item.ReorderLevel = request.ReorderLevel;
        item.UnitCost = request.UnitCost;
        item.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(cancellationToken);
        var updated = await LoadItemAsync(item.Id, cancellationToken);
        return Ok(ToResponse(updated!));
    }

    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> DeleteInventoryItem(Guid id, CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var item = await LoadItemAsync(id, cancellationToken);
        if (item is null)
        {
            return NotFound();
        }

        if (!await RequireItemAccessAsync(
                InventoryAuthorizationPolicies.InventoryWrite,
                item,
                cancellationToken))
        {
            return Forbid();
        }

        if (item.Quantity != 0)
        {
            return Conflict(new { message = "Item still has stock on hand. Adjust or receive stock to zero before deleting." });
        }

        item.IsActive = false;
        item.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(cancellationToken);
        return NoContent();
    }

    [HttpPost("{id:guid}/adjust")]
    [Consumes("application/json")]
    [ProducesResponseType(typeof(InventoryItemResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<InventoryItemResponse>> AdjustInventoryItem(
        Guid id,
        AdjustInventoryRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var item = await LoadItemAsync(id, cancellationToken);
        if (item is null)
        {
            return NotFound();
        }

        if (!await RequireItemAccessAsync(
                InventoryAuthorizationPolicies.InventoryWrite,
                item,
                cancellationToken))
        {
            return Forbid();
        }

        if (request.Quantity == 0)
        {
            ModelState.AddModelError("quantity", "Adjustment quantity cannot be zero.");
            return ValidationProblem(ModelState);
        }

        if (!item.BranchId.HasValue)
        {
            return Conflict(new { message = "Stock operations require the item to be assigned to a branch." });
        }

        if (request.Quantity < 0 && item.Quantity + request.Quantity < 0)
        {
            return Conflict(new { message = $"Adjustment would take '{item.Name}' below zero ({item.Quantity} on hand)." });
        }

        item.Quantity += request.Quantity;
        item.UpdatedAt = DateTime.UtcNow;

        db.StockMovements.Add(new StockMovement
        {
            InventoryItemId = item.Id,
            BranchId = item.BranchId.Value,
            MovementType = "Adjustment",
            Quantity = request.Quantity,
            Reference = request.Reference,
            Notes = request.Notes,
            OccurredAt = DateTime.UtcNow,
        });

        await db.SaveChangesAsync(cancellationToken);
        return Ok(ToResponse(item));
    }

    [HttpPost("{id:guid}/receive")]
    [Consumes("application/json")]
    [ProducesResponseType(typeof(InventoryItemResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<InventoryItemResponse>> ReceiveInventoryItem(
        Guid id,
        ReceiveInventoryRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var item = await LoadItemAsync(id, cancellationToken);
        if (item is null)
        {
            return NotFound();
        }

        if (!await RequireItemAccessAsync(
                InventoryAuthorizationPolicies.InventoryWrite,
                item,
                cancellationToken))
        {
            return Forbid();
        }

        if (request.Quantity <= 0)
        {
            ModelState.AddModelError("quantity", "Receive quantity must be greater than zero.");
            return ValidationProblem(ModelState);
        }

        if (!item.BranchId.HasValue)
        {
            return Conflict(new { message = "Stock operations require the item to be assigned to a branch." });
        }

        if (request.UnitCost < 0)
        {
            ModelState.AddModelError("unitCost", "Unit cost cannot be negative.");
            return ValidationProblem(ModelState);
        }

        item.Quantity += request.Quantity;
        if (request.UnitCost.HasValue)
        {
            item.UnitCost = request.UnitCost;
        }
        item.UpdatedAt = DateTime.UtcNow;

        db.StockMovements.Add(new StockMovement
        {
            InventoryItemId = item.Id,
            BranchId = item.BranchId.Value,
            MovementType = "Receive",
            Quantity = request.Quantity,
            UnitCost = request.UnitCost,
            Reference = request.Reference,
            Notes = request.Notes,
            OccurredAt = DateTime.UtcNow,
        });

        await db.SaveChangesAsync(cancellationToken);
        return Ok(ToResponse(item));
    }

    [HttpPost]
    [Consumes("application/json")]
    [ProducesResponseType(typeof(InventoryItemResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
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

    private async Task<InventoryItem?> LoadItemAsync(Guid id, CancellationToken cancellationToken) =>
        await db.InventoryItems
            .Include(item => item.Category)
            .Include(item => item.Unit)
            .Include(item => item.Branch)
            .SingleOrDefaultAsync(item => item.Id == id, cancellationToken);

    private async Task<bool> RequireItemAccessAsync(
        string policy,
        InventoryItem item,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return false;
        }

        return await this.IsInventoryOperationAuthorizedAsync(
            authorizationService,
            policy,
            tenantId,
            item.BranchId);
    }

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

public sealed record InventoryMovementResponse(
    Guid Id,
    DateTime OccurredAt,
    string Item,
    string Sku,
    string MovementType,
    decimal Quantity,
    string? Reference,
    string? Notes);

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

public sealed record UpdateInventoryRequest(
    string? Name,
    string? Sku,
    string? Description,
    Guid? CategoryId,
    Guid? UnitId,
    Guid? BranchId,
    decimal ReorderLevel = 0,
    decimal? UnitCost = null);

public sealed record AdjustInventoryRequest(
    decimal Quantity,
    string? Reference = null,
    string? Notes = null);

public sealed record ReceiveInventoryRequest(
    decimal Quantity,
    decimal? UnitCost = null,
    string? Reference = null,
    string? Notes = null);
