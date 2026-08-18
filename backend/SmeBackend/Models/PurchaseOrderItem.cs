using System;

namespace SmeBackend.Models;

public class PurchaseOrderItem : BaseEntity, ITenantScopedEntity
{
    public Guid TenantId { get; set; }
    public Guid PurchaseOrderId { get; set; }
    public Guid? InventoryItemId { get; set; }
    public string? Description { get; set; }
    public decimal Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal ReceivedQuantity { get; set; }
}
