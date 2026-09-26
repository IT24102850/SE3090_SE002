using SmeBackend.Models;

namespace SmeBackend.Shared;

/// <param name="Capacity">The sailing's licensed capacity, or null on a resource booked one party at a time.</param>
/// <param name="SeatsRemaining">Seats still for sale on a shared sailing; null when the resource is exclusive.</param>
public record SlotResult(
    DateTime StartTime,
    DateTime EndTime,
    bool IsAvailable,
    int? Capacity = null,
    int? SeatsRemaining = null);

/// A booking already occupying part of the day. <paramref name="Seats"/> is
/// only consulted on a shared resource; an exclusive one blocks its slot
/// whatever the party size.
public readonly record struct SlotBooking(DateTime StartTime, DateTime EndTime, int Seats = 1);

/// Pure slot-generation logic shared by BookingsController.GetAvailableSlots,
/// ResourcesController.SearchAvailability (FR-B1), and the planner's
/// greedy-fill (FR-B12), so all three agree on what "open" means.
///
/// Two rules, chosen by whether the operator has declared a passenger
/// capacity (see <see cref="CapacityRules"/>):
///
///   * exclusive (capacity null or 1) - any overlapping booking takes the
///     slot, buffers included. A consulting room or a hire car.
///   * shared (capacity > 1) - overlapping bookings are summed against the
///     capacity and the slot stays open while seats remain. A 120-seat whale
///     watching boat is not full because four people booked it.
///
/// Before this split, one 4-passenger booking closed a 120-seat sailing in
/// the customer's date picker while <see cref="Availability.CheckAsync"/> -
/// which has always summed seats - would happily have taken the booking. The
/// two halves of the engine now answer the same question the same way.
public static class SlotCalculator
{
    public static (bool IsOpen, List<SlotResult> Slots) Calculate(
        DateTime date,
        ResourceSchedule? schedule,
        int duration,
        int bufferBeforeMinutes,
        int bufferAfterMinutes,
        IReadOnlyList<SlotBooking> existingBookings,
        DateTime now,
        bool isClosedException = false,
        int? capacity = null)
    {
        // FR-AS6: a one-off closed date (holiday/closure) overrides the
        // otherwise-open weekly schedule for just that day.
        if (isClosedException)
            return (false, new List<SlotResult>());

        if (schedule != null && !schedule.IsAvailable)
            return (false, new List<SlotResult>());

        var dayStart = schedule?.StartTime ?? TimeSpan.FromHours(9);
        var dayEnd = schedule?.EndTime ?? TimeSpan.FromHours(17);
        if (duration <= 0) duration = 60;

        var shared = capacity is > 1;

        var slots = new List<SlotResult>();
        var cursor = date.Date.Add(dayStart);
        var dayEndTime = date.Date.Add(dayEnd);
        var step = TimeSpan.FromMinutes(duration);

        while (cursor.Add(step) <= dayEndTime)
        {
            var slotStart = cursor;
            var slotEnd = cursor.Add(step);
            var isPast = slotStart < now;

            if (shared)
            {
                // Seats sold on this sailing, matched on plain overlap -
                // the same comparison Availability.CheckAsync makes when it
                // lets a booking through. Buffers are turnaround time
                // between different parties on an exclusive resource; they
                // do not apply to guests sharing one departure.
                var seatsTaken = existingBookings
                    .Where(b => b.StartTime < slotEnd && b.EndTime > slotStart)
                    .Sum(b => b.Seats);
                var remaining = Math.Max(capacity!.Value - seatsTaken, 0);

                slots.Add(new SlotResult(slotStart, slotEnd, remaining > 0 && !isPast, capacity, remaining));
            }
            else
            {
                var bufferedStart = slotStart.AddMinutes(-bufferBeforeMinutes);
                var bufferedEnd = slotEnd.AddMinutes(bufferAfterMinutes);

                var conflict = existingBookings.Any(b => b.StartTime < bufferedEnd && b.EndTime > bufferedStart);

                slots.Add(new SlotResult(slotStart, slotEnd, !conflict && !isPast));
            }

            cursor = cursor.Add(step);
        }

        return (true, slots);
    }
}
