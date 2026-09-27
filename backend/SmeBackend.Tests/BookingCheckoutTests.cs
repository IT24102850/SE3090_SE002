using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using SmeBackend.Models;
using SmeBackend.Services.BookingPayments;
using SmeBackend.Data;
using SmeBackend.Shared;

namespace SmeBackend.Tests;

/// Pay to confirm a booking.
///
/// The money rules, not the gateway: the gateway half is Stripe/PayPal and
/// is exercised by the billing engine's own tests. What matters here is
/// that a seat cannot be sold twice while someone is paying for it, that an
/// abandoned checkout hands the seat back, and that only the gateway can
/// turn a hold into a confirmed booking.
public class BookingCheckoutTests
{
    /// Resources and bookings carry a tenant query filter, so every test
    /// runs inside one tenant.
    private static readonly Guid TenantId = Guid.NewGuid();

    private static readonly DateTime Sailing = new(2026, 10, 12, 10, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime SailingEnd = new(2026, 10, 12, 14, 0, 0, DateTimeKind.Utc);

    // ── The payment rules a booking type declares ───────────────────────

    [Fact]
    public void A_booking_type_that_says_nothing_takes_no_money_up_front()
    {
        // The guard for every tenant that predates this: no "payment" block
        // means the booking confirms exactly as it always did.
        var rules = BookingPaymentRules.From(new BookingType { ConfigJson = """{"pricing":{"adult":7500}}""" });

        Assert.Equal(PaymentMode.PayAtVenue, rules.Mode);
        Assert.False(rules.RequiresPrepayment);
        Assert.Equal(0m, rules.AmountPayableNow(15000m));
    }

    [Fact]
    public void A_deposit_takes_its_percentage_and_leaves_the_balance()
    {
        var rules = BookingPaymentRules.From(new BookingType
        {
            ConfigJson = """{"payment":{"mode":"deposit","depositPercent":25,"holdMinutes":20}}""",
        });

        Assert.Equal(PaymentMode.Deposit, rules.Mode);
        Assert.True(rules.RequiresPrepayment);
        Assert.Equal(3750m, rules.AmountPayableNow(15000m));
        Assert.Equal(TimeSpan.FromMinutes(20), rules.HoldWindow);
    }

    [Fact]
    public void Full_payment_asks_for_the_whole_fare()
    {
        var rules = BookingPaymentRules.From(new BookingType { ConfigJson = """{"payment":{"mode":"full"}}""" });

        Assert.Equal(15000m, rules.AmountPayableNow(15000m));
    }

    [Theory]
    [InlineData(0)]     // would expire before the gateway could answer
    [InlineData(-5)]
    [InlineData(9999)]  // an all-day hold on a 120-seat boat is a denial of service
    public void A_nonsense_hold_window_is_clamped_to_something_sane(int minutes)
    {
        var rules = BookingPaymentRules.From(new BookingType
        {
            ConfigJson = $$$"""{"payment":{"mode":"full","holdMinutes":{{{minutes}}}}}""",
        });

        Assert.InRange(rules.HoldWindow, TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(120));
    }

    [Fact]
    public void A_deposit_that_prices_to_nothing_charges_the_whole_fare_instead()
    {
        // Otherwise a 0% deposit would hold a seat for free.
        var rules = BookingPaymentRules.From(new BookingType
        {
            ConfigJson = """{"payment":{"mode":"deposit","depositPercent":0}}""",
        });

        Assert.Equal(15000m, rules.AmountPayableNow(15000m));
    }

    // ── Holding the seat ────────────────────────────────────────────────

    [Fact]
    public async Task A_live_hold_blocks_someone_else_paying_for_the_same_seat()
    {
        await using var db = TestHelpers.NewInMemoryDb(TenantId);
        var (resource, type) = await SeedExclusiveAsync(db);
        await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromMinutes(10));

        var conflict = await Availability.HasConflictAsync(db, resource.Id, Sailing, SailingEnd);

        Assert.True(conflict);
    }

    [Fact]
    public async Task A_lapsed_hold_frees_the_seat_without_waiting_for_the_sweeper()
    {
        // The sweeper tidies the record; it is not what releases the seat.
        // A customer who abandons a checkout must not hold the slot until
        // the next background pass runs.
        await using var db = TestHelpers.NewInMemoryDb(TenantId);
        var (resource, type) = await SeedExclusiveAsync(db);
        await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromMinutes(-1));

