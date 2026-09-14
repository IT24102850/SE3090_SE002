namespace SmeBackend.Models;

public class EquipmentMaintenance : BaseEntity
{
    public Guid? EquipmentItemId { get; set; }
    public EquipmentItem? EquipmentItem { get; set; }
    public DateTime MaintenanceDate { get; set; }
    public DateTime NextDueDate { get; set; }
    public decimal Cost { get; set; }
    public string? Notes { get; set; }
    public string Status { get; set; } = "Scheduled";
}
