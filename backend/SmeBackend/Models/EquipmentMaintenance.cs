namespace SmeBackend.Models;

public class EquipmentMaintenance : BaseEntity
{
    public Guid? InventoryItemId { get; set; }
    public InventoryItem? InventoryItem { get; set; }
    public DateTime MaintenanceDate { get; set; }
    public DateTime NextDueDate { get; set; }
    public decimal Cost { get; set; }
    public string? Notes { get; set; }
    public string Status { get; set; } = "Scheduled";
}