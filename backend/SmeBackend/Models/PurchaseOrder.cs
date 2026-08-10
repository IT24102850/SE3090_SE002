namespace SmeBackend.Models;

public class PurchaseOrder : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid SupplierId { get; set; }
    public Supplier Supplier { get; set; } = null!;
    public string Status { get; set; } = "Draft";
    public decimal TotalAmount { get; set; }
    public DateTime? ExpectedDelivery { get; set; }
    public string? Notes { get; set; }
    public Guid? CreatedBy { get; set; }
}