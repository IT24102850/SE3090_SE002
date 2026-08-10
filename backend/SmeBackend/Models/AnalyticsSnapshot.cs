namespace SmeBackend.Models;

public class AnalyticsSnapshot : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public string MetricType { get; set; } = string.Empty;
    public decimal MetricValue { get; set; }
    public string? Dimension { get; set; }
    public DateTime SnapshotDate { get; set; }
}