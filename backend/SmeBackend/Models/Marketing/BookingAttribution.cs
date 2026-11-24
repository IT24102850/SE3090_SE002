using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace SmeBackend.Models.Marketing;

/// Where a booking made through a public link came from, and what the ad
/// platforms need to match it back to a click.
///
/// Kept beside Booking rather than as columns on it: most bookings (walk-in,
/// staff-made, in-app) have none of this, and the booking table already
/// carries an exclusion constraint and a history recorder that do not need
/// to know about marketing.
public class BookingAttribution : ITenantScoped
{
    [Key]
    public Guid BookingId { get; set; }

    public Guid TenantId { get; set; }

    /// Normalised channel: Facebook | Instagram | TikTok | Website | other.
    /// The same value is written to Booking.Source.
    [MaxLength(50)]
    public string Channel { get; set; } = "Website";

    public bool IsPaid { get; set; }

    [MaxLength(100)] public string? UtmSource { get; set; }
    [MaxLength(100)] public string? UtmMedium { get; set; }
    [MaxLength(200)] public string? UtmCampaign { get; set; }
    [MaxLength(200)] public string? UtmContent { get; set; }
    [MaxLength(200)] public string? UtmTerm { get; set; }

    /// Meta click id from the landing URL.
    [MaxLength(500)] public string? Fbclid { get; set; }
    /// _fbc / _fbp cookies, as the Meta pixel formats them.
    [MaxLength(600)] public string? Fbc { get; set; }
    [MaxLength(200)] public string? Fbp { get; set; }

    /// TikTok click id and _ttp cookie.
    [MaxLength(500)] public string? Ttclid { get; set; }
    [MaxLength(200)] public string? Ttp { get; set; }

    [MaxLength(2048)] public string? LandingUrl { get; set; }
    [MaxLength(2048)] public string? Referrer { get; set; }

    /// Required raw (not hashed) by both conversion APIs for matching.
    [MaxLength(64)] public string? ClientIp { get; set; }
    [MaxLength(512)] public string? UserAgent { get; set; }

    /// Inbox conversation the booking link was sent from, when it was.
    public Guid? SocialConversationId { get; set; }

    [Column(TypeName = "decimal(18,2)")]
    public decimal? Value { get; set; }

    [MaxLength(3)]
    public string? Currency { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
