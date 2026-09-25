namespace SmeBackend.Models;

public class RecurringPattern : BaseEntity
{
    public Guid? BookingId { get; set; }
    public Booking? Booking { get; set; }
    public string Frequency { get; set; } = string.Empty; // Daily, Weekly, Monthly
    public DateTime EndDate { get; set; }
    public List<int> DaysOfWeek { get; set; } = new();
}