namespace SmeBackend.Models;

public class CustomerOrderItem : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid CustomerOrderId { get; set; }
    public Guid InventoryItemId { get; set; }
    public string ItemName { get; set; } = string.Empty;
    public string Sku { get; set; } = string.Empty;
    public string? UnitName { get; set; }
    public decimal Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal LineTotal { get; set; }
}
