using Microsoft.EntityFrameworkCore;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;

namespace SmeBackend.Tests;

/// Spec 2.8: unit tests for the conflict-detection logic and the
/// availability algorithms — the two pieces of the booking engine that,
/// if wrong, quietly sell the same hour twice.
///
/// SlotCalculator is exercised directly because it is the single definition
/// of "open" shared by GetAvailableSlots, SearchAvailability and the
/// planner's greedy fill; a bug there is a bug in all three at once.
public class AvailabilityAndConflictTests
{
    private static readonly DateTime Monday = new(2026, 9, 21, 0, 0, 0, DateTimeKind.Utc);

    private static ResourceSchedule NineToFive(int dayOfWeek = 1) => new()
    {
        DayOfWeek = dayOfWeek,
        StartTime = TimeSpan.FromHours(9),
        EndTime = TimeSpan.FromHours(17),
        IsAvailable = true,
    };

    /// Before the working day, so nothing is filtered out for being in the past.
    private static DateTime EarlyMorning => Monday.AddHours(1);

    // ── Availability algorithm ──────────────────────────────────────────

    [Fact]
    public void A_nine_to_five_day_at_sixty_minutes_yields_eight_slots()
    {
        var (isOpen, slots) = SlotCalculator.Calculate(
            Monday, NineToFive(), 60, 0, 0, Array.Empty<SlotBooking>(), EarlyMorning);

        Assert.True(isOpen);
        Assert.Equal(8, slots.Count);
        Assert.Equal(Monday.AddHours(9), slots[0].StartTime);
        Assert.Equal(Monday.AddHours(17), slots[^1].EndTime);
    }

    [Fact]
    public void A_slot_that_would_run_past_closing_is_not_offered()
    {
        // 90-minute slots into an 8-hour day: 5 fit (09:00-16:30), the sixth
        // would end at 18:00 and must not be sold.
        var (_, slots) = SlotCalculator.Calculate(
            Monday, NineToFive(), 90, 0, 0, Array.Empty<SlotBooking>(), EarlyMorning);

        Assert.Equal(5, slots.Count);
        Assert.All(slots, s => Assert.True(s.EndTime <= Monday.AddHours(17)));
    }

    [Fact]
    public void A_day_the_resource_is_closed_offers_nothing()
    {
        var closed = NineToFive();
        closed.IsAvailable = false;

        var (isOpen, slots) = SlotCalculator.Calculate(
            Monday, closed, 60, 0, 0, Array.Empty<SlotBooking>(), EarlyMorning);

        Assert.False(isOpen);
        Assert.Empty(slots);
    }

    [Fact]
    public void A_one_off_closed_date_beats_the_weekly_pattern()
    {
        // FR-AS6: a holiday closes a day the weekly schedule says is open.
        var (isOpen, slots) = SlotCalculator.Calculate(
            Monday, NineToFive(), 60, 0, 0, Array.Empty<SlotBooking>(), EarlyMorning, isClosedException: true);

        Assert.False(isOpen);
        Assert.Empty(slots);
    }

    [Fact]
    public void A_day_with_no_schedule_falls_back_to_nine_to_five()
    {
        var (isOpen, slots) = SlotCalculator.Calculate(
            Monday, null, 60, 0, 0, Array.Empty<SlotBooking>(), EarlyMorning);

        Assert.True(isOpen);
        Assert.Equal(8, slots.Count);
    }

    // ── Conflict detection ──────────────────────────────────────────────

    [Fact]
    public void An_existing_booking_makes_its_own_slot_unavailable()
    {
        var existing = new[] { new SlotBooking(Monday.AddHours(10), Monday.AddHours(11)) };

        var (_, slots) = SlotCalculator.Calculate(
            Monday, NineToFive(), 60, 0, 0, existing, EarlyMorning);

        var ten = slots.Single(s => s.StartTime == Monday.AddHours(10));
        var eleven = slots.Single(s => s.StartTime == Monday.AddHours(11));
        Assert.False(ten.IsAvailable);
        Assert.True(eleven.IsAvailable);
    }

    [Fact]
    public void A_booking_that_only_partly_overlaps_still_blocks_the_slot()
    {
        // 10:30-11:30 touches both the 10:00 and the 11:00 slot. Treating
        // an overlap as "free because it did not start here" is exactly how
        // a double booking gets sold.
        var existing = new[] { new SlotBooking(Monday.AddHours(10).AddMinutes(30), Monday.AddHours(11).AddMinutes(30)) };

        var (_, slots) = SlotCalculator.Calculate(
            Monday, NineToFive(), 60, 0, 0, existing, EarlyMorning);

        Assert.False(slots.Single(s => s.StartTime == Monday.AddHours(10)).IsAvailable);
        Assert.False(slots.Single(s => s.StartTime == Monday.AddHours(11)).IsAvailable);
        Assert.True(slots.Single(s => s.StartTime == Monday.AddHours(12)).IsAvailable);
    }

