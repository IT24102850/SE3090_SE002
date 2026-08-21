using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
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
    public async Task<IActionResult> GetAll([FromQuery] Guid tenantId)
    {
        var items = await _db.EquipmentItems.AsNoTracking()
            .Where(i => i.TenantId == tenantId && i.IsActive)
            .OrderBy(i => i.Name)
            .ToListAsync();
        return Ok(items);
    }

    [HttpPost]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> Create([FromBody] CreateEquipmentItemDto dto)
    {
        var item = new EquipmentItem
        {
            TenantId = dto.TenantId,
            BranchId = dto.BranchId,
            Name = dto.Name,
            Category = dto.Category ?? string.Empty,
            SKU = dto.SKU ?? string.Empty,
            Unit = dto.Unit ?? string.Empty,
            CurrentStock = dto.CurrentStock,
            ReorderLevel = dto.ReorderLevel,
            CostPrice = dto.CostPrice,
            SellingPrice = dto.SellingPrice
        };
        _db.EquipmentItems.Add(item);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetAll), new { tenantId = dto.TenantId }, item);
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
    decimal SellingPrice
);
