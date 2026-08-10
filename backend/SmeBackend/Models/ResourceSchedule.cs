namespace SmeBackend.Models;

public class ResourceSchedule : BaseEntity
{
    public Guid? ResourceId { get; set; }
    public Resource? Resource { get; set; }
    public int DayOfWeek { get; set; }
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public bool IsAvailable { get; set; } = true;
}