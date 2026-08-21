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

    // "Slot" (fixed-duration time slot, the original/default shape) | "Night"
    // (check-in/check-out, e.g. homestays) | "DateRange" (multi-day, e.g.
    // vehicle rental) | "Package" (multi-day itinerary against one primary
    // resource - see docs/tourism-business-template.md). Existing rows
    // default to "Slot" so every pre-existing business type is unaffected.
    [MaxLength(20)]
    public string BookingUnit { get; set; } = "Slot";

    // Free-form per-bookingUnit/per-tourism-subtype config (capacity,
    // weather-dependent, cancellation cutoff/refund, check-in/out time,
    // itinerary, ...) - same config-not-code pattern as
    // Resource.CustomAttributes and TenantModule.ConfigJson.
    [Column(TypeName = "jsonb")]
    public string? ConfigJson { get; set; }

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