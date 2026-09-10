using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;

namespace SmeBackend.Tests;

/// End-to-end-ish coverage of the departure operations endpoints against an
/// in-memory context, in the style of the existing controller tests.
public class DepartureOpsTests
{
    private static readonly Guid TenantId = Guid.NewGuid();
    private static readonly Guid AdminId = Guid.NewGuid();

    private const string WhaleConfig = """
    {
      "subType": "whaleWatching",
      "pricing": { "adult": 7500, "child": 4000, "infant": 0, "currency": "LKR" },
      "season": { "months": ["Nov","Dec","Jan","Feb","Mar","Apr"], "weatherDependent": true }
    }
    """;

    private sealed record Fixture(
        AppDbContext Db, Resource Vessel, BookingType Tour, Departure Departure);

    /// A tenant with one 120-seat vessel and one scheduled departure.
    private static Fixture NewFixture(int capacity = 120, DateTime? departsAt = null)
    {
        var db = TestHelpers.NewInMemoryDb();

        db.Tenants.Add(new Tenant
        {
            Id = TenantId,
            Name = "Mirissa Jetliner",
            BusinessType = "Tourism",
            SubType = "Whale / dolphin watching",
            RescheduleCutoffHours = 2,
        });

        var vessel = new Resource
        {
            TenantId = TenantId,
            Name = "Sea Guardian",
            Category = ResourceCategory.Vehicle,
            CustomAttributes = JsonSerializer.Serialize(new { capacity }),
        };
        var tour = new BookingType
        {
            TenantId = TenantId,
            Name = "Whale Watching Tour",
            Slug = $"whale-{Guid.NewGuid():N}",
            DefaultDurationMinutes = 240,
            MaxParticipants = capacity,
            ConfigJson = WhaleConfig,
        };
        var departure = new Departure
        {
            TenantId = TenantId,
            ResourceId = vessel.Id,
            BookingTypeId = tour.Id,
            ScheduledDeparture = departsAt ?? DateTime.UtcNow.Date.AddDays(3).AddHours(6.5),
            ScheduledReturn = (departsAt ?? DateTime.UtcNow.Date.AddDays(3).AddHours(6.5)).AddHours(4),
        };

        db.Resources.Add(vessel);
        db.BookingTypes.Add(tour);
        db.Departures.Add(departure);
        db.SaveChanges();

        return new Fixture(db, vessel, tour, departure);
    }

    private static Booking AddBooking(Fixture f, int adults, int children = 0, bool waiverSigned = false, string? source = null)
    {
        var lines = new List<TicketLine> { new() { Type = "Adult", Qty = adults } };
        if (children > 0) lines.Add(new TicketLine { Type = "Child", Qty = children });
        var priced = TicketPricing.Price(lines, f.Tour, f.Departure.ScheduledDeparture);

        var booking = new Booking
        {
            TenantId = TenantId,
            ResourceId = f.Vessel.Id,
            BookingTypeId = f.Tour.Id,
            BookedBy = Guid.NewGuid(),
            DepartureId = f.Departure.Id,
            StartTime = f.Departure.ScheduledDeparture,
            EndTime = f.Departure.ScheduledReturn,
            Status = BookingStatus.Confirmed,
            TicketBreakdown = TicketPricing.Serialize(priced.Lines),
            AttendeeCount = priced.TotalQuantity,
            TotalCost = priced.Total,
            Source = source,
            Waiver = waiverSigned
                ? JsonSerializer.Serialize(new { signedAt = DateTime.UtcNow, signerName = "Guest", minorCount = children })
                : null,
        };
        f.Db.Bookings.Add(booking);
        f.Db.SaveChanges();
        return booking;
    }

    private static BookingsController NewBookingsController(AppDbContext db, string role = Roles.Admin)
    {
        var controller = new BookingsController(db, new NoopReminderSender(), new NoopPushSender());
        TestHelpers.SetUser(controller, AdminId, TenantId, role);
        return controller;
    }

    private static DeparturesController NewDeparturesController(AppDbContext db, string role = Roles.Admin)
    {
        var controller = new DeparturesController(db, new NoopPushSender());
        TestHelpers.SetUser(controller, AdminId, TenantId, role);
        return controller;
    }

    private static SightingsController NewSightingsController(AppDbContext db, string role = Roles.Staff)
    {
        var controller = new SightingsController(db);
        TestHelpers.SetUser(controller, AdminId, TenantId, role);
        return controller;
    }

