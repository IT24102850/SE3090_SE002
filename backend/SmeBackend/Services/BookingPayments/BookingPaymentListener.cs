using Microsoft.EntityFrameworkCore;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Services.BookingPayments;

/// Told when an invoice's balance changes, so a booking that was waiting on
/// money can be confirmed.
///
/// This exists so the payment engine does not have to know what a booking
/// is. <see cref="Billing.PaymentCheckoutService"/> calls it after it has
/// applied a payment; everything about seats and holds stays on this side
/// of the line. <see cref="NullBookingPaymentListener"/> is the default, so
/// the billing engine works unchanged in tests and in any deployment that
/// does not wire the booking side in.
public interface IBookingPaymentListener
{
    Task OnInvoicePaidAsync(Invoice invoice, CancellationToken ct = default);
}

public sealed class NullBookingPaymentListener : IBookingPaymentListener
{
    public Task OnInvoicePaidAsync(Invoice invoice, CancellationToken ct = default) => Task.CompletedTask;
}

public sealed class BookingPaymentListener(
    AppDbContext db,
    ILogger<BookingPaymentListener> logger) : IBookingPaymentListener
{
    public async Task OnInvoicePaidAsync(Invoice invoice, CancellationToken ct = default)
    {
        if (invoice.BookingId is not { } bookingId) return;

        var booking = await db.Bookings.IgnoreQueryFilters()
            .FirstOrDefaultAsync(b => b.Id == bookingId && b.DeletedAt == null, ct);
        if (booking == null) return;

        // Idempotent on purpose. A webhook can arrive twice, and it can
        // arrive while the API call that started the checkout is still in
        // flight, so "already confirmed" is a normal outcome, not an error.
        if (booking.Status != BookingStatus.PendingPayment && booking.Status != BookingStatus.Expired) return;

        var now = DateTime.UtcNow;
        var lapsed = booking.Status == BookingStatus.Expired
                     || (booking.HoldExpiresAt is { } held && held < now);

        if (lapsed)
        {
            // The money arrived after the hold lapsed. The seat may have
            // been sold to someone else in between, so it has to be won
            // again rather than assumed.
            var seats = TicketPricing.SeatsUsed(booking.TicketBreakdown, booking.AttendeeCount);
            var availability = await Availability.CheckAsync(
                db, booking.ResourceId, booking.BookingTypeId, booking.DepartureId,
                booking.StartTime, booking.EndTime, seats, excludeBookingId: booking.Id);

            if (availability.Error != null)
            {
                // Someone else has the seat. Leave it theirs and flag the
                // payment for a refund rather than confirming two bookings
                // onto one slot.
                booking.Status = BookingStatus.Expired;
                booking.CancellationReason =
                    "Paid after the hold expired and the slot had gone. A refund is due.";
                booking.UpdatedAt = now;

                NotificationHelper.Queue(db, booking.TenantId, booking.BookedBy,
                    "BookingPaymentLate", "Your payment arrived too late",
                    "The slot was taken before your payment reached us, so the booking could not be confirmed. " +
                    "A refund is being arranged.");

                logger.LogWarning(
                    "Booking {BookingId} was paid after its hold lapsed and the slot is gone; refund required.",
                    booking.Id);

                await db.SaveChangesAsync(ct);
                return;
            }

            logger.LogInformation(
                "Booking {BookingId} was paid after its hold lapsed, but the slot was still free.", booking.Id);
        }

        booking.Status = BookingStatus.Confirmed;
        booking.HoldExpiresAt = null;
        booking.UpdatedAt = now;

        NotificationHelper.Queue(db, booking.TenantId, booking.BookedBy,
            "BookingConfirmed", "Booking confirmed",
            $"Your payment went through and your booking on {booking.StartTime:MMM d, h:mm tt} is confirmed.");

        await db.SaveChangesAsync(ct);
    }
}
