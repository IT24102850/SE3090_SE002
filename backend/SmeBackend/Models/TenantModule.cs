namespace SmeBackend.Models;

public class TenantModule : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Tenant Tenant { get; set; } = null!;
    public string ModuleName { get; set; } = string.Empty; // Appointments, Billing, Inventory, Analytics
    public bool IsEnabled { get; set; } = true;
    // Business-type-specific config
    public string? ConfigJson { get; set; }
}