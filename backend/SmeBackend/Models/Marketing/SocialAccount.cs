using System.ComponentModel.DataAnnotations;

namespace SmeBackend.Models.Marketing;

public static class SocialPlatform
{
    public const string Facebook = "Facebook";
    public const string Instagram = "Instagram";
    public const string TikTok = "TikTok";

    public static readonly string[] All = { Facebook, Instagram, TikTok };

    public static string? Normalize(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "facebook" or "fb" => Facebook,
        "instagram" or "ig" => Instagram,
        "tiktok" or "tt" => TikTok,
        _ => null,
    };
}

public static class SocialAccountStatus
{
    /// Token works as far as we last knew.
    public const string Connected = "Connected";
    /// The provider rejected the token (revoked, password changed, expired
    /// refresh token). Publishing and replies stop until it is reconnected.
    public const string NeedsReconnect = "NeedsReconnect";
    /// Removed by the business. The row stays (tokens wiped) so the history
    /// of what was posted to it survives, and connecting the same profile
    /// again revives it instead of creating a duplicate.
    public const string Disconnected = "Disconnected";
}

/// One social profile a business has connected: a Facebook Page, the
/// Instagram professional account linked to a Page, or a TikTok account.
///
/// Tokens are encrypted with IPlatformSecretProtector (AES-256-GCM, key from
/// configuration) exactly like PaymentGateway secrets, and never leave the
/// API: the client only ever sees the account's name, handle and status.
///
/// A sandbox account has no token at all. It exists so a business can try
/// the composer and inbox before going through Meta/TikTok app review, and
/// every action on it is reported as Simulated, never as published.
public class SocialAccount : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }

    /// Facebook | Instagram | TikTok
    [MaxLength(20)]
    public string Platform { get; set; } = string.Empty;

    /// Page id / Instagram business account id / TikTok open_id.
    [MaxLength(100)]
    public string ExternalId { get; set; } = string.Empty;

    /// For Instagram: the Facebook Page it is linked to. Instagram messaging
    /// and the page token both go through that Page.
    [MaxLength(100)]
    public string? ParentExternalId { get; set; }

    [MaxLength(200)]
    public string DisplayName { get; set; } = string.Empty;

    [MaxLength(100)]
    public string? Handle { get; set; }

    [MaxLength(2048)]
    public string? AvatarUrl { get; set; }

    public string? AccessTokenEncrypted { get; set; }
    public DateTime? AccessTokenExpiresAt { get; set; }

    /// TikTok only; Meta page tokens do not expire and have no refresh token.
    public string? RefreshTokenEncrypted { get; set; }
    public DateTime? RefreshTokenExpiresAt { get; set; }

    [MaxLength(1000)]
    public string? Scopes { get; set; }

    [MaxLength(30)]
    public string Status { get; set; } = SocialAccountStatus.Connected;

    [MaxLength(1000)]
    public string? LastError { get; set; }

    public bool IsSandbox { get; set; }

    /// TikTok privacy level used when publishing (PUBLIC_TO_EVERYONE,
    /// MUTUAL_FOLLOW_FRIENDS, FOLLOWER_OF_CREATOR, SELF_ONLY). Unaudited
    /// TikTok apps may only post SELF_ONLY, which the publisher falls back
    /// to when the creator's allowed options say so.
    [MaxLength(40)]
    public string? DefaultPrivacy { get; set; }

    public Guid? ConnectedByUserId { get; set; }
    public DateTime? LastSyncedAt { get; set; }
}
