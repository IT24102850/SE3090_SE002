namespace SmeBackend.Services.Marketing;

/// App-level credentials for the social platforms, bound from the "Social"
/// configuration section (or Social__Meta__AppId, ... environment variables).
///
/// These identify the Unify app to Meta/TikTok; they are the platform's, not
/// any tenant's. Each tenant's own access tokens are per-account and live
/// encrypted in the database. With nothing configured, the connect buttons
/// explain what to set and only sandbox accounts are available.
public sealed class SocialOptions
{
    public const string Section = "Social";

    public MetaAppOptions Meta { get; set; } = new();
    public TikTokAppOptions TikTok { get; set; } = new();

    /// Public https base of this API (e.g. https://api.example.com), used to
    /// build the OAuth redirect URI that must be registered with each
    /// provider. Falls back to the incoming request's scheme and host.
    public string? PublicApiBaseUrl { get; set; }
}

public sealed class MetaAppOptions
{
    public string? AppId { get; set; }
    public string? AppSecret { get; set; }

    /// The string typed into the App Dashboard's webhook "Verify token" box.
    public string? WebhookVerifyToken { get; set; }

    public string GraphVersion { get; set; } = "v23.0";

    /// What the connect dialog asks for. Publishing, Messenger/Instagram
    /// DMs and ad reporting each need their own permission, and each needs
    /// Meta App Review before it works for accounts that are not app testers.
    public string Scopes { get; set; } = string.Join(',',
        "pages_show_list",
        "pages_read_engagement",
        "pages_manage_posts",
        "pages_manage_metadata",
        "pages_messaging",
        "instagram_basic",
        "instagram_content_publish",
        "instagram_manage_messages",
        "business_management",
        "ads_read");

    public bool IsConfigured => !string.IsNullOrWhiteSpace(AppId) && !string.IsNullOrWhiteSpace(AppSecret);
}

public sealed class TikTokAppOptions
{
    public string? ClientKey { get; set; }
    public string? ClientSecret { get; set; }

    public string Scopes { get; set; } = "user.info.basic,video.publish,video.upload";

    public bool IsConfigured => !string.IsNullOrWhiteSpace(ClientKey) && !string.IsNullOrWhiteSpace(ClientSecret);
}
