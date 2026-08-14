namespace SmeBackend.Models;

public class AnalyticsSnapshot : BaseEntity
{
    public Guid TenantId { get; set; }
    public Tenant Tenant { get; set; } = null!;
    public Guid? BranchId { get; set; }
    public Branch? Branch { get; set; }
    public string SnapshotType { get; set; } = string.Empty;
    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }
    public string Data { get; set; } = "{}";
    public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
}
