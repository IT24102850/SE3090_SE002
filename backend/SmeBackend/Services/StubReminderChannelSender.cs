using SmeBackend.Models;

namespace SmeBackend.Services;

/// No SMS (Twilio), WhatsApp Business API, or SMTP credentials exist in
/// this project yet, so every channel logs exactly what it would send
/// instead of sending it - the same honesty already used for the
/// pre-existing simulated reminder dispatch, just consolidated into one
/// real, swappable abstraction instead of duplicated inline in two places.
/// Swap this registration in Program.cs for a real implementation per
/// channel once credentials exist; nothing else needs to change.
public class StubReminderChannelSender : IReminderChannelSender
{
    private readonly ILogger<StubReminderChannelSender> _logger;
    public StubReminderChannelSender(ILogger<StubReminderChannelSender> logger) => _logger = logger;

    public Task SendAsync(Booking booking, string channel)
    {
        var body = $"Reminder: you have an appointment on {booking.StartTime:MMM d, h:mm tt}.";

        switch (channel)
        {
            case "Sms":
                _logger.LogInformation("[STUB SMS] Would text booking {BookingId}'s customer: {Body}", booking.Id, body);
                break;
            case "WhatsApp":
                _logger.LogInformation("[STUB WhatsApp] Would message booking {BookingId}'s customer: {Body}", booking.Id, body);
                break;
            case "Email":
            default:
                _logger.LogInformation("[STUB Email] Would email booking {BookingId}'s customer: {Body}", booking.Id, body);
                break;
        }

        return Task.CompletedTask;
    }
}
