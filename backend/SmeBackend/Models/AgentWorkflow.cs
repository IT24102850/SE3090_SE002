namespace SmeBackend.Models;

public class AgentWorkflow : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public string Objective { get; set; } = string.Empty;
    public string? PlanJson { get; set; }
    public string Status { get; set; } = "Pending";
    public int CurrentStep { get; set; }
    public string? ToolResultsJson { get; set; }
    public string? ValidationResults { get; set; }
    public string ApprovalStatus { get; set; } = "Pending";
    public Guid? ApprovedBy { get; set; }
    public DateTime? ApprovedAt { get; set; }
    public string? FinalOutcome { get; set; }
    public string? ErrorLog { get; set; }
    public DateTime? CompletedAt { get; set; }
}