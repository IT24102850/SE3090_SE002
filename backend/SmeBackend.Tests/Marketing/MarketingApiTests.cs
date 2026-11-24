using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Moq;
using SmeBackend.Controllers;
using SmeBackend.Controllers.Marketing;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Models.Marketing;
using SmeBackend.Services;
using SmeBackend.Services.Marketing;
using SmeBackend.Shared;

namespace SmeBackend.Tests.Marketing;

public class MarketingApiTests
{
    private readonly IPlatformSecretProtector _protector = MarketingTestKit.Protector();

    // ── Public booking attribution ─────────────────────────────────────────

    private static async Task<(AppDbContext Db, Guid TenantId, Guid DepartureId)> SeedTourAsync()
    {
        var db = TestHelpers.NewInMemoryDb(tenantId: null);
        var tenantId = Guid.NewGuid();
        db.Tenants.Add(new Tenant { Id = tenantId, Name = "Mirissa Jetliner", BusinessType = "Tourism", SubType = "Whale / dolphin watching" });
        var resource = new Resource { TenantId = tenantId, Name = "Sea Guardian", Category = ResourceCategory.Vehicle, Status = ResourceStatus.Available, Capacity = 20 };
        var type = new BookingType
        {
            TenantId = tenantId, Name = "Whale Watching Tour", Slug = "whales", Status = BookingTypeStatus.Active, DefaultDurationMinutes = 240,
            ConfigJson = """{ "pricing": { "adult": 7500, "child": 4000, "infant": 0, "currency": "LKR" } }""",
        };
        var departure = new Departure
        {
            TenantId = tenantId, ResourceId = resource.Id, Resource = resource, BookingTypeId = type.Id, BookingType = type,
            ScheduledDeparture = DateTime.UtcNow.AddDays(3).Date.AddHours(6.5), ScheduledReturn = DateTime.UtcNow.AddDays(3).Date.AddHours(10.5),
            Status = DepartureStatus.Scheduled,
        };
        db.Resources.Add(resource);
        db.BookingTypes.Add(type);
        db.Departures.Add(departure);
        await db.SaveChangesAsync();
        return (db, tenantId, departure.Id);
    }

    private static PublicBookingRequest Request(Guid departureId) => new()
    {
        FullName = "Amaya Perera", Email = "amaya@example.com", Phone = "+94 77 123 4567", DepartureId = departureId, Adults = 2,
    };

    [Fact]
    public async Task PublicBooking_FromAnInstagramAd_IsAttributed()
    {
        var (db, tenantId, departureId) = await SeedTourAsync();
        var req = Request(departureId);
        req.Attribution = new AttributionInput { UtmSource = "instagram", UtmMedium = "paid_social", UtmCampaign = "1203", Fbclid = "IwAR9" };

        var result = await new PublicBookingController(db).Create(tenantId, req);

        Assert.IsType<OkObjectResult>(result);
        var booking = await db.Bookings.IgnoreQueryFilters().SingleAsync();
        Assert.Equal("Instagram", booking.Source);
        var a = await db.BookingAttributions.IgnoreQueryFilters().SingleAsync();
        Assert.Equal(booking.Id, a.BookingId);
        Assert.Equal(tenantId, a.TenantId);
        Assert.Equal("1203", a.UtmCampaign);
        Assert.True(a.IsPaid);
        Assert.Equal(15000m, a.Value);
        Assert.Equal("LKR", a.Currency);
        Assert.StartsWith("fb.1.", a.Fbc);
    }

    [Fact]
    public async Task PublicBooking_WithNoTags_StaysAWebsiteBooking()
    {
        var (db, tenantId, departureId) = await SeedTourAsync();
        await new PublicBookingController(db).Create(tenantId, Request(departureId));
        Assert.Equal("Website", (await db.Bookings.IgnoreQueryFilters().SingleAsync()).Source);
    }