    private static T Value<T>(IActionResult result) where T : class
    {
        var payload = result switch
        {
            OkObjectResult ok => ok.Value,
            CreatedAtActionResult created => created.Value,
            BadRequestObjectResult bad => bad.Value,
            ConflictObjectResult conflict => conflict.Value,
            _ => null,
        };
        Assert.NotNull(payload);
        // Controllers return anonymous types; round-tripping through JSON is
        // the least brittle way to assert on them.
        var json = JsonSerializer.Serialize(payload);
        return JsonSerializer.Deserialize<T>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
    }

    // ── Capacity (acceptance criterion 3) ──────────────────────────────
    private sealed class CapacityErrorPayload
    {
        public string? Message { get; set; }
        public int? Capacity { get; set; }
        public int? SeatsRemaining { get; set; }
    }

    private sealed class CreatedBookingPayload
    {
        public Guid Id { get; set; }
        public decimal? TotalCost { get; set; }
        public string? TicketBreakdown { get; set; }
        public string? CapacityWarning { get; set; }
        public string? Currency { get; set; }
        public bool IsOffPeakRate { get; set; }
    }

    [Fact]
    public async Task Overbooking_beyond_licensed_capacity_is_rejected()
    {
        var f = NewFixture(capacity: 10);
        AddBooking(f, adults: 8);

        var controller = NewBookingsController(f.Db);
        var result = await controller.Create(NewBookingDto(f, adults: 3));

        Assert.IsType<BadRequestObjectResult>(result);
        var payload = Value<CapacityErrorPayload>(result);
        Assert.Equal(10, payload.Capacity);
        Assert.Equal(2, payload.SeatsRemaining);
    }

    [Fact]
    public async Task Booking_at_ninety_percent_is_allowed_but_warns()
    {
        var f = NewFixture(capacity: 10);
        AddBooking(f, adults: 8);

        var controller = NewBookingsController(f.Db);
        var result = await controller.Create(NewBookingDto(f, adults: 1));

        Assert.IsType<CreatedAtActionResult>(result);
        var payload = Value<CreatedBookingPayload>(result);
        Assert.NotNull(payload.CapacityWarning);
    }

    [Fact]
    public async Task Twenty_reservations_can_share_one_sailing()
    {
        // The behaviour the original exclusive-occupancy conflict check made
        // impossible, and the reason CheckAvailabilityAsync exists.
        var f = NewFixture(capacity: 120);
        var controller = NewBookingsController(f.Db);

        for (var i = 0; i < 20; i++)
        {
            var result = await controller.Create(NewBookingDto(f, adults: 2));
            Assert.IsType<CreatedAtActionResult>(result);
        }

        Assert.Equal(20, f.Db.Bookings.Count(b => b.DepartureId == f.Departure.Id));
    }

    [Fact]
    public async Task Exclusive_resources_still_reject_any_overlap()
    {
        // The regression guard for every non-shared resource in the system.
        var db = TestHelpers.NewInMemoryDb();
        db.Tenants.Add(new Tenant { Id = TenantId, Name = "Clinic", BusinessType = "Clinic" });
        var room = new Resource { TenantId = TenantId, Name = "Consulting Room 1", Category = ResourceCategory.Room };
        var consult = new BookingType
        {
            TenantId = TenantId, Name = "Consultation", Slug = $"c-{Guid.NewGuid():N}", DefaultDurationMinutes = 30,
        };
        db.Resources.Add(room);
        db.BookingTypes.Add(consult);
        var start = DateTime.UtcNow.Date.AddDays(2).AddHours(10);
        db.Bookings.Add(new Booking
        {
            TenantId = TenantId, ResourceId = room.Id, BookingTypeId = consult.Id, BookedBy = Guid.NewGuid(),
            StartTime = start, EndTime = start.AddMinutes(30), Status = BookingStatus.Confirmed,
        });
        db.SaveChanges();

        var controller = NewBookingsController(db);
        var result = await controller.Create(new CreateBookingDto(
            TenantId, room.Id, consult.Id, Guid.NewGuid(), start, start.AddMinutes(30),
            null, null, null, BookingPriority.Normal, null, null));

        Assert.IsType<ConflictObjectResult>(result);
    }

    [Fact]
    public async Task A_booking_with_no_departure_id_is_linked_to_the_sailing_it_is_on()
    {
        // The customer app and the admin booking form both predate departures
        // and send no DepartureId, so without this the guest is a real
        // reservation that never appears on the operator's departure board.
        var f = NewFixture();
        var controller = NewBookingsController(f.Db);

        var result = await controller.Create(new CreateBookingDto(
            TenantId, f.Vessel.Id, f.Tour.Id, Guid.NewGuid(),
            f.Departure.ScheduledDeparture, f.Departure.ScheduledReturn,
            "Whale watching", null, null, BookingPriority.Normal, 2, null));

        Assert.IsType<CreatedAtActionResult>(result);
        Assert.Equal(f.Departure.Id, f.Db.Bookings.Single().DepartureId);
    }

