using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.AspNetCore.Http;
using SmeBackend.Controllers;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Services;
using SmeBackend.Shared;

namespace SmeBackend.Tests;

/// Live notification delivery: who receives what, and that a row reaching the
/// database is what triggers delivery - not a call someone has to remember.
public class NotificationStreamTests
{
    private static readonly Guid TenantA = Guid.NewGuid();
    private static readonly Guid TenantB = Guid.NewGuid();
    private static readonly Guid Alice = Guid.NewGuid();
    private static readonly Guid Bob = Guid.NewGuid();

    private static NotificationStream NewStream() => new(NullLogger<NotificationStream>.Instance);

    private static NotificationEvent Event(Guid tenantId, Guid? userId, string title = "Something happened") =>
        new(Guid.NewGuid(), tenantId, userId, "Test", title, "body", DateTime.UtcNow);

    private static async Task<List<NotificationEvent>> DrainAsync(INotificationSubscription sub, int expected)
    {
        var received = new List<NotificationEvent>();
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        try
        {
            await foreach (var e in sub.ReadAllAsync(cts.Token))
            {
                received.Add(e);
                if (received.Count >= expected) break;
            }
        }
        catch (OperationCanceledException) { /* fewer than expected arrived */ }
        return received;
    }

    // ── who receives what ───────────────────────────────────────────────
    [Fact]
    public async Task A_notification_addressed_to_me_reaches_me()
    {
        var stream = NewStream();
        using var alice = stream.Subscribe(new StreamAudience(TenantA, Alice, IsStaff: false));

        stream.Publish(Event(TenantA, Alice, "Your booking is confirmed"));

        var received = await DrainAsync(alice, 1);
        Assert.Equal("Your booking is confirmed", Assert.Single(received).Title);
    }

    [Fact]
    public async Task A_notification_for_someone_else_does_not_reach_me()
    {
        var stream = NewStream();
        using var alice = stream.Subscribe(new StreamAudience(TenantA, Alice, IsStaff: false));

        stream.Publish(Event(TenantA, Bob));

        Assert.Empty(await DrainAsync(alice, 1));
    }

    [Fact]
    public async Task A_notification_never_crosses_a_tenant_boundary()
    {
        // The same person id in another tenant must not be a way through.
        var stream = NewStream();
        using var alice = stream.Subscribe(new StreamAudience(TenantA, Alice, IsStaff: true));

        stream.Publish(Event(TenantB, Alice));
        stream.Publish(Event(TenantB, null));

        Assert.Empty(await DrainAsync(alice, 1));
    }

    [Fact]
    public async Task A_tenant_wide_notification_reaches_staff_but_not_customers()
    {
        var stream = NewStream();
        using var manager = stream.Subscribe(new StreamAudience(TenantA, Alice, IsStaff: true));
        using var customer = stream.Subscribe(new StreamAudience(TenantA, Bob, IsStaff: false));

        stream.Publish(Event(TenantA, null, "A plan needs approval"));

        Assert.Single(await DrainAsync(manager, 1));
        Assert.Empty(await DrainAsync(customer, 1));
    }

    [Fact]
    public void Streaming_rules_match_what_the_list_endpoint_would_return()
    {
        // If these ever disagree, someone is pushed a notification they cannot
        // then open - which is a leak, not a cosmetic bug.
        var staff = new StreamAudience(TenantA, Alice, IsStaff: true);
        var customer = new StreamAudience(TenantA, Bob, IsStaff: false);

        Assert.True(staff.Receives(Event(TenantA, Alice)));
        Assert.True(staff.Receives(Event(TenantA, null)));
        Assert.False(staff.Receives(Event(TenantA, Bob)));
        Assert.False(staff.Receives(Event(TenantB, Alice)));

        Assert.True(customer.Receives(Event(TenantA, Bob)));
        Assert.False(customer.Receives(Event(TenantA, null)));
    }

