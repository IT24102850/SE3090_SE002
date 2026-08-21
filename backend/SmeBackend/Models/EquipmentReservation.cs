namespace SmeBackend.Models;

/// Links a Booking to an InventoryItem it reserves (e.g. dive tanks for a
/// diving trip, a wheelchair for a clinic visit). Minimal placeholder for
/// Student 3's fuller Inventory module — see InventoryController.cs.
public class EquipmentReservation : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid BookingId { get; set; }
    public Booking? Booking { get; set; }
    public Guid InventoryItemId { get; set; }
    public InventoryItem? InventoryItem { get; set; }
    public decimal Quantity { get; set; }
}
