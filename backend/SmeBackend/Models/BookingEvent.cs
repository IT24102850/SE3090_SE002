namespace SmeBackend.Models;

/// <summary>
/// One recorded change to a booking: what changed, from what to what, who did
/// it and when. Append-only - nothing updates or deletes a row here, so the
/// timeline a customer or an auditor sees is the whole truth.
///
/// Written by <see cref="Data.BookingHistoryRecorder"/> from EF Core's change
/// tracker, so every path that saves a booking is covered without each one
/// having to remember.
/// </summary>
public class BookingEvent
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid TenantId { get; set; }
    public Guid BookingId { get; set; }

    /// <summary>Created, StatusChanged, Rescheduled, ResourceChanged, CheckedIn, Deleted.</summary>
    public string Type { get; set; } = string.Empty;

    /// <summary>What the field held before, as text; null when the booking was created.</summary>
    public string? FromValue { get; set; }

    /// <summary>What it holds now, as text.</summary>
    public string? ToValue { get; set; }

    /// <summary>The signed-in user who caused it, when the change came through a request.</summary>
    public Guid? ActorUserId { get; set; }

    /// <summary>Their role at the time, or "System" for a background service.</summary>
    public string? ActorRole { get; set; }

    /// <summary>A cancellation or rejection reason the booking already carries.</summary>
    public string? Reason { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