    [Fact]
    public async Task A_closed_connection_stops_receiving_and_is_forgotten()
    {
        var stream = NewStream();
        var alice = stream.Subscribe(new StreamAudience(TenantA, Alice, IsStaff: false));
        Assert.Equal(1, stream.ConnectionCount);

        alice.Dispose();
        Assert.Equal(0, stream.ConnectionCount);

        // Publishing after everyone has gone must not throw.
        stream.Publish(Event(TenantA, Alice));
        await Task.CompletedTask;
    }

    [Fact]
    public async Task A_client_that_stops_reading_costs_a_bounded_amount_of_memory()
    {
        // 64-deep buffer, DropOldest: a dead reader loses events rather than
        // growing the process until it falls over.
        var stream = NewStream();
        using var alice = stream.Subscribe(new StreamAudience(TenantA, Alice, IsStaff: false));

        for (var i = 0; i < 500; i++) stream.Publish(Event(TenantA, Alice, $"n{i}"));

        var received = await DrainAsync(alice, 64);
        Assert.Equal(64, received.Count);
        Assert.Equal("n499", received[^1].Title);   // the newest survived
    }

    // ── the interceptor: saving a row is what delivers it ───────────────
    private sealed class RecordingStream : INotificationStream
    {
        public List<NotificationEvent> Published { get; } = new();
        public int ConnectionCount => 0;
        public INotificationSubscription Subscribe(StreamAudience audience) => throw new NotSupportedException();
        public void Publish(NotificationEvent notification) => Published.Add(notification);
    }

    private static AppDbContext NewDbWith(RecordingStream stream)
    {
        var interceptor = new NotificationPublishInterceptor(
            stream, NullLogger<NotificationPublishInterceptor>.Instance);
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .AddInterceptors(interceptor)
            .Options;
        return new AppDbContext(options, new TenantContext());
    }

    [Fact]
    public async Task Queueing_a_notification_publishes_it_when_the_save_commits()
    {
        var stream = new RecordingStream();
        await using var db = NewDbWith(stream);

        NotificationHelper.Queue(db, TenantA, Alice, "BookingConfirmed", "Confirmed", "See you Saturday.");
        Assert.Empty(stream.Published);          // queued only; nothing announced yet

        await db.SaveChangesAsync();

        var published = Assert.Single(stream.Published);
        Assert.Equal(TenantA, published.TenantId);
        Assert.Equal(Alice, published.UserId);
        Assert.Equal("Confirmed", published.Title);
    }

    [Fact]
    public async Task Saving_something_that_is_not_a_notification_publishes_nothing()
    {
        var stream = new RecordingStream();
        await using var db = NewDbWith(stream);

        db.Resources.Add(new Resource { TenantId = TenantA, Name = "Boat", Category = ResourceCategory.Vehicle });
        await db.SaveChangesAsync();

        Assert.Empty(stream.Published);
    }

    [Fact]
    public async Task Every_notification_in_one_save_is_published()
    {
        var stream = new RecordingStream();
        await using var db = NewDbWith(stream);

        NotificationHelper.Queue(db, TenantA, Alice, "T", "One", "a");
        NotificationHelper.Queue(db, TenantA, Bob, "T", "Two", "b");
        NotificationHelper.Queue(db, TenantA, null, "T", "Three", "c");
        await db.SaveChangesAsync();

        Assert.Equal(3, stream.Published.Count);
        Assert.Equal(new[] { "One", "Two", "Three" }, stream.Published.Select(p => p.Title));
    }

    [Fact]
    public async Task A_second_save_does_not_republish_the_first_notification()
    {
        var stream = new RecordingStream();
        await using var db = NewDbWith(stream);

        NotificationHelper.Queue(db, TenantA, Alice, "T", "First", "a");
        await db.SaveChangesAsync();
        await db.SaveChangesAsync();                     // nothing new added

        Assert.Single(stream.Published);
    }

