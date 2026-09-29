using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Services.BookingPayments;

/// Tidies up holds nobody paid for.
///
/// It is not what frees the seat - Availability.HoldingSeats already stops
/// counting a hold the moment its window lapses, so a seat is back on sale
/// the second it expires whether or not this has run. What this does is
/// settle the record: flip the row to Expired so the customer's list and
/// the operator's reports stop showing a booking that is never happening,
/// and tell the customer their checkout timed out.
///
/// Modelled on ReminderDispatchService: same hosted-service shape, same
/// scope-per-pass, and the same tolerance for a pass that throws - a
/// failed sweep must not take the process down, because the next one will
/// pick up the same rows.
public sealed class BookingHoldExpiryService(
    IServiceProvider services,
    ILogger<BookingHoldExpiryService> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromMinutes(1);

    /// A grace period on top of the hold itself: a gateway that answers a
    /// few seconds late should still find its booking, rather than racing
    /// this sweep.
    private static readonly TimeSpan Grace = TimeSpan.FromSeconds(90);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await SweepAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Booking hold sweep failed; the next pass will retry.");
            }

            try
            {
                if (!await timer.WaitForNextTickAsync(stoppingToken)) break;
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    internal static async Task<int> SweepAsync(AppDbContext db, DateTime now, ILogger logger, CancellationToken ct)
    {
        var cutoff = now - Grace;

        var lapsed = await db.Bookings.IgnoreQueryFilters()
            .Where(b => b.Status == BookingStatus.PendingPayment
                && b.DeletedAt == null
                && b.HoldExpiresAt != null
                && b.HoldExpiresAt < cutoff)
            .ToListAsync(ct);

        if (lapsed.Count == 0) return 0;

        foreach (var booking in lapsed)
        {
            booking.Status = BookingStatus.Expired;
            booking.HoldExpiresAt = null;
            booking.CancellationReason = "Payment was not completed before the hold expired.";
            booking.UpdatedAt = now;

            NotificationHelper.Queue(db, booking.TenantId, booking.BookedBy,
                "BookingHoldExpired", "Your held booking expired",
                $"We could not confirm your booking on {booking.StartTime:MMM d, h:mm tt} because the payment " +
                "was not completed in time. The slot is available again if you would like to try once more.");
        }

        await db.SaveChangesAsync(ct);
        logger.LogInformation("Released {Count} expired booking hold(s).", lapsed.Count);
        return lapsed.Count;
    }

    private async Task SweepAsync(CancellationToken ct)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await SweepAsync(db, DateTime.UtcNow, logger, ct);
    }
}
