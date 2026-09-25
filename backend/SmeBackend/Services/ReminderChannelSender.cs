using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services.Billing;

namespace SmeBackend.Services;

/// Sends booking reminders over Twilio (SMS, WhatsApp) and SendGrid (email).
///
/// It delegates to IBillingMessenger rather than re-implementing either
/// gateway: that class already handles the Twilio form encoding, the SendGrid
/// payload, the basic-auth header and the "not configured" path, and having
/// one implementation means a fix to either provider fixes both billing and
/// booking at once.
///
/// What this class adds is the booking half: who to send to, what to say, and
/// turning the delivery response into the status stored on BookingReminders.
///
/// Every outcome is reported honestly. Without credentials the message is
/// logged and recorded as Simulated, never as Sent - a Reports screen that
/// counts reminders is only worth reading if "sent" means sent.
public sealed class ReminderChannelSender : IReminderChannelSender
{
    private readonly AppDbContext _db;
    private readonly IBillingMessenger _messenger;
    private readonly ILogger<ReminderChannelSender> _logger;

    public ReminderChannelSender(AppDbContext db, IBillingMessenger messenger, ILogger<ReminderChannelSender> logger)
    {
        _db = db;
        _messenger = messenger;
        _logger = logger;
    }

    public async Task<ReminderDeliveryResult> SendAsync(Booking booking, string channel, CancellationToken ct = default)
    {
        var normalized = MessageChannels.Normalize(channel) ?? MessageChannels.Email;
        var recipient = await RecipientAsync(booking, ct);
        if (recipient is null) return ReminderDeliveryResult.Skipped("The guest on this booking has no contact details.");

        var when = booking.StartTime.ToString("ddd d MMM, HH:mm");
        var what = await DescribeAsync(booking, ct);

        try
        {
            if (normalized == MessageChannels.Email)
            {
                if (string.IsNullOrWhiteSpace(recipient.Email))
                    return ReminderDeliveryResult.Skipped("No email address on file for this guest.");

                var html =
                    $"<p>Hello {System.Net.WebUtility.HtmlEncode(recipient.Name)},</p>" +
                    $"<p>This is a reminder of your booking: <strong>{System.Net.WebUtility.HtmlEncode(what)}</strong> " +
                    $"on <strong>{when}</strong>.</p>" +
                    "<p>Please arrive 15 minutes early. Reply to this email if you need to change it.</p>";

                var result = await _messenger.SendEmailAsync(recipient.Email, $"Reminder: {what} on {when}", html, null, ct);
                return Translate(result, normalized, recipient.Email);
            }

            if (string.IsNullOrWhiteSpace(recipient.Phone))
                return ReminderDeliveryResult.Skipped($"No phone number on file, so {normalized} could not be used.");

            var body = $"Reminder: {what} on {when}. Please arrive 15 minutes early.";
            var text = await _messenger.SendTextAsync(normalized, recipient.Phone, body, ct);
            return Translate(text, normalized, recipient.Phone);
        }
        catch (Exception ex)
        {
            // A reminder failing must never take down the booking flow or the
            // background dispatcher that asked for it.
            _logger.LogWarning(ex, "Reminder over {Channel} for booking {BookingId} threw.", normalized, booking.Id);
            return ReminderDeliveryResult.Failed($"{normalized} sender threw: {ex.Message}");
        }
    }

    private ReminderDeliveryResult Translate(MessageDeliveryResponse response, string channel, string to)
    {
        if (response.Delivered) return ReminderDeliveryResult.Sent(response.ProviderMessageId);

        if (response.Simulated)
        {
            _logger.LogInformation("[SIMULATED {Channel}] to {To}: no credentials configured.", channel, to);
            return ReminderDeliveryResult.Simulated(response.Error ?? $"{channel} is not configured on this server.");
        }

        return ReminderDeliveryResult.Failed(response.Error ?? $"{channel} delivery failed.");
    }

    private sealed record Recipient(string Name, string? Email, string? Phone);

    /// The guest is BookedFor when someone booked on their behalf, otherwise
    /// the person who made the booking.
    private async Task<Recipient?> RecipientAsync(Booking booking, CancellationToken ct)
    {
        var guestId = booking.BookedFor ?? booking.BookedBy;
        var user = await _db.Users.AsNoTracking().IgnoreQueryFilters()
            .FirstOrDefaultAsync(u => u.Id == guestId, ct);
        if (user is null) return null;

        var hasContact = !string.IsNullOrWhiteSpace(user.Email) || !string.IsNullOrWhiteSpace(user.Phone);
        return hasContact ? new Recipient(user.FullName ?? "there", user.Email, user.Phone) : null;
    }

    private async Task<string> DescribeAsync(Booking booking, CancellationToken ct)
    {
        var name = await _db.BookingTypes.AsNoTracking().IgnoreQueryFilters()
            .Where(bt => bt.Id == booking.BookingTypeId)
            .Select(bt => bt.Name)
            .FirstOrDefaultAsync(ct);
        return string.IsNullOrWhiteSpace(name) ? "your booking" : name;
    }
}