    [Fact]
    public void A_booking_that_merely_touches_the_boundary_does_not_block()
    {
        // 09:00-10:00 ends exactly as the 10:00 slot begins. Back-to-back is
        // normal trading, not a clash.
        var existing = new[] { new SlotBooking(Monday.AddHours(9), Monday.AddHours(10)) };

        var (_, slots) = SlotCalculator.Calculate(
            Monday, NineToFive(), 60, 0, 0, existing, EarlyMorning);

        Assert.False(slots.Single(s => s.StartTime == Monday.AddHours(9)).IsAvailable);
        Assert.True(slots.Single(s => s.StartTime == Monday.AddHours(10)).IsAvailable);
    }

    [Fact]
    public void Buffers_keep_the_slots_either_side_of_a_booking_clear()
    {
        // 15 minutes of turnaround either side of an 11:00-12:00 booking
        // spills into the neighbouring hours.
        var existing = new[] { new SlotBooking(Monday.AddHours(11), Monday.AddHours(12)) };

        var (_, slots) = SlotCalculator.Calculate(
            Monday, NineToFive(), 60, 15, 15, existing, EarlyMorning);

        Assert.False(slots.Single(s => s.StartTime == Monday.AddHours(10)).IsAvailable);
        Assert.False(slots.Single(s => s.StartTime == Monday.AddHours(11)).IsAvailable);
        Assert.False(slots.Single(s => s.StartTime == Monday.AddHours(12)).IsAvailable);
        Assert.True(slots.Single(s => s.StartTime == Monday.AddHours(13)).IsAvailable);
    }

    [Fact]
    public void Slots_already_in_the_past_are_not_offered()
    {
        // Asking at 13:00 must not offer this morning.
        var (_, slots) = SlotCalculator.Calculate(
            Monday, NineToFive(), 60, 0, 0, Array.Empty<SlotBooking>(), Monday.AddHours(13));

        Assert.All(slots.Where(s => s.StartTime < Monday.AddHours(13)), s => Assert.False(s.IsAvailable));
        Assert.True(slots.Single(s => s.StartTime == Monday.AddHours(13)).IsAvailable);
    }

    // ── Materialised slots (spec 2.3: AvailabilitySlots) ────────────────

    [Fact]
    public async Task Generation_materialises_one_row_per_open_window()
    {
        var tenantId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var resource = await SeedResourceAsync(db, tenantId);

        var result = await AvailabilitySlotService.GenerateAsync(db, resource, Monday, Monday, 60);

        Assert.Equal(8, result.Created);
        Assert.Equal(0, result.Skipped);
        Assert.Equal(8, await db.AvailabilitySlots.CountAsync());
    }

    [Fact]
    public async Task Generating_the_same_range_twice_adds_nothing()
    {
        var tenantId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var resource = await SeedResourceAsync(db, tenantId);

        await AvailabilitySlotService.GenerateAsync(db, resource, Monday, Monday, 60);
        var second = await AvailabilitySlotService.GenerateAsync(db, resource, Monday, Monday, 60);

        // A nightly job and a manual click must not double the inventory.
        Assert.Equal(0, second.Created);
        Assert.Equal(8, second.Skipped);
        Assert.Equal(8, await db.AvailabilitySlots.CountAsync());
    }

    [Fact]
    public async Task Generation_marks_slots_an_existing_booking_already_holds()
    {
        var tenantId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var resource = await SeedResourceAsync(db, tenantId);

        db.Bookings.Add(new Booking
        {
            TenantId = tenantId,
            ResourceId = resource.Id,
            BookingTypeId = Guid.NewGuid(),
            BookedBy = Guid.NewGuid(),
            StartTime = Monday.AddHours(10),
            EndTime = Monday.AddHours(11),
            Status = BookingStatus.Confirmed,
        });
        await db.SaveChangesAsync();

        await AvailabilitySlotService.GenerateAsync(db, resource, Monday, Monday, 60);

        var taken = await db.AvailabilitySlots.Where(s => s.IsBooked).ToListAsync();
        Assert.Single(taken);
        Assert.Equal(TimeSpan.FromHours(10), taken[0].StartTime);
    }

