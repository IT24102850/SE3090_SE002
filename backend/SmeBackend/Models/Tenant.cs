namespace SmeBackend.Models;

public class Tenant : BaseEntity
{
    public string Name { get; set; } = string.Empty;
    public string BusinessType { get; set; } = string.Empty;
    public string? LogoUrl { get; set; }
    public bool IsActive { get; set; } = true;

    public ICollection<Branch> Branches { get; set; } = new List<Branch>();
    public ICollection<User> Users { get; set; } = new List<User>();
    public ICollection<AgentWorkflow> AgentWorkflows { get; set; } = new List<AgentWorkflow>();
    public ICollection<Resource> Resources { get; set; } = new List<Resource>();
    public ICollection<Booking> Bookings { get; set; } = new List<Booking>();
}