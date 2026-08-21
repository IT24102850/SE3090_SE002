namespace SmeBackend.Models;

/// Equipment a booking can reserve (e.g. dive tanks, wheelchairs) - separate
/// from the full Inventory module's InventoryItem/stock-tracking domain.
/// Renamed from the original placeholder "InventoryItem" once the real
/// Inventory module (categories, units, suppliers, purchase orders) landed.
public class EquipmentItem : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid BranchId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string SKU { get; set; } = string.Empty;
    public string Unit { get; set; } = string.Empty;
    public decimal CurrentStock { get; set; }
    public decimal ReorderLevel { get; set; }
    public decimal ReorderQuantity { get; set; }
    public decimal CostPrice { get; set; }
    public decimal SellingPrice { get; set; }
    public Guid? SupplierId { get; set; }
    public bool IsActive { get; set; } = true;
}
