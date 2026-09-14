namespace SmeBackend.Models;

public interface ITenantScoped
{
    Guid TenantId { get; set; }
}