namespace SmeBackend.Models;

public class PaymentGateway : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }

    public string Name { get; set; } = string.Empty;

    public string Provider { get; set; } = string.Empty;

    public string Currency { get; set; } = "LKR";

    public bool IsActive { get; set; } = true;

    public string? ConfigurationJson { get; set; }
}