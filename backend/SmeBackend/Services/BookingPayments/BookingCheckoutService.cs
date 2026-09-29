using Microsoft.EntityFrameworkCore;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.DTOs;
using SmeBackend.Models;
using SmeBackend.Services.Billing;
using SmeBackend.Shared;

namespace SmeBackend.Services.BookingPayments;

/// What the customer needs to finish paying: the booking that is being held,
/// and the gateway handoff for it. <paramref name="Checkout"/> is null when
/// the booking type takes payment at the venue - there is nothing to pay
/// now and the booking is already Confirmed.
public sealed record BookingCheckoutResult(
    Guid BookingId,
    string Status,
    decimal AmountDue,
    decimal AmountPayableNow,
    string Currency,
    string PaymentMode,
    DateTime? HoldExpiresAt,
    Guid? InvoiceId,
    CheckoutResponse? Checkout);

public interface IBookingCheckoutService
{
    Task<BillingResult<BookingCheckoutResult>> StartAsync(
        BillingActor actor, CreateBookingDto dto, string? provider, string method, CancellationToken ct = default);
}

/// Pay to confirm a booking.
///
/// This is the booking half of a payment flow whose gateway half already
/// exists: Stripe, PayPal and the sandbox all live behind
/// <see cref="IPaymentCheckoutService"/>, and nothing here knows which one
/// a tenant uses. What was missing was the link - a booking was created
/// Pending with no money attached, and an invoice never referenced it.
///
/// The order matters and is the whole point:
///
///   1. price the booking on the SERVER, from the booking type's own
///      config, so a client cannot name its own fare;
///   2. take the seat with a PendingPayment hold inside a transaction, so
///      two customers racing for the last seat cannot both win;
///   3. raise the invoice against that booking;
///   4. hand off to the gateway.
///
/// Only the gateway can then say the money arrived - see
/// <see cref="BookingPaymentListener"/>. The client is never trusted with
/// either the price or the outcome.
public sealed class BookingCheckoutService(
    AppDbContext db,
    IBillingService billing,
    IPaymentCheckoutService checkout,
    ILogger<BookingCheckoutService> logger) : IBookingCheckoutService
{
    public async Task<BillingResult<BookingCheckoutResult>> StartAsync(
        BillingActor actor, CreateBookingDto dto, string? provider, string method, CancellationToken ct = default)
    {
        var start = DateTimeUtil.AsUtc(dto.StartTime);
        var end = DateTimeUtil.AsUtc(dto.EndTime);
        if (end <= start)
            return BillingResult<BookingCheckoutResult>.BadRequest("EndTime must be after StartTime.");

        var resource = await db.Resources.AsNoTracking().FirstOrDefaultAsync(r => r.Id == dto.ResourceId, ct);
        if (resource == null) return BillingResult<BookingCheckoutResult>.NotFound("Resource not found.");

        var bookingType = await db.BookingTypes.AsNoTracking().FirstOrDefaultAsync(bt => bt.Id == dto.BookingTypeId, ct);
        if (bookingType == null) return BillingResult<BookingCheckoutResult>.NotFound("Booking type not found.");

        var rules = BookingPaymentRules.From(bookingType);

        // 1. The price is the server's to decide. TicketPricing reads the
        //    unit prices off the booking type, so "2 adults + 1 child" costs
        //    what the operator published, whatever the client sent.
        var priced = dto.TicketBreakdown is { Count: > 0 }
            ? TicketPricing.Price(dto.TicketBreakdown, bookingType, start)
            : null;
        var amountDue = priced?.Total ?? 0m;
        var currency = priced?.Currency ?? "LKR";
        var seats = TicketPricing.SeatsUsed(
            priced != null ? TicketPricing.Serialize(priced.Lines) : null, dto.AttendeeCount);
        var payableNow = rules.AmountPayableNow(amountDue);

        // Nothing to collect - either the operator takes payment at the
        // desk, or the product is free. Confirm it and skip the gateway
        // entirely rather than holding a seat against a zero invoice.
        var prepaying = rules.RequiresPrepayment && payableNow > 0;

        var now = DateTime.UtcNow;
        var holdExpiresAt = prepaying ? now.Add(rules.HoldWindow) : (DateTime?)null;

        // 2. Take the seat. The availability check and the insert are one
        //    transaction: between checking and writing, another customer
        //    could otherwise pay for the same seat.
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        var availability = await Availability.CheckAsync(
            db, dto.ResourceId, dto.BookingTypeId, dto.DepartureId, start, end, seats);
        if (availability.Error != null)
        {
            await tx.RollbackAsync(ct);
            return availability.IsCapacityFailure
                ? BillingResult<BookingCheckoutResult>.BadRequest(availability.Error)
                : BillingResult<BookingCheckoutResult>.Conflict(availability.Error);
        }

        var booking = new Booking
        {
            TenantId = actor.TenantId,
            ResourceId = dto.ResourceId,
            BookingTypeId = dto.BookingTypeId,
            BookedBy = actor.UserId ?? dto.BookedBy,
            BookedFor = dto.BookedFor,
            Title = dto.Title,
            Notes = dto.Notes,
            StartTime = start,
            EndTime = end,
            Status = prepaying ? BookingStatus.PendingPayment : BookingStatus.Confirmed,
            Priority = dto.Priority,
            AttendeeCount = dto.AttendeeCount ?? (priced?.TotalQuantity > 0 ? priced.TotalQuantity : null),
            FormData = dto.FormData,
            DepartureId = dto.DepartureId,
            TicketBreakdown = priced != null ? TicketPricing.Serialize(priced.Lines) : null,
            Waiver = dto.Waiver,
            Source = dto.Source,
            TotalCost = amountDue,
            AmountDue = amountDue,
            DepositAmount = prepaying ? payableNow : null,
            PaymentMode = rules.Mode.ToString(),
            HoldExpiresAt = holdExpiresAt,
        };
        db.Bookings.Add(booking);
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);

        if (!prepaying)
        {
            return BillingResult<BookingCheckoutResult>.Ok(new BookingCheckoutResult(
                booking.Id, booking.Status.ToString(), amountDue, 0m, currency,
                rules.Mode.ToString(), null, null, null));
        }

        // 3. The invoice is what the gateway charges against, and its
        //    BookingId is what tells the listener which seat to confirm.
        var invoice = await billing.CreateInvoiceAsync(actor, new CreateInvoiceRequest(
            CustomerId: booking.BookedBy,
            InvoiceNumber: null,
            BookingId: booking.Id,
            DueDate: holdExpiresAt!.Value,
            Currency: currency,
            Discount: 0m,
            Tax: 0m,
            Items: BuildItems(priced, bookingType, rules, amountDue, payableNow),
            Notes: $"{bookingType.Name} on {start:yyyy-MM-dd HH:mm} UTC"), ct);

        if (!invoice.Success || invoice.Value is null)
        {
            await ReleaseAsync(booking, "invoice could not be raised", ct);
            return BillingResult<BookingCheckoutResult>.BadRequest(
                invoice.Error ?? "The invoice for this booking could not be created.");
        }

        // 4. Hand off to whichever gateway the tenant has configured. A
        //    deposit pays part of the invoice, so the amount is explicit.
        var started = await checkout.StartCheckoutAsync(actor, invoice.Value.Id,
            new CheckoutRequest(Provider: provider, Method: method, Amount: payableNow), ct);

        if (!started.Success || started.Value is null)
        {
            await ReleaseAsync(booking, "checkout could not be started", ct);
            return BillingResult<BookingCheckoutResult>.BadRequest(
                started.Error ?? "Payment could not be started for this booking.");
        }

        return BillingResult<BookingCheckoutResult>.Ok(new BookingCheckoutResult(
            booking.Id, booking.Status.ToString(), amountDue, payableNow, currency,
            rules.Mode.ToString(), holdExpiresAt, invoice.Value.Id, started.Value));
    }

    /// A hold whose payment never got off the ground is released now rather
    /// than left for the sweeper: the customer is still on the screen and
    /// the seat should be back on sale before they retry.
    private async Task ReleaseAsync(Booking booking, string why, CancellationToken ct)
    {
        logger.LogWarning("Releasing held booking {BookingId}: {Why}.", booking.Id, why);
        booking.Status = BookingStatus.Expired;
        booking.HoldExpiresAt = null;
        booking.CancellationReason = $"Hold released - {why}.";
        booking.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
    }

    /// One line per ticket type, so the invoice reads like the fare the
    /// guest was quoted rather than a single opaque total.
    ///
    /// A deposit is invoiced for the deposit, not for the whole fare. An
    /// invoice raised for the full amount and paid 25% sits at
    /// PartiallyPaid forever, which is both a lie on the books - the guest
    /// owes nothing until they arrive - and a booking that never confirms,
    /// because confirmation waits for the invoice to be Paid. The balance
    /// is its own invoice, raised at check-in.
    private static List<CreateInvoiceItemRequest> BuildItems(
        PricedTickets? priced, BookingType bookingType, BookingPaymentRules rules,
        decimal amountDue, decimal payableNow)
    {
        if (rules.Mode == PaymentMode.Deposit && payableNow < amountDue)
        {
            return new List<CreateInvoiceItemRequest>
            {
                new($"{bookingType.Name} - deposit ({rules.DepositPercent:0.##}% of {amountDue:N2})",
                    1, payableNow, "Booking deposit"),
            };
        }

        if (priced is { Lines.Count: > 0 })
        {
            var lines = priced.Lines
                .Where(l => l.Qty > 0)
                .Select(l => new CreateInvoiceItemRequest(
                    $"{bookingType.Name} - {l.Type}",
                    l.Qty,
                    l.UnitPrice ?? Math.Round((l.LineTotal ?? 0m) / l.Qty, 2),
                    "Booking"))
                .ToList();
            if (lines.Count > 0) return lines;
        }

        return new List<CreateInvoiceItemRequest>
        {
            new(bookingType.Name, 1, amountDue, "Booking"),
        };
    }
}
