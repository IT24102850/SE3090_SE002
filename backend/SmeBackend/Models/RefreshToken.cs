namespace SmeBackend.Models;

/// <summary>
/// One issued refresh token (Services/RefreshTokenStore.cs). Only the SHA-256
/// hash is stored: a database leak must not hand out working sessions, and the
/// token is 64 random bytes, so an unsalted hash cannot be brute-forced.
/// Tokens rotate - each is redeemable once, and redeeming it records which
/// token replaced it, so a replayed token can be recognised as theft.
/// </summary>
public class RefreshToken
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;
    public string TokenHash { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
    public DateTime? RevokedAt { get; set; }
    public string? ReplacedByTokenHash { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
