namespace SmeBackend.Models;

public class BookingType : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? ConfigJson { get; set; }
    public bool IsActive { get; set; } = true;
}