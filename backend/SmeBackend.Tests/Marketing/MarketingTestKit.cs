using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using SmeBackend.Data;
using SmeBackend.Models;
using SmeBackend.Models.Marketing;
using SmeBackend.Services;
using SmeBackend.Services.Marketing;

namespace SmeBackend.Tests.Marketing;

internal static class MarketingTestKit
{
    public static IConfiguration Config(params (string Key, string Value)[] extra)
    {
        var values = new Dictionary<string, string?> { ["Jwt:Key"] = "test-signing-key-that-is-long-enough-for-hmac-256!!" };
        foreach (var (k, v) in extra) values[k] = v;
        return new ConfigurationBuilder().AddInMemoryCollection(values).Build();
    }

    public static IPlatformSecretProtector Protector() => new PlatformSecretProtector(Config());

    public static OAuthStateProtector StateProtector() =>
        new(Config(), new MemoryCache(new MemoryCacheOptions()));

    public static SocialAccount Account(Guid tenantId, string platform, IPlatformSecretProtector? protector = null, bool sandbox = false, string? externalId = null) => new()
    {
        TenantId = tenantId,
        Platform = platform,
        ExternalId = externalId ?? (platform + "-" + Guid.NewGuid().ToString("N")[..6]),
        ParentExternalId = platform == SocialPlatform.Instagram ? "page-1" : null,
        DisplayName = platform + " account",
        Handle = "biz",
        IsSandbox = sandbox,
        Status = SocialAccountStatus.Connected,
        AccessTokenEncrypted = sandbox ? null : (protector ?? Protector()).Protect("token-" + platform),
        AccessTokenExpiresAt = platform == SocialPlatform.TikTok ? DateTime.UtcNow.AddHours(12) : null,
    };

    public static Tenant Tenant(AppDbContext db, Guid? id = null)
    {
        var t = new Tenant { Id = id ?? Guid.NewGuid(), Name = "Mirissa Jetliner", BusinessType = "Tourism", IsActive = true };
        db.Tenants.Add(t);
        return t;
    }

    public static SocialPublisher Publisher(Mock<IMetaGraphClient> meta, Mock<ITikTokClient> tikTok, IPlatformSecretProtector protector) =>
        new(meta.Object, tikTok.Object, new SocialTokenService(protector, tikTok.Object), NullLogger<SocialPublisher>.Instance);
}
