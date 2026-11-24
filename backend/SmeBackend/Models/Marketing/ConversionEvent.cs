using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace SmeBackend.Models.Marketing;

public static class ConversionEventName
{
    /// A booking request was made (Meta "Schedule", TikTok "PlaceAnOrder").
    public const string BookingCreated = "BookingCreated";
    /// The booking was paid for or delivered (Meta "Purchase", TikTok "CompletePayment").
    public const string BookingCompleted = "BookingCompleted";
}

public static class ConversionEventStatus
{
    public const string Pending = "Pending";
    public const string Sent = "Sent";
    public const string Failed = "Failed";
    /// Too old for the platform to accept (Meta: 7 days) or the platform was
    /// unconfigured by the time it came up. Kept so the log is honest.
    public const string Skipped = "Skipped";
}

/// Outbox row for one server-side conversion sent to one ad platform.
/// (BookingId, Platform, EventName) is unique, so whatever notices a
/// conversion - the sweeper, a retry, a redeploy mid-run - can only ever
/// produce one event per booking per platform. The booking id doubles as
/// the platform's event_id, which dedupes against any browser pixel too.
public class ConversionEvent : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }

    public Guid BookingId { get; set; }

    /// Facebook (Meta CAPI, covers Instagram ads too) | TikTok
    [MaxLength(20)]
    public string Platform { get; set; } = string.Empty;

    [MaxLength(30)]
    public string EventName { get; set; } = string.Empty;

    [MaxLength(20)]
    public string Status { get; set; } = ConversionEventStatus.Pending;

    public DateTime EventTime { get; set; }

    [Column(TypeName = "decimal(18,2)")]
    public decimal? Value { get; set; }

    [MaxLength(3)]
    public string? Currency { get; set; }

    public int Attempts { get; set; }
    public DateTime? NextAttemptAt { get; set; }
    public DateTime? SentAt { get; set; }

    [MaxLength(1000)]
    public string? LastError { get; set; }

    public bool IsTest { get; set; }
}
