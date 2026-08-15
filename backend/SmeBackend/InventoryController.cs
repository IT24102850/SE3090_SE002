using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Controllers;

/// Minimal placeholder for Student 3's Inventory module - just enough
/// tenant-scoped CRUD for InventoryItem (which already existed as a model,
/// unused) to unblock BookingsController's equipment-reservation endpoints
/// below. Not a substitute for a fuller Inventory feature (purchase
/// orders, suppliers, stock movements, low-stock alerts, ...).
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class InventoryController : ControllerBase
{
    private readonly AppDbContext _db;
    public InventoryController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] Guid tenantId)
    {
        var items = await _db.InventoryItems.AsNoTracking()
            .Where(i => i.TenantId == tenantId && i.IsActive)
            .OrderBy(i => i.Name)
            .ToListAsync();
        return Ok(items);
    }

    [HttpPost]
    [Authorize(Roles = $"{Roles.Admin},{Roles.Manager}")]
    public async Task<IActionResult> Create([FromBody] CreateInventoryItemDto dto)
    {
        var item = new InventoryItem
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
        _db.InventoryItems.Add(item);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetAll), new { tenantId = dto.TenantId }, item);
    }
}

public record CreateInventoryItemDto(
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
