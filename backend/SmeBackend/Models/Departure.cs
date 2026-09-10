using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace SmeBackend.Models;

/// The operational lifecycle of one sailing/drive. Deliberately separate
/// from BookingStatus: a departure is the *vessel's* state (has it left the
/// harbour yet?), while each guest's Booking keeps its own state (did this
/// particular guest check in?). Fixed-departure excursions - archetype A in
/// docs/tourism-business-template.md - are the only businesses that need it.
public enum DepartureStatus
{
    Scheduled,
    Boarding,
    AtSea,
    Returned,
    CancelledWeather,
    CancelledOther
}

/// One scheduled sailing of one vessel: the row an operator's departure
/// board is built from. Bookings point at it via Booking.DepartureId, so a
/// departure is the natural grouping for a manifest, a safety checklist, a
/// weather cancellation, and a sightings log entry.
///
/// Plain TenantId (not ITenantScoped) on purpose - the whole booking engine
/// (Booking, Resource, BookingType) scopes explicitly in its controllers
/// off the JWT's tenantId claim rather than through AppDbContext's
/// ApplyTenantScope, and this table belongs to that half of the schema.
public class Departure
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public Guid TenantId { get; set; }

    /// The vessel/jeep. Its CustomAttributes.capacity is the licensed
    /// passenger capacity unless LicensedCapacity below overrides it.
    [Required]
    public Guid ResourceId { get; set; }

    [ForeignKey(nameof(ResourceId))]
    public Resource Resource { get; set; } = null!;

    public Guid? BookingTypeId { get; set; }

    [ForeignKey(nameof(BookingTypeId))]
    public BookingType? BookingType { get; set; }

    [Required]
    public DateTime ScheduledDeparture { get; set; }

    [Required]
    public DateTime ScheduledReturn { get; set; }

    public DateTime? ActualDepartureAt { get; set; }

    public DateTime? ActualReturnAt { get; set; }

    public DepartureStatus Status { get; set; } = DepartureStatus.Scheduled;

    /// The User (Staff role) skippering this sailing.
    public Guid? CaptainUserId { get; set; }

    /// jsonb array of crew, same raw-JSON-string convention as
    /// Resource.CustomAttributes: [{ "userId": "...", "name": "...", "role": "Guide" }]
    [Column(TypeName = "jsonb")]
    public string? Crew { get; set; }

    /// jsonb pre-departure safety checklist:
    /// { "jacketsCounted": true, "briefingDone": true, "manifestClosed": false,
    ///   "weatherChecked": true, "completedAt": "...", "completedBy": "..." }
    /// Incomplete blocks the AtSea transition for non-Admin callers.
    [Column(TypeName = "jsonb")]
    public string? SafetyChecklist { get; set; }

    /// Overrides Resource.CustomAttributes.capacity for this one sailing
    /// (e.g. a vessel running below licensed max while a section is out of
    /// service). Null = fall back to the resource's configured capacity.
    public int? LicensedCapacity { get; set; }

    [MaxLength(500)]
    public string? CancellationReason { get; set; }

    [MaxLength(2000)]
    public string? Notes { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public Guid? CreatedBy { get; set; }

    public Guid? UpdatedBy { get; set; }

    public DateTime? DeletedAt { get; set; }
}
