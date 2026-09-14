using SmeBackend.Models;

namespace SmeBackend.Shared;

/// The outcome of checking one booking against a shared resource's licensed
/// capacity. <see cref="Warning"/> is set (with <see cref="Allowed"/> still
/// true) at the 90% threshold, so the admin UI can flag a nearly-full
/// departure without blocking the sale.
public sealed record CapacityCheck(
    bool Allowed,
    int Capacity,
    int SeatsTaken,
    int SeatsRequested,
    string? Error,
    string? Warning)
{
    public int SeatsRemaining => Math.Max(Capacity - SeatsTaken, 0);

    public double PercentFull => Capacity > 0
        ? Math.Round((SeatsTaken + SeatsRequested) / (double)Capacity * 100, 1)
        : 0;
}

/// Capacity rules for shared-vehicle bookings.
///
/// The booking engine's original rule is exclusive occupancy: any overlap on
/// a resource is a conflict (BookingsController.HasConflictAsync). That is
/// right for a consulting room or a hire car, and wrong for a 120-seat whale
/// watching boat, where twenty separate reservations share one sailing.
///
/// So capacity sharing is opt-in per resource: it applies only where the
/// operator has actually declared a passenger capacity greater than one
/// (Resource.CustomAttributes.capacity, Resource.Capacity, or
/// BookingType.MaxParticipants). Every resource that predates this - and
/// every one-at-a-time resource - has no such figure and keeps the exclusive
/// behaviour byte for byte.
public static class CapacityRules
{
    /// Warn, but still allow, once a departure reaches this fraction full.
    public const double WarnThreshold = 0.9;

    /// The licensed passenger capacity for a sailing, most specific source
    /// first: the departure's own override, then the resource's
    /// CustomAttributes.capacity (the key documented in
    /// docs/tourism-business-template.md), then Resource.Capacity, then the
    /// booking type's MaxParticipants. Null = not a shared resource.
    public static int? Resolve(Resource? resource, BookingType? bookingType, Departure? departure = null)
    {
        if (departure?.LicensedCapacity is > 0) return departure.LicensedCapacity;

        var custom = JsonAttributes.Int(JsonAttributes.Root(resource?.CustomAttributes), "capacity");
        if (custom is > 0) return custom;

        if (resource?.Capacity is > 0) return resource.Capacity;
        if (bookingType?.MaxParticipants is > 0) return bookingType.MaxParticipants;

        return null;
    }

    /// True when this resource/booking type pair is a shared vehicle whose
    /// overlapping bookings should be summed against a capacity rather than
    /// treated as conflicts.
    public static bool IsShared(Resource? resource, BookingType? bookingType, Departure? departure = null) =>
        Resolve(resource, bookingType, departure) is > 1;

    /// Checks a requested number of seats against what is already sold.
    /// Rejects over the licensed capacity; warns from 90% full.
    public static CapacityCheck Check(int capacity, int seatsTaken, int seatsRequested)
    {
        if (capacity <= 0)
        {
            return new CapacityCheck(true, capacity, seatsTaken, seatsRequested, null, null);
        }

        var total = seatsTaken + seatsRequested;
        if (total > capacity)
        {
            var remaining = Math.Max(capacity - seatsTaken, 0);
            return new CapacityCheck(
                false, capacity, seatsTaken, seatsRequested,
                $"This departure is licensed for {capacity} passenger(s); {seatsTaken} are already booked, so only {remaining} seat(s) remain and {seatsRequested} were requested.",
                null);
        }

        var warning = total >= capacity * WarnThreshold
            ? $"This departure would be {Math.Round(total / (double)capacity * 100)}% full ({total} of {capacity} seats)."
            : null;

        return new CapacityCheck(true, capacity, seatsTaken, seatsRequested, null, warning);
    }
}
