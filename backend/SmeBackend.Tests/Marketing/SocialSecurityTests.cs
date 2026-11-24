using System.Security.Cryptography;
using System.Text;
using SmeBackend.Services.Marketing;

namespace SmeBackend.Tests.Marketing;

public class SocialSecurityTests
{
    [Fact]
    public void OAuthState_RoundTrips_AndIsSingleUse()
    {
        var protector = MarketingTestKit.StateProtector();
        var tenant = Guid.NewGuid();
        var user = Guid.NewGuid();

        var state = protector.Create(tenant, user, "meta", "https://app.example.com");
        var parsed = protector.Consume(state, "meta");

        Assert.NotNull(parsed);
        Assert.Equal(tenant, parsed!.TenantId);
        Assert.Equal(user, parsed.UserId);
        Assert.Equal("https://app.example.com", parsed.ReturnOrigin);

        // A leaked callback URL cannot be replayed.
        Assert.Null(protector.Consume(state, "meta"));
    }

    [Fact]
    public void OAuthState_TamperedPayload_IsRejected()
    {
        var protector = MarketingTestKit.StateProtector();
        var state = protector.Create(Guid.NewGuid(), Guid.NewGuid(), "meta", "https://app.example.com");
        var dot = state.IndexOf('.');
        var payload = state[..dot];
        // Flip a character in the payload but keep the old signature.
        var tampered = (payload[0] == 'A' ? 'B' : 'A') + payload[1..] + state[dot..];

        Assert.Null(protector.Consume(tampered, "meta"));
    }

    [Fact]
    public void OAuthState_ForAnotherProvider_IsRejected()
    {
        var protector = MarketingTestKit.StateProtector();
        var state = protector.Create(Guid.NewGuid(), Guid.NewGuid(), "meta", "https://app.example.com");
        Assert.Null(protector.Consume(state, "tiktok"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("no-dot")]
    [InlineData("abc.!!!")]
    [InlineData(".")]
    public void OAuthState_Garbage_IsRejected(string? state)
    {
        Assert.Null(MarketingTestKit.StateProtector().Consume(state, "meta"));
    }

    [Fact]
    public void OAuthState_SignedWithAnotherServersKey_IsRejected()
    {
        var other = new OAuthStateProtector(
            MarketingTestKit.Config(("Social:StateKey", "a-completely-different-key")),
            new Microsoft.Extensions.Caching.Memory.MemoryCache(new Microsoft.Extensions.Caching.Memory.MemoryCacheOptions()));
        var state = other.Create(Guid.NewGuid(), Guid.NewGuid(), "meta", "https://app.example.com");
        Assert.Null(MarketingTestKit.StateProtector().Consume(state, "meta"));
    }

    [Fact]
    public void WebhookSignature_Valid_IsAccepted()
    {
        var body = Encoding.UTF8.GetBytes("{\"object\":\"page\"}");
        var sig = "sha256=" + Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes("app-secret"), body)).ToLowerInvariant();
        Assert.True(MetaGraphClient.VerifySignature(body, sig, "app-secret"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("sha1=abcdef")]
    [InlineData("sha256=nothex")]
    [InlineData("sha256=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff")]
    public void WebhookSignature_MissingOrWrong_IsRejected(string? header)
    {
        var body = Encoding.UTF8.GetBytes("{\"object\":\"page\"}");
        Assert.False(MetaGraphClient.VerifySignature(body, header, "app-secret"));
    }

    [Fact]
    public void WebhookSignature_WithNoAppSecretConfigured_IsAlwaysRejected()
    {
        var body = Encoding.UTF8.GetBytes("{}");
        var sig = "sha256=" + Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(""), body));
        Assert.False(MetaGraphClient.VerifySignature(body, sig, null));
        Assert.False(MetaGraphClient.VerifySignature(body, sig, ""));
    }
}
