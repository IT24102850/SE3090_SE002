using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Tests;

/// Pricing and capacity are pure functions over the jsonb config columns, so
/// they are tested directly rather than through a controller - the rules are
/// the part that has to be right, and they are shared by the create,
/// re-ticket, quote and reschedule paths.
public class TicketPricingTests
{
    private static BookingType WhaleTour(string? configJson) => new()
    {
        Name = "Whale Watching Tour",
        DefaultDurationMinutes = 240,
        MaxParticipants = 120,
        ConfigJson = configJson,
    };

    private const string BaseConfig = """
    {
      "subType": "whaleWatching",
      "bookingUnit": "Slot",
      "pricing": { "adult": 7500, "child": 4000, "infant": 0, "currency": "LKR" },
      "capacity": 120,
      "season": { "months": ["Nov","Dec","Jan","Feb","Mar","Apr"], "weatherDependent": true }
    }
    """;

    private const string SeasonalConfig = """
    {
      "pricing": { "adult": 7500, "child": 4000, "currency": "LKR" },
      "seasonalPricing": [
        { "label": "Peak", "months": ["Dec","Jan","Feb","Mar"], "offPeak": false,
          "pricing": { "adult": 9000, "child": 5000 } },
        { "label": "Off-peak", "months": ["May","Jun","Jul","Aug","Sep"], "offPeak": true,
          "pricing": { "adult": 6000, "child": 3000 } }
      ]
    }
    """;

    [Fact]
    public void Prices_two_adults_and_one_child_in_one_booking()
    {
        var lines = new List<TicketLine>
        {
            new() { Type = "Adult", Qty = 2 },
            new() { Type = "Child", Qty = 1 },
        };

        var priced = TicketPricing.Price(lines, WhaleTour(BaseConfig), new DateTime(2026, 1, 15));

        Assert.Equal(3, priced.TotalQuantity);
        Assert.Equal(19000m, priced.Total); // 2 x 7500 + 1 x 4000
        Assert.Equal("LKR", priced.Currency);
        Assert.Equal(7500m, priced.Lines.Single(l => l.Type == "Adult").UnitPrice);
        Assert.Equal(15000m, priced.Lines.Single(l => l.Type == "Adult").LineTotal);
        Assert.Equal(4000m, priced.Lines.Single(l => l.Type == "Child").LineTotal);
    }

    [Fact]
    public void Infant_priced_at_zero_still_occupies_a_seat()
    {
        var lines = new List<TicketLine>
        {
            new() { Type = "Adult", Qty = 2 },
            new() { Type = "Infant", Qty = 1 },
        };

        var priced = TicketPricing.Price(lines, WhaleTour(BaseConfig), new DateTime(2026, 1, 15));

        Assert.Equal(15000m, priced.Total);
        Assert.Equal(3, priced.TotalQuantity);
        Assert.Equal(3, TicketPricing.SeatsUsed(TicketPricing.Serialize(priced.Lines), null));
    }

    [Fact]
    public void Seasonal_window_overrides_base_pricing_and_flags_off_peak()
    {
        var lines = new List<TicketLine> { new() { Type = "Adult", Qty = 1 } };
        var bookingType = WhaleTour(SeasonalConfig);

        var peak = TicketPricing.Price(lines, bookingType, new DateTime(2026, 1, 10));
        var offPeak = TicketPricing.Price(lines, bookingType, new DateTime(2026, 6, 10));
        var unlisted = TicketPricing.Price(lines, bookingType, new DateTime(2026, 11, 10));

        Assert.Equal(9000m, peak.Total);
        Assert.Equal("Peak", peak.SeasonLabel);
        Assert.False(peak.IsOffPeak);

        Assert.Equal(6000m, offPeak.Total);
        Assert.True(offPeak.IsOffPeak);

        // A month named by no window falls through to base pricing rather
        // than to whichever window happens to be listed first.
        Assert.Equal(7500m, unlisted.Total);
        Assert.Null(unlisted.SeasonLabel);
    }

    [Fact]
    public void Explicit_unit_price_survives_repricing()
    {
        var discounted = new List<TicketLine> { new() { Type = "Adult", Qty = 2, UnitPrice = 5000m } };

        var priced = TicketPricing.Price(discounted, WhaleTour(BaseConfig), new DateTime(2026, 1, 15));

        Assert.Equal(10000m, priced.Total);
    }

    [Fact]
    public void Bookings_without_a_breakdown_keep_their_original_behaviour()
    {
        // The backward-compatibility guarantee: no breakdown means one seat,
        // or the attendee count if the booking carried one.
        Assert.Equal(1, TicketPricing.SeatsUsed(null, null));
        Assert.Equal(1, TicketPricing.SeatsUsed("", null));
        Assert.Equal(4, TicketPricing.SeatsUsed(null, 4));

        // Malformed jsonb must degrade the same way, not throw: these
        // columns are operator-authored.
        Assert.Equal(1, TicketPricing.SeatsUsed("{not json", null));
        Assert.Empty(TicketPricing.Parse("{not json"));
    }

