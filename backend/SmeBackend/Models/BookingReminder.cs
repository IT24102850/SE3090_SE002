namespace SmeBackend.Models;

public class BookingReminder : BaseEntity
{
    public Guid? BookingId { get; set; }
    public Booking? Booking { get; set; }
    public string Channel { get; set; } = string.Empty; // SMS, WhatsApp, Email
    public string Status { get; set; } = string.Empty;
    public DateTime? SentAt { get; set; }
}