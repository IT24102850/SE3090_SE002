using SmeBackend.Models;

namespace SmeBackend.Shared;

public record SlotResult(DateTime StartTime, DateTime EndTime, bool IsAvailable);

/// Pure slot-generation logic shared by BookingsController.GetAvailableSlots,
/// ResourcesController.SearchAvailability (FR-B1), and the planner's
/// greedy-fill (FR-B12), so all three agree on what "open" means.
public static class SlotCalculator
{
    public static (bool IsOpen, List<SlotResult> Slots) Calculate(
        DateTime date,
        ResourceSchedule? schedule,
        int duration,
        int bufferBeforeMinutes,
        int bufferAfterMinutes,
        IReadOnlyList<(DateTime StartTime, DateTime EndTime)> existingBookings,
        DateTime now,
        bool isClosedException = false)
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

        var slots = new List<SlotResult>();
        var cursor = date.Date.Add(dayStart);
        var dayEndTime = date.Date.Add(dayEnd);
        var step = TimeSpan.FromMinutes(duration);

        while (cursor.Add(step) <= dayEndTime)
        {
            var slotStart = cursor;
            var slotEnd = cursor.Add(step);
            var bufferedStart = slotStart.AddMinutes(-bufferBeforeMinutes);
            var bufferedEnd = slotEnd.AddMinutes(bufferAfterMinutes);

            var conflict = existingBookings.Any(b => b.StartTime < bufferedEnd && b.EndTime > bufferedStart);
            var isPast = slotStart < now;

            slots.Add(new SlotResult(slotStart, slotEnd, !conflict && !isPast));
            cursor = cursor.Add(step);
        }

        return (true, slots);
    }
}
