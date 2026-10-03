using System.Data;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;
using SmeBackend.Services;

namespace SmeBackend.Controllers;

[ApiController]
[Authorize]
[Route("api/inventory")]
[Produces("application/json")]
public sealed class InventoryController(
    AppDbContext db,
    IAuthorizationService authorizationService,
    IInventoryAgentService inventoryAgentService,
    IJwtService jwtService) : ControllerBase
{
    private const int MaxPageSize = 100;

    [HttpGet("branches")]
    public async Task<ActionResult<IReadOnlyList<InventoryBranchOptionResponse>>> GetBranches(
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }

        var branchScope = ResolveBranchScope(null);
        if (User.IsInRole(UserRole.Staff.ToString()) && !branchScope.HasValue)
        {
            return Forbid();
        }

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryRead,
                tenantId,
                branchScope))
        {
            return Forbid();
        }

        var query = db.Branches.AsNoTracking().Where(branch => branch.TenantId == tenantId);
        if (branchScope.HasValue)
        {
            query = query.Where(branch => branch.Id == branchScope.Value);
        }

        var branches = await query
            .OrderBy(branch => branch.Name)
            .Select(branch => new InventoryBranchOptionResponse(
                branch.Id,
                branch.Name,
                branch.Latitude,
                branch.Longitude))
            .ToListAsync(cancellationToken);
        return Ok(branches);
    }

    [HttpPost("agent/plan")]
    public async Task<IActionResult> PlanInventory(
        [FromBody] InventoryAgentPlanRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        if (string.IsNullOrWhiteSpace(request.Objective))
            return BadRequest(new { message = "Describe what you want the inventory assistant to check." });

        Guid? branchId;
        if (User.IsInRole(UserRole.Staff.ToString()))
        {
            if (!Guid.TryParse(
                    User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value,
                    out var staffBranchId))
            {
                return Forbid();
            }

            branchId = staffBranchId;
        }
        else
        {
            branchId = ResolveBranchScope(request.BranchId);
        }

        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService, InventoryAuthorizationPolicies.InventoryRead, tenantId, branchId))
            return Forbid();

        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        if (!Guid.TryParse(userIdClaim, out var userId)) return Unauthorized();
        var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(candidate => candidate.Id == userId, cancellationToken);
        if (user is null || user.TenantId != tenantId) return Unauthorized();

        var response = await inventoryAgentService.PlanAsync(new InventoryAgentRequest(
            request.Objective.Trim(), tenantId, branchId, jwtService.GenerateAccessToken(user)), cancellationToken);
        return new ContentResult
        {
            StatusCode = response.StatusCode,
            Content = response.Body,
            ContentType = response.ContentType,
        };
    }

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
            .Include(item => item.Supplier)
            .AsNoTracking();

        if (!string.IsNullOrWhiteSpace(category))
        {
            var normalized = category.Trim();
            query = query.Where(item =>
                item.Category != null && EF.Functions.ILike(item.Category.Name, normalized));
        }

        if (lowStock)
        {
            query = query.Where(item => item.Quantity <= 0 || item.Quantity <= item.ReorderLevel);
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

    [HttpGet("categories")]
    [ProducesResponseType(typeof(IReadOnlyList<InventoryCategoryOptionResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<IReadOnlyList<InventoryCategoryOptionResponse>>> GetCategories(
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();
        var branchId = ResolveBranchScope(null);
        if (!await this.IsInventoryOperationAuthorizedAsync(
                authorizationService,
                InventoryAuthorizationPolicies.InventoryMetadataRead,
                tenantId,
                branchId))
            return Forbid();

        if (!await db.InventoryCategories.IgnoreQueryFilters()
                .AnyAsync(category => category.TenantId == tenantId, cancellationToken))
        {
            var tenant = await db.Tenants.IgnoreQueryFilters()
                .AsNoTracking()
                .FirstOrDefaultAsync(candidate => candidate.Id == tenantId && candidate.IsActive, cancellationToken);
            if (tenant is not null)
            {
                db.InventoryCategories.AddRange(DefaultInventoryCatalog.CategoriesFor(tenant.BusinessType)
                    .Select(name => new InventoryCategory { TenantId = tenantId, Name = name }));
                await db.SaveChangesAsync(cancellationToken);
            }
        }

        var categories = await db.InventoryCategories
            .AsNoTracking()
            .OrderBy(category => category.Name)
            .Select(category => new InventoryCategoryOptionResponse(category.Id, category.Name))
            .ToListAsync(cancellationToken);
        return Ok(categories);
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
    public async Task<ActionResult<InventoryMovementListResponse>> GetMovements(
        [FromQuery] Guid? branchId = null,
        [FromQuery] int page = 1,
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

        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);
        var query = db.StockMovements
            .AsNoTracking()
            .OrderByDescending(movement => movement.OccurredAt)
            .ThenByDescending(movement => movement.Id)
            .AsQueryable();

        if (branchId.HasValue)
        {
            query = query.Where(movement => movement.BranchId == branchId.Value);
        }

        var totalCount = await query.CountAsync(cancellationToken);
        var totalPages = (int)Math.Ceiling(totalCount / (double)pageSize);
        page = totalPages == 0 ? 1 : Math.Min(page, totalPages);
        var movements = await query
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(cancellationToken);
        var itemIds = movements.Select(movement => movement.InventoryItemId).Distinct().ToList();
        var items = await db.InventoryItems
            .AsNoTracking()
            .Where(item => itemIds.Contains(item.Id))
            .ToDictionaryAsync(item => item.Id, cancellationToken);
        var supplierIds = movements
            .Where(movement => movement.SupplierId.HasValue)
            .Select(movement => movement.SupplierId!.Value)
            .Distinct()
            .ToList();
        var suppliers = await db.Suppliers
            .AsNoTracking()
            .Where(supplier => supplierIds.Contains(supplier.Id))
            .ToDictionaryAsync(supplier => supplier.Id, cancellationToken);

        var movementResponses = movements.Select(movement =>
        {
            items.TryGetValue(movement.InventoryItemId, out var item);
            Supplier? supplier = null;
            if (movement.SupplierId.HasValue)
                suppliers.TryGetValue(movement.SupplierId.Value, out supplier);
            return new InventoryMovementResponse(
                movement.Id,
                movement.BranchId,
                movement.OccurredAt,
                item?.Name ?? "Unknown item",
                item?.Sku ?? "Unknown SKU",
                movement.MovementType,
                movement.Quantity,
                movement.Reference,
                movement.Notes,
                movement.SupplierId,
                supplier?.Name,
                supplier?.LeadTimeDays,
                movement.PerformedBy);
        }).ToList();

        return Ok(new InventoryMovementListResponse(
            movementResponses,
            page,
            pageSize,
            totalCount,
            totalPages));
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
        if (User.IsInRole(UserRole.Staff.ToString()))
        {
            return Forbid();
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

        if (request.BranchStocks is null &&
            !await this.IsInventoryOperationAuthorizedAsync(
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

        if (!IsValidImageUrl(request.ImageUrl))
        {
            ModelState.AddModelError("imageUrl", "Image URL must be a valid HTTP or HTTPS link no longer than 2048 characters.");
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
        if (request.UnitCost.HasValue && decimal.Round(request.UnitCost.Value, 2) != request.UnitCost)
        {
            ModelState.AddModelError("unitCost", "Unit cost can have up to two decimal places.");
            return ValidationProblem(ModelState);
        }
        if (request.SellingPrice < 0)
        {
            ModelState.AddModelError("sellingPrice", "Selling price cannot be negative.");
            return ValidationProblem(ModelState);
        }
        if (request.SellingPrice.HasValue && decimal.Round(request.SellingPrice.Value, 2) != request.SellingPrice)
        {
            ModelState.AddModelError("sellingPrice", "Selling price can have up to two decimal places.");
            return ValidationProblem(ModelState);
        }
        if (request.UnitCost.HasValue &&
            request.SellingPrice.HasValue &&
            request.SellingPrice <= request.UnitCost)
        {
            ModelState.AddModelError("sellingPrice", "Selling price must be greater than unit cost.");
            return ValidationProblem(ModelState);
        }

        if (request.BranchId.HasValue &&
            !await db.Branches.AnyAsync(branch => branch.Id == request.BranchId.Value, cancellationToken))
        {
            ModelState.AddModelError("branchId", "The branch does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        var categoryId = request.CategoryId.HasValue || !string.IsNullOrWhiteSpace(request.Category)
            ? await ResolveCategoryIdAsync(tenantId, request.CategoryId, request.Category, cancellationToken)
            : item.CategoryId;
        if (ModelState.ErrorCount > 0)
        {
            return ValidationProblem(ModelState);
        }

        if (request.UnitId.HasValue &&
            !await db.InventoryUnits.AnyAsync(unit => unit.Id == request.UnitId.Value, cancellationToken))
        {
            ModelState.AddModelError("unitId", "The unit does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        if (request.SupplierId.HasValue &&
            !await db.Suppliers.AnyAsync(supplier => supplier.Id == request.SupplierId.Value, cancellationToken))
        {
            ModelState.AddModelError("supplierId", "The supplier does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        if (request.BranchStocks is not null)
        {
            if (request.BranchId.HasValue)
            {
                ModelState.AddModelError("branchStocks", "Specify either branchStocks or branchId, not both.");
                return ValidationProblem(ModelState);
            }

            var requestedBranchStocks = request.BranchStocks.ToList();
            if (requestedBranchStocks.Count == 0)
            {
                ModelState.AddModelError("branchStocks", "Select at least one branch to update.");
                return ValidationProblem(ModelState);
            }
            if (requestedBranchStocks.GroupBy(stock => stock.BranchId).Any(group => group.Count() > 1))
            {
                ModelState.AddModelError("branchStocks", "A branch can be selected only once.");
                return ValidationProblem(ModelState);
            }
            if (requestedBranchStocks.Any(stock => stock.Quantity < 0))
            {
                ModelState.AddModelError("branchStocks", "Branch stock quantity cannot be negative.");
                return ValidationProblem(ModelState);
            }

            var selectedBranchIds = requestedBranchStocks.Select(stock => stock.BranchId).ToList();
            var validBranchIds = await db.Branches
                .Where(branch => branch.TenantId == tenantId && selectedBranchIds.Contains(branch.Id))
                .Select(branch => branch.Id)
                .ToListAsync(cancellationToken);
            if (validBranchIds.Count != selectedBranchIds.Count)
            {
                ModelState.AddModelError("branchStocks", "One or more selected branches do not exist for this tenant.");
                return ValidationProblem(ModelState);
            }

            foreach (var branchId in selectedBranchIds)
            {
                if (!await this.IsInventoryOperationAuthorizedAsync(
                        authorizationService,
                        InventoryAuthorizationPolicies.InventoryWrite,
                        tenantId,
                        branchId))
                {
                    return Forbid();
                }
            }

            var existingBranchItems = await db.InventoryItems
                .Where(candidate =>
                    candidate.TenantId == tenantId &&
                    candidate.Sku == item.Sku &&
                    candidate.BranchId.HasValue &&
                    selectedBranchIds.Contains(candidate.BranchId.Value))
                .ToListAsync(cancellationToken);
            var existingBranchItemIds = existingBranchItems.Select(candidate => candidate.Id).ToList();

            if (await db.InventoryItems.IgnoreQueryFilters()
                .AnyAsync(candidate =>
                        candidate.TenantId == tenantId &&
                        candidate.BranchId.HasValue &&
                        selectedBranchIds.Contains(candidate.BranchId.Value) &&
                        candidate.Sku == sku &&
                        !existingBranchItemIds.Contains(candidate.Id),
                    cancellationToken))
            {
                return Conflict(new { message = $"An item with SKU '{sku}' already exists in one of the selected branches." });
            }

            var existingByBranch = existingBranchItems.ToDictionary(candidate => candidate.BranchId!.Value);
            var now = DateTime.UtcNow;
            foreach (var branchStock in requestedBranchStocks)
            {
                if (!existingByBranch.TryGetValue(branchStock.BranchId, out var branchItem))
                {
                    branchItem = new InventoryItem
                    {
                        TenantId = tenantId,
                        BranchId = branchStock.BranchId,
                        Quantity = branchStock.Quantity,
                    };
                    db.InventoryItems.Add(branchItem);
                }
                else
                {
                    var adjustmentQuantity = branchStock.Quantity - branchItem.Quantity;
                    if (adjustmentQuantity != 0)
                    {
                        db.StockMovements.Add(new StockMovement
                        {
                            TenantId = tenantId,
                            InventoryItemId = branchItem.Id,
                            BranchId = branchStock.BranchId,
                            MovementType = "Adjustment",
                            Quantity = adjustmentQuantity,
                            Reference = "Inventory manager edit",
                            Notes = "Branch stock changed while editing the inventory item.",
                            OccurredAt = now,
                            PerformedBy = CurrentActorName(),
                        });
                    }
                    branchItem.Quantity = branchStock.Quantity;
                }

                branchItem.Name = name;
                branchItem.Sku = sku;
                branchItem.Description = string.IsNullOrWhiteSpace(request.Description) ? null : request.Description.Trim();
                branchItem.ImageUrl = string.IsNullOrWhiteSpace(request.ImageUrl) ? null : request.ImageUrl.Trim();
                branchItem.CategoryId = categoryId;
                branchItem.UnitId = request.UnitId ?? item.UnitId;
                if (request.SupplierId.HasValue) branchItem.SupplierId = request.SupplierId;
                else if (request.ClearSupplier) branchItem.SupplierId = null;
                branchItem.ReorderLevel = request.ReorderLevel;
                branchItem.UnitCost = request.UnitCost;
                branchItem.SellingPrice = request.SellingPrice;
                branchItem.UpdatedAt = now;
            }

            NotificationHelper.Queue(
                db,
                tenantId,
                null,
                "InventoryUpdated",
                "Inventory item updated",
                $"{name} was updated in {requestedBranchStocks.Count} branch(es).");
            await db.SaveChangesAsync(cancellationToken);
            var updatedItem = await LoadItemAsync(item.Id, cancellationToken);
            return Ok(ToResponse(updatedItem!));
        }

        var destinationBranchId = request.BranchId ?? item.BranchId;
        if (await db.InventoryItems.IgnoreQueryFilters()
            .AnyAsync(candidate =>
                    candidate.TenantId == tenantId &&
                    candidate.BranchId == destinationBranchId &&
                    candidate.Sku == sku &&
                    candidate.Id != id,
                cancellationToken))
        {
            return Conflict(new { message = $"An item with SKU '{sku}' already exists in this branch." });
        }

        item.Name = name;
        item.Sku = sku;
        item.Description = string.IsNullOrWhiteSpace(request.Description) ? null : request.Description.Trim();
        item.ImageUrl = string.IsNullOrWhiteSpace(request.ImageUrl) ? null : request.ImageUrl.Trim();
        item.CategoryId = categoryId;
        item.UnitId = request.UnitId ?? item.UnitId;
        item.BranchId = request.BranchId ?? item.BranchId;
        if (request.SupplierId.HasValue) item.SupplierId = request.SupplierId;
        else if (request.ClearSupplier) item.SupplierId = null;
        item.ReorderLevel = request.ReorderLevel;
        item.UnitCost = request.UnitCost;
        item.SellingPrice = request.SellingPrice;
        item.UpdatedAt = DateTime.UtcNow;

        NotificationHelper.Queue(db, tenantId, null, "InventoryUpdated", "Inventory item updated", $"{item.Name} was updated.");
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
        if (User.IsInRole(UserRole.Staff.ToString()))
        {
            return Forbid();
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
        NotificationHelper.Queue(db, tenantId, null, "InventoryDeleted", "Inventory item removed", $"{item.Name} was removed from inventory.");
        await db.SaveChangesAsync(cancellationToken);
        return NoContent();
    }

    [HttpPost("{id:guid}/sell")]
    [Consumes("application/json")]
    [ProducesResponseType(typeof(RecordInventorySaleResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<RecordInventorySaleResponse>> RecordInventorySale(
        Guid id,
        RecordInventorySaleRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId)) return Unauthorized();

        var item = await LoadItemAsync(id, cancellationToken);
        if (item is null) return NotFound();
        if (!await RequireItemAccessAsync(
                InventoryAuthorizationPolicies.InventoryWrite,
                item,
                cancellationToken))
            return Forbid();

        if (request.Quantity <= 0)
        {
            ModelState.AddModelError("quantity", "Sale quantity must be greater than zero.");
            return ValidationProblem(ModelState);
        }
        if (decimal.Round(request.Quantity, 3) != request.Quantity)
        {
            ModelState.AddModelError("quantity", "Sale quantity can have up to three decimal places.");
            return ValidationProblem(ModelState);
        }
        if (!item.BranchId.HasValue)
            return Conflict(new { message = "Sales require the item to be assigned to a branch." });
        if (!item.UnitCost.HasValue)
            return Conflict(new { message = "Set a unit cost for this item in web inventory before recording a sale." });
        if (!item.SellingPrice.HasValue)
            return Conflict(new { message = "Set a selling price for this item in web inventory before recording a sale." });
        if (item.SellingPrice <= item.UnitCost)
            return Conflict(new { message = "Selling price must be greater than unit cost to record a profitable sale." });
        if (request.ExpectedSellingPrice.HasValue &&
            request.ExpectedSellingPrice.Value != item.SellingPrice.Value)
            return Conflict(new { message = "The selling price changed. Refresh the item and confirm the sale again." });
        if (request.ExpectedUnitCost.HasValue &&
            request.ExpectedUnitCost.Value != item.UnitCost.Value)
            return Conflict(new { message = "The unit cost changed. Refresh the item and confirm the sale again." });
        if (item.Quantity < request.Quantity)
            return Conflict(new { message = $"Only {item.Quantity} unit(s) of '{item.Name}' are available." });

        var now = DateTime.UtcNow;
        var reference = string.IsNullOrWhiteSpace(request.Reference)
            ? $"SALE-{now:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}"
            : request.Reference.Trim();
        if (reference.Length > 100)
        {
            ModelState.AddModelError("reference", "Sale reference cannot exceed 100 characters.");
            return ValidationProblem(ModelState);
        }
        const decimal maximumSaleAmount = 9_999_999_999_999_999.99m;
        var unitPrice = item.SellingPrice.Value;
        if (unitPrice > maximumSaleAmount / request.Quantity)
        {
            ModelState.AddModelError("quantity", "Sale total exceeds the supported amount.");
            return ValidationProblem(ModelState);
        }
        var amount = decimal.Round(request.Quantity * unitPrice, 2, MidpointRounding.AwayFromZero);
        if (amount > maximumSaleAmount)
        {
            ModelState.AddModelError("quantity", "Sale total exceeds the supported amount.");
            return ValidationProblem(ModelState);
        }
        var costOfGoodsSold = request.Quantity * item.UnitCost.Value;
        var grossProfit = amount - costOfGoodsSold;

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        var updatedItems = await db.InventoryItems
            .Where(candidate =>
                candidate.Id == item.Id &&
                candidate.BranchId == item.BranchId &&
                candidate.Quantity >= request.Quantity)
            .ExecuteUpdateAsync(updates => updates
                .SetProperty(candidate => candidate.Quantity,
                    candidate => candidate.Quantity - request.Quantity)
                .SetProperty(candidate => candidate.UpdatedAt, now), cancellationToken);
        if (updatedItems == 0)
        {
            return Conflict(new { message = "Stock changed before the sale could be saved. Refresh and try again." });
        }

        var remainingQuantity = await db.InventoryItems
            .AsNoTracking()
            .Where(candidate => candidate.Id == item.Id)
            .Select(candidate => candidate.Quantity)
            .SingleAsync(cancellationToken);
        var notes = $"Sale of {request.Quantity} {item.Name} at {unitPrice} each.";
        db.Sales.Add(new Sale
        {
            TenantId = tenantId,
            BranchId = item.BranchId.Value,
            OccurredAt = now,
            Amount = amount,
            Reference = reference,
        });
        db.StockMovements.Add(new StockMovement
        {
            TenantId = tenantId,
            InventoryItemId = item.Id,
            BranchId = item.BranchId.Value,
            MovementType = "Sale",
            Quantity = -request.Quantity,
            UnitCost = item.UnitCost,
            Reference = reference,
            Notes = notes.Length <= 2000 ? notes : notes[..2000],
            OccurredAt = now,
            PerformedBy = CurrentActorName(),
        });

        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return Ok(new RecordInventorySaleResponse(
            reference,
            item.Id,
            item.Name,
            request.Quantity,
            unitPrice,
            amount,
            costOfGoodsSold,
            grossProfit,
            remainingQuantity,
            now));
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
            PerformedBy = CurrentActorName(),
        });

        NotificationHelper.Queue(db, tenantId, null, "StockAdjusted", "Stock adjusted", $"{item.Name} stock changed by {request.Quantity}.");
        await db.SaveChangesAsync(cancellationToken);
        return Ok(ToResponse(item));
    }

    [HttpPost("{id:guid}/physical-count")]
    [Consumes("application/json")]
    [ProducesResponseType(typeof(PhysicalStockCountResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(PhysicalStockCountResponse), StatusCodes.Status202Accepted)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<PhysicalStockCountResponse>> RecordPhysicalCount(
        Guid id,
        RecordPhysicalCountRequest request,
        CancellationToken cancellationToken)
    {
        if (!TryGetTenantId(out var tenantId))
        {
            return Unauthorized();
        }
        var countedByUserId = CurrentUserId();
        if (!countedByUserId.HasValue)
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

        const decimal maxStockQuantity = 999999999999999.999m;
        if (request.CountedQuantity < 0 ||
            request.SystemQuantityAtCount < 0 ||
            request.CountedQuantity > maxStockQuantity ||
            request.SystemQuantityAtCount > maxStockQuantity)
        {
            ModelState.AddModelError("countedQuantity", "Counted and recorded quantities cannot be negative.");
            return ValidationProblem(ModelState);
        }
        if (decimal.Round(request.CountedQuantity, 3) != request.CountedQuantity ||
            decimal.Round(request.SystemQuantityAtCount, 3) != request.SystemQuantityAtCount)
        {
            ModelState.AddModelError("countedQuantity", "Stock quantities can have up to three decimal places.");
            return ValidationProblem(ModelState);
        }
        if (request.CountedAt == default ||
            string.IsNullOrWhiteSpace(request.Reference) ||
            request.Reference.Length > 100 ||
            string.IsNullOrWhiteSpace(request.Reason) ||
            request.Reason.Length > 40 ||
            (request.Reason == "Other" && string.IsNullOrWhiteSpace(request.ReasonNotes)) ||
            request.ReasonNotes is { Length: > 1000 })
        {
            ModelState.AddModelError("reason", "Choose a reason for a discrepancy. Add notes when the reason is Other.");
            return ValidationProblem(ModelState);
        }
        if (request.Latitude.HasValue != request.Longitude.HasValue ||
            request.Latitude is < -90m or > 90m ||
            request.Longitude is < -180m or > 180m)
        {
            ModelState.AddModelError(
                "location",
                "Provide both valid latitude and longitude coordinates, or leave both empty.");
            return ValidationProblem(ModelState);
        }
        var requestedVariance = request.CountedQuantity - request.SystemQuantityAtCount;
        if (!PhysicalStockCountReasons.All.Contains(request.Reason, StringComparer.Ordinal) ||
            (requestedVariance == 0 && request.Reason != "NoDiscrepancy") ||
            (requestedVariance != 0 && request.Reason == "NoDiscrepancy"))
        {
            ModelState.AddModelError("reason", "Choose a valid physical-count discrepancy reason.");
            return ValidationProblem(ModelState);
        }
        if (!item.BranchId.HasValue)
        {
            return Conflict(new { message = "Stock counts require the item to be assigned to a branch." });
        }

        await using var transaction = db.Database.IsRelational()
            ? await db.Database.BeginTransactionAsync(
                IsolationLevel.Serializable,
                cancellationToken)
            : null;

        var existingCount = await db.PhysicalStockCounts.AsNoTracking()
            .SingleOrDefaultAsync(
                count => count.Reference == request.Reference,
                cancellationToken);
        if (existingCount is not null)
        {
            return Ok(ToPhysicalCountResponse(existingCount));
        }

        const double branchVerificationRadiusMeters = 150;
        var branchLatitude = item.Branch?.Latitude;
        var branchLongitude = item.Branch?.Longitude;
        if (request.Latitude.HasValue &&
            branchLatitude.HasValue &&
            branchLongitude.HasValue)
        {
            var distanceMeters = DistanceBetweenMeters(
                (double)request.Latitude.Value,
                (double)request.Longitude!.Value,
                (double)branchLatitude.Value,
                (double)branchLongitude.Value);
            if (distanceMeters > branchVerificationRadiusMeters)
            {
                return Conflict(new
                {
                    message = $"GPS is {Math.Round(distanceMeters)} m from {item.Branch!.Name}; counts with GPS must be within {branchVerificationRadiusMeters:0} m. Remove GPS to record an unverified manual count."
                });
            }
        }

        var countedAtUtc = request.CountedAt.UtcDateTime;
        var changedMovements = await GetMovementsAfterCountAsync(
            item.Id,
            countedAtUtc,
            cancellationToken);
        if (changedMovements.Count > 0 || item.Quantity != request.SystemQuantityAtCount)
        {
            return Conflict(new
            {
                message = $"'{item.Name}' changed after this count was taken. Refresh inventory, recount the item, and save a new count.",
                currentQuantity = item.Quantity,
                changedMovements
            });
        }

        var adjustment = request.CountedQuantity - request.SystemQuantityAtCount;
        var now = DateTime.UtcNow;
        var count = new PhysicalStockCount
        {
            TenantId = tenantId,
            InventoryItemId = item.Id,
            BranchId = item.BranchId.Value,
            ItemName = item.Name,
            Sku = item.Sku,
            SystemQuantityAtCount = request.SystemQuantityAtCount,
            CountedQuantity = request.CountedQuantity,
            Variance = adjustment,
            Reason = request.Reason,
            ReasonNotes = string.IsNullOrWhiteSpace(request.ReasonNotes)
                ? null
                : request.ReasonNotes.Trim(),
            CountedAt = countedAtUtc,
            CountedByUserId = countedByUserId,
            CountedBy = CurrentActorName(),
            Reference = request.Reference,
            Latitude = request.Latitude,
            Longitude = request.Longitude,
            Status = adjustment == 0 ? "Matched" : "Applied",
        };
        var requiresApproval = IsLargePhysicalCountVariance(
            adjustment,
            request.SystemQuantityAtCount);
        if (requiresApproval)
        {
            NotificationHelper.Queue(
                db,
                tenantId,
                null,
                "PhysicalCountApproval",
                "Physical stock count needs approval",
                $"{item.Name}: {adjustment:+0.###;-0.###} adjustment requested by {count.CountedBy}.");
            count.Status = "PendingApproval";
            db.PhysicalStockCounts.Add(count);
            await db.SaveChangesAsync(cancellationToken);
            if (transaction is not null)
                await transaction.CommitAsync(cancellationToken);
            return Accepted(ToPhysicalCountResponse(count));
        }

        if (adjustment != 0)
        {
            var notes = BuildPhysicalCountNotes(count);
            if (db.Database.IsRelational())
            {
                var updated = await db.InventoryItems
                    .Where(candidate =>
                        candidate.Id == item.Id &&
                        candidate.Quantity == request.SystemQuantityAtCount)
                    .ExecuteUpdateAsync(updates => updates
                        .SetProperty(candidate => candidate.Quantity, request.CountedQuantity)
                        .SetProperty(candidate => candidate.UpdatedAt, now),
                        cancellationToken);
                if (updated == 0)
                {
                    return Conflict(new
                    {
                        message = $"'{item.Name}' stock changed while this count was being saved. Refresh inventory, recount the item, and save a new count.",
                        currentQuantity = item.Quantity,
                        changedMovements = await GetMovementsAfterCountAsync(item.Id, countedAtUtc, cancellationToken)
                    });
                }
                db.Entry(item).State = EntityState.Detached;
            }
            else
            {
                item.Quantity = request.CountedQuantity;
                item.UpdatedAt = now;
            }
            db.StockMovements.Add(new StockMovement
            {
                TenantId = tenantId,
                InventoryItemId = item.Id,
                BranchId = item.BranchId.Value,
                MovementType = "Adjustment",
                Quantity = adjustment,
                Reference = request.Reference,
                Notes = notes,
                OccurredAt = now,
                PerformedBy = count.CountedBy,
            });
            NotificationHelper.Queue(
                db,
                tenantId,
                null,
                "StockAdjusted",
                "Physical stock count recorded",
                $"{item.Name} stock adjusted by {adjustment:0.###} after physical counting.");
        }

        db.PhysicalStockCounts.Add(count);
        await db.SaveChangesAsync(cancellationToken);
        if (transaction is not null)
            await transaction.CommitAsync(cancellationToken);
        return Ok(ToPhysicalCountResponse(count));
    }

    [HttpPost("{id:guid}/issue")]
    [Consumes("application/json")]
    [ProducesResponseType(typeof(InventoryItemResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<InventoryItemResponse>> IssueInventoryItem(
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

        if (request.Quantity <= 0)
        {
            ModelState.AddModelError("quantity", "Issue quantity must be greater than zero.");
            return ValidationProblem(ModelState);
        }
        if (!item.BranchId.HasValue)
        {
            return Conflict(new { message = "Stock operations require the item to be assigned to a branch." });
        }
        if (item.Quantity < request.Quantity)
        {
            return Conflict(new { message = $"Cannot issue {request.Quantity} units of '{item.Name}'; only {item.Quantity} are in stock." });
        }

        item.Quantity -= request.Quantity;
        item.UpdatedAt = DateTime.UtcNow;
        db.StockMovements.Add(new StockMovement
        {
            InventoryItemId = item.Id,
            BranchId = item.BranchId.Value,
            MovementType = "Issue",
            Quantity = -request.Quantity,
            UnitCost = item.UnitCost,
            Reference = request.Reference,
            Notes = request.Notes,
            OccurredAt = DateTime.UtcNow,
            PerformedBy = CurrentActorName(),
        });

        NotificationHelper.Queue(
            db,
            tenantId,
            null,
            "StockIssued",
            "Stock checked out",
            $"{item.Name}: {request.Quantity} units issued.");
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
        if (request.UnitCost.HasValue && decimal.Round(request.UnitCost.Value, 2) != request.UnitCost)
        {
            ModelState.AddModelError("unitCost", "Unit cost can have up to two decimal places.");
            return ValidationProblem(ModelState);
        }
        item.Quantity += request.Quantity;
        if (request.UnitCost.HasValue)
        {
            item.UnitCost = item.Quantity == request.Quantity || item.UnitCost.HasValue
                ? decimal.Round(
                    ((item.Quantity - request.Quantity) * (item.UnitCost ?? 0m) +
                     request.Quantity * request.UnitCost.Value) / item.Quantity,
                    2,
                    MidpointRounding.AwayFromZero)
                : null;
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
            PerformedBy = CurrentActorName(),
        });

        NotificationHelper.Queue(db, tenantId, null, "StockReceived", "Stock received", $"{item.Name} received {request.Quantity} units.");
        await db.SaveChangesAsync(cancellationToken);
        return Ok(ToResponse(item));
    }

    /// Logs food/stock waste: takes the quantity off hand and writes a
    /// "Waste" movement priced at the item's unit cost, so the restaurant
    /// dashboard can report waste cost and variance separately from
    /// ordinary adjustments. Kept as its own movement type rather than a
    /// negative Adjustment because that distinction is the whole report.
    [HttpPost("{id:guid}/waste")]
    [Consumes("application/json")]
    [ProducesResponseType(typeof(InventoryItemResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<InventoryItemResponse>> LogWaste(
        Guid id,
        WasteInventoryRequest request,
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
            ModelState.AddModelError("quantity", "Waste quantity must be greater than zero.");
            return ValidationProblem(ModelState);
        }

        if (!item.BranchId.HasValue)
        {
            return Conflict(new { message = "Stock operations require the item to be assigned to a branch." });
        }

        if (item.Quantity - request.Quantity < 0)
        {
            return Conflict(new { message = $"Waste would take '{item.Name}' below zero ({item.Quantity} on hand)." });
        }

        var reason = string.IsNullOrWhiteSpace(request.Reason) ? "Unspecified" : request.Reason.Trim();
        item.Quantity -= request.Quantity;
        item.UpdatedAt = DateTime.UtcNow;

        db.StockMovements.Add(new StockMovement
        {
            InventoryItemId = item.Id,
            BranchId = item.BranchId.Value,
            MovementType = "Waste",
            Quantity = -request.Quantity,
            UnitCost = item.UnitCost,
            Reference = string.IsNullOrWhiteSpace(request.Reference) ? $"WASTE-{DateTime.UtcNow:yyyyMMdd-HHmm}" : request.Reference.Trim(),
            Notes = string.IsNullOrWhiteSpace(request.Notes) ? reason : $"{reason}: {request.Notes.Trim()}",
            OccurredAt = DateTime.UtcNow,
            PerformedBy = CurrentActorName(),
        });

        NotificationHelper.Queue(db, tenantId, null, "StockWasted", "Waste logged", $"{item.Name}: {request.Quantity} written off ({reason}).");
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
        if (User.IsInRole(UserRole.Staff.ToString()))
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

        if (!IsValidImageUrl(request.ImageUrl))
        {
            ModelState.AddModelError("imageUrl", "Image URL must be a valid HTTP or HTTPS link no longer than 2048 characters.");
            return ValidationProblem(ModelState);
        }

        if (request.Quantity < 0)
        {
            ModelState.AddModelError("quantity", "Quantity cannot be negative.");
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
        if (request.UnitCost.HasValue && decimal.Round(request.UnitCost.Value, 2) != request.UnitCost)
        {
            ModelState.AddModelError("unitCost", "Unit cost can have up to two decimal places.");
            return ValidationProblem(ModelState);
        }
        if (request.SellingPrice < 0)
        {
            ModelState.AddModelError("sellingPrice", "Selling price cannot be negative.");
            return ValidationProblem(ModelState);
        }
        if (request.SellingPrice.HasValue && decimal.Round(request.SellingPrice.Value, 2) != request.SellingPrice)
        {
            ModelState.AddModelError("sellingPrice", "Selling price can have up to two decimal places.");
            return ValidationProblem(ModelState);
        }
        if (request.UnitCost.HasValue &&
            request.SellingPrice.HasValue &&
            request.SellingPrice <= request.UnitCost)
        {
            ModelState.AddModelError("sellingPrice", "Selling price must be greater than unit cost.");
            return ValidationProblem(ModelState);
        }

        var categoryId = await ResolveCategoryIdAsync(
            tenantId, request.CategoryId, request.Category, cancellationToken);
        if (ModelState.ErrorCount > 0)
        {
            return ValidationProblem(ModelState);
        }

        if (request.UnitId.HasValue &&
            !await db.InventoryUnits.AnyAsync(
                unit => unit.Id == request.UnitId.Value, cancellationToken))
        {
            ModelState.AddModelError("unitId", "The unit does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        if (request.SupplierId.HasValue &&
            !await db.Suppliers.AnyAsync(supplier => supplier.Id == request.SupplierId.Value, cancellationToken))
        {
            ModelState.AddModelError("supplierId", "The supplier does not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        if (request.BranchStocks is not null && request.BranchId.HasValue)
        {
            ModelState.AddModelError("branchStocks", "Specify either branchStocks or branchId, not both.");
            return ValidationProblem(ModelState);
        }

        List<(Guid? BranchId, decimal Quantity)> branchStocks;
        if (request.BranchStocks is not null)
        {
            var requestedBranchStocks = request.BranchStocks.ToList();
            if (requestedBranchStocks.Count == 0)
            {
                ModelState.AddModelError("branchStocks", "Select at least one branch.");
                return ValidationProblem(ModelState);
            }
            if (requestedBranchStocks.GroupBy(stock => stock.BranchId).Any(group => group.Count() > 1))
            {
                ModelState.AddModelError("branchStocks", "A branch can be selected only once.");
                return ValidationProblem(ModelState);
            }
            if (requestedBranchStocks.Any(stock => stock.Quantity < 0))
            {
                ModelState.AddModelError("branchStocks", "Initial stock quantity cannot be negative.");
                return ValidationProblem(ModelState);
            }
            branchStocks = requestedBranchStocks
                .Select(stock => ((Guid?)stock.BranchId, stock.Quantity))
                .ToList();
        }
        else
        {
            var branchId = request.BranchId;
            if (Guid.TryParse(User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value, out var userBranchId))
            {
                branchId ??= userBranchId;
            }
            if (!branchId.HasValue)
            {
                branchId = await db.Branches
                    .Where(branch => branch.TenantId == tenantId)
                    .Select(branch => (Guid?)branch.Id)
                    .FirstOrDefaultAsync(cancellationToken);
            }
            branchStocks = [(branchId, request.Quantity)];
        }

        var branchIds = branchStocks
            .Where(stock => stock.BranchId.HasValue)
            .Select(stock => stock.BranchId!.Value)
            .ToList();
        var validBranchIds = branchIds.Count == 0
            ? new List<Guid>()
            : await db.Branches
                .Where(branch => branch.TenantId == tenantId && branchIds.Contains(branch.Id))
                .Select(branch => branch.Id)
                .ToListAsync(cancellationToken);
        if (validBranchIds.Count != branchIds.Distinct().Count())
        {
            ModelState.AddModelError("branchStocks", "One or more selected branches do not exist for this tenant.");
            return ValidationProblem(ModelState);
        }

        foreach (var branchId in branchStocks.Select(stock => stock.BranchId).Distinct())
        {
            if (!await this.IsInventoryOperationAuthorizedAsync(
                    authorizationService,
                    InventoryAuthorizationPolicies.InventoryWrite,
                    tenantId,
                    branchId))
            {
                return Forbid();
            }
        }

        foreach (var stock in branchStocks)
        {
            if (await db.InventoryItems.IgnoreQueryFilters()
                .AnyAsync(item =>
                        item.TenantId == tenantId &&
                        item.BranchId == stock.BranchId &&
                        item.Sku == sku,
                    cancellationToken))
            {
                return Conflict(new { message = $"An item with SKU '{sku}' already exists in one of the selected branches." });
            }
        }

        var createdItems = branchStocks.Select(stock => new InventoryItem
        {
            Name = name,
            Sku = sku,
            Description = string.IsNullOrWhiteSpace(request.Description) ? null : request.Description.Trim(),
            ImageUrl = string.IsNullOrWhiteSpace(request.ImageUrl) ? null : request.ImageUrl.Trim(),
            CategoryId = categoryId,
            UnitId = request.UnitId,
            BranchId = stock.BranchId,
            SupplierId = request.SupplierId,
            Quantity = stock.Quantity,
            ReorderLevel = request.ReorderLevel,
            UnitCost = request.UnitCost,
            SellingPrice = request.SellingPrice,
        }).ToList();

        db.InventoryItems.AddRange(createdItems);
        NotificationHelper.Queue(db, tenantId, null, "InventoryCreated", "New inventory item", $"{name} was added to {createdItems.Count} branch(es).");
        await db.SaveChangesAsync(cancellationToken);

        var created = await db.InventoryItems
            .Include(createdItem => createdItem.Category)
            .Include(createdItem => createdItem.Unit)
            .Include(createdItem => createdItem.Branch)
            .Include(createdItem => createdItem.Supplier)
            .AsNoTracking()
            .SingleAsync(createdItem => createdItem.Id == createdItems[0].Id, cancellationToken);

        return CreatedAtAction(nameof(GetInventory), new { }, ToResponse(created));
    }

    private bool TryGetTenantId(out Guid tenantId) =>
        Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out tenantId);

    private string CurrentActorName() =>
        User.FindFirst("fullName")?.Value ??
        User.Identity?.Name ??
        "Authorized user";

    private Guid? CurrentUserId() =>
        Guid.TryParse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var userId)
            ? userId
            : null;

    private static bool IsLargePhysicalCountVariance(decimal variance, decimal systemQuantity)
    {
        var absoluteVariance = Math.Abs(variance);
        return absoluteVariance > 5m ||
               (systemQuantity == 0m
                   ? absoluteVariance > 0m
                   : absoluteVariance / systemQuantity > 0.10m);
    }

    private static double DistanceBetweenMeters(
        double latitudeOne,
        double longitudeOne,
        double latitudeTwo,
        double longitudeTwo)
    {
        const double earthRadiusMeters = 6_371_000;
        static double ToRadians(double degrees) => degrees * Math.PI / 180;

        var latitudeDelta = ToRadians(latitudeTwo - latitudeOne);
        var longitudeDelta = ToRadians(longitudeTwo - longitudeOne);
        var haversine = Math.Pow(Math.Sin(latitudeDelta / 2), 2) +
                        Math.Cos(ToRadians(latitudeOne)) *
                        Math.Cos(ToRadians(latitudeTwo)) *
                        Math.Pow(Math.Sin(longitudeDelta / 2), 2);
        return earthRadiusMeters * 2 *
               Math.Atan2(Math.Sqrt(haversine), Math.Sqrt(1 - haversine));
    }

    private static string BuildPhysicalCountNotes(PhysicalStockCount count)
    {
        var reason = count.ReasonNotes is null
            ? count.Reason
            : $"{count.Reason}: {count.ReasonNotes}";
        return $"Physical count {count.Reference}: counted {count.CountedQuantity:0.###}; system had {count.SystemQuantityAtCount:0.###}; reason: {reason}.";
    }

    public static PhysicalStockCountResponse ToPhysicalCountResponse(PhysicalStockCount count) =>
        new(
            count.Id,
            count.InventoryItemId,
            count.ItemName,
            count.Sku,
            count.SystemQuantityAtCount,
            count.CountedQuantity,
            count.Variance,
            count.Reason,
            count.ReasonNotes,
            count.CountedAt,
            count.CountedBy,
            count.BranchId,
            count.Reference,
            count.Status,
            DeserializePhotoUrls(count.PhotoUrlsJson),
            count.ReviewedBy,
            count.ReviewedAt,
            count.ReviewNotes,
            count.Latitude,
            count.Longitude);

    private async Task<IReadOnlyList<PhysicalCountChangedMovement>> GetMovementsAfterCountAsync(
        Guid inventoryItemId,
        DateTime countedAt,
        CancellationToken cancellationToken) =>
        await db.StockMovements.AsNoTracking()
            .Where(movement =>
                movement.InventoryItemId == inventoryItemId &&
                movement.OccurredAt > countedAt)
            .OrderBy(movement => movement.OccurredAt)
            .Take(20)
            .Select(movement => new PhysicalCountChangedMovement(
                movement.MovementType,
                movement.Quantity,
                movement.OccurredAt,
                movement.Reference,
                movement.PerformedBy,
                movement.Notes))
            .ToListAsync(cancellationToken);

    private static IReadOnlyList<string> DeserializePhotoUrls(string? photoUrlsJson) =>
        string.IsNullOrWhiteSpace(photoUrlsJson)
            ? []
            : JsonSerializer.Deserialize<IReadOnlyList<string>>(photoUrlsJson) ?? [];

    private async Task<Guid?> ResolveCategoryIdAsync(
        Guid tenantId,
        Guid? categoryId,
        string? categoryName,
        CancellationToken cancellationToken)
    {
        if (categoryId.HasValue)
        {
            if (await db.InventoryCategories.AnyAsync(
                    category => category.Id == categoryId.Value && category.TenantId == tenantId,
                    cancellationToken))
            {
                return categoryId;
            }

            ModelState.AddModelError("categoryId", "The category does not exist for this tenant.");
            return null;
        }

        var normalizedName = categoryName?.Trim();
        if (string.IsNullOrWhiteSpace(normalizedName))
        {
            return null;
        }

        var existingCategory = await db.InventoryCategories.FirstOrDefaultAsync(
            category => category.TenantId == tenantId && category.Name.ToLower() == normalizedName.ToLower(),
            cancellationToken);
        if (existingCategory is not null)
        {
            return existingCategory.Id;
        }

        var newCategory = new InventoryCategory { TenantId = tenantId, Name = normalizedName };
        db.InventoryCategories.Add(newCategory);
        return newCategory.Id;
    }

    private Guid? ResolveBranchScope(Guid? requestedBranchId)
    {
        if (User.IsInRole(UserRole.Admin.ToString()))
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
            .Include(item => item.Supplier)
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
            : item.Quantity <= item.ReorderLevel
                ? "LowStock"
                : "InStock";

        return new InventoryItemResponse(
            item.Id,
            item.Name,
            item.Sku,
            item.Description,
            item.ImageUrl,
            item.CategoryId,
            item.Category?.Name,
            item.UnitId,
            item.Unit?.Code,
            item.BranchId,
            item.Branch?.Name,
            item.SupplierId,
            item.Supplier?.Name,
            item.Supplier?.LeadTimeDays,
            item.Quantity,
            item.ReorderLevel,
            item.UnitCost,
            item.SellingPrice,
            status,
            item.CreatedAt);
    }

    private static bool IsValidImageUrl(string? imageUrl)
    {
        if (string.IsNullOrWhiteSpace(imageUrl)) return true;
        return imageUrl.Length <= 2048 &&
               Uri.TryCreate(imageUrl.Trim(), UriKind.Absolute, out var uri) &&
               (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps);
    }
}

public sealed record InventoryListResponse(
    IReadOnlyList<InventoryItemResponse> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages);

public sealed record InventoryCategoryOptionResponse(Guid Id, string Name);
public sealed record InventoryBranchOptionResponse(
    Guid Id,
    string Name,
    decimal? Latitude,
    decimal? Longitude);
public sealed record InventoryBranchStockRequest(Guid BranchId, decimal Quantity);

public sealed record InventoryItemResponse(
    Guid Id,
    string Name,
    string Sku,
    string? Description,
    string? ImageUrl,
    Guid? CategoryId,
    string? Category,
    Guid? UnitId,
    string? Unit,
    Guid? BranchId,
    string? Branch,
    Guid? SupplierId,
    string? SupplierName,
    int? SupplierLeadTimeDays,
    decimal Quantity,
    decimal ReorderLevel,
    decimal? UnitCost,
    decimal? SellingPrice,
    string Status,
    DateTime CreatedAt);

public sealed record RecordInventorySaleRequest(
    decimal Quantity,
    string? Reference = null,
    decimal? ExpectedSellingPrice = null,
    decimal? ExpectedUnitCost = null);

public sealed record RecordInventorySaleResponse(
    string Reference,
    Guid InventoryItemId,
    string ItemName,
    decimal Quantity,
    decimal UnitPrice,
    decimal Amount,
    decimal CostOfGoodsSold,
    decimal GrossProfit,
    decimal RemainingQuantity,
    DateTime OccurredAt);

public sealed record InventoryMovementResponse(
    Guid Id,
    Guid? BranchId,
    DateTime OccurredAt,
    string Item,
    string Sku,
    string MovementType,
    decimal Quantity,
    string? Reference,
    string? Notes,
    Guid? SupplierId,
    string? SupplierName,
    int? SupplierLeadTimeDays,
    string? PerformedBy);

public sealed record InventoryMovementListResponse(
    IReadOnlyList<InventoryMovementResponse> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages);

public sealed record CreateInventoryRequest(
    string Name,
    string Sku,
    string? Description,
    Guid? CategoryId,
    Guid? UnitId,
    Guid? BranchId,
    decimal Quantity = 0,
    decimal ReorderLevel = 0,
    decimal? UnitCost = null,
    Guid? SupplierId = null,
    string? Category = null,
    decimal? SellingPrice = null,
    IReadOnlyList<InventoryBranchStockRequest>? BranchStocks = null,
    string? ImageUrl = null);

public sealed record UpdateInventoryRequest(
    string? Name,
    string? Sku,
    string? Description,
    Guid? CategoryId,
    Guid? UnitId,
    Guid? BranchId,
    decimal ReorderLevel = 0,
    decimal? UnitCost = null,
    Guid? SupplierId = null,
    bool ClearSupplier = false,
    string? Category = null,
    decimal? SellingPrice = null,
    IReadOnlyList<InventoryBranchStockRequest>? BranchStocks = null,
    string? ImageUrl = null);

public sealed record AdjustInventoryRequest(
    decimal Quantity,
    string? Reference = null,
    string? Notes = null);

public sealed record RecordPhysicalCountRequest(
    decimal CountedQuantity,
    decimal SystemQuantityAtCount,
    DateTimeOffset CountedAt,
    string Reference,
    string Reason,
    string? ReasonNotes = null,
    decimal? Latitude = null,
    decimal? Longitude = null);

public sealed record PhysicalStockCountResponse(
    Guid Id,
    Guid InventoryItemId,
    string ItemName,
    string Sku,
    decimal SystemQuantityAtCount,
    decimal CountedQuantity,
    decimal Variance,
    string Reason,
    string? ReasonNotes,
    DateTime CountedAt,
    string CountedBy,
    Guid BranchId,
    string Reference,
    string Status,
    IReadOnlyList<string> PhotoUrls,
    string? ReviewedBy,
    DateTime? ReviewedAt,
    string? ReviewNotes,
    decimal? Latitude = null,
    decimal? Longitude = null,
    bool CanReview = true);

public sealed record PhysicalCountChangedMovement(
    string MovementType,
    decimal Quantity,
    DateTime OccurredAt,
    string? Reference,
    string? PerformedBy,
    string? Notes);

public static class PhysicalStockCountReasons
{
    public static readonly string[] All =
    [
        "NoDiscrepancy",
        "DamagedStock",
        "LostOrMissing",
        "CountingError",
        "SupplierShortage",
        "Other",
    ];
}

/// Reason is free text on purpose ("Spoiled", "Over-prepped", "Dropped",
/// "Expired") - the waste report groups by it, and every kitchen names
/// these differently.
public sealed record WasteInventoryRequest(
    decimal Quantity,
    string? Reason = null,
    string? Reference = null,
    string? Notes = null);

public sealed record InventoryAgentPlanRequest(string Objective, Guid? BranchId = null);

public sealed record ReceiveInventoryRequest(
    decimal Quantity,
    decimal? UnitCost = null,
    string? Reference = null,
    string? Notes = null);
