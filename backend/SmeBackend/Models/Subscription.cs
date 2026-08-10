namespace SmeBackend.Models;

public class Subscription : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid CustomerId { get; set; }
    public string PlanName { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public string BillingCycle { get; set; } = string.Empty;
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public bool AutoRenew { get; set; }
    public string Status { get; set; } = "Active";
}