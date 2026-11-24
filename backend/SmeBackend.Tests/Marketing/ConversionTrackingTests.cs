using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Models.Marketing;
using SmeBackend.Services;
using SmeBackend.Services.Marketing;

namespace SmeBackend.Tests.Marketing;

public class ConversionTrackingTests
{
    private static readonly DateTime Now = DateTime.UtcNow;
    private readonly IPlatformSecretProtector _protector = MarketingTestKit.Protector();
    private readonly Mock<IMetaGraphClient> _meta = new();
    private readonly Mock<ITikTokClient> _tikTok = new();

    private sealed record World(AppDbContext Db, Guid TenantId, Booking Booking);

    private World Seed(bool meta = true, bool tikTok = true, BookingStatus status = BookingStatus.Pending)
    {
        var db = TestHelpers.NewInMemoryDb();
        var tenant = MarketingTestKit.Tenant(db);
        var guest = new User { TenantId = tenant.Id, Email = "Amaya@Example.com", FullName = "Amaya Perera", Phone = "0771234567", Role = UserRole.Customer, PasswordHash = "x" };
        db.Users.Add(guest);
        var booking = new Booking
        {
            TenantId = tenant.Id, ResourceId = Guid.NewGuid(), BookingTypeId = Guid.NewGuid(), BookedBy = guest.Id, BookedFor = guest.Id,
            StartTime = Now.AddDays(3), EndTime = Now.AddDays(3).AddHours(4), Status = status, Source = "Instagram", TotalCost = 22500m,
            CreatedAt = Now.AddHours(-1), UpdatedAt = Now.AddMinutes(-5),
        };
        db.Bookings.Add(booking);
        db.BookingAttributions.Add(new BookingAttribution
        {
            BookingId = booking.Id, TenantId = tenant.Id, Channel = "Instagram", UtmCampaign = "whales", Fbclid = "abc", Fbc = "fb.1.1.abc",
            ClientIp = "203.0.113.9", UserAgent = "Mozilla/5.0", LandingUrl = "https://app.example/embed/book/x?utm_source=instagram",
            Value = 22500m, Currency = "LKR", CreatedAt = Now.AddHours(-1),
        });
        db.MarketingSettings.Add(new MarketingSettings
        {
            TenantId = tenant.Id,
            MetaPixelId = meta ? "111" : null, MetaCapiTokenEncrypted = meta ? _protector.Protect("capi") : null,
            TikTokPixelCode = tikTok ? "CXYZ" : null, TikTokEventsTokenEncrypted = tikTok ? _protector.Protect("tt-events") : null,
        });
        db.SaveChanges();
        return new World(db, tenant.Id, booking);
    }

    private Task<(int Queued, int Sent)> Run(AppDbContext db, DateTime? at = null) =>
        ConversionWorker.RunOnceAsync(db, _meta.Object, _tikTok.Object, _protector, at ?? Now, NullLogger.Instance, default);

    [Fact]
    public async Task ANewAttributedBooking_IsSentToEveryConfiguredPlatform_Once()
    {
        var w = Seed();
        object? metaPayload = null;
        _meta.Setup(m => m.SendConversionAsync("111", "capi", null, It.IsAny<object>(), It.IsAny<CancellationToken>()))
            .Callback<string, string, string?, object, CancellationToken>((_, _, _, p, _) => metaPayload = p)
            .Returns(Task.CompletedTask);

        var first = await Run(w.Db);
        var second = await Run(w.Db);

        Assert.Equal(2, first.Queued);
        Assert.Equal(2, first.Sent);
        Assert.Equal((0, 0), second); // idempotent
        var events = await w.Db.ConversionEvents.IgnoreQueryFilters().ToListAsync();
        Assert.All(events, e => Assert.Equal(ConversionEventStatus.Sent, e.Status));
        Assert.Equal(new[] { "Facebook", "TikTok" }, events.Select(e => e.Platform).OrderBy(p => p));

        // PII leaves only as hashes; click data goes through for matching.
        var json = System.Text.Json.JsonSerializer.Serialize(metaPayload);
        Assert.DoesNotContain("amaya@example.com", json, StringComparison.OrdinalIgnoreCase);
        Assert.Contains(ConversionPayloads.Sha256("amaya@example.com"), json);
        Assert.Contains(ConversionPayloads.Sha256("94771234567"), json);
        Assert.Contains("\"fbc\":\"fb.1.1.abc\"", json);
        Assert.Contains("\"event_name\":\"Schedule\"", json);
        Assert.Contains("\"action_source\":\"website\"", json);
    }

    [Fact]
    public async Task ACompletedBooking_AlsoSendsAPurchase()
    {
        var w = Seed(tikTok: false, status: BookingStatus.Completed);
        await Run(w.Db);

        var names = await w.Db.ConversionEvents.IgnoreQueryFilters().Select(e => e.EventName).OrderBy(n => n).ToListAsync();
        Assert.Equal(new[] { ConversionEventName.BookingCompleted, ConversionEventName.BookingCreated }, names);
    }

    [Fact]
    public async Task NoPixelConfigured_QueuesNothing()
    {
        var w = Seed(meta: false, tikTok: false);
        Assert.Equal((0, 0), await Run(w.Db));
    }

    [Fact]
    public async Task TrackingSwitchedOff_QueuesNothing()
    {
        var w = Seed();
        (await w.Db.MarketingSettings.IgnoreQueryFilters().SingleAsync()).ConversionTrackingEnabled = false;
        await w.Db.SaveChangesAsync();
        Assert.Equal((0, 0), await Run(w.Db));
    }

    [Fact]
    public async Task TransientFailure_IsRetriedLater_PermanentFailure_IsRecorded()
    {
        var w = Seed();
        _meta.Setup(m => m.SendConversionAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string?>(), It.IsAny<object>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new SocialApiException("rate limited", transient: true));
        _tikTok.Setup(t => t.SendEventAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string?>(), It.IsAny<object>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new SocialApiException("Invalid pixel code"));

        await Run(w.Db);

        var events = await w.Db.ConversionEvents.IgnoreQueryFilters().ToDictionaryAsync(e => e.Platform);
        Assert.Equal(ConversionEventStatus.Pending, events["Facebook"].Status);
        Assert.NotNull(events["Facebook"].NextAttemptAt);
        Assert.Equal(ConversionEventStatus.Failed, events["TikTok"].Status);
        Assert.Equal("Invalid pixel code", events["TikTok"].LastError);
    }

    [Fact]
    public async Task EventsOlderThanSevenDays_AreSkipped_NotSent()
    {
        var w = Seed(tikTok: false);
        w.Db.ConversionEvents.Add(new ConversionEvent
        {
            TenantId = w.TenantId, BookingId = w.Booking.Id, Platform = "Facebook", EventName = ConversionEventName.BookingCompleted,
            EventTime = Now.AddDays(-8), Status = ConversionEventStatus.Pending,
        });
        await w.Db.SaveChangesAsync();
        _meta.Setup(m => m.SendConversionAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string?>(), It.IsAny<object>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        await Run(w.Db);

        var old = await w.Db.ConversionEvents.IgnoreQueryFilters().SingleAsync(e => e.EventName == ConversionEventName.BookingCompleted);
        Assert.Equal(ConversionEventStatus.Skipped, old.Status);
    }
}
