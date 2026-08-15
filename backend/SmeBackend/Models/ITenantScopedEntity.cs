namespace SmeBackend.Models;

public interface ITenantScopedEntity
{
    Guid TenantId { get; set; }
}
