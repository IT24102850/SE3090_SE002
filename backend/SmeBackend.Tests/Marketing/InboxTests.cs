using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using SmeBackend.Controllers.Marketing;
using SmeBackend.Data;
using SmeBackend.Models.Marketing;
using SmeBackend.Services;
using SmeBackend.Services.Marketing;
using SmeBackend.Shared;

namespace SmeBackend.Tests.Marketing;

public class InboxTests
{
    private static readonly DateTime Now = DateTime.UtcNow;
    private readonly IPlatformSecretProtector _protector = MarketingTestKit.Protector();
    private readonly Mock<IMetaGraphClient> _meta = new();
    private readonly Mock<ITikTokClient> _tikTok = new();

    private MetaWebhookProcessor Processor(AppDbContext db) =>
        new(db, _meta.Object, new SocialTokenService(_protector, _tikTok.Object), NullLogger<MetaWebhookProcessor>.Instance);

    private static JsonElement Webhook(string obj, string entryId, string sender, string recipient, string mid, string text, bool echo = false)
    {
        var json = JsonSerializer.Serialize(new
        {
            @object = obj,
            entry = new[]
            {
                new
                {
                    id = entryId,
                    time = 1,
                    messaging = new object[]
                    {
                        new
                        {
                            sender = new { id = sender },
                            recipient = new { id = recipient },
                            timestamp = new DateTimeOffset(Now).ToUnixTimeMilliseconds(),
                            message = new { mid, text, is_echo = echo },
                        },
                        // Read receipts and the like are ignored.
                        new { sender = new { id = sender }, recipient = new { id = recipient }, timestamp = 1, read = new { watermark = 1 } },
                    },
                },
            },
        });
        return JsonDocument.Parse(json).RootElement.Clone();
    }

    [Fact]
    public async Task IncomingDm_CreatesAThread_WithTheSendersName_AndNotifiesTheBusiness()
    {
        var db = TestHelpers.NewInMemoryDb();
        var tenantId = Guid.NewGuid();
        var account = MarketingTestKit.Account(tenantId, SocialPlatform.Instagram, _protector, externalId: "ig-1");
        db.SocialAccounts.Add(account);
        await db.SaveChangesAsync();
        _meta.Setup(m => m.GetParticipantNameAsync("user-7", "token-Instagram", true, It.IsAny<CancellationToken>())).ReturnsAsync("Amaya Perera");

        var recorded = await Processor(db).ProcessAsync(Webhook("instagram", "ig-1", "user-7", "ig-1", "mid.1", "Do you have space on Saturday?"), Now, default);

        Assert.Equal(1, recorded);
        var conv = await db.SocialConversations.IgnoreQueryFilters().SingleAsync();
        Assert.Equal(tenantId, conv.TenantId);
        Assert.Equal("Amaya Perera", conv.ParticipantName);
        Assert.Equal(1, conv.UnreadCount);
        Assert.NotNull(conv.LastInboundAt);
        Assert.Single(await db.Notifications.IgnoreQueryFilters().Where(n => n.TenantId == tenantId && n.Type == "SocialMessage").ToListAsync());
    }

    [Fact]
    public async Task RedeliveredWebhook_IsANoOp()
    {
        var db = TestHelpers.NewInMemoryDb();
        var account = MarketingTestKit.Account(Guid.NewGuid(), SocialPlatform.Facebook, _protector, externalId: "page-1");
        db.SocialAccounts.Add(account);
        await db.SaveChangesAsync();
        var hook = Webhook("page", "page-1", "psid-1", "page-1", "mid.same", "Hello");

        await Processor(db).ProcessAsync(hook, Now, default);
        var second = await Processor(db).ProcessAsync(hook, Now, default);

        Assert.Equal(0, second);
        Assert.Single(await db.SocialMessages.IgnoreQueryFilters().ToListAsync());
        Assert.Equal(1, (await db.SocialConversations.IgnoreQueryFilters().SingleAsync()).UnreadCount);
    }

