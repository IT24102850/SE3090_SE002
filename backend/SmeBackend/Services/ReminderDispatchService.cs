using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Services;

/// FR-B6: automatically sends a reminder for every upcoming booking, instead
/// of relying on staff to click "send reminder" (BookingsController's
/// /remind endpoint, which stays available for on-demand/last-minute sends).
/// Channel dispatch goes through the same IReminderChannelSender the manual
/// endpoint uses, so both places log the same stubbed "would send" output
/// until a real SMS/WhatsApp/Email gateway is configured.
public class ReminderDispatchService : BackgroundService
{
    private static readonly TimeSpan PollInterval = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan ReminderLeadTime = TimeSpan.FromHours(24);

    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<ReminderDispatchService> _logger;

    public ReminderDispatchService(IServiceScopeFactory scopeFactory, ILogger<ReminderDispatchService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await DispatchDueRemindersAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Reminder dispatch pass failed.");
            }

            try
            {
                await Task.Delay(PollInterval, stoppingToken);
            }
            catch (TaskCanceledException)
            {
                // Shutting down.
            }
        }
    }

    private async Task DispatchDueRemindersAsync(CancellationToken stoppingToken)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var reminderSender = scope.ServiceProvider.GetRequiredService<IReminderChannelSender>();
        var pushSender = scope.ServiceProvider.GetRequiredService<IPushNotificationSender>();

        var now = DateTime.UtcNow;
        var horizon = now.Add(ReminderLeadTime);

        var due = await db.Bookings
            .Where(b => b.DeletedAt == null
                && !b.ReminderSent
                && (b.Status == BookingStatus.Pending || b.Status == BookingStatus.Confirmed)
                && b.StartTime > now
                && b.StartTime <= horizon)
            .ToListAsync(stoppingToken);

        if (due.Count == 0) return;

        foreach (var booking in due)
        {
            await reminderSender.SendAsync(booking, "Email");

            db.BookingReminders.Add(new BookingReminder
            {
                BookingId = booking.Id,
                Channel = "Email",
                Status = "Sent",
                SentAt = now
            });
            booking.ReminderSent = true;
            booking.UpdatedAt = now;

            var reminderMessage = $"Reminder: you have an appointment on {booking.StartTime:MMM d, h:mm tt}.";
            NotificationHelper.Queue(db, booking.TenantId, booking.BookedBy, "BookingReminder",
                "Upcoming appointment", reminderMessage);

            await pushSender.SendAsync(booking.TenantId, booking.BookedBy, "Upcoming appointment", reminderMessage);
        }

        await db.SaveChangesAsync(stoppingToken);
        _logger.LogInformation("Auto-dispatched {Count} booking reminder(s).", due.Count);
    }
}