    [Fact]
    public async Task Booking_a_slot_takes_it_and_cancelling_hands_it_back()
    {
        var tenantId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var resource = await SeedResourceAsync(db, tenantId);
        await AvailabilitySlotService.GenerateAsync(db, resource, Monday, Monday, 60);

        var booking = new Booking
        {
            TenantId = tenantId,
            ResourceId = resource.Id,
            BookingTypeId = Guid.NewGuid(),
            BookedBy = Guid.NewGuid(),
            StartTime = Monday.AddHours(14),
            EndTime = Monday.AddHours(15),
            Status = BookingStatus.Confirmed,
        };
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();

        await AvailabilitySlotService.MarkBookedAsync(db, booking);
        await db.SaveChangesAsync();
        Assert.Equal(1, await db.AvailabilitySlots.CountAsync(s => s.IsBooked));

        await AvailabilitySlotService.ReleaseAsync(db, booking.Id);
        await db.SaveChangesAsync();
        Assert.Equal(0, await db.AvailabilitySlots.CountAsync(s => s.IsBooked));
    }

    [Fact]
    public async Task Releasing_one_booking_never_frees_another_bookings_slot()
    {
        var tenantId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var resource = await SeedResourceAsync(db, tenantId);
        await AvailabilitySlotService.GenerateAsync(db, resource, Monday, Monday, 60);

        var mine = await BookAsync(db, tenantId, resource.Id, Monday.AddHours(10));
        var theirs = await BookAsync(db, tenantId, resource.Id, Monday.AddHours(11));

        await AvailabilitySlotService.ReleaseAsync(db, mine.Id);
        await db.SaveChangesAsync();

        var stillHeld = await db.AvailabilitySlots.SingleAsync(s => s.IsBooked);
        Assert.Equal(theirs.Id, stillHeld.BookingId);
    }

    [Fact]
    public async Task A_booking_spanning_two_slots_takes_both()
    {
        var tenantId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var resource = await SeedResourceAsync(db, tenantId);
        await AvailabilitySlotService.GenerateAsync(db, resource, Monday, Monday, 60);

        var booking = new Booking
        {
            TenantId = tenantId,
            ResourceId = resource.Id,
            BookingTypeId = Guid.NewGuid(),
            BookedBy = Guid.NewGuid(),
            StartTime = Monday.AddHours(10),
            EndTime = Monday.AddHours(12),
            Status = BookingStatus.Confirmed,
        };
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();

        await AvailabilitySlotService.MarkBookedAsync(db, booking);
        await db.SaveChangesAsync();

        Assert.Equal(2, await db.AvailabilitySlots.CountAsync(s => s.IsBooked));
    }

