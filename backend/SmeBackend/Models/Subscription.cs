namespace SmeBackend.Models;

/// A membership: one customer on one plan for one period. The class existed
/// unused since the initial schema; the gym dashboard wired it up.
///
/// Status is the membership's lifecycle - Active | Frozen | Cancelled |
/// Expired - and PaymentStatus is the state of its latest billing run -
/// Paid | Pending | Failed | Overdue - kept apart because a member whose
/// card bounced is still an active member the desk should chase, not a
/// lapsed one.
public class Subscription : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid? BranchId { get; set; }
    public Guid CustomerId { get; set; }
    /// The tier: "Basic", "Standard", "Premium", "Student"... free text,
    /// grouped by the reports as-is.
    public string PlanName { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    /// Monthly | Quarterly | Yearly | OneOff (day passes and drop-ins).
    public string BillingCycle { get; set; } = string.Empty;
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public bool AutoRenew { get; set; }
    public string Status { get; set; } = "Active";
    public string PaymentStatus { get; set; } = "Paid";
    public DateTime? LastPaymentAt { get; set; }
    public DateTime? NextBillingAt { get; set; }
    public string? Notes { get; set; }
}
