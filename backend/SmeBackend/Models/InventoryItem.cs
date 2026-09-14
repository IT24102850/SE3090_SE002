namespace SmeBackend.Models;

public class InventoryItem : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Sku { get; set; } = string.Empty;
    public string? Description { get; set; }
    public Guid? CategoryId { get; set; }
    public InventoryCategory? Category { get; set; }
    public Guid? UnitId { get; set; }
    public InventoryUnit? Unit { get; set; }
    public Guid? BranchId { get; set; }
    public Branch? Branch { get; set; }
    public decimal Quantity { get; set; }
    public decimal ReorderLevel { get; set; }
    public decimal? UnitCost { get; set; }
    public bool IsActive { get; set; } = true;
}
