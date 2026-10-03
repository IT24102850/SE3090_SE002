using SmeBackend.Models;

namespace SmeBackend.Services;

/// Sends a booking reminder over one channel (Sms, WhatsApp, Email).
/// Replaces the simulation that used to be duplicated inline in
/// BookingsController.SendReminder and ReminderDispatchService.
public interface IReminderChannelSender
{
    Task SendAsync(Booking booking, string channel);
}
