namespace SmeBackend.Models;

public class PurchaseOrder : BaseEntity
{
    public Guid TenantId { get; set; }
    public Tenant Tenant { get; set; } = null!;
    public Guid BranchId { get; set; }
    public Branch Branch { get; set; } = null!;
    public Guid SupplierId { get; set; }
    public Supplier Supplier { get; set; } = null!;
    public string OrderNumber { get; set; } = string.Empty;
    public DateTime OrderedAt { get; set; } = DateTime.UtcNow;
    public DateTime? ExpectedDeliveryAt { get; set; }
    public DateTime? ReceivedAt { get; set; }
    public string Status { get; set; } = "Draft";
    public decimal TotalAmount { get; set; }
    public string? Notes { get; set; }
    public ICollection<StockMovement> StockMovements { get; set; } = [];
}
