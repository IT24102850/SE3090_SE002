using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace SmeBackend.Models;

public enum BookingStatus
{
    Pending,
    Confirmed,
    CheckedIn,
    InProgress,
    Completed,
    Cancelled,
    NoShow,
    Rejected
}

public enum BookingPriority
{
    Low,
    Normal,
    High,
    Urgent
}

public class Booking
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public Guid TenantId { get; set; }

    [Required]
    public Guid ResourceId { get; set; }

    [ForeignKey(nameof(ResourceId))]
    public Resource Resource { get; set; } = null!;

    [Required]
    public Guid BookingTypeId { get; set; }

    [ForeignKey(nameof(BookingTypeId))]
    public BookingType BookingType { get; set; } = null!;

    [Required]
    public Guid BookedBy { get; set; }

    public Guid? BookedFor { get; set; }

    [MaxLength(200)]
    public string? Title { get; set; }

    [MaxLength(2000)]
    public string? Notes { get; set; }

    [Required]
    public DateTime StartTime { get; set; }

    [Required]
    public DateTime EndTime { get; set; }

    public BookingStatus Status { get; set; } = BookingStatus.Pending;

    public BookingPriority Priority { get; set; } = BookingPriority.Normal;

    public int? AttendeeCount { get; set; }

    public DateTime? CheckInAt { get; set; }

    public DateTime? CheckOutAt { get; set; }

    public Guid? ApprovedBy { get; set; }

    public DateTime? ApprovedAt { get; set; }

    [MaxLength(500)]
    public string? RejectionReason { get; set; }

    [MaxLength(500)]
    public string? CancellationReason { get; set; }

    [Column(TypeName = "jsonb")]
    public string? FormData { get; set; }

    public bool ReminderSent { get; set; } = false;

    [Column(TypeName = "decimal(18,2)")]
    public decimal? TotalCost { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public Guid? CreatedBy { get; set; }

    public Guid? UpdatedBy { get; set; }

    public DateTime? DeletedAt { get; set; }

    public int Version { get; set; } = 1;
}