using Microsoft.EntityFrameworkCore;
using Moq;
using SmeBackend.Models.Marketing;
using SmeBackend.Services.Marketing;

namespace SmeBackend.Tests.Marketing;

public class SocialPublisherTests
{
    private static readonly DateTime Now = new(2026, 11, 20, 10, 0, 0, DateTimeKind.Utc);
    private readonly Mock<IMetaGraphClient> _meta = new(MockBehavior.Strict);
    private readonly Mock<ITikTokClient> _tikTok = new(MockBehavior.Strict);
    private readonly SmeBackend.Services.IPlatformSecretProtector _protector = MarketingTestKit.Protector();

    private (SocialPost Post, SocialPostTarget Target) Post(SocialAccount account, string mediaType = SocialMediaType.Image, string caption = "Whale season is here")
    {
        var post = new SocialPost
        {
            TenantId = account.TenantId,
            Caption = caption,
            MediaType = mediaType,
            MediaUrl = mediaType == SocialMediaType.None ? null : "https://cdn.example.com/whale.jpg",
            LinkUrl = "https://app.example.com/embed/book/x?utm_source=instagram",
            Status = SocialPostStatus.Scheduled,
        };
        var target = new SocialPostTarget { TenantId = account.TenantId, SocialPostId = post.Id, SocialAccountId = account.Id, Account = account, Post = post };
        post.Targets.Add(target);
        return (post, target);
    }

