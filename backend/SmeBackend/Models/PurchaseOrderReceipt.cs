namespace SmeBackend.Models;

public class PurchaseOrderReceipt : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid PurchaseOrderId { get; set; }
    public DateTime ReceivedAt { get; set; } = DateTime.UtcNow;
    public string ReceivedBy { get; set; } = string.Empty;
    public IList<PurchaseOrderReceiptItem> Items { get; set; } = new List<PurchaseOrderReceiptItem>();
}
