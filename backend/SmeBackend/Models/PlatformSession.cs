namespace SmeBackend.Models;

/// One signed-in platform console. The JWT's jti points here, and the
/// PlatformOwner policy refuses any token whose row is missing, revoked,
/// past its hard expiry or idle too long - so a stolen token dies with the
/// session, not with the clock.
public class PlatformSession
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;

    /// The JWT id claim; the token and this row are matched on it.
    public string Jti { get; set; } = string.Empty;
    public string IpAddress { get; set; } = string.Empty;
    public string UserAgent { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastSeenAt { get; set; } = DateTime.UtcNow;
    public DateTime ExpiresAt { get; set; }
    public DateTime? RevokedAt { get; set; }
    public string? RevokedReason { get; set; }

    public bool IsLive(DateTime now, TimeSpan idleTimeout) =>
        RevokedAt == null && ExpiresAt > now && now - LastSeenAt <= idleTimeout;
}
