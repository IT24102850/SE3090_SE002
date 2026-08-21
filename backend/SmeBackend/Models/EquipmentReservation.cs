namespace SmeBackend.Models;

/// Links a Booking to an EquipmentItem it reserves (e.g. dive tanks for a
/// diving trip, a wheelchair for a clinic visit) - separate from the full
/// Inventory module's InventoryItem/stock-tracking domain.
public class EquipmentReservation : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid BookingId { get; set; }
    public Booking? Booking { get; set; }
    public Guid EquipmentItemId { get; set; }
    public EquipmentItem? EquipmentItem { get; set; }
    public decimal Quantity { get; set; }
}
