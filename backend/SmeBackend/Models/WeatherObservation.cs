using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace SmeBackend.Models;

/// A sea-state/weather reading, entered by hand today.
///
/// There is no external weather API wired up (deliberately out of scope),
/// so `Source` is "Manual" for every row this codebase writes. The column
/// exists so a future provider integration can write rows tagged
/// "OpenWeather"/"StormGlass" alongside the manual ones without a schema
/// change or a backfill - the reader code already ignores the difference.
public class WeatherObservation
{
    [Key]
    public Guid Id { get; set; } = Guid.NewGuid();

    [Required]
    public Guid TenantId { get; set; }

    /// The vessel or the departure the reading was taken for. Both null =
    /// a tenant-wide reading for the harbour, which is what the dashboard's
    /// weather panel shows by default.
    public Guid? ResourceId { get; set; }

    public Guid? DepartureId { get; set; }

    [Required]
    public DateTime ObservedAt { get; set; }

    [Column(TypeName = "decimal(6,2)")]
    public decimal? WindSpeedKnots { get; set; }

    [Column(TypeName = "decimal(6,2)")]
    public decimal? WaveHeightMetres { get; set; }

    [Column(TypeName = "decimal(6,2)")]
    public decimal? VisibilityKm { get; set; }

    /// Douglas sea-state scale, 0 (calm/glassy) to 9 (phenomenal).
    public int? SeaStateCode { get; set; }

    [MaxLength(1000)]
    public string? Note { get; set; }

    [MaxLength(50)]
    public string Source { get; set; } = "Manual";

    public Guid? RecordedByUserId { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
