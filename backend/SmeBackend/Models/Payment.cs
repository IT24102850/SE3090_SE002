namespace SmeBackend.Models;

public class Payment : BaseEntity
{
    public Guid? InvoiceId { get; set; }
    public Invoice? Invoice { get; set; }
    public decimal Amount { get; set; }
    public string Method { get; set; } = string.Empty;
    public string? TransactionRef { get; set; }
    public string? GatewayResponse { get; set; }
    public DateTime? PaidAt { get; set; }
}