    [Fact]
    public async Task A_booking_at_a_different_time_is_not_folded_into_the_sailing()
    {
        // 09:00 is not the 06:30 departure. Linking it would put a guest on a
        // manifest they never booked, so the link is left null instead.
        var f = NewFixture();
        var controller = NewBookingsController(f.Db);

        var offHour = f.Departure.ScheduledDeparture.AddHours(2.5);
        var result = await controller.Create(new CreateBookingDto(
            TenantId, f.Vessel.Id, f.Tour.Id, Guid.NewGuid(),
            offHour, offHour.AddHours(4),
            "Whale watching", null, null, BookingPriority.Normal, 2, null));

        Assert.IsType<CreatedAtActionResult>(result);
        Assert.Null(f.Db.Bookings.Single().DepartureId);
    }

    // ── Ticket pricing end to end (acceptance criterion 6) ─────────────
    [Fact]
    public async Task Two_adults_and_one_child_prices_correctly_through_the_endpoint()
    {
        var f = NewFixture();
        var controller = NewBookingsController(f.Db);

        var result = await controller.Create(NewBookingDto(f, adults: 2, children: 1));

        Assert.IsType<CreatedAtActionResult>(result);
        var payload = Value<CreatedBookingPayload>(result);
        Assert.Equal(19000m, payload.TotalCost);
        Assert.Equal("LKR", payload.Currency);

        var saved = f.Db.Bookings.Single(b => b.Id == payload.Id);
        Assert.Equal(3, saved.AttendeeCount);
        Assert.Equal(3, TicketPricing.SeatsUsed(saved.TicketBreakdown, saved.AttendeeCount));
    }

    [Fact]
    public async Task A_client_cannot_set_its_own_ticket_price()
    {
        // Unit prices are resolved server-side from ConfigJson, so a crafted
        // request cannot buy a 7500 seat for 1.
        var f = NewFixture();
        var controller = NewBookingsController(f.Db);

        var dto = NewBookingDto(f, adults: 0) with
        {
            TicketBreakdown = new List<TicketLine> { new() { Type = "Adult", Qty = 2, UnitPrice = null } },
        };
        var result = await controller.Create(dto);

        var payload = Value<CreatedBookingPayload>(result);
        Assert.Equal(15000m, payload.TotalCost);
    }

    [Fact]
    public async Task Booking_with_no_breakdown_behaves_exactly_as_before()
    {
        var f = NewFixture();
        var controller = NewBookingsController(f.Db);

        var result = await controller.Create(new CreateBookingDto(
            TenantId, f.Vessel.Id, f.Tour.Id, Guid.NewGuid(),
            f.Departure.ScheduledDeparture, f.Departure.ScheduledReturn,
            "Legacy booking", null, null, BookingPriority.Normal, 2, null));

        Assert.IsType<CreatedAtActionResult>(result);
        var saved = f.Db.Bookings.Single();
        Assert.Null(saved.TicketBreakdown);
        Assert.Null(saved.TotalCost);
        Assert.Equal(2, saved.AttendeeCount);
    }

    // ── Weather cancellation (acceptance criterion 4) ──────────────────
    private sealed class WeatherCancelPayload
    {
        public Guid DepartureId { get; set; }
        public string? Status { get; set; }
        public int BookingsCancelled { get; set; }
        public int GuestsNotified { get; set; }
        public List<RescheduleOption> RescheduleOptions { get; set; } = new();
    }

    private sealed class RescheduleOption
    {
        public Guid DepartureId { get; set; }
        public int SeatsRemaining { get; set; }
    }

