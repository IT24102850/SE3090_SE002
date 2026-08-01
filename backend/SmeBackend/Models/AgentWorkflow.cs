namespace SmeBackend.Models;

public enum AgentWorkflowStatus
{
    Draft,
    InProgress,
    Completed,
    Failed
}

public class AgentWorkflow : BaseEntity
{
    public Guid TenantId { get; set; }
    public Tenant Tenant { get; set; } = null!;
    public Guid? BranchId { get; set; }
    public Branch? Branch { get; set; }
    public Guid? CreatedByUserId { get; set; }
    public User? CreatedByUser { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? InputPayload { get; set; }
    public string? OutputPayload { get; set; }
    public AgentWorkflowStatus Status { get; set; } = AgentWorkflowStatus.Draft;
}