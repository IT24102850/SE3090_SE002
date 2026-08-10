namespace SmeBackend.Models;

public class StockMovement : BaseEntity
{
    public Guid? InventoryItemId { get; set; }
    public InventoryItem? InventoryItem { get; set; }
    public string Type { get; set; } = string.Empty; // In, Out, Adjustment
    public decimal Quantity { get; set; }
    public string? Reason { get; set; }
    public Guid? ReferenceId { get; set; }
    public string? ReferenceType { get; set; }
    public Guid? CreatedBy { get; set; }
}