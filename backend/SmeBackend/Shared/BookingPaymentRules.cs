using SmeBackend.Models;

namespace SmeBackend.Shared;

/// How a booking type expects to be paid, read from its own ConfigJson:
///
///   "payment": { "mode": "full" | "deposit" | "payAtVenue",
///                "depositPercent": 25, "holdMinutes": 15,
///                "freeCancelHours": 24, "refundPercent": 100 }
///
/// It lives in ConfigJson rather than in columns because the answer is
/// per-product and business-type specific: a clinic takes payment at the
/// desk, a tourism operator wants a deposit to stop no-shows on a boat it
/// has to crew anyway, and a gym class is paid for in full or it is not
/// booked. A booking type that says nothing keeps today's behaviour -
/// PayAtVenue, no hold, no money taken - so every existing tenant is
/// unaffected until it opts in.
public sealed record BookingPaymentRules(
    PaymentMode Mode,
    decimal DepositPercent,
    int HoldMinutes,
    int FreeCancelHours,
    decimal RefundPercent)
{
    /// What a tenant gets before configuring anything: the pre-payment
    /// behaviour this platform has always had.
    public static readonly BookingPaymentRules PayAtVenue =
        new(PaymentMode.PayAtVenue, 0m, 0, 0, 100m);

    /// True when the booking cannot be confirmed until money arrives.
    public bool RequiresPrepayment => Mode is PaymentMode.Full or PaymentMode.Deposit;

    /// The slice payable up front. Deposits round to the cent; a deposit
    /// that computes to nothing (or to more than the fare) falls back to
    /// the whole amount rather than letting someone hold a seat for free.
    public decimal AmountPayableNow(decimal total)
    {
        if (!RequiresPrepayment || total <= 0) return 0m;
        if (Mode == PaymentMode.Full) return total;

        var deposit = Math.Round(total * DepositPercent / 100m, 2, MidpointRounding.AwayFromZero);
        return deposit <= 0 || deposit > total ? total : deposit;
    }

    /// How long the seat is held while the customer is at the payment
    /// screen. Clamped: a zero-minute hold would expire before the gateway
    /// could answer, and an all-day hold is a denial-of-service on a boat
    /// with 120 seats.
    public TimeSpan HoldWindow => TimeSpan.FromMinutes(Math.Clamp(HoldMinutes <= 0 ? 15 : HoldMinutes, 5, 120));

    public static BookingPaymentRules From(BookingType? bookingType)
    {
        var payment = JsonAttributes.Path(JsonAttributes.Root(bookingType?.ConfigJson), "payment");
        if (payment is null) return PayAtVenue;

        var mode = (JsonAttributes.String(payment, "mode") ?? "payAtVenue").Trim().ToLowerInvariant() switch
        {
            "full" => PaymentMode.Full,
            "deposit" => PaymentMode.Deposit,
            _ => PaymentMode.PayAtVenue,
        };

        return new BookingPaymentRules(
            mode,
            JsonAttributes.Decimal(payment, "depositPercent") ?? 25m,
            JsonAttributes.Int(payment, "holdMinutes") ?? 15,
            JsonAttributes.Int(payment, "freeCancelHours") ?? 24,
            JsonAttributes.Decimal(payment, "refundPercent") ?? 100m);
    }
}

public enum PaymentMode
{
    /// Settled at the counter; the booking confirms without money moving.
    PayAtVenue,

    /// The whole fare up front.
    Full,

    /// Part now to hold the seat, the balance at check-in.
    Deposit,
}