    [Fact]
    public async Task SandboxAccount_IsSimulated_AndNothingIsSent()
    {
        var account = MarketingTestKit.Account(Guid.NewGuid(), SocialPlatform.Instagram, sandbox: true);
        var (post, target) = Post(account);

        await MarketingTestKit.Publisher(_meta, _tikTok, _protector).ProcessAsync(target, post, account, Now, default);

        Assert.Equal(SocialTargetStatus.Simulated, target.Status);
        Assert.Equal(SocialPostStatus.Published, SocialPostRules.Rollup(post));
        _meta.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task Facebook_PublishesInOneStep_WithTheDecryptedPageToken()
    {
        var account = MarketingTestKit.Account(Guid.NewGuid(), SocialPlatform.Facebook, _protector);
        var (post, target) = Post(account, SocialMediaType.None);
        _meta.Setup(m => m.PublishFacebookAsync(account.ExternalId, "token-Facebook", It.IsAny<PublishRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(PublishStep.Done("123_456", "https://www.facebook.com/123_456"));

        await MarketingTestKit.Publisher(_meta, _tikTok, _protector).ProcessAsync(target, post, account, Now, default);

        Assert.Equal(SocialTargetStatus.Published, target.Status);
        Assert.Equal("123_456", target.ExternalPostId);
        Assert.Equal(Now, target.PublishedAt);
    }

    [Fact]
    public async Task Instagram_Video_IsPolledUntilReady_ThenPublished()
    {
        var account = MarketingTestKit.Account(Guid.NewGuid(), SocialPlatform.Instagram, _protector);
        var (post, target) = Post(account, SocialMediaType.Video);
        _meta.Setup(m => m.StartInstagramAsync(account.ExternalId, "token-Instagram", It.IsAny<PublishRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(PublishStep.Processing("container-1"));
        _meta.Setup(m => m.ContinueInstagramAsync(account.ExternalId, "token-Instagram", "container-1", It.IsAny<CancellationToken>()))
            .ReturnsAsync(PublishStep.Done("media-9", "https://instagram.com/p/x"));
        var publisher = MarketingTestKit.Publisher(_meta, _tikTok, _protector);

        await publisher.ProcessAsync(target, post, account, Now, default);
        Assert.Equal(SocialTargetStatus.Processing, target.Status);
        Assert.Equal("container-1", target.ProviderContainerId);
        Assert.Equal(Now + SocialPublisher.PollInterval, target.NextAttemptAt);
        Assert.Equal(0, target.Attempts); // polling is not a failed attempt
        Assert.Equal(SocialPostStatus.Publishing, SocialPostRules.Rollup(post));

        await publisher.ProcessAsync(target, post, account, Now.AddSeconds(30), default);
        Assert.Equal(SocialTargetStatus.Published, target.Status);
        Assert.Equal("https://instagram.com/p/x", target.PermalinkUrl);
    }

    [Fact]
    public async Task ProcessingThatNeverFinishes_TimesOut()
    {
        var account = MarketingTestKit.Account(Guid.NewGuid(), SocialPlatform.Instagram, _protector);
        var (post, target) = Post(account, SocialMediaType.Video);
        target.Status = SocialTargetStatus.Processing;
        target.ProviderContainerId = "c";
        target.ProcessingSince = Now - SocialPublisher.ProcessingTimeout - TimeSpan.FromMinutes(1);

        await MarketingTestKit.Publisher(_meta, _tikTok, _protector).ProcessAsync(target, post, account, Now, default);

        Assert.Equal(SocialTargetStatus.Failed, target.Status);
        _meta.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task RevokedToken_FailsTheTarget_AndFlagsTheAccountForReconnect()
    {
        var account = MarketingTestKit.Account(Guid.NewGuid(), SocialPlatform.Facebook, _protector);
        var (post, target) = Post(account, SocialMediaType.None);
        _meta.Setup(m => m.PublishFacebookAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<PublishRequest>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new SocialApiException("Error validating access token", tokenInvalid: true, providerCode: 190));

        await MarketingTestKit.Publisher(_meta, _tikTok, _protector).ProcessAsync(target, post, account, Now, default);

        Assert.Equal(SocialTargetStatus.Failed, target.Status);
        Assert.Equal(SocialAccountStatus.NeedsReconnect, account.Status);
    }

    [Fact]
    public async Task TransientError_IsRetriedWithBackoff_ThenGivenUp()
    {
        var account = MarketingTestKit.Account(Guid.NewGuid(), SocialPlatform.Facebook, _protector);
        var (post, target) = Post(account, SocialMediaType.None);
        _meta.Setup(m => m.PublishFacebookAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<PublishRequest>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new SocialApiException("Application request limit reached", transient: true, providerCode: 4));
        var publisher = MarketingTestKit.Publisher(_meta, _tikTok, _protector);

        await publisher.ProcessAsync(target, post, account, Now, default);
        Assert.Equal(SocialTargetStatus.Pending, target.Status);
        Assert.Equal(1, target.Attempts);
        Assert.Equal(Now.AddMinutes(1), target.NextAttemptAt);

        for (var i = 1; i < SocialPublisher.MaxAttempts; i++)
            await publisher.ProcessAsync(target, post, account, Now, default);

        Assert.Equal(SocialTargetStatus.Failed, target.Status);
        Assert.Equal(SocialPublisher.MaxAttempts, target.Attempts);
        Assert.Equal(SocialAccountStatus.Connected, account.Status);
    }

    [Fact]
    public async Task InstagramWithoutMedia_FailsWithoutCallingInstagram()
    {
        var account = MarketingTestKit.Account(Guid.NewGuid(), SocialPlatform.Instagram, _protector);
        var (post, target) = Post(account, SocialMediaType.None);

        await MarketingTestKit.Publisher(_meta, _tikTok, _protector).ProcessAsync(target, post, account, Now, default);

        Assert.Equal(SocialTargetStatus.Failed, target.Status);
        Assert.Contains("image or a video", target.Error);
        _meta.VerifyNoOtherCalls();
    }

    [Fact]
    public async Task TikTok_ExpiringToken_IsRefreshedBeforePublishing()
    {
        var account = MarketingTestKit.Account(Guid.NewGuid(), SocialPlatform.TikTok, _protector);
        account.AccessTokenExpiresAt = DateTime.UtcNow.AddMinutes(2);
        account.RefreshTokenEncrypted = _protector.Protect("refresh-1");
        var (post, target) = Post(account, SocialMediaType.Video);
        _tikTok.Setup(t => t.RefreshAsync("refresh-1", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new TikTokToken("fresh-token", DateTime.UtcNow.AddHours(24), "refresh-2", DateTime.UtcNow.AddDays(365), "open-1", null));
        _tikTok.Setup(t => t.StartPublishAsync("fresh-token", It.IsAny<PublishRequest>(), null, It.IsAny<CancellationToken>()))
            .ReturnsAsync(PublishStep.Processing("pub-1"));

        await MarketingTestKit.Publisher(_meta, _tikTok, _protector).ProcessAsync(target, post, account, Now, default);

        Assert.Equal(SocialTargetStatus.Processing, target.Status);
        Assert.Equal("fresh-token", _protector.Unprotect(account.AccessTokenEncrypted!));
        Assert.Equal("refresh-2", _protector.Unprotect(account.RefreshTokenEncrypted!));
    }

    [Fact]
    public void Rollup_MixedOutcome_IsPartiallyPublished()
    {
        var post = new SocialPost { Status = SocialPostStatus.Publishing };
        post.Targets.Add(new SocialPostTarget { Status = SocialTargetStatus.Published });
        post.Targets.Add(new SocialPostTarget { Status = SocialTargetStatus.Failed });
        Assert.Equal(SocialPostStatus.PartiallyPublished, SocialPostRules.Rollup(post));
    }

    [Fact]
    public async Task Worker_PublishesDuePosts_AndLeavesFutureOnesAlone()
    {
        var tenantId = Guid.NewGuid();
        var db = TestHelpers.NewInMemoryDb(tenantId);
        var account = MarketingTestKit.Account(tenantId, SocialPlatform.Facebook, sandbox: true);
        db.SocialAccounts.Add(account);

        SocialPost Make(DateTime? at)
        {
            var p = new SocialPost { TenantId = tenantId, Caption = "Hi", ScheduledAt = at, Status = SocialPostStatus.Scheduled };
            p.Targets.Add(new SocialPostTarget { TenantId = tenantId, SocialPostId = p.Id, SocialAccountId = account.Id });
            db.SocialPosts.Add(p);
            return p;
        }
        var now = Make(null);
        var due = Make(Now.AddMinutes(-5));
        var later = Make(Now.AddHours(2));
        var draft = Make(null);
        draft.Status = SocialPostStatus.Draft;
        await db.SaveChangesAsync();

        var processed = await SocialPublishingWorker.RunOnceAsync(db, MarketingTestKit.Publisher(_meta, _tikTok, _protector), Now, default);

        Assert.Equal(2, processed);
        var statuses = await db.SocialPosts.ToDictionaryAsync(p => p.Id, p => p.Status);
        Assert.Equal(SocialPostStatus.Published, statuses[now.Id]);
        Assert.Equal(SocialPostStatus.Published, statuses[due.Id]);
        Assert.Equal(SocialPostStatus.Scheduled, statuses[later.Id]);
        Assert.Equal(SocialPostStatus.Draft, statuses[draft.Id]);
    }
}
