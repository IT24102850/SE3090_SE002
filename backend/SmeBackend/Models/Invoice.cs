namespace SmeBackend.Models;

public class Invoice : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public Guid? BranchId { get; set; }
    public Guid CustomerId { get; set; }
    public Guid? BookingId { get; set; }
    public Booking? Booking { get; set; }
    /// Set when the invoice was raised by a subscription (manually or by the
    /// renewal engine) - what backs a member's payment history.
    public Guid? SubscriptionId { get; set; }
    public Guid? TemplateId { get; set; }
    public string InvoiceNumber { get; set; } = string.Empty;
    public decimal TotalAmount { get; set; }
    public decimal Discount { get; set; }
    /// The code the discount came from (a coupon or promo), kept for the
    /// audit trail and for the agent's discount-cap check.
    public string? DiscountCode { get; set; }
    public decimal Tax { get; set; }
    public decimal FinalAmount { get; set; }
    public string Status { get; set; } = "Draft";
    public DateTime DueDate { get; set; }
    public string Currency { get; set; } = "LKR";
    public string? Notes { get; set; }
    /// Payment schedules (installments, milestones, deposit + balance) are a
    /// set of invoices sharing one ScheduleGroup; ScheduleLabel names the part
    /// ("Deposit", "Installment 2 of 4", "Milestone: Handover").
    public string? ScheduleGroup { get; set; }
    public string? ScheduleLabel { get; set; }
    /// When the automation last chased this invoice - reminders are spaced
    /// out, never sent on every run.
    public DateTime? LastReminderAt { get; set; }
    public ICollection<InvoiceItem> Items { get; set; } = new List<InvoiceItem>();
    public ICollection<Payment> Payments { get; set; } = new List<Payment>();
}
