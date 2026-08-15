namespace SmeBackend.Models;

public class PurchaseOrder : BaseEntity, ITenantScopedEntity
{
    public Guid TenantId { get; set; }
    public Guid BranchId { get; set; }
    public Guid SupplierId { get; set; }
    public string Number { get; set; } = string.Empty;
    public string Status { get; set; } = "Draft";
}