    [Fact]
    public async Task A_closed_day_materialises_no_slots()
    {
        var tenantId = Guid.NewGuid();
        await using var db = TestHelpers.NewInMemoryDb(tenantId);
        var resource = await SeedResourceAsync(db, tenantId);

        db.ResourceScheduleExceptions.Add(new ResourceScheduleException
        {
            ResourceId = resource.Id,
            Date = Monday,
            Reason = "Public holiday",
        });
        await db.SaveChangesAsync();

        var result = await AvailabilitySlotService.GenerateAsync(db, resource, Monday, Monday, 60);

        Assert.Equal(0, result.Created);
        Assert.Equal(0, await db.AvailabilitySlots.CountAsync());
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private static async Task<Resource> SeedResourceAsync(Data.AppDbContext db, Guid tenantId)
    {
        var resource = new Resource
        {
            TenantId = tenantId,
            Name = "Room A",
            Category = ResourceCategory.Room,
            Status = ResourceStatus.Available,
        };
        db.Resources.Add(resource);
        db.ResourceSchedules.Add(new ResourceSchedule
        {
            ResourceId = resource.Id,
            DayOfWeek = (int)Monday.DayOfWeek,
            StartTime = TimeSpan.FromHours(9),
            EndTime = TimeSpan.FromHours(17),
            IsAvailable = true,
        });
        await db.SaveChangesAsync();
        return resource;
    }

    private static async Task<Booking> BookAsync(Data.AppDbContext db, Guid tenantId, Guid resourceId, DateTime start)
    {
        var booking = new Booking
        {
            TenantId = tenantId,
            ResourceId = resourceId,
            BookingTypeId = Guid.NewGuid(),
            BookedBy = Guid.NewGuid(),
            StartTime = start,
            EndTime = start.AddHours(1),
            Status = BookingStatus.Confirmed,
        };
        db.Bookings.Add(booking);
        await db.SaveChangesAsync();
        await AvailabilitySlotService.MarkBookedAsync(db, booking);
        await db.SaveChangesAsync();
        return booking;
    }

    // ── Shared vessels: seats, not exclusive occupancy ──────────────────
    // A 120-seat whale watching boat is not full because four people booked
    // it. Before this, one booking closed the sailing in the customer's date
    // picker while Availability.CheckAsync would still have taken the
    // booking - the picker said "no open slots" on a boat with 116 seats
    // free.

    /// The Morning Cruise as it is actually configured: open 10:00-14:00 for
    /// a 240-minute tour, so the window holds exactly one sailing a day.
    private static ResourceSchedule MorningCruise(int dayOfWeek = 1) => new()
    {
        DayOfWeek = dayOfWeek,
        StartTime = TimeSpan.FromHours(10),
        EndTime = TimeSpan.FromHours(14),
        IsAvailable = true,
    };

    [Fact]
    public void A_shared_sailing_with_seats_left_stays_open()
    {
        var existing = new[] { new SlotBooking(Monday.AddHours(10), Monday.AddHours(14), 4) };

        var (isOpen, slots) = SlotCalculator.Calculate(
            Monday, MorningCruise(), 240, 0, 30, existing, EarlyMorning, capacity: 120);

        Assert.True(isOpen);
        var sailing = Assert.Single(slots);
        Assert.True(sailing.IsAvailable);
        Assert.Equal(120, sailing.Capacity);
        Assert.Equal(116, sailing.SeatsRemaining);
    }

    [Fact]
    public void A_shared_sailing_closes_only_once_its_seats_are_gone()
    {
        var existing = new[]
        {
            new SlotBooking(Monday.AddHours(10), Monday.AddHours(14), 100),
            new SlotBooking(Monday.AddHours(10), Monday.AddHours(14), 20),
        };

        var (_, slots) = SlotCalculator.Calculate(
            Monday, MorningCruise(), 240, 0, 30, existing, EarlyMorning, capacity: 120);

        var sailing = Assert.Single(slots);
        Assert.False(sailing.IsAvailable);
        Assert.Equal(0, sailing.SeatsRemaining);
    }

    [Fact]
    public void An_overbooked_sailing_reports_no_seats_rather_than_a_negative_count()
    {
        var existing = new[] { new SlotBooking(Monday.AddHours(10), Monday.AddHours(14), 130) };

        var (_, slots) = SlotCalculator.Calculate(
            Monday, MorningCruise(), 240, 0, 30, existing, EarlyMorning, capacity: 120);

        Assert.Equal(0, Assert.Single(slots).SeatsRemaining);
    }

    [Fact]
    public void Buffers_do_not_shrink_a_shared_sailing()
    {
        // The 30-minute turnaround is time between two parties on an
        // exclusive resource. Applying it to guests sharing one departure
        // would count a booking that merely abuts the window.
        var existing = new[] { new SlotBooking(Monday.AddHours(14), Monday.AddHours(15), 10) };

        var (_, slots) = SlotCalculator.Calculate(
            Monday, MorningCruise(), 240, 0, 30, existing, EarlyMorning, capacity: 120);

        var sailing = Assert.Single(slots);
        Assert.True(sailing.IsAvailable);
        Assert.Equal(120, sailing.SeatsRemaining);
    }

    [Fact]
    public void A_shared_sailing_in_the_past_is_still_closed()
    {
        var (_, slots) = SlotCalculator.Calculate(
            Monday, MorningCruise(), 240, 0, 30, Array.Empty<SlotBooking>(),
            Monday.AddHours(13), capacity: 120);

        Assert.False(Assert.Single(slots).IsAvailable);
    }

    [Theory]
    [InlineData(null)]
    [InlineData(1)]
    public void A_resource_booked_one_party_at_a_time_keeps_exclusive_occupancy(int? capacity)
    {
        // The guard that keeps every consulting room, hire car and treatment
        // chair behaving exactly as it did: one booking takes the slot,
        // whatever the party size, and no seat count is reported.
        var existing = new[] { new SlotBooking(Monday.AddHours(10), Monday.AddHours(11), 1) };

        var (_, slots) = SlotCalculator.Calculate(
            Monday, NineToFive(), 60, 0, 0, existing, EarlyMorning, capacity: capacity);

        var taken = Assert.Single(slots, s => s.StartTime == Monday.AddHours(10));
        Assert.False(taken.IsAvailable);
        Assert.Null(taken.Capacity);
        Assert.Null(taken.SeatsRemaining);
        Assert.True(Assert.Single(slots, s => s.StartTime == Monday.AddHours(11)).IsAvailable);
    }
}