    [Fact]
    public void Round_trips_through_the_jsonb_column()
    {
        var priced = TicketPricing.Price(
            new List<TicketLine> { new() { Type = "Adult", Qty = 2 }, new() { Type = "Child", Qty = 1 } },
            WhaleTour(BaseConfig),
            new DateTime(2026, 1, 15));

        var reparsed = TicketPricing.Parse(TicketPricing.Serialize(priced.Lines));

        Assert.Equal(2, reparsed.Count);
        Assert.Equal(19000m, reparsed.Sum(l => l.LineTotal ?? 0m));
        Assert.Equal(3, reparsed.Sum(l => l.Qty));
    }

    [Fact]
    public void Season_membership_is_null_when_no_season_is_declared()
    {
        var declared = JsonAttributes.Root(BaseConfig);
        var undeclared = JsonAttributes.Root("""{ "pricing": { "adult": 100 } }""");

        Assert.True(TicketPricing.IsInSeason(declared, new DateTime(2026, 1, 15)));
        Assert.False(TicketPricing.IsInSeason(declared, new DateTime(2026, 7, 15)));
        // Not the same as "out of season" - the operator never said.
        Assert.Null(TicketPricing.IsInSeason(undeclared, new DateTime(2026, 7, 15)));
    }

    [Fact]
    public void Zero_and_negative_quantity_lines_are_dropped()
    {
        var lines = new List<TicketLine>
        {
            new() { Type = "Adult", Qty = 2 },
            new() { Type = "Child", Qty = 0 },
            new() { Type = "Infant", Qty = -1 },
        };

        var priced = TicketPricing.Price(lines, WhaleTour(BaseConfig), new DateTime(2026, 1, 15));

        Assert.Single(priced.Lines);
        Assert.Equal(2, priced.TotalQuantity);
    }
}

public class CapacityRulesTests
{
    private static Resource Vessel(string? customAttributes, int? capacity = null) => new()
    {
        Name = "Sea Guardian",
        Category = ResourceCategory.Vehicle,
        Capacity = capacity,
        CustomAttributes = customAttributes,
    };

    [Fact]
    public void Capacity_comes_from_custom_attributes_first()
    {
        var vessel = Vessel("""{ "capacity": 120 }""", capacity: 40);

        // CustomAttributes.capacity is the key the tourism template and the
        // Flutter app already use; Resource.Capacity is the generic fallback.
        Assert.Equal(120, CapacityRules.Resolve(vessel, null));
    }

    [Fact]
    public void Falls_back_through_resource_capacity_then_max_participants()
    {
        Assert.Equal(40, CapacityRules.Resolve(Vessel(null, capacity: 40), null));
        Assert.Equal(12, CapacityRules.Resolve(Vessel(null), new BookingType { MaxParticipants = 12 }));
        Assert.Null(CapacityRules.Resolve(Vessel(null), new BookingType()));
    }

    [Fact]
    public void Departure_override_wins_over_the_vessel()
    {
        var vessel = Vessel("""{ "capacity": 120 }""");
        var departure = new Departure { LicensedCapacity = 80 };

        Assert.Equal(80, CapacityRules.Resolve(vessel, null, departure));
    }

    [Fact]
    public void Resources_with_no_declared_capacity_stay_exclusive()
    {
        // This is the guarantee that every pre-existing resource - a
        // consulting room, a hire car - keeps single-occupancy conflict
        // detection rather than silently becoming shareable.
        Assert.False(CapacityRules.IsShared(Vessel(null), new BookingType()));
        Assert.False(CapacityRules.IsShared(Vessel(null, capacity: 1), new BookingType()));
        Assert.True(CapacityRules.IsShared(Vessel("""{ "capacity": 120 }"""), null));
    }

    [Fact]
    public void Rejects_a_booking_that_would_exceed_licensed_capacity()
    {
        var check = CapacityRules.Check(capacity: 120, seatsTaken: 118, seatsRequested: 3);

        Assert.False(check.Allowed);
        Assert.NotNull(check.Error);
        Assert.Contains("120", check.Error);
        Assert.Equal(2, check.SeatsRemaining);
    }

    [Fact]
    public void Allows_a_booking_that_exactly_fills_the_boat()
    {
        var check = CapacityRules.Check(capacity: 120, seatsTaken: 117, seatsRequested: 3);

        Assert.True(check.Allowed);
        // Full is still a warning, because the crew should know.
        Assert.NotNull(check.Warning);
    }

    [Fact]
    public void Warns_from_ninety_percent_full_without_blocking()
    {
        var under = CapacityRules.Check(capacity: 100, seatsTaken: 80, seatsRequested: 5);
        var at = CapacityRules.Check(capacity: 100, seatsTaken: 85, seatsRequested: 5);

        Assert.True(under.Allowed);
        Assert.Null(under.Warning);

        Assert.True(at.Allowed);
        Assert.NotNull(at.Warning);
        Assert.Contains("90", at.Warning);
    }

    [Fact]
    public void Unknown_capacity_never_blocks()
    {
        var check = CapacityRules.Check(capacity: 0, seatsTaken: 99, seatsRequested: 99);

        Assert.True(check.Allowed);
        Assert.Null(check.Error);
    }
}