        var conflict = await Availability.HasConflictAsync(db, resource.Id, Sailing, SailingEnd);

        Assert.False(conflict);
    }

    [Fact]
    public async Task An_expired_booking_never_blocks_the_seat()
    {
        await using var db = TestHelpers.NewInMemoryDb(TenantId);
        var (resource, type) = await SeedExclusiveAsync(db);
        var held = await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromMinutes(10));
        held.Status = BookingStatus.Expired;
        await db.SaveChangesAsync();

        Assert.False(await Availability.HasConflictAsync(db, resource.Id, Sailing, SailingEnd));
    }

    [Fact]
    public async Task A_hold_on_a_shared_vessel_takes_its_seats_not_the_whole_sailing()
    {
        await using var db = TestHelpers.NewInMemoryDb(TenantId);
        var (resource, type) = await SeedSharedAsync(db, capacity: 120);
        await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromMinutes(10), seats: 4);

        var outcome = await Availability.CheckAsync(
            db, resource.Id, type.Id, null, Sailing, SailingEnd, seats: 2);

        Assert.Null(outcome.Error);
        Assert.Equal(116, outcome.SeatsRemaining);
    }

    [Fact]
    public async Task A_hold_for_the_last_seats_stops_the_next_customer()
    {
        await using var db = TestHelpers.NewInMemoryDb(TenantId);
        var (resource, type) = await SeedSharedAsync(db, capacity: 6);
        await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromMinutes(10), seats: 6);

        var outcome = await Availability.CheckAsync(
            db, resource.Id, type.Id, null, Sailing, SailingEnd, seats: 1);

        Assert.NotNull(outcome.Error);
        Assert.True(outcome.IsCapacityFailure);
    }

    // ── The sweeper ─────────────────────────────────────────────────────

    [Fact]
    public async Task The_sweeper_settles_lapsed_holds_and_leaves_live_ones_alone()
    {
        await using var db = TestHelpers.NewInMemoryDb(TenantId);
        var (resource, type) = await SeedExclusiveAsync(db);
        var lapsed = await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromMinutes(-10));
        var live = await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromMinutes(10),
            start: Sailing.AddDays(1), end: SailingEnd.AddDays(1));

        var released = await BookingHoldExpiryService.SweepAsync(
            db, DateTime.UtcNow, NullLogger.Instance, CancellationToken.None);

        Assert.Equal(1, released);
        Assert.Equal(BookingStatus.Expired, (await db.Bookings.FindAsync(lapsed.Id))!.Status);
        Assert.Equal(BookingStatus.PendingPayment, (await db.Bookings.FindAsync(live.Id))!.Status);
    }

    [Fact]
    public async Task The_sweeper_gives_a_late_gateway_a_grace_period()
    {
        // A hold that lapsed seconds ago is left alone: the gateway may be
        // mid-answer, and racing it would expire a booking that was paid.
        await using var db = TestHelpers.NewInMemoryDb(TenantId);
        var (resource, type) = await SeedExclusiveAsync(db);
        await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromSeconds(-5));

        var released = await BookingHoldExpiryService.SweepAsync(
            db, DateTime.UtcNow, NullLogger.Instance, CancellationToken.None);

        Assert.Equal(0, released);
    }

    // ── Only the gateway confirms ───────────────────────────────────────

    [Fact]
    public async Task A_paid_invoice_confirms_the_booking_it_names()
    {
        await using var db = TestHelpers.NewInMemoryDb(TenantId);
        var (resource, type) = await SeedExclusiveAsync(db);
        var booking = await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromMinutes(10));
        var invoice = await InvoiceFor(db, booking);

        await Listener(db).OnInvoicePaidAsync(invoice);

        var confirmed = await db.Bookings.FindAsync(booking.Id);
        Assert.Equal(BookingStatus.Confirmed, confirmed!.Status);
        Assert.Null(confirmed.HoldExpiresAt);
    }

    [Fact]
    public async Task Confirming_twice_is_harmless()
    {
        // Webhooks arrive twice, and can arrive while the call that started
        // the checkout is still in flight.
        await using var db = TestHelpers.NewInMemoryDb(TenantId);
        var (resource, type) = await SeedExclusiveAsync(db);
        var booking = await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromMinutes(10));
        var invoice = await InvoiceFor(db, booking);

        await Listener(db).OnInvoicePaidAsync(invoice);
        await Listener(db).OnInvoicePaidAsync(invoice);

        Assert.Equal(BookingStatus.Confirmed, (await db.Bookings.FindAsync(booking.Id))!.Status);
    }

    [Fact]
    public async Task Paying_after_the_hold_lapsed_still_confirms_when_the_seat_is_free()
    {
        await using var db = TestHelpers.NewInMemoryDb(TenantId);
        var (resource, type) = await SeedExclusiveAsync(db);
        var booking = await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromMinutes(-30));
        var invoice = await InvoiceFor(db, booking);

        await Listener(db).OnInvoicePaidAsync(invoice);

        Assert.Equal(BookingStatus.Confirmed, (await db.Bookings.FindAsync(booking.Id))!.Status);
    }

    [Fact]
    public async Task Paying_after_the_seat_was_resold_leaves_it_with_the_other_customer()
    {
        await using var db = TestHelpers.NewInMemoryDb(TenantId);
        var (resource, type) = await SeedExclusiveAsync(db);
        var late = await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromMinutes(-30));
        // Somebody else took the slot while the first customer dithered.
        var winner = await HoldAsync(db, resource, type, expiresIn: TimeSpan.FromMinutes(10));
        winner.Status = BookingStatus.Confirmed;
        await db.SaveChangesAsync();

        await Listener(db).OnInvoicePaidAsync(await InvoiceFor(db, late));

        var loser = await db.Bookings.FindAsync(late.Id);
        Assert.Equal(BookingStatus.Expired, loser!.Status);
        Assert.Contains("refund", loser.CancellationReason, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(BookingStatus.Confirmed, (await db.Bookings.FindAsync(winner.Id))!.Status);
    }

    [Fact]
    public async Task An_invoice_with_no_booking_is_ignored()
    {
        await using var db = TestHelpers.NewInMemoryDb(TenantId);
        var invoice = new Invoice { TenantId = Guid.NewGuid(), CustomerId = Guid.NewGuid(), BookingId = null };

        await Listener(db).OnInvoicePaidAsync(invoice);   // must not throw
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private static BookingPaymentListener Listener(AppDbContext db) =>
        new(db, NullLogger<BookingPaymentListener>.Instance);

    private static async Task<Invoice> InvoiceFor(AppDbContext db, Booking booking)
    {
        var invoice = new Invoice
        {
            TenantId = booking.TenantId,
            CustomerId = booking.BookedBy,
            BookingId = booking.Id,
            InvoiceNumber = $"INV-{Guid.NewGuid():N}"[..16],
            Status = "Paid",
            DueDate = DateTime.UtcNow,
        };
        db.Invoices.Add(invoice);
        await db.SaveChangesAsync();
        return invoice;
    }

    private static async Task<(Resource Resource, BookingType Type)> SeedExclusiveAsync(AppDbContext db)
        => await SeedAsync(db, capacity: null);

    private static async Task<(Resource Resource, BookingType Type)> SeedSharedAsync(AppDbContext db, int capacity)
        => await SeedAsync(db, capacity);

    private static async Task<(Resource, BookingType)> SeedAsync(AppDbContext db, int? capacity)
    {
        var tenantId = TenantId;
        var resource = new Resource
        {
            TenantId = tenantId,
            Name = capacity is null ? "Consulting room 1" : "Whale Watching Boat",
            Capacity = capacity ?? 0,
        };
        var type = new BookingType
        {
            TenantId = tenantId,
            Name = capacity is null ? "Consultation" : "Whale Watching",
            DefaultDurationMinutes = 240,
            ConfigJson = """{"payment":{"mode":"full","holdMinutes":15}}""",
        };
        db.Resources.Add(resource);
        db.BookingTypes.Add(type);
        await db.SaveChangesAsync();
        return (resource, type);
    }

    private static async Task<Booking> HoldAsync(
        AppDbContext db, Resource resource, BookingType type, TimeSpan expiresIn,
        int seats = 1, DateTime? start = null, DateTime? end = null)
    {
        var booking = new Booking
        {
            TenantId = resource.TenantId,
            ResourceId = resource.Id,
            BookingTypeId = type.Id,
            BookedBy = Guid.NewGuid(),
            StartTime = start ?? Sailing,
            EndTime = end ?? SailingEnd,
            Status = BookingStatus.PendingPayment,
            AttendeeCount = seats,
            HoldExpiresAt = DateTime.UtcNow.Add(expiresIn),
            PaymentMode = nameof(PaymentMode.Full),
        };
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();
        return booking;
    }
}
