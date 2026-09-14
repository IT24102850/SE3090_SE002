namespace SmeBackend.Models;

public class Notification : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid? UserId { get; set; }
    public Guid? BranchId { get; set; }
    public string Type { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public bool IsRead { get; set; }
}
