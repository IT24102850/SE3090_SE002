namespace SmeBackend.Models;

/// The security record behind a SuperAdmin user: MFA enrolment, lockout
/// counters and last-login facts. Kept apart from User so the ordinary
/// tenant tables never carry a TOTP secret, and so the fields cannot leak
/// through the tenant-facing user DTOs.
///
/// The TOTP secret is stored AES-GCM encrypted (PlatformSecretProtector);
/// the database alone is not enough to mint codes.
public class PlatformAdmin
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;

    public string? MfaSecretEncrypted { get; set; }
    public DateTime? MfaEnabledAt { get; set; }

    // Enrolment in flight: the secret shown as a QR code, and the one-time
    // token the browser hands back with the first code. Both are dropped
    // the moment enrolment succeeds or the window lapses.
    public string? PendingMfaSecretEncrypted { get; set; }
    public string? MfaSetupTokenHash { get; set; }
    public DateTime? MfaSetupExpiresAt { get; set; }

    // A TOTP code is valid for a 30 s step; remembering the last step that
    // was accepted stops a sniffed code being replayed inside that window.
    public long LastAcceptedTotpStep { get; set; }

    public int FailedLoginAttempts { get; set; }
    public DateTime? LockoutEndUtc { get; set; }

    public DateTime? LastLoginAt { get; set; }
    public string? LastLoginIp { get; set; }
    public DateTime? PasswordChangedAt { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
