using SmeBackend.Models;

namespace SmeBackend.Services;

/// What actually happened to one reminder.
///
/// `Status` is written straight to BookingReminders.Status, and is one of:
///   Sent       - the gateway accepted it
///   Simulated  - no credentials configured, so it was logged, not sent
///   Failed     - the gateway rejected it or could not be reached
///   Skipped    - there was nobody to send to (no phone number, no email)
///
/// Simulated and Failed are deliberately different. Recording both as "Sent",
/// as this used to, makes the Reports screen claim reminders went out when
/// none did - which is worse than not having the feature.
public sealed record ReminderDeliveryResult(string Status, string? Detail = null, string? ProviderMessageId = null)
{
    public static ReminderDeliveryResult Sent(string? id = null) => new("Sent", null, id);
    public static ReminderDeliveryResult Simulated(string detail) => new("Simulated", detail);
    public static ReminderDeliveryResult Failed(string detail) => new("Failed", detail);
    public static ReminderDeliveryResult Skipped(string detail) => new("Skipped", detail);

    public bool DeliveredOrSimulated => Status is "Sent" or "Simulated";
}

/// Sends a booking reminder over one channel (Sms, WhatsApp, Email).
public interface IReminderChannelSender
{
    Task<ReminderDeliveryResult> SendAsync(Booking booking, string channel, CancellationToken ct = default);
}