    [Fact]
    public async Task The_published_event_carries_the_id_the_row_was_given()
    {
        // The client uses the id to mark the notification read, so a made-up
        // one would make the live copy unactionable.
        var stream = new RecordingStream();
        await using var db = NewDbWith(stream);

        NotificationHelper.Queue(db, TenantA, Alice, "T", "Has an id", "a");
        await db.SaveChangesAsync();

        var saved = await db.Notifications.SingleAsync();
        Assert.Equal(saved.Id, Assert.Single(stream.Published).Id);
        Assert.NotEqual(Guid.Empty, saved.Id);
    }
    // ── the wire format the browser and the phone actually parse ────────
    [Fact]
    public async Task The_endpoint_writes_a_ready_frame_then_one_frame_per_notification()
    {
        var stream = NewStream();
        await using var db = NewDbWith(new RecordingStream());
        var controller = new NotificationsController(db, stream);
        TestHelpers.SetUser(controller, Alice, TenantA, Roles.Manager);

        // Capture what is written to the response.
        var body = new MemoryStream();
        controller.ControllerContext.HttpContext.Response.Body = body;

        using var cts = new CancellationTokenSource();
        var streaming = controller.Stream(cts.Token);

        // Wait for the connection to register, then publish through it.
        for (var i = 0; i < 100 && stream.ConnectionCount == 0; i++) await Task.Delay(10);
        Assert.Equal(1, stream.ConnectionCount);

        stream.Publish(new NotificationEvent(
            Guid.NewGuid(), TenantA, Alice, "BookingConfirmed",
            "Your booking is confirmed", "Saturday 06:30", DateTime.UtcNow));

        // Give the writer a moment, then close the connection as a browser would.
        await Task.Delay(200);
        cts.Cancel();
        await streaming;

        var text = System.Text.Encoding.UTF8.GetString(body.ToArray());

        // SSE framing: "event: <name>", "data: <json>", blank line.
        Assert.Contains("event: ready", text);
        Assert.Contains("event: notification", text);
        Assert.Contains("\"title\":\"Your booking is confirmed\"", text);
        Assert.Contains("\n\n", text);
        // camelCase, because both clients read it that way.
        Assert.Contains("\"createdAt\"", text);
        Assert.DoesNotContain("\"Title\"", text);
    }

    [Fact]
    public async Task The_endpoint_refuses_a_caller_with_no_tenant()
    {
        var stream = NewStream();
        await using var db = NewDbWith(new RecordingStream());
        var controller = new NotificationsController(db, stream);
        // Authenticated, but the tenant claim is unusable.
        TestHelpers.SetUser(controller, Alice, Guid.Empty, Roles.Manager);
        controller.ControllerContext.HttpContext.User = new System.Security.Claims.ClaimsPrincipal(
            new System.Security.Claims.ClaimsIdentity(
                new[] { new System.Security.Claims.Claim("tenantId", "not-a-guid") }, "TestAuth"));
        controller.ControllerContext.HttpContext.Response.Body = new MemoryStream();

        await controller.Stream(CancellationToken.None);

        Assert.Equal(StatusCodes.Status401Unauthorized, controller.Response.StatusCode);
        Assert.Equal(0, stream.ConnectionCount);
    }

    [Fact]
    public async Task A_disconnecting_client_releases_its_connection()
    {
        var stream = NewStream();
        await using var db = NewDbWith(new RecordingStream());
        var controller = new NotificationsController(db, stream);
        TestHelpers.SetUser(controller, Alice, TenantA, Roles.Manager);
        controller.ControllerContext.HttpContext.Response.Body = new MemoryStream();

        using var cts = new CancellationTokenSource();
        var streaming = controller.Stream(cts.Token);
        for (var i = 0; i < 100 && stream.ConnectionCount == 0; i++) await Task.Delay(10);
        Assert.Equal(1, stream.ConnectionCount);

        cts.Cancel();
        await streaming;

        // Otherwise every reconnect would leak a subscription for the life
        // of the process.
        Assert.Equal(0, stream.ConnectionCount);
    }
}
