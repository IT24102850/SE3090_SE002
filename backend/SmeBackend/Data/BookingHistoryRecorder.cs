using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using SmeBackend.Models;
using SmeBackend.Services;

namespace SmeBackend.Data;

/// <summary>
/// Turns pending booking changes into <see cref="BookingEvent"/> rows.
///
/// It reads EF Core's change tracker rather than being called from each
/// controller: a booking's status is set in fifteen places across controllers
/// and background services, and a timeline with gaps is worse than none - an
/// auditor cannot tell "nothing happened" from "we forgot to record it".
/// Doing it here means a path added tomorrow is recorded too.
///
/// Called before SaveChanges, while the original values are still available.
/// </summary>
public static class BookingHistoryRecorder
{
    public static void Capture(ChangeTracker changeTracker, ICurrentActor? actor, Action<BookingEvent> add)
    {
        var actorId = actor?.UserId;
        var actorRole = actor?.Role ?? "System";

        foreach (var entry in changeTracker.Entries<Booking>().ToList())
        {
            switch (entry.State)
            {
                case EntityState.Added:
                    add(Event(entry.Entity, "Created", null, entry.Entity.Status.ToString(), actorId, actorRole));
                    break;

                case EntityState.Modified:
                    foreach (var change in Changes(entry, actorId, actorRole)) add(change);
                    break;
            }
        }
    }

    private static IEnumerable<BookingEvent> Changes(EntityEntry<Booking> entry, Guid? actorId, string actorRole)
    {
        var booking = entry.Entity;

        // A soft delete is the end of the booking's life, and says more than
        // the status change that usually accompanies it.
        if (Changed(entry, nameof(Booking.DeletedAt)) && booking.DeletedAt is not null)
        {
            yield return Event(booking, "Deleted", null, null, actorId, actorRole, booking.CancellationReason);
            yield break;
        }

        if (Changed(entry, nameof(Booking.Status)))
        {
            var from = entry.OriginalValues.GetValue<BookingStatus>(nameof(Booking.Status));
            yield return Event(booking, "StatusChanged", from.ToString(), booking.Status.ToString(),
                actorId, actorRole, booking.CancellationReason);
        }

        // Start and end move together on a reschedule, so they are one event.
        if (Changed(entry, nameof(Booking.StartTime)) || Changed(entry, nameof(Booking.EndTime)))
        {
            var fromStart = entry.OriginalValues.GetValue<DateTime>(nameof(Booking.StartTime));
            var fromEnd = entry.OriginalValues.GetValue<DateTime>(nameof(Booking.EndTime));
            yield return Event(booking, "Rescheduled", Window(fromStart, fromEnd),
                Window(booking.StartTime, booking.EndTime), actorId, actorRole);
        }

        if (Changed(entry, nameof(Booking.ResourceId)))
        {
            var from = entry.OriginalValues.GetValue<Guid>(nameof(Booking.ResourceId));
            yield return Event(booking, "ResourceChanged", from.ToString(), booking.ResourceId.ToString(),
                actorId, actorRole);
        }
    }

    private static bool Changed(EntityEntry<Booking> entry, string property)
    {
        var p = entry.Property(property);
        return p.IsModified && !Equals(p.OriginalValue, p.CurrentValue);
    }

    private static string Window(DateTime start, DateTime end) =>
        $"{start:yyyy-MM-ddTHH:mm:ssZ}/{end:yyyy-MM-ddTHH:mm:ssZ}";

    private static BookingEvent Event(
        Booking booking, string type, string? from, string? to,
        Guid? actorId, string actorRole, string? reason = null) => new()
        {
            TenantId = booking.TenantId,
            BookingId = booking.Id,
            Type = type,
            FromValue = from,
            ToValue = to,
            ActorUserId = actorId,
            ActorRole = actorRole,
            Reason = string.IsNullOrWhiteSpace(reason) ? null : reason,
        };
}