    [Fact]
    public async Task PublicBooking_FromAnInboxLink_LinksTheConversation_ButOnlyForItsOwnTenant()
    {
        var (db, tenantId, departureId) = await SeedTourAsync();
        var account = MarketingTestKit.Account(tenantId, SocialPlatform.Instagram, sandbox: true);
        var mine = new SocialConversation { TenantId = tenantId, SocialAccountId = account.Id, ParticipantId = "p1" };
        var foreign = new SocialConversation { TenantId = Guid.NewGuid(), SocialAccountId = Guid.NewGuid(), ParticipantId = "p2" };
        db.SocialAccounts.Add(account);
        db.SocialConversations.AddRange(mine, foreign);
        await db.SaveChangesAsync();

        var req = Request(departureId);
        req.PageUrl = $"https://app.example/embed/book/{tenantId}?utm_source=instagram&utm_medium=dm&conv={mine.Id}";
        await new PublicBookingController(db).Create(tenantId, req);
        var booking = await db.Bookings.IgnoreQueryFilters().SingleAsync();
        Assert.Equal(booking.Id, (await db.SocialConversations.IgnoreQueryFilters().SingleAsync(c => c.Id == mine.Id)).LinkedBookingId);

        var req2 = Request(departureId);
        req2.Email = "other@example.com";
        req2.PageUrl = $"https://app.example/embed/book/{tenantId}?conv={foreign.Id}";
        await new PublicBookingController(db).Create(tenantId, req2);
        Assert.Null((await db.SocialConversations.IgnoreQueryFilters().SingleAsync(c => c.Id == foreign.Id)).LinkedBookingId);
    }

    // ── Posts ──────────────────────────────────────────────────────────────

