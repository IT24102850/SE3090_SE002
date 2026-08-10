namespace SmeBackend.Models;

public class Resource : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid BranchId { get; set; }
    public string ResourceType { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int? Capacity { get; set; }
    public bool IsActive { get; set; } = true;
}