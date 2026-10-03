namespace SmeBackend.Models;

public class CustomerOrderStatusUpdate : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid CustomerOrderId { get; set; }
    public string Status { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public Guid? ChangedByUserId { get; set; }
}
