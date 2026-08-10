namespace SmeBackend.Models;

public class Booking : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid BranchId { get; set; }
    public string BookingType { get; set; } = string.Empty;
    public Guid CustomerId { get; set; }
    public Guid? ResourceId { get; set; }
    public DateTime ScheduledDateTime { get; set; }
    public int Duration { get; set; }
    public string Status { get; set; } = "Pending";
    public string? Notes { get; set; }
    public Guid? CreatedBy { get; set; }
}