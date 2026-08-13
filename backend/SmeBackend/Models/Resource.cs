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

    [Required]
    [MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(20)]
    public string? Code { get; set; }

    public ResourceCategory Category { get; set; } = ResourceCategory.Other;

    public ResourceStatus Status { get; set; } = ResourceStatus.Available;

    [MaxLength(500)]
    public string? Description { get; set; }

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