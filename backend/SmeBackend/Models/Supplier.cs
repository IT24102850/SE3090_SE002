namespace SmeBackend.Models;

public class Supplier : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? ContactPerson { get; set; }
    public string Email { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
    public string? Address { get; set; }
    public string? PaymentTerms { get; set; }
    public bool IsActive { get; set; } = true;
}