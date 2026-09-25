namespace SmeBackend.Models;

/// Pipeline: Submitted -> UnderReview -> Approved | Rejected.
public class InsuranceClaim : BaseEntity
{
    public Guid? InvoiceId { get; set; }
    public Invoice? Invoice { get; set; }
    public string Provider { get; set; } = string.Empty;
    public string PolicyNumber { get; set; } = string.Empty;
    public decimal ClaimAmount { get; set; }
    public string Status { get; set; } = "Submitted";
    public DateTime? SubmittedAt { get; set; }
    public DateTime? ReviewStartedAt { get; set; }
    public DateTime? ApprovedAt { get; set; }
    public string? RejectionReason { get; set; }
    public string? Notes { get; set; }
    /// JSON array of { url, fileName, uploadedAt } - supporting documents
    /// (photos of the policy card, discharge notes) uploaded from the app.
    public string? DocumentsJson { get; set; }
}