    [Fact]
    public async Task Echo_IsRecordedAsOutbound_OnTheCustomersThread()
    {
        var db = TestHelpers.NewInMemoryDb();
        var account = MarketingTestKit.Account(Guid.NewGuid(), SocialPlatform.Facebook, _protector, externalId: "page-1");
        db.SocialAccounts.Add(account);
        await db.SaveChangesAsync();

        await Processor(db).ProcessAsync(Webhook("page", "page-1", "page-1", "psid-9", "mid.echo", "Thanks!", echo: true), Now, default);

        var conv = await db.SocialConversations.IgnoreQueryFilters().SingleAsync();
        Assert.Equal("psid-9", conv.ParticipantId);
        Assert.Equal(0, conv.UnreadCount);
        Assert.Equal(SocialMessageDirection.Outbound, (await db.SocialMessages.IgnoreQueryFilters().SingleAsync()).Direction);
    }

    [Fact]
    public async Task WebhookForAPageNobodyConnected_IsIgnored()
    {
        var db = TestHelpers.NewInMemoryDb();
        var recorded = await Processor(db).ProcessAsync(Webhook("page", "unknown", "psid", "unknown", "mid", "Hi"), Now, default);
        Assert.Equal(0, recorded);
        Assert.Empty(await db.SocialConversations.IgnoreQueryFilters().ToListAsync());
    }

    private (SocialInboxController Controller, AppDbContext Db, SocialAccount Account, SocialConversation Conv) Inbox(bool sandbox, DateTime? lastInbound)
    {
        var tenantId = Guid.NewGuid();
        var db = TestHelpers.NewInMemoryDb(tenantId);
        var account = MarketingTestKit.Account(tenantId, SocialPlatform.Facebook, _protector, sandbox, externalId: "page-1");
        var conv = new SocialConversation { TenantId = tenantId, SocialAccountId = account.Id, ParticipantId = "psid-1", LastInboundAt = lastInbound, UnreadCount = 2 };
        db.SocialAccounts.Add(account);
        db.SocialConversations.Add(conv);
        db.SaveChanges();
        var controller = new SocialInboxController(db, _meta.Object, new SocialTokenService(_protector, _tikTok.Object), Processor(db));
        TestHelpers.SetUser(controller, Guid.NewGuid(), tenantId, Roles.Staff);
        return (controller, db, account, conv);
    }

    [Fact]
    public async Task Reply_WithinTheWindow_IsSentThroughThePage()
    {
        var (controller, db, _, conv) = Inbox(sandbox: false, lastInbound: Now.AddHours(-2));
        _meta.Setup(m => m.SendMessageAsync("page-1", "token-Facebook", "psid-1", "See you at 6:30!", It.IsAny<CancellationToken>()))
            .ReturnsAsync("m_abc");

        var result = await controller.Reply(conv.Id, new SocialInboxController.ReplyRequest { Text = "See you at 6:30!" }, default);

        Assert.IsType<OkObjectResult>(result);
        var msg = await db.SocialMessages.SingleAsync();
        Assert.Equal("m_abc", msg.ExternalMessageId);
        Assert.Equal(0, (await db.SocialConversations.SingleAsync()).UnreadCount);
    }

    [Fact]
    public async Task Reply_After24Hours_IsRefusedBeforeCallingMeta()
    {
        var (controller, _, _, conv) = Inbox(sandbox: false, lastInbound: Now.AddHours(-30));

        var result = await controller.Reply(conv.Id, new SocialInboxController.ReplyRequest { Text = "Hello?" }, default);

        Assert.IsType<ConflictObjectResult>(result);
        _meta.Verify(m => m.SendMessageAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Reply_OnSandbox_IsStoredWithoutMeta()
    {
        var (controller, db, _, conv) = Inbox(sandbox: true, lastInbound: null);
        var result = await controller.Reply(conv.Id, new SocialInboxController.ReplyRequest { Text = "Hi from sandbox" }, default);
        Assert.IsType<OkObjectResult>(result);
        Assert.StartsWith("sandbox-", (await db.SocialMessages.SingleAsync()).ExternalMessageId);
    }

    [Fact]
    public async Task AnotherTenantsConversation_IsNotFound()
    {
        var (_, _, _, conv) = Inbox(sandbox: true, lastInbound: null);
        var (other, _, _, _) = Inbox(sandbox: true, lastInbound: null);

        var result = await other.Reply(conv.Id, new SocialInboxController.ReplyRequest { Text = "x" }, default);
        Assert.IsType<NotFoundObjectResult>(result);
    }
}
