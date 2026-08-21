namespace SmeBackend.Models;

public class ResourceSchedule : BaseEntity
{
    public Guid? ResourceId { get; set; }
    public Resource? Resource { get; set; }
    public int DayOfWeek { get; set; }
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public bool IsAvailable { get; set; } = true;

    // Business-rule validation (BookingsController.ValidateBusinessRulesAsync).
    // Both null = no lunch break enforced for this day.
    public TimeSpan? LunchBreakStart { get; set; }
    public TimeSpan? LunchBreakEnd { get; set; }

    // Null = falls back to the platform default of 8 hours/day.
    public decimal? MaxDailyBookedHours { get; set; }
}