    private (SocialPostsController Controller, AppDbContext Db, Guid TenantId) Posts()
    {
        var tenantId = Guid.NewGuid();
        var db = TestHelpers.NewInMemoryDb(tenantId);
        var controller = new SocialPostsController(db);
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenantId, Roles.Manager);
        return (controller, db, tenantId);
    }

    [Fact]
    public async Task CreatePost_ForInstagramWithoutMedia_IsRejected()
    {
        var (controller, db, tenantId) = Posts();
        var ig = MarketingTestKit.Account(tenantId, SocialPlatform.Instagram, sandbox: true);
        db.SocialAccounts.Add(ig);
        await db.SaveChangesAsync();

        var result = await controller.Create(new SocialPostsController.UpsertPostRequest { Caption = "Hi", AccountIds = { ig.Id } });

        var bad = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains("Instagram", JsonSerializer.Serialize(bad.Value));
    }

    [Fact]
    public async Task CreatePost_ToAnotherTenantsAccount_IsRejected()
    {
        var (controller, db, _) = Posts();
        var foreign = MarketingTestKit.Account(Guid.NewGuid(), SocialPlatform.Facebook, sandbox: true);
        db.SocialAccounts.Add(foreign);
        await db.SaveChangesAsync();

        var result = await controller.Create(new SocialPostsController.UpsertPostRequest { Caption = "Hi", AccountIds = { foreign.Id } });
        Assert.IsType<BadRequestObjectResult>(result);
        Assert.Empty(await db.SocialPosts.IgnoreQueryFilters().ToListAsync());
    }

    [Fact]
    public async Task CreatePost_ToFacebookAndInstagram_CreatesOneTargetEach_AndCanBeCancelled()
    {
        var (controller, db, tenantId) = Posts();
        var fb = MarketingTestKit.Account(tenantId, SocialPlatform.Facebook, sandbox: true);
        var ig = MarketingTestKit.Account(tenantId, SocialPlatform.Instagram, sandbox: true);
        db.SocialAccounts.AddRange(fb, ig);
        await db.SaveChangesAsync();

        var result = await controller.Create(new SocialPostsController.UpsertPostRequest
        {
            Caption = "Whale season", MediaType = SocialMediaType.Image, MediaUrl = "https://cdn.example.com/w.jpg",
            ScheduledAt = DateTime.UtcNow.AddDays(1), AccountIds = { fb.Id, ig.Id },
        });

        Assert.IsType<CreatedAtActionResult>(result);
        var post = await db.SocialPosts.Include(p => p.Targets).SingleAsync();
        Assert.Equal(2, post.Targets.Count);
        Assert.Equal(SocialPostStatus.Scheduled, post.Status);

        Assert.IsType<OkObjectResult>(await controller.Cancel(post.Id));
        Assert.Equal(SocialPostStatus.Cancelled, (await db.SocialPosts.SingleAsync()).Status);
    }

    [Fact]
    public async Task CreatePost_InThePast_IsRejected()
    {
        var (controller, db, tenantId) = Posts();
        var fb = MarketingTestKit.Account(tenantId, SocialPlatform.Facebook, sandbox: true);
        db.SocialAccounts.Add(fb);
        await db.SaveChangesAsync();

        var result = await controller.Create(new SocialPostsController.UpsertPostRequest
        {
            Caption = "Late", ScheduledAt = DateTime.UtcNow.AddHours(-2), AccountIds = { fb.Id },
        });
        Assert.IsType<BadRequestObjectResult>(result);
    }

    // ── Ads settings ───────────────────────────────────────────────────────

    [Fact]
    public async Task Settings_StoreTokensEncrypted_AndNeverReturnThem()
    {
        var tenantId = Guid.NewGuid();
        var db = TestHelpers.NewInMemoryDb(tenantId);
        var controller = new MarketingController(db, _protector, Mock.Of<IMetaGraphClient>(), Mock.Of<ITikTokClient>(), Mock.Of<IMarketingAnalyticsService>());
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenantId, Roles.Admin);

        var result = await controller.UpdateSettings(new MarketingController.UpdateSettingsRequest
        {
            MetaPixelId = "123456789", MetaCapiToken = "EAAB-super-secret-capi-token", MetaAdAccountId = "987",
        });

        var ok = Assert.IsType<OkObjectResult>(result);
        var json = JsonSerializer.Serialize(ok.Value);
        Assert.DoesNotContain("super-secret", json);
        Assert.Contains("\"metaTrackingActive\":true", json);
        Assert.Contains("act_987", json);

        var stored = await db.MarketingSettings.SingleAsync();
        Assert.NotEqual("EAAB-super-secret-capi-token", stored.MetaCapiTokenEncrypted);
        Assert.Equal("EAAB-super-secret-capi-token", _protector.Unprotect(stored.MetaCapiTokenEncrypted!));

        // null leaves the token alone, "" clears it.
        await controller.UpdateSettings(new MarketingController.UpdateSettingsRequest { MetaTestEventCode = "TEST1" });
        Assert.NotNull((await db.MarketingSettings.SingleAsync()).MetaCapiTokenEncrypted);
        await controller.UpdateSettings(new MarketingController.UpdateSettingsRequest { MetaCapiToken = "" });
        Assert.Null((await db.MarketingSettings.SingleAsync()).MetaCapiTokenEncrypted);
    }

    [Fact]
    public async Task Settings_RejectNonNumericPixelIds()
    {
        var tenantId = Guid.NewGuid();
        var controller = new MarketingController(TestHelpers.NewInMemoryDb(tenantId), _protector, Mock.Of<IMetaGraphClient>(), Mock.Of<ITikTokClient>(), Mock.Of<IMarketingAnalyticsService>());
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenantId, Roles.Admin);
        Assert.IsType<BadRequestObjectResult>(await controller.UpdateSettings(new MarketingController.UpdateSettingsRequest { MetaPixelId = "<script>" }));
    }

    // ── Campaign report ────────────────────────────────────────────────────

    [Fact]
    public async Task CampaignReport_JoinsAdSpendToAttributedBookings_ById_AndByName()
    {
        var tenantId = Guid.NewGuid();
        var db = TestHelpers.NewInMemoryDb(tenantId);
        var now = DateTime.UtcNow;

        void Book(string channel, string campaign, decimal cost, BookingStatus status)
        {
            var b = new Booking
            {
                TenantId = tenantId, ResourceId = Guid.NewGuid(), BookingTypeId = Guid.NewGuid(), BookedBy = Guid.NewGuid(),
                StartTime = now.AddDays(2), EndTime = now.AddDays(2).AddHours(1), Status = status, Source = channel, TotalCost = cost, CreatedAt = now.AddDays(-1),
            };
            db.Bookings.Add(b);
            db.BookingAttributions.Add(new BookingAttribution { BookingId = b.Id, TenantId = tenantId, Channel = channel, UtmCampaign = campaign, CreatedAt = now.AddDays(-1) });
        }
        Book("Instagram", "120001", 20000m, BookingStatus.Confirmed);           // matched by id
        Book("Facebook", "120001", 10000m, BookingStatus.Completed);            // same Meta campaign
        Book("Facebook", "120001", 99999m, BookingStatus.Cancelled);            // lost: no revenue
        Book("TikTok", "Spring Promo", 5000m, BookingStatus.Pending);           // matched by name
        Book("Instagram", "bio-link", 3000m, BookingStatus.Confirmed);          // organic, no spend
        db.MarketingSettings.Add(new MarketingSettings
        {
            TenantId = tenantId,
            MetaAdAccountId = "act_1", MetaAdsTokenEncrypted = _protector.Protect("meta-ads"),
            TikTokAdvertiserId = "7", TikTokAdsTokenEncrypted = _protector.Protect("tt-ads"),
        });
        await db.SaveChangesAsync();

        var meta = new Mock<IMetaGraphClient>();
        meta.Setup(m => m.GetCampaignSpendAsync("act_1", "meta-ads", It.IsAny<DateOnly>(), It.IsAny<DateOnly>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new[] { new CampaignSpend("120001", "Whale Season", 10000m, 50000, 1000), new CampaignSpend("120002", "Dead Campaign", 2000m, 9000, 10) });
        var tikTok = new Mock<ITikTokClient>();
        tikTok.Setup(t => t.GetCampaignSpendAsync("7", "tt-ads", It.IsAny<DateOnly>(), It.IsAny<DateOnly>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new SocialApiException("TikTok: Access token is incorrect (code 40105)", tokenInvalid: true));
        var service = new MarketingAnalyticsService(db, meta.Object, tikTok.Object, _protector, new MemoryCache(new MemoryCacheOptions()));

        var report = await service.GetCampaignsAsync(tenantId, now.AddDays(-7), now.AddDays(1), default);

        var whale = report.Campaigns.Single(c => c.CampaignId == "120001");
        Assert.Equal(3, whale.Bookings);
        Assert.Equal(30000m, whale.Revenue);       // the cancelled one does not count
        Assert.Equal(3.00m, whale.Roas);           // 30,000 / 10,000
        Assert.Equal(3333.33m, whale.CostPerBooking);
        Assert.Equal(0.02m, whale.Ctr);
        Assert.Equal(10m, whale.Cpc);

        var dead = report.Campaigns.Single(c => c.CampaignId == "120002");
        Assert.Equal(0, dead.Bookings);
        Assert.Equal(0m, dead.Roas);

        // TikTok spend failed: its bookings still show, with a warning, not an error.
        Assert.Contains(report.Warnings, w => w.Contains("TikTok"));
        Assert.Contains(report.Campaigns, c => c.Campaign == "Spring Promo" && c.Bookings == 1 && !c.MatchedToAdAccount);
        Assert.Contains(report.Campaigns, c => c.Campaign == "bio-link" && c.Spend == null);
        Assert.Equal(12000m, report.TotalSpend);
    }
}