    [Fact]
    public async Task Weather_cancel_marks_bookings_notifies_guests_and_offers_a_reschedule()
    {
        var f = NewFixture();
        AddBooking(f, adults: 2);
        AddBooking(f, adults: 1, children: 1);

        // A later sailing to offer as the alternative.
        var alternative = new Departure
        {
            TenantId = TenantId,
            ResourceId = f.Vessel.Id,
            BookingTypeId = f.Tour.Id,
            ScheduledDeparture = f.Departure.ScheduledDeparture.AddDays(1),
            ScheduledReturn = f.Departure.ScheduledReturn.AddDays(1),
        };
        f.Db.Departures.Add(alternative);
        f.Db.SaveChanges();

        var controller = NewDeparturesController(f.Db);
        var result = await controller.CancelForWeather(
            f.Departure.Id,
            new CancelForWeatherDto("Force 6 winds, harbour master advised against sailing.",
                new WeatherReadingDto(28m, 2.5m, 4m, 5, null)));

        var payload = Value<WeatherCancelPayload>(result);
        Assert.Equal("CancelledWeather", payload.Status);
        Assert.Equal(2, payload.BookingsCancelled);
        Assert.Equal(2, payload.GuestsNotified);
        Assert.Contains(payload.RescheduleOptions, o => o.DepartureId == alternative.Id);

        Assert.All(
            f.Db.Bookings.Where(b => b.DepartureId == f.Departure.Id),
            b => Assert.Equal(BookingStatus.WeatherCancelled, b.Status));
        Assert.Equal(2, f.Db.Notifications.Count(n => n.Type == "WeatherCancellation"));
        // The reading that justified the call is kept alongside the decision.
        Assert.Single(f.Db.WeatherObservations.Where(w => w.DepartureId == f.Departure.Id));
    }

    [Fact]
    public async Task Weather_cancelled_seats_are_released_for_resale()
    {
        var f = NewFixture(capacity: 4);
        AddBooking(f, adults: 4);

        var controller = NewDeparturesController(f.Db);
        await controller.CancelForWeather(f.Departure.Id, null);

        // The boat is full of cancelled bookings; a new sale must still fit.
        var bookings = NewBookingsController(f.Db);
        var result = await bookings.Create(NewBookingDto(f, adults: 4));

        Assert.IsType<CreatedAtActionResult>(result);
    }

    private sealed class BulkReschedulePayload
    {
        public int MovedCount { get; set; }
        public int SkippedCount { get; set; }
    }

    [Fact]
    public async Task Bulk_reschedule_moves_guests_keeping_their_ticket_breakdown()
    {
        var f = NewFixture();
        var a = AddBooking(f, adults: 2, children: 1);
        var b = AddBooking(f, adults: 1);

        var target = new Departure
        {
            TenantId = TenantId,
            ResourceId = f.Vessel.Id,
            BookingTypeId = f.Tour.Id,
            ScheduledDeparture = f.Departure.ScheduledDeparture.AddDays(2),
            ScheduledReturn = f.Departure.ScheduledReturn.AddDays(2),
        };
        f.Db.Departures.Add(target);
        f.Db.SaveChanges();

        var controller = NewDeparturesController(f.Db);
        await controller.CancelForWeather(f.Departure.Id, null);

        var result = await controller.BulkReschedule(
            f.Departure.Id, new BulkRescheduleDto(target.Id, new List<Guid> { a.Id, b.Id }));

        var payload = Value<BulkReschedulePayload>(result);
        Assert.Equal(2, payload.MovedCount);
        Assert.Equal(0, payload.SkippedCount);

        var moved = f.Db.Bookings.Single(x => x.Id == a.Id);
        Assert.Equal(target.Id, moved.DepartureId);
        Assert.Equal(target.ScheduledDeparture, moved.StartTime);
        Assert.Equal(BookingStatus.Confirmed, moved.Status);
        Assert.Equal(3, TicketPricing.SeatsUsed(moved.TicketBreakdown, moved.AttendeeCount));
    }

