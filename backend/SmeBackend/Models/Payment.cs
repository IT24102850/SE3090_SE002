namespace SmeBackend.Models;

public class Payment : BaseEntity
{
    public Guid? InvoiceId { get; set; }
    public Invoice? Invoice { get; set; }
    public decimal Amount { get; set; }
    public string Method { get; set; } = string.Empty;
    /// Stripe | PayPal | Manual. Null on payments recorded before gateways.
    public string? Provider { get; set; }
    /// Pending (gateway checkout started, webhook not yet received) |
    /// Succeeded | Failed | Refunded. Only Succeeded counts toward the
    /// invoice balance.
    public string Status { get; set; } = PaymentStatuses.Succeeded;
    /// Who paid this share of a split bill ("Guest 2", a name) - optional.
    public string? PayerLabel { get; set; }
    public string? TransactionRef { get; set; }
    public string? GatewayResponse { get; set; }
    public DateTime? PaidAt { get; set; }
}

public static class PaymentStatuses
{
    public const string Pending = "Pending";
    public const string Succeeded = "Succeeded";
    public const string Failed = "Failed";
    public const string Refunded = "Refunded";
}
