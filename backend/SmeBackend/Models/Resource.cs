using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace SmeBackend.Models;

public enum ResourceStatus
{
    Available,
    UnderMaintenance,
    Archived,
    Reserved
}

public enum ResourceCategory
{
    Room,
    Equipment,
    Vehicle,
    Staff,
    Desk,
    Other
}

public class Resource
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public Guid TenantId { get; set; }

    public Guid? BranchId { get; set; }
    public Branch? Branch { get; set; }

    [Required]
    [MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(20)]
    public string? Code { get; set; }

    public ResourceCategory Category { get; set; } = ResourceCategory.Other;

    public ResourceStatus Status { get; set; } = ResourceStatus.Available;

    [MaxLength(500)]
    public string? Description { get; set; }

    /// Doctor/staff specialty (e.g. "Cardiology"), used by FR-B1 availability search.
    [MaxLength(100)]
    public string? Specialty { get; set; }

    /// The User (Staff role) this resource represents, so a doctor's login maps to
    /// their own bookings for "my schedule" (FR-B8).
    public Guid? LinkedUserId { get; set; }

    public int? Capacity { get; set; }

    [Column(TypeName = "jsonb")]
    public string? LocationMetadata { get; set; }

    [Column(TypeName = "jsonb")]
    public string? CustomAttributes { get; set; }

    [Column(TypeName = "decimal(18,2)")]
    public decimal? HourlyRate { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public Guid? CreatedBy { get; set; }

    public Guid? UpdatedBy { get; set; }

    public DateTime? DeletedAt { get; set; }

    public ICollection<Booking> Bookings { get; set; } = new List<Booking>();
}