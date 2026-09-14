using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Shared;

namespace SmeBackend.Tests;

/// Tenant scoping and success-rate arithmetic for the sightings endpoints.
///
/// Tenant scoping is the one that matters most: SightingsLog carries a plain
/// TenantId rather than going through AppDbContext's ITenantScoped filter, so
/// every query has to scope itself and a regression here leaks one operator's
/// data to another.
public class SightingsControllerTests
{
    private sealed record Fixture(AppDbContext Db, Guid TenantId, Resource Vessel);

    private static Fixture NewFixture(AppDbContext? shared = null, Guid? tenantId = null)
    {
        var db = shared ?? TestHelpers.NewInMemoryDb();
        var tid = tenantId ?? Guid.NewGuid();

        var vessel = new Resource
        {
            TenantId = tid,
            Name = $"Vessel {tid.ToString()[..4]}",
            Category = ResourceCategory.Vehicle,
            CustomAttributes = """{ "capacity": 120 }""",
        };
        db.Resources.Add(vessel);
        db.SaveChanges();

        return new Fixture(db, tid, vessel);
    }

    private static SightingsController NewController(AppDbContext db, Guid tenantId, string role = Roles.Staff)
    {
        var controller = new SightingsController(db);
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenantId, role);
        return controller;
    }

    /// A departure in the past, already marked Returned so it counts in the
    /// success-rate denominator.
    private static Departure AddReturnedDeparture(Fixture f, int daysAgo, DepartureStatus status = DepartureStatus.Returned)
    {
        var when = DateTime.UtcNow.Date.AddDays(-daysAgo).AddHours(6.5);
        var departure = new Departure
        {
            TenantId = f.TenantId,
            ResourceId = f.Vessel.Id,
            ScheduledDeparture = when,
            ScheduledReturn = when.AddHours(4),
            Status = status,
        };
        f.Db.Departures.Add(departure);
        f.Db.SaveChanges();
        return departure;
    }

    private static T Value<T>(IActionResult result) where T : class
    {
        var payload = result switch
        {
            OkObjectResult ok => ok.Value,
            CreatedAtActionResult created => created.Value,
            BadRequestObjectResult bad => bad.Value,
            _ => null,
        };
        Assert.NotNull(payload);
        var json = JsonSerializer.Serialize(payload);
        return JsonSerializer.Deserialize<T>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
    }

    private sealed class SuccessRatePayload
    {
        public int DeparturesCompleted { get; set; }
        public int DeparturesWithSighting { get; set; }
        public double SuccessRate { get; set; }
        public string? SpeciesFilter { get; set; }
    }

    private sealed class ListPayload
    {
        public List<SightingRow> Items { get; set; } = new();
        public int Total { get; set; }
    }

    private sealed class SightingRow
    {
        public Guid Id { get; set; }
        public string Species { get; set; } = string.Empty;
        public int? Count { get; set; }
    }

    // ── Auth ───────────────────────────────────────────────────────────
    [Fact]
    public async Task Rejects_a_caller_with_no_tenant_claim()
    {
        var f = NewFixture();
        var controller = new SightingsController(f.Db);
        // Authenticated, but with a malformed tenantId claim.
        TestHelpers.SetUser(controller, Guid.NewGuid(), Guid.Empty, Roles.Staff);
        controller.ControllerContext.HttpContext.User = new System.Security.Claims.ClaimsPrincipal(
            new System.Security.Claims.ClaimsIdentity(
                new[] { new System.Security.Claims.Claim("tenantId", "not-a-guid") }, "TestAuth"));

        Assert.IsType<UnauthorizedResult>(await controller.GetSuccessRate(null, null, null));
        Assert.IsType<UnauthorizedResult>(await controller.GetAll(null, null, null, null, null));
    }

    // ── Tenant scoping ─────────────────────────────────────────────────
    [Fact]
    public async Task One_tenant_never_sees_another_tenants_sightings()
    {
        var db = TestHelpers.NewInMemoryDb();
        var alice = NewFixture(db);
        var bob = NewFixture(db);

        var aliceDeparture = AddReturnedDeparture(alice, 2);
        var bobDeparture = AddReturnedDeparture(bob, 2);

        await NewController(db, alice.TenantId).Create(new CreateSightingDto(
            aliceDeparture.Id, Guid.Empty, null, default, SightingSpecies.BlueWhale, 2, null, null, null, null, null));
        await NewController(db, bob.TenantId).Create(new CreateSightingDto(
            bobDeparture.Id, Guid.Empty, null, default, SightingSpecies.Leopard, 1, null, null, null, null, null));

        var aliceList = Value<ListPayload>(await NewController(db, alice.TenantId).GetAll(null, null, null, null, null));
        var bobList = Value<ListPayload>(await NewController(db, bob.TenantId).GetAll(null, null, null, null, null));

        Assert.Equal(1, aliceList.Total);
        Assert.Equal("BlueWhale", aliceList.Items.Single().Species);
        Assert.Equal(1, bobList.Total);
        Assert.Equal("Leopard", bobList.Items.Single().Species);
    }

    [Fact]
    public async Task Cannot_log_a_sighting_against_another_tenants_departure()
    {
        var db = TestHelpers.NewInMemoryDb();
        var alice = NewFixture(db);
        var bob = NewFixture(db);
        var bobDeparture = AddReturnedDeparture(bob, 1);

        var result = await NewController(db, alice.TenantId).Create(new CreateSightingDto(
            bobDeparture.Id, Guid.Empty, null, default, SightingSpecies.BlueWhale, 1, null, null, null, null, null));

        Assert.IsType<NotFoundObjectResult>(result);
        Assert.Empty(db.SightingsLogs.Where(s => s.TenantId == alice.TenantId));
    }

    [Fact]
    public async Task Success_rate_is_scoped_to_the_calling_tenant()
    {
        var db = TestHelpers.NewInMemoryDb();
        var alice = NewFixture(db);
        var bob = NewFixture(db);

        // Alice: 2 departures, 1 with a sighting -> 50%.
        var a1 = AddReturnedDeparture(alice, 3);
        AddReturnedDeparture(alice, 4);
        await NewController(db, alice.TenantId).Create(new CreateSightingDto(
            a1.Id, Guid.Empty, null, default, SightingSpecies.BlueWhale, 1, null, null, null, null, null));

        // Bob: 1 departure, 1 sighting -> 100%. Must not move Alice's number.
        var b1 = AddReturnedDeparture(bob, 3);
        await NewController(db, bob.TenantId).Create(new CreateSightingDto(
            b1.Id, Guid.Empty, null, default, SightingSpecies.SpermWhale, 1, null, null, null, null, null));

        var aliceRate = Value<SuccessRatePayload>(
            await NewController(db, alice.TenantId).GetSuccessRate(null, null, null));
        var bobRate = Value<SuccessRatePayload>(
            await NewController(db, bob.TenantId).GetSuccessRate(null, null, null));

        Assert.Equal(2, aliceRate.DeparturesCompleted);
        Assert.Equal(50, aliceRate.SuccessRate);
        Assert.Equal(1, bobRate.DeparturesCompleted);
        Assert.Equal(100, bobRate.SuccessRate);
    }

    // ── Success-rate maths ─────────────────────────────────────────────
    [Fact]
    public async Task Counts_a_departure_once_however_many_sightings_it_had()
    {
        var f = NewFixture();
        var departure = AddReturnedDeparture(f, 2);
        AddReturnedDeparture(f, 3);

        var controller = NewController(f.Db, f.TenantId);
        foreach (var species in new[] { SightingSpecies.BlueWhale, SightingSpecies.SpinnerDolphin, SightingSpecies.Turtle })
        {
            await controller.Create(new CreateSightingDto(
                departure.Id, Guid.Empty, null, default, species, 3, null, null, null, null, null));
        }

        var payload = Value<SuccessRatePayload>(await controller.GetSuccessRate(null, null, null));

        // 3 sightings, but only 1 of 2 departures saw anything.
        Assert.Equal(2, payload.DeparturesCompleted);
        Assert.Equal(1, payload.DeparturesWithSighting);
        Assert.Equal(50, payload.SuccessRate);
    }

    [Fact]
    public async Task Cancelled_departures_are_out_of_the_denominator()
    {
        var f = NewFixture();
        var sailed = AddReturnedDeparture(f, 2);
        AddReturnedDeparture(f, 3, DepartureStatus.CancelledWeather);
        AddReturnedDeparture(f, 4, DepartureStatus.CancelledOther);

        var controller = NewController(f.Db, f.TenantId);
        await controller.Create(new CreateSightingDto(
            sailed.Id, Guid.Empty, null, default, SightingSpecies.BlueWhale, 1, null, null, null, null, null));

        var payload = Value<SuccessRatePayload>(await controller.GetSuccessRate(null, null, null));

        // Rough seas are not a failure to find whales.
        Assert.Equal(1, payload.DeparturesCompleted);
        Assert.Equal(100, payload.SuccessRate);
    }

    [Fact]
    public async Task Reports_zero_rather_than_dividing_by_zero_with_no_departures()
    {
        var f = NewFixture();
        var payload = Value<SuccessRatePayload>(
            await NewController(f.Db, f.TenantId).GetSuccessRate(null, null, null));

        Assert.Equal(0, payload.DeparturesCompleted);
        Assert.Equal(0, payload.SuccessRate);
    }

    [Fact]
    public async Task Can_be_filtered_to_one_species()
    {
        var f = NewFixture();
        var a = AddReturnedDeparture(f, 2);
        var b = AddReturnedDeparture(f, 3);

        var controller = NewController(f.Db, f.TenantId);
        await controller.Create(new CreateSightingDto(
            a.Id, Guid.Empty, null, default, SightingSpecies.BlueWhale, 1, null, null, null, null, null));
        await controller.Create(new CreateSightingDto(
            b.Id, Guid.Empty, null, default, SightingSpecies.SpinnerDolphin, 20, null, null, null, null, null));

        var all = Value<SuccessRatePayload>(await controller.GetSuccessRate(null, null, null));
        var blue = Value<SuccessRatePayload>(
            await controller.GetSuccessRate(null, null, SightingSpecies.BlueWhale));

        Assert.Equal(100, all.SuccessRate);
        Assert.Equal(50, blue.SuccessRate);
        Assert.Equal("BlueWhale", blue.SpeciesFilter);
    }

    [Fact]
    public async Task Honours_the_date_range()
    {
        var f = NewFixture();
        var recent = AddReturnedDeparture(f, 2);
        var old = AddReturnedDeparture(f, 90);

        var controller = NewController(f.Db, f.TenantId);
        await controller.Create(new CreateSightingDto(
            recent.Id, Guid.Empty, null, default, SightingSpecies.BlueWhale, 1, null, null, null, null, null));
        await controller.Create(new CreateSightingDto(
            old.Id, Guid.Empty, null, default, SightingSpecies.BlueWhale, 1, null, null, null, null, null));

        var lastWeek = Value<SuccessRatePayload>(await controller.GetSuccessRate(
            DateTime.UtcNow.Date.AddDays(-7), DateTime.UtcNow.Date, null));

        Assert.Equal(1, lastWeek.DeparturesCompleted);
        Assert.Equal(100, lastWeek.SuccessRate);
    }

    [Fact]
    public async Task Rejects_an_inverted_date_range()
    {
        var f = NewFixture();
        var result = await NewController(f.Db, f.TenantId).GetSuccessRate(
            DateTime.UtcNow.Date, DateTime.UtcNow.Date.AddDays(-7), null);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    // ── Logging ────────────────────────────────────────────────────────
    [Fact]
    public async Task A_new_sighting_shows_up_immediately_in_the_list_and_the_rate()
    {
        var f = NewFixture();
        var departure = AddReturnedDeparture(f, 1);
        var controller = NewController(f.Db, f.TenantId);

        var before = Value<SuccessRatePayload>(await controller.GetSuccessRate(null, null, null));
        Assert.Equal(0, before.SuccessRate);

        await controller.Create(new CreateSightingDto(
            departure.Id, Guid.Empty, null, default,
            SightingSpecies.BlueWhale, 2, 5.94, 80.45, SightingBehaviour.Breaching, "Two adults", null));

        var list = Value<ListPayload>(await controller.GetAll(null, null, null, null, null));
        var after = Value<SuccessRatePayload>(await controller.GetSuccessRate(null, null, null));

        Assert.Equal(1, list.Total);
        Assert.Equal(100, after.SuccessRate);
    }

    [Fact]
    public async Task A_sighting_takes_its_vessel_and_time_from_the_departure()
    {
        var f = NewFixture();
        var departure = AddReturnedDeparture(f, 1);

        await NewController(f.Db, f.TenantId).Create(new CreateSightingDto(
            departure.Id, Guid.Empty, null, default, SightingSpecies.BlueWhale, 1, null, null, null, null, null));

        // The client sent no ResourceId and no time; both come from the
        // departure so the two can never disagree.
        var saved = f.Db.SightingsLogs.Single();
        Assert.Equal(f.Vessel.Id, saved.ResourceId);
        Assert.Equal(departure.ScheduledDeparture, saved.DepartureDateTime);
    }

    [Fact]
    public async Task Rejects_a_non_positive_count_but_allows_an_unknown_one()
    {
        var f = NewFixture();
        var departure = AddReturnedDeparture(f, 1);
        var controller = NewController(f.Db, f.TenantId);

        Assert.IsType<BadRequestObjectResult>(await controller.Create(new CreateSightingDto(
            departure.Id, Guid.Empty, null, default, SightingSpecies.BlueWhale, 0, null, null, null, null, null)));

        // Null is not zero: an unseen pod size is unknown, not empty.
        Assert.IsType<CreatedAtActionResult>(await controller.Create(new CreateSightingDto(
            departure.Id, Guid.Empty, null, default, SightingSpecies.BlueWhale, null, null, null, null, null, null)));
        Assert.Null(f.Db.SightingsLogs.Single().Count);
    }

    [Fact]
    public async Task A_deleted_sighting_leaves_the_success_rate()
    {
        var f = NewFixture();
        var departure = AddReturnedDeparture(f, 1);
        var controller = NewController(f.Db, f.TenantId);

        await controller.Create(new CreateSightingDto(
            departure.Id, Guid.Empty, null, default, SightingSpecies.BlueWhale, 1, null, null, null, null, null));
        var logged = f.Db.SightingsLogs.Single();

        var admin = NewController(f.Db, f.TenantId, Roles.Admin);
        Assert.IsType<NoContentResult>(await admin.Delete(logged.Id));

        var after = Value<SuccessRatePayload>(await controller.GetSuccessRate(null, null, null));
        Assert.Equal(0, after.SuccessRate);
    }
}
