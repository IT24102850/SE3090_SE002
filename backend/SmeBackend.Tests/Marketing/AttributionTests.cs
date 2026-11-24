using SmeBackend.Models.Marketing;
using SmeBackend.Services.Marketing;

namespace SmeBackend.Tests.Marketing;

public class AttributionTests
{
    private static readonly DateTime Now = new(2026, 11, 20, 10, 0, 0, DateTimeKind.Utc);

    [Theory]
    [InlineData("instagram", "Instagram")]
    [InlineData("IG", "Instagram")]
    [InlineData("facebook", "Facebook")]
    [InlineData("fb", "Facebook")]
    [InlineData("meta", "Facebook")]
    [InlineData("tiktok", "TikTok")]
    [InlineData("newsletter", "Newsletter")]
    public void UtmSource_SetsTheChannel(string utmSource, string expected)
    {
        var a = AttributionResolver.Resolve(new AttributionInput { UtmSource = utmSource }, null, Now);
        Assert.Equal(expected, a.Channel);
    }

    [Fact]
    public void NoSignalAtAll_IsWebsite()
    {
        var a = AttributionResolver.Resolve(null, "https://mirissa.example/book", Now);
        Assert.Equal("Website", a.Channel);
        Assert.False(a.IsPaid);
    }

    [Fact]
    public void Fbclid_WithoutUtm_IsFacebook_AndBuildsTheFbcCookieValue()
    {
        var a = AttributionResolver.Resolve(new AttributionInput { Fbclid = "IwAR123" }, null, Now);
        Assert.Equal(SocialPlatform.Facebook, a.Channel);
        Assert.Equal($"fb.1.{new DateTimeOffset(Now).ToUnixTimeMilliseconds()}.IwAR123", a.Fbc);
    }

    [Fact]
    public void AnExistingFbcCookie_IsKeptAsIs()
    {
        var a = AttributionResolver.Resolve(new AttributionInput { Fbclid = "IwAR123", Fbc = "fb.1.1700000000000.IwAR123" }, null, Now);
        Assert.Equal("fb.1.1700000000000.IwAR123", a.Fbc);
    }

    [Fact]
    public void Ttclid_IsTikTok_AndPaid()
    {
        var a = AttributionResolver.Resolve(new AttributionInput { Ttclid = "E.C.P.abc" }, null, Now);
        Assert.Equal(SocialPlatform.TikTok, a.Channel);
        Assert.True(a.IsPaid);
    }

    [Fact]
    public void InstagramReferrer_IsInstagram()
    {
        var a = AttributionResolver.Resolve(new AttributionInput { Referrer = "https://l.instagram.com/?u=x" }, null, Now);
        Assert.Equal(SocialPlatform.Instagram, a.Channel);
    }

    [Fact]
    public void UtmTagsInThePageUrl_AreUsedWhenTheRequestHasNone()
    {
        var a = AttributionResolver.Resolve(null,
            "https://site.example/tours?utm_source=instagram&utm_medium=paid_social&utm_campaign=Whale%20Season%202026", Now);
        Assert.Equal(SocialPlatform.Instagram, a.Channel);
        Assert.Equal("Whale Season 2026", a.UtmCampaign);
        Assert.True(a.IsPaid);
    }

    [Fact]
    public void ExplicitValues_WinOverThePageUrl()
    {
        var a = AttributionResolver.Resolve(new AttributionInput { UtmSource = "tiktok" },
            "https://site.example/?utm_source=instagram", Now);
        Assert.Equal(SocialPlatform.TikTok, a.Channel);
    }

    [Fact]
    public void ConversationId_FromTheLink_IsCaptured()
    {
        var conv = Guid.NewGuid();
        var a = AttributionResolver.Resolve(null, $"https://app.example/embed/book/x?utm_source=instagram&utm_medium=dm&conv={conv}", Now);
        Assert.Equal(conv, a.SocialConversationId);
    }

    [Fact]
    public void OverlongValues_AreClipped_NotRejected()
    {
        var a = AttributionResolver.Resolve(new AttributionInput { UtmCampaign = new string('x', 5000) }, null, Now);
        Assert.Equal(200, a.UtmCampaign!.Length);
    }

    [Fact]
    public void ConversionPayloads_HashNormalisedEmailAndSriLankanPhone()
    {
        Assert.Equal("amaya.test@example.com", ConversionPayloads.NormaliseEmail("  Amaya.Test@Example.com "));
        Assert.Equal("94771234567", ConversionPayloads.NormalisePhoneDigits("077 123 4567"));
        Assert.Equal("94771234567", ConversionPayloads.NormalisePhoneDigits("+94 77 123 4567"));
        Assert.Equal("+94771234567", ConversionPayloads.NormalisePhoneE164("0771234567"));
        Assert.Equal("447911123456", ConversionPayloads.NormalisePhoneDigits("+44 7911 123456"));
        // A foreign number typed without its country code cannot be matched; send nothing rather than a wrong hash.
        Assert.Null(ConversionPayloads.NormalisePhoneDigits("7911 123456"));
        // Lowercase hex, as both platforms expect.
        Assert.Equal("2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881", ConversionPayloads.Sha256("x"));
    }
}
