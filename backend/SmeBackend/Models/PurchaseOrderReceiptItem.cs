namespace SmeBackend.Models;

public class PurchaseOrderReceiptItem : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid PurchaseOrderReceiptId { get; set; }
    public Guid PurchaseOrderItemId { get; set; }
    public decimal DeliveredQuantity { get; set; }
    public decimal AcceptedQuantity { get; set; }
    public decimal DamagedQuantity { get; set; }
    public decimal ShortageQuantity { get; set; }
    public string? Notes { get; set; }
}
