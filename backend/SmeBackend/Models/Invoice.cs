namespace SmeBackend.Models;

public class Invoice : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid CustomerId { get; set; }
    public Guid? BookingId { get; set; }
    public string InvoiceNumber { get; set; } = string.Empty;
    public decimal TotalAmount { get; set; }
    public decimal Discount { get; set; }
    public decimal Tax { get; set; }
    public decimal FinalAmount { get; set; }
    public string Status { get; set; } = "Draft";
    public DateTime DueDate { get; set; }
    public string Currency { get; set; } = "LKR";
}