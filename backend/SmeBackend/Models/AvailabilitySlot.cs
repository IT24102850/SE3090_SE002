namespace SmeBackend.Models;

public class AvailabilitySlot : BaseEntity
{
    public Guid? ResourceId { get; set; }
    public Resource? Resource { get; set; }
    public DateTime Date { get; set; }
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public bool IsBooked { get; set; }
    public Guid? BookingId { get; set; }
}