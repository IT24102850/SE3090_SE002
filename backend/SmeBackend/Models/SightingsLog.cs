using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace SmeBackend.Models;

/// Deliberately spans marine *and* land wildlife rather than being
/// whale-only: a Yala safari operator logs leopard/elephant sightings
/// against the exact same table and the same success-rate analytics that a
/// Mirissa whale-watching operator uses. Adding a species is one enum value.
public enum SightingSpecies
{
    // Marine - whale watching (Mirissa, Trincomalee)
    BlueWhale,
    SpermWhale,
    BrydesWhale,
    HumpbackWhale,
    FinWhale,
    KillerWhale,
    SpinnerDolphin,
    BottlenoseDolphin,
    RissoDolphin,
    Turtle,
    // Land - safari (Yala, Udawalawe, Wilpattu, Minneriya)
    Leopard,
    Elephant,
    SlothBear,
    WaterBuffalo,
    Crocodile,
    Deer,
    Bird,
    Other
}

public enum SightingBehaviour
{
    Breaching,
    Spyhopping,
    TailSlapping,
    PodSwimming,
    Feeding,
    Resting,
    Hunting,
    Other
}

/// One wildlife sighting logged by the captain/guide, normally from the
/// departure's manifest view. The unit of the "sighting success rate" KPI:
/// departures with at least one row here / total departures that sailed.
public class SightingsLog
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public Guid TenantId { get; set; }

    /// The vessel/jeep the sighting was made from.
    [Required]
    public Guid ResourceId { get; set; }

    [ForeignKey(nameof(ResourceId))]
    public Resource Resource { get; set; } = null!;

    /// Set when the sighting is logged against a departure (the normal
    /// path). Null for a sighting recorded outside the departure board,
    /// e.g. backfilled historical data.
    public Guid? DepartureId { get; set; }

    [ForeignKey(nameof(DepartureId))]
    public Departure? Departure { get; set; }

    /// Optional link to one guest's booking - e.g. the guest whose photo
    /// this is. Not the normal case; a sighting belongs to the departure.
    public Guid? BookingId { get; set; }

    [Required]
    public DateTime DepartureDateTime { get; set; }

    public SightingSpecies Species { get; set; } = SightingSpecies.Other;

    /// Pod/herd size where it could be counted; null when unknown rather
    /// than 0, matching the pricing.child null-not-zero rule in
    /// docs/tourism-business-template.md.
    public int? Count { get; set; }

    public double? LocationLat { get; set; }

    public double? LocationLng { get; set; }

    public SightingBehaviour? Behaviour { get; set; }

    [MaxLength(2000)]
    public string? Notes { get; set; }

    /// jsonb string[] of Cloudinary URLs, same shape as
    /// Tenant.GalleryImageUrls.
    [Column(TypeName = "jsonb")]
    public string? PhotoUrls { get; set; }

    public Guid? LoggedByUserId { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime? DeletedAt { get; set; }
}
