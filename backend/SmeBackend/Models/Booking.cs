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
    Rejected,
    // Weather cancellations are tracked apart from ordinary Cancelled ones:
    // the operator did not lose the guest, the sea did, so these feed the
    // weather-cancellation report and the bulk-reschedule offer rather than
    // the churn/no-show numbers. Appended last - BookingStatus is persisted
    // by name (HasConversion<string>), so existing rows are unaffected, and
    // the mobile app's status switch already has a default branch.
    WeatherCancelled
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

    // ── Fixed-departure excursion fields (archetype A) ──────────────────
    // All optional and all additive: a booking that leaves them null prices
    // and behaves exactly as it did before they existed.

    /// The sailing this reservation is on. Null for every booking that is
    /// not part of a shared departure (a room night, a dive lesson, ...).
    public Guid? DepartureId { get; set; }

    /// jsonb ticket breakdown, the fix for the per-ticket-type-pricing
    /// limitation in docs/tourism-business-template.md section 6:
    ///   [{ "type": "Adult", "qty": 2, "unitPrice": 7500 },
    ///    { "type": "Child", "qty": 1, "unitPrice": 4000 }]
    /// Unit prices come from BookingType.ConfigJson pricing.adult/.child/
    /// .infant. Null = the pre-existing "one unit at one price" behaviour.
    [Column(TypeName = "jsonb")]
    public string? TicketBreakdown { get; set; }

    /// jsonb liability-waiver state:
    ///   { "signedAt": "...", "signerName": "...", "minorCount": 1 }
    /// Null/absent signedAt = unsigned, which is what the manifest's waiver
    /// completion percentage counts.
    [Column(TypeName = "jsonb")]
    public string? Waiver { get; set; }

    /// Booking channel - "WalkIn" | "Online" | "OTA" | free text. Free-form
    /// rather than an enum because channel names are per-operator; the
    /// reports group by whatever string is stored. No OTA integration is
    /// implied by this field (explicitly out of scope) - it only records
    /// where a booking came from so the channel-split report can exist.
    [MaxLength(50)]
    public string? Source { get; set; }

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