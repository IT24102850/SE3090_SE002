using System.ComponentModel.DataAnnotations.Schema;

namespace SmeBackend.Models;

public class Tenant : BaseEntity
{
    public string Name { get; set; } = string.Empty;
    public string BusinessType { get; set; } = string.Empty;

    // Optional finer-grained category within BusinessType - currently only
    // populated for Tourism (e.g. "Accommodation", "Water sports / diving"),
    // see docs/tourism-business-template.md.
    public string? SubType { get; set; }

    public string? LogoUrl { get; set; }
    public bool IsActive { get; set; } = true;

    // FR-AS11: reschedule/cancellation cutoff policy, configurable per tenant
    // (previously hardcoded in BookingsController).
    public int RescheduleCutoffHours { get; set; } = 2;
    public int CancellationCutoffHours { get; set; } = 1;

    // ── Business Profile (TenantProfileController) ─────────────────────
    // Shared, business-type-agnostic "TripAdvisor listing" shell. None of
    // this is Tourism/diving-specific - sub-type content stays on
    // BookingType, entirely separate.
    public string? CoverImageUrl { get; set; }

    // jsonb raw JSON text, same pattern as Resource.CustomAttributes /
    // BookingType.ConfigJson / Booking.FormData - not EF's native
    // JSON-to-POCO column mapping.
    [Column(TypeName = "jsonb")]
    public string? GalleryImageUrls { get; set; } // JSON string[]

    public string? Description { get; set; }
    public string? ShortTagline { get; set; }

    [Column(TypeName = "jsonb")]
    public string? Amenities { get; set; } // JSON string[]

    public string? ContactPhone { get; set; }
    public string? ContactEmail { get; set; }
    public string? Website { get; set; }

    [Column(TypeName = "jsonb")]
    public string? SocialLinks { get; set; } // JSON object { platform: url }

    [Column(TypeName = "jsonb")]
    public string? BusinessHours { get; set; } // JSON BusinessHourEntry[]

    // Cached rating - left null/0 until a reviews feature exists to compute it.
    public decimal? AverageRating { get; set; }
    public int ReviewCount { get; set; } = 0;

    public DateTime? ProfileUpdatedAt { get; set; }
}