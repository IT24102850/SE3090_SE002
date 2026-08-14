namespace SmeBackend.Models;

public class EquipmentMaintenance : BaseEntity
{
    public Guid TenantId { get; set; }
    public Tenant Tenant { get; set; } = null!;
    public Guid BranchId { get; set; }
    public Branch Branch { get; set; } = null!;
    public Guid InventoryItemId { get; set; }
    public InventoryItem InventoryItem { get; set; } = null!;
    public string MaintenanceType { get; set; } = string.Empty;
    public string Status { get; set; } = "Scheduled";
    public DateTime ScheduledFor { get; set; }
    public DateTime? CompletedAt { get; set; }
    public decimal? Cost { get; set; }
    public string? PerformedBy { get; set; }
    public string? Notes { get; set; }
}
