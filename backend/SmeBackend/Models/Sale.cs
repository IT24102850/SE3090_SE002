namespace SmeBackend.Models;

public class Sale : BaseEntity, ITenantScopedEntity
{
    public Guid TenantId { get; set; }
    public Guid BranchId { get; set; }
    public DateTime OccurredAt { get; set; } = DateTime.UtcNow;
    public decimal Amount { get; set; }
    public string Reference { get; set; } = string.Empty;
}
