namespace SmeBackend.Services;

public interface ITenantContext
{
    Guid? CurrentTenantId { get; }
    void SetTenantId(Guid tenantId);
}

public class TenantContext : ITenantContext
{
    public Guid? CurrentTenantId { get; private set; }
    
    public void SetTenantId(Guid tenantId)
    {
        CurrentTenantId = tenantId;
    }
}