    [Fact]
    public async Task Bulk_reschedule_honours_the_tenants_reschedule_cutoff()
    {
        var f = NewFixture();
        var booking = AddBooking(f, adults: 2);

        // Inside the tenant's 2-hour cutoff.
        var imminent = new Departure
        {
            TenantId = TenantId,
            ResourceId = f.Vessel.Id,
            BookingTypeId = f.Tour.Id,
            ScheduledDeparture = DateTime.UtcNow.AddMinutes(30),
            ScheduledReturn = DateTime.UtcNow.AddHours(4),
        };
        f.Db.Departures.Add(imminent);
        f.Db.SaveChanges();

        var controller = NewDeparturesController(f.Db);
        var result = await controller.BulkReschedule(
            f.Departure.Id, new BulkRescheduleDto(imminent.Id, new List<Guid> { booking.Id }));

        var bad = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains("cutoff", JsonSerializer.Serialize(bad.Value), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Bulk_reschedule_skips_guests_who_would_not_fit()
    {
        var f = NewFixture();
        var big = AddBooking(f, adults: 6);

        var small = new Departure
        {
            TenantId = TenantId,
            ResourceId = f.Vessel.Id,
            BookingTypeId = f.Tour.Id,
            ScheduledDeparture = f.Departure.ScheduledDeparture.AddDays(1),
            ScheduledReturn = f.Departure.ScheduledReturn.AddDays(1),
            LicensedCapacity = 4,
        };
        f.Db.Departures.Add(small);
        f.Db.SaveChanges();

        var controller = NewDeparturesController(f.Db);
        var result = await controller.BulkReschedule(
            f.Departure.Id, new BulkRescheduleDto(small.Id, new List<Guid> { big.Id }));

        var payload = Value<BulkReschedulePayload>(result);
        Assert.Equal(0, payload.MovedCount);
        Assert.Equal(1, payload.SkippedCount);
    }

    // ── Safety checklist gate (section 3.5) ────────────────────────────
    [Fact]
    public async Task Cannot_go_to_sea_without_a_complete_safety_checklist()
    {
        var f = NewFixture();
        var controller = NewDeparturesController(f.Db, Roles.Staff);

        var result = await controller.SetStatus(
            f.Departure.Id, new SetDepartureStatusDto(DepartureStatus.AtSea, null));

        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Equal(DepartureStatus.Scheduled, f.Db.Departures.Single(d => d.Id == f.Departure.Id).Status);
    }

    [Fact]
    public async Task Staff_cannot_override_the_safety_checklist_but_admin_can()
    {
        var f = NewFixture();

        var staff = NewDeparturesController(f.Db, Roles.Staff);
        var refused = await staff.SetStatus(
            f.Departure.Id, new SetDepartureStatusDto(DepartureStatus.AtSea, null, OverrideSafetyChecklist: true));
        Assert.IsType<BadRequestObjectResult>(refused);

        var admin = NewDeparturesController(f.Db, Roles.Admin);
        var allowed = await admin.SetStatus(
            f.Departure.Id, new SetDepartureStatusDto(DepartureStatus.AtSea, null, OverrideSafetyChecklist: true));
        Assert.IsType<OkObjectResult>(allowed);
        Assert.Equal(DepartureStatus.AtSea, f.Db.Departures.Single(d => d.Id == f.Departure.Id).Status);
    }

    [Fact]
    public async Task A_completed_checklist_lets_the_departure_sail()
    {
        var f = NewFixture();
        var controller = NewDeparturesController(f.Db, Roles.Staff);

        await controller.SetSafetyChecklist(f.Departure.Id, new SafetyChecklistDto(true, true, true, true));
        var result = await controller.SetStatus(f.Departure.Id, new SetDepartureStatusDto(DepartureStatus.AtSea, null));

        Assert.IsType<OkObjectResult>(result);
        var saved = f.Db.Departures.Single(d => d.Id == f.Departure.Id);
        Assert.Equal(DepartureStatus.AtSea, saved.Status);
        Assert.NotNull(saved.ActualDepartureAt);
    }

    [Fact]
    public async Task Weather_cancellation_cannot_be_smuggled_through_the_status_setter()
    {
        // Routing it there would skip the guest notifications entirely.
        var f = NewFixture();
        var controller = NewDeparturesController(f.Db);

        var result = await controller.SetStatus(
            f.Departure.Id, new SetDepartureStatusDto(DepartureStatus.CancelledWeather, "storm"));

        Assert.IsType<BadRequestObjectResult>(result);
    }

    // ── Sightings analytics (acceptance criterion 5) ───────────────────
    private sealed class AnalyticsPayload
    {
        public int DeparturesSailed { get; set; }
        public int DeparturesWithSighting { get; set; }
        public double SuccessRate { get; set; }
        public int TotalSightings { get; set; }
        public int TotalIndividuals { get; set; }
        public List<SpeciesRow> SpeciesFrequency { get; set; } = new();
    }

    private sealed class SpeciesRow
    {
        public string Species { get; set; } = string.Empty;
        public int Sightings { get; set; }
    }

    [Fact]
    public async Task A_sighting_logged_today_shows_in_todays_success_rate()
    {
        var today = DateTime.UtcNow.Date.AddHours(6.5);
        var f = NewFixture(departsAt: today);

        var sightings = NewSightingsController(f.Db);
        var logged = await sightings.Create(new CreateSightingDto(
            f.Departure.Id, Guid.Empty, null, default,
            SightingSpecies.BlueWhale, 2, 5.94, 80.45, SightingBehaviour.Breaching, "Two adults", null));
        Assert.IsType<CreatedAtActionResult>(logged);

        var result = await sightings.GetAnalytics(DateTime.UtcNow.Date, DateTime.UtcNow.Date, null);
        var payload = Value<AnalyticsPayload>(result);

        Assert.Equal(1, payload.DeparturesSailed);
        Assert.Equal(1, payload.DeparturesWithSighting);
        Assert.Equal(100, payload.SuccessRate);
        Assert.Equal(2, payload.TotalIndividuals);
        Assert.Contains(payload.SpeciesFrequency, s => s.Species == "BlueWhale");
    }

    [Fact]
    public async Task Weather_cancelled_departures_are_left_out_of_the_success_rate()
    {
        // Otherwise a stormy month reads as bad spotting rather than bad
        // weather, which is the whole point of separating the two statuses.
        var today = DateTime.UtcNow.Date.AddHours(6.5);
        var f = NewFixture(departsAt: today);

        var cancelled = new Departure
        {
            TenantId = TenantId,
            ResourceId = f.Vessel.Id,
            BookingTypeId = f.Tour.Id,
            ScheduledDeparture = today.AddHours(4),
            ScheduledReturn = today.AddHours(8),
            Status = DepartureStatus.CancelledWeather,
        };
        f.Db.Departures.Add(cancelled);
        f.Db.SaveChanges();

        var sightings = NewSightingsController(f.Db);
        await sightings.Create(new CreateSightingDto(
            f.Departure.Id, Guid.Empty, null, default,
            SightingSpecies.SpinnerDolphin, 30, null, null, null, null, null));

        var payload = Value<AnalyticsPayload>(
            await sightings.GetAnalytics(DateTime.UtcNow.Date, DateTime.UtcNow.Date, null));

        Assert.Equal(1, payload.DeparturesSailed);
        Assert.Equal(100, payload.SuccessRate);
    }

    [Fact]
    public async Task Success_rate_can_be_filtered_to_one_species()
    {
        var today = DateTime.UtcNow.Date.AddHours(6.5);
        var f = NewFixture(departsAt: today);

        var second = new Departure
        {
            TenantId = TenantId,
            ResourceId = f.Vessel.Id,
            BookingTypeId = f.Tour.Id,
            ScheduledDeparture = today.AddHours(4),
            ScheduledReturn = today.AddHours(8),
        };
        f.Db.Departures.Add(second);
        f.Db.SaveChanges();

        var sightings = NewSightingsController(f.Db);
        await sightings.Create(new CreateSightingDto(
            f.Departure.Id, Guid.Empty, null, default, SightingSpecies.BlueWhale, 1, null, null, null, null, null));
        await sightings.Create(new CreateSightingDto(
            second.Id, Guid.Empty, null, default, SightingSpecies.SpinnerDolphin, 20, null, null, null, null, null));

        var all = Value<AnalyticsPayload>(await sightings.GetAnalytics(DateTime.UtcNow.Date, DateTime.UtcNow.Date, null));
        var blueOnly = Value<AnalyticsPayload>(
            await sightings.GetAnalytics(DateTime.UtcNow.Date, DateTime.UtcNow.Date, SightingSpecies.BlueWhale));

        Assert.Equal(100, all.SuccessRate);
        Assert.Equal(50, blueOnly.SuccessRate);
    }

    [Fact]
    public async Task Sightings_span_land_wildlife_for_safari_operators()
    {
        // SightingsLog is deliberately not whale-specific (task section 5).
        var f = NewFixture(departsAt: DateTime.UtcNow.Date.AddHours(6));
        var sightings = NewSightingsController(f.Db);

        var result = await sightings.Create(new CreateSightingDto(
            f.Departure.Id, Guid.Empty, null, default,
            SightingSpecies.Leopard, 1, null, null, SightingBehaviour.Hunting, "Block 1", null));

        Assert.IsType<CreatedAtActionResult>(result);
        Assert.Equal(SightingSpecies.Leopard, f.Db.SightingsLogs.Single().Species);
    }

    // ── Manifest and waiver (section 3.6) ──────────────────────────────
    private sealed class ManifestPayload
    {
        public double WaiverCompletionPercent { get; set; }
        public int CheckedInCount { get; set; }
        public List<PassengerRow> Passengers { get; set; } = new();
    }

    private sealed class PassengerRow
    {
        public Guid BookingId { get; set; }
        public int Seats { get; set; }
        public bool WaiverSigned { get; set; }
        public int MinorCount { get; set; }
        public bool CheckedIn { get; set; }
    }

    [Fact]
    public async Task Manifest_reports_waiver_completion_and_seat_counts()
    {
        var f = NewFixture();
        AddBooking(f, adults: 2, waiverSigned: true);
        AddBooking(f, adults: 1, children: 1, waiverSigned: false);

        var controller = NewDeparturesController(f.Db, Roles.Staff);
        var payload = Value<ManifestPayload>(await controller.GetManifest(f.Departure.Id));

        Assert.Equal(2, payload.Passengers.Count);
        Assert.Equal(50, payload.WaiverCompletionPercent);
        Assert.Equal(4, payload.Passengers.Sum(p => p.Seats));
    }

    [Fact]
    public async Task Signing_a_waiver_moves_the_manifest_percentage()
    {
        var f = NewFixture();
        var booking = AddBooking(f, adults: 2);

        var bookings = NewBookingsController(f.Db);
        var signed = await bookings.SetWaiver(booking.Id, new SetWaiverDto("Nadeesha Perera", null, 1));
        Assert.IsType<OkObjectResult>(signed);

        var departures = NewDeparturesController(f.Db, Roles.Staff);
        var payload = Value<ManifestPayload>(await departures.GetManifest(f.Departure.Id));

        Assert.Equal(100, payload.WaiverCompletionPercent);
        Assert.True(payload.Passengers.Single().WaiverSigned);
        Assert.Equal(1, payload.Passengers.Single().MinorCount);
    }

    [Fact]
    public async Task A_waiver_needs_a_signer_name()
    {
        var f = NewFixture();
        var booking = AddBooking(f, adults: 1);

        var result = await NewBookingsController(f.Db).SetWaiver(booking.Id, new SetWaiverDto("  ", null, 0));

        Assert.IsType<BadRequestObjectResult>(result);
    }

    // ── Board ──────────────────────────────────────────────────────────
    private sealed class BoardPayload
    {
        public List<DepartureCard> Upcoming { get; set; } = new();
        public List<DepartureCard> Today { get; set; } = new();
    }

    private sealed class DepartureCard
    {
        public Guid Id { get; set; }
        public string VesselName { get; set; } = string.Empty;
        public int Capacity { get; set; }
        public int PaxBooked { get; set; }
        public int SeatsRemaining { get; set; }
        public double OccupancyPercent { get; set; }
        public bool NearCapacity { get; set; }
        public double WaiverCompletionPercent { get; set; }
        public Dictionary<string, int> TicketMix { get; set; } = new();
        public string Status { get; set; } = string.Empty;
    }

    [Fact]
    public async Task Board_shows_pax_against_capacity_and_the_ticket_mix()
    {
        var f = NewFixture(capacity: 120, departsAt: DateTime.UtcNow.Date.AddHours(6.5));
        AddBooking(f, adults: 2, children: 1, waiverSigned: true);
        AddBooking(f, adults: 3);

        var controller = NewDeparturesController(f.Db, Roles.Staff);
        var payload = Value<BoardPayload>(await controller.GetBoard(DateTime.UtcNow.Date, 7));

        var card = Assert.Single(payload.Today);
        Assert.Equal("Sea Guardian", card.VesselName);
        Assert.Equal(120, card.Capacity);
        Assert.Equal(6, card.PaxBooked);
        Assert.Equal(114, card.SeatsRemaining);
        Assert.Equal(5, card.TicketMix["Adult"]);
        Assert.Equal(1, card.TicketMix["Child"]);
        Assert.Equal(50, card.WaiverCompletionPercent);
        Assert.False(card.NearCapacity);
    }

    [Fact]
    public async Task Board_flags_a_nearly_full_departure()
    {
        var f = NewFixture(capacity: 10, departsAt: DateTime.UtcNow.Date.AddHours(6.5));
        AddBooking(f, adults: 9);

        var payload = Value<BoardPayload>(
            await NewDeparturesController(f.Db, Roles.Staff).GetBoard(DateTime.UtcNow.Date, 7));

        Assert.True(Assert.Single(payload.Today).NearCapacity);
    }

    // ── Excursion KPIs ─────────────────────────────────────────────────
    private sealed class KpiPayload
    {
        public int DeparturesToday { get; set; }
        public int PaxBookedToday { get; set; }
        public int CapacityToday { get; set; }
        public double OccupancyTodayPercent { get; set; }
        public double SightingSuccessRate { get; set; }
        public decimal RevenueToday { get; set; }
        public int WeatherCancelledThisMonth { get; set; }
        public double WaiverCompletionPercent { get; set; }
    }

    [Fact]
    public async Task Kpi_cards_add_up_across_todays_departures()
    {
        var f = NewFixture(capacity: 120, departsAt: DateTime.UtcNow.Date.AddHours(6.5));
        AddBooking(f, adults: 2, children: 1, waiverSigned: true);

        var controller = new ExcursionReportsController(f.Db);
        TestHelpers.SetUser(controller, AdminId, TenantId, Roles.Admin);

        var payload = Value<KpiPayload>(await controller.GetKpis(null, 7));

        Assert.Equal(1, payload.DeparturesToday);
        Assert.Equal(3, payload.PaxBookedToday);
        Assert.Equal(120, payload.CapacityToday);
        Assert.Equal(2.5, payload.OccupancyTodayPercent);
        Assert.Equal(19000m, payload.RevenueToday);
        Assert.Equal(100, payload.WaiverCompletionPercent);
    }

    private sealed class RevenueByTicketPayload
    {
        public List<TicketTypeRow> ByTicketType { get; set; } = new();
        public decimal TotalRevenue { get; set; }
        public int TotalTickets { get; set; }
    }

    private sealed class TicketTypeRow
    {
        public string TicketType { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public decimal Revenue { get; set; }
    }

    [Fact]
    public async Task Revenue_report_splits_by_ticket_type()
    {
        var f = NewFixture(departsAt: DateTime.UtcNow.Date.AddHours(6.5));
        AddBooking(f, adults: 2, children: 1);
        AddBooking(f, adults: 1);

        var controller = new ExcursionReportsController(f.Db);
        TestHelpers.SetUser(controller, AdminId, TenantId, Roles.Admin);

        var payload = Value<RevenueByTicketPayload>(
            await controller.GetRevenueByTicketType(DateTime.UtcNow.Date, DateTime.UtcNow.Date));

        Assert.Equal(3, payload.ByTicketType.Single(r => r.TicketType == "Adult").Quantity);
        Assert.Equal(22500m, payload.ByTicketType.Single(r => r.TicketType == "Adult").Revenue);
        Assert.Equal(4000m, payload.ByTicketType.Single(r => r.TicketType == "Child").Revenue);
        Assert.Equal(26500m, payload.TotalRevenue);
        Assert.Equal(4, payload.TotalTickets);
    }

    private sealed class ChannelSplitPayload
    {
        public List<ChannelRow> ByChannel { get; set; } = new();
    }

    private sealed class ChannelRow
    {
        public string Channel { get; set; } = string.Empty;
        public int Bookings { get; set; }
        public int Pax { get; set; }
    }

    [Fact]
    public async Task Channel_split_reports_unknown_rather_than_guessing()
    {
        var f = NewFixture(departsAt: DateTime.UtcNow.Date.AddHours(6.5));
        AddBooking(f, adults: 2, source: "Online");
        AddBooking(f, adults: 1, source: "WalkIn");
        AddBooking(f, adults: 1); // pre-dates the Source column

        var controller = new ExcursionReportsController(f.Db);
        TestHelpers.SetUser(controller, AdminId, TenantId, Roles.Admin);

        var payload = Value<ChannelSplitPayload>(
            await controller.GetChannelSplit(DateTime.UtcNow.Date, DateTime.UtcNow.Date));

        Assert.Equal(2, payload.ByChannel.Single(c => c.Channel == "Online").Pax);
        Assert.Equal(1, payload.ByChannel.Single(c => c.Channel == "WalkIn").Bookings);
        Assert.Equal(1, payload.ByChannel.Single(c => c.Channel == "Unknown").Bookings);
    }

    private static CreateBookingDto NewBookingDto(Fixture f, int adults, int children = 0)
    {
        var lines = new List<TicketLine>();
        if (adults > 0) lines.Add(new TicketLine { Type = "Adult", Qty = adults });
        if (children > 0) lines.Add(new TicketLine { Type = "Child", Qty = children });

        return new CreateBookingDto(
            TenantId, f.Vessel.Id, f.Tour.Id, Guid.NewGuid(),
            f.Departure.ScheduledDeparture, f.Departure.ScheduledReturn,
            "Whale watching", null, null, BookingPriority.Normal, null, null,
            DepartureId: f.Departure.Id,
            TicketBreakdown: lines,
            Source: "Online");
    }
}

/// The push sender is a no-op in tests: FcmPushNotificationSender needs a
/// Firebase credential that does not exist in this project, and the
/// in-app Notification rows are what these tests actually assert on.
internal sealed class NoopPushSender : IPushNotificationSender
{
    public Task SendAsync(Guid tenantId, Guid userId, string title, string body) => Task.CompletedTask;
}

/// StubReminderChannelSender needs an ILogger; these tests never assert on
/// reminders, so a no-op keeps the fixture free of logging plumbing.
internal sealed class NoopReminderSender : IReminderChannelSender
{
    public Task SendAsync(Booking booking, string channel) => Task.CompletedTask;
}
