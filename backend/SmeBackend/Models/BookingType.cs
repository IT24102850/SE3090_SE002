using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace SmeBackend.Models;

public enum BookingTypeStatus
{
    Active,
    Inactive,
    Archived
}

public class BookingType
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public Guid TenantId { get; set; }

    [Required]
    [MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [MaxLength(50)]
    public string Slug { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? Description { get; set; }

    [MaxLength(7)]
    public string? ColorHex { get; set; } = "#3B82F6";

    public BookingTypeStatus Status { get; set; } = BookingTypeStatus.Active;

    public int DefaultDurationMinutes { get; set; } = 60;

    public bool RequiresApproval { get; set; } = false;

    public int? MaxParticipants { get; set; }

    public int BufferMinutesBefore { get; set; } = 0;

    public int BufferMinutesAfter { get; set; } = 0;

    [Column(TypeName = "jsonb")]
    public string? CancellationPolicy { get; set; }

    [Column(TypeName = "jsonb")]
    public string? CustomFormSchema { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public Guid? CreatedBy { get; set; }

    public Guid? UpdatedBy { get; set; }

    public DateTime? DeletedAt { get; set; }

    public ICollection<Booking> Bookings { get; set; } = new List<Booking>();
}