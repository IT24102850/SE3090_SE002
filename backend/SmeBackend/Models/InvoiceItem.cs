namespace SmeBackend.Models;

public class InvoiceItem : BaseEntity
{
    public Guid? InvoiceId { get; set; }
    public Invoice? Invoice { get; set; }
    public string Description { get; set; } = string.Empty;
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal Amount { get; set; }
    public string Category { get; set; } = string.Empty;
}