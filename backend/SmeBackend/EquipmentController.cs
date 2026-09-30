using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Authorization;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// Minimal tenant-scoped CRUD for EquipmentItem, used to back
/// BookingsController's equipment-reservation endpoints (dive tanks,
/// wheelchairs, ...). Distinct from the full Inventory module's
/// InventoryController (categories, units, suppliers, purchase orders,
/// stock movements, low-stock alerts).
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class EquipmentController : ControllerBase
{
    private readonly AppDbContext _db;
    public EquipmentController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<IActionResult> GetAll(
        [FromQuery] Guid tenantId,
        CancellationToken cancellationToken)
    {
        if (!Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out var callerTenantId))
            return Unauthorized();
        if (callerTenantId != tenantId)
            return Forbid();

        var itemsQuery = _db.EquipmentItems.AsNoTracking()
            .Where(item => item.TenantId == callerTenantId && item.IsActive);
        if (User.IsInRole(Roles.Manager))
        {
            if (!Guid.TryParse(User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value, out var branchId))
                return Forbid();
            itemsQuery = itemsQuery.Where(item => item.BranchId == branchId);
        }

        var items = await itemsQuery
            .OrderBy(i => i.Name)
            .ToListAsync(cancellationToken);
        return Ok(items);
    }

    [HttpPost]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> Create([FromBody] CreateEquipmentItemDto dto)
    {
        if (!Guid.TryParse(User.FindFirst(InventoryAccessHandler.TenantIdClaimType)?.Value, out var tenantId))
            return Unauthorized();
        if (string.IsNullOrWhiteSpace(dto.Name) || dto.Name.Trim().Length > 200)
            return BadRequest(new { message = "Equipment name is required and must be 200 characters or fewer." });
        if (dto.BranchId == Guid.Empty ||
            !await _db.Branches.AnyAsync(branch =>
                branch.Id == dto.BranchId &&
                branch.TenantId == tenantId &&
                branch.IsActive))
            return BadRequest(new { message = "Select an active branch belonging to your business." });
        if (User.IsInRole(Roles.Manager) &&
            (!Guid.TryParse(User.FindFirst(InventoryAccessHandler.BranchIdClaimType)?.Value, out var managerBranchId) ||
             managerBranchId != dto.BranchId))
            return Forbid();
        if (dto.CurrentStock < 0 || dto.ReorderLevel < 0 || dto.CostPrice < 0 || dto.SellingPrice < 0)
            return BadRequest(new { message = "Stock levels and prices cannot be negative." });

        var item = new EquipmentItem
        {
            TenantId = tenantId,
            BranchId = dto.BranchId,
            Name = dto.Name.Trim(),
            Category = dto.Category ?? string.Empty,
            SKU = dto.SKU ?? string.Empty,
            Unit = dto.Unit ?? string.Empty,
            CurrentStock = dto.CurrentStock,
            ReorderLevel = dto.ReorderLevel,
            CostPrice = dto.CostPrice,
            SellingPrice = dto.SellingPrice,
            // Only set for date-controlled safety gear (life rafts, flares,
            // extinguishers, EPIRBs, first-aid kits). Null everywhere else,
            // which the safety panel reads as "not expiry-tracked".
            ExpiryDate = dto.ExpiryDate.HasValue ? DateTimeUtil.AsUtc(dto.ExpiryDate.Value) : null
        };
        _db.EquipmentItems.Add(item);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetAll), new { tenantId }, item);
    }

    /// <summary>Updates an equipment item's stock or its safety-gear expiry date.</summary>
    [HttpPut("{id}")]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateEquipmentItemDto dto)
    {
        var item = await _db.EquipmentItems.FirstOrDefaultAsync(i => i.Id == id);
        if (item == null) return NotFound();

        if (!string.IsNullOrWhiteSpace(dto.Name)) item.Name = dto.Name;
        if (dto.Category != null) item.Category = dto.Category;
        if (dto.CurrentStock.HasValue) item.CurrentStock = dto.CurrentStock.Value;
        if (dto.ReorderLevel.HasValue) item.ReorderLevel = dto.ReorderLevel.Value;
        // Servicing an item pushes its expiry forward; ClearExpiryDate is the
        // only way to unset one, since a null ExpiryDate in the payload has
        // to mean "leave it alone" for every partial update that omits it.
        if (dto.ExpiryDate.HasValue) item.ExpiryDate = DateTimeUtil.AsUtc(dto.ExpiryDate.Value);
        else if (dto.ClearExpiryDate == true) item.ExpiryDate = null;
        if (dto.IsActive.HasValue) item.IsActive = dto.IsActive.Value;
        item.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return Ok(item);
    }
}

public record CreateEquipmentItemDto(
    Guid TenantId,
    Guid BranchId,
    string Name,
    string? Category,
    string? SKU,
    string? Unit,
    decimal CurrentStock,
    decimal ReorderLevel,
    decimal CostPrice,
    decimal SellingPrice,
    DateTime? ExpiryDate = null
);

public record UpdateEquipmentItemDto(
    string? Name,
    string? Category,
    decimal? CurrentStock,
    decimal? ReorderLevel,
    DateTime? ExpiryDate,
    bool? ClearExpiryDate,
    bool? IsActive
);
