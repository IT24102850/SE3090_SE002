namespace SmeBackend.Models;

public class Branch : BaseEntity
{
    public Guid TenantId { get; set; }
    public Tenant Tenant { get; set; } = null!;
    public string Name { get; set; } = string.Empty;
    public string Address { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;

    public ICollection<User> Users { get; set; } = new List<User>();
    public ICollection<AgentWorkflow> AgentWorkflows { get; set; } = new List<AgentWorkflow>();
    public ICollection<Resource> Resources { get; set; } = new List<Resource>();
    public ICollection<Booking> Bookings { get; set; } = new List<Booking>